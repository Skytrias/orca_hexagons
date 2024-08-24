package src

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/ease"
import "core:math/rand"
import "core:slice"
import "core:strings"
import oc "core:sys/orca"
import "core:time"
import "hex"
import "hsluv"

TICK_RATE :: 20
TICK_TIME :: 1.0 / TICK_RATE

GRID_WIDTH :: 6
GRID_HEIGHT :: 10 * 2

SWAP_FRAMES :: 5
CLEAR_FRAMES :: 30
SPAWN_TIME :: 60 * 10
SCORE_DURATION :: time.Second * 2

Particle :: struct {
	using pos:           [2]f32,
	direction:           [2]f32,
	color:               [3]f32,
	radius:              f32,
	lifetime_framecount: int,
	lifetime:            int,
}

Game_State :: struct {
	offset:                   oc.vec2,
	hexagon_size:             f32,
	layout:                   hex.Layout,
	grid:                     []Piece,
	piece_dragging:           ^Piece,
	piece_dragging_direction: int,
	piece_dragging_cursor:    hex.FHex,
	particles:                [dynamic]Particle,
	cursor_width:             f32,
	spawn_ticks:              f32,
	score:                    int,
	score_stats:              [dynamic]Score_Stat,
	flux:                     ease.Flux_Map(f32),
}

Score_Stat :: struct {
	timestamp: time.Time,
	text:      string,
}

Piece_State :: enum {
	Idle,
	Hang,
	Fall,
	Clear_Counting,
	Clearing,
	Swapping,
}

piece_colors := [?][3]f32 {
	{1, 0, 0},
	{0, 1, 0},
	{0, 0, 1},
	{1, 1, 0},
	{1, 0, 1},
}

Piece :: struct {
	is_color:          bool,
	coord:             hex.Doubled_Coord,
	array_index:       int,
	color_index:       int,
	state:             Piece_State,
	state_framecount:  int,
	swap_framecount:   int,
	swap_from:         hex.Doubled_Coord,
	swap_to:           hex.Doubled_Coord,
	swap_interpolated: [2]f32,
}

Fall_Check :: struct {
	next_index: int,
	next_root:  hex.Hex,
	can_fall:   bool,
}

game_state_init :: proc(state: ^Game_State) {
	state.hexagon_size = 50
	state.grid = make([]Piece, GRID_WIDTH * GRID_HEIGHT)
	grid_init(state.grid)
	state.spawn_ticks = SPAWN_TIME
	state.score_stats = make([dynamic]Score_Stat, 0, 64)
	state.particles = make([dynamic]Particle, 0, 64)

	state.flux = ease.flux_init(f32, 64)
}

game_state_destroy :: proc(state: ^Game_State) {
	delete(state.score_stats)
	delete(state.grid)
	delete(state.particles)
}

grid_init :: proc(grid: []Piece) {
	for index := 0; index < len(grid); index += 1 {
		grid[index] = {}
	}

	for x := 0; x < GRID_WIDTH; x += 1 {
		//		for y := 0; y < 4; y += 1 {
		index := xy2i(x, 0)
		grid[index] = piece_make()
		//		}
	}
}

game_state_score_stats_append :: proc(state: ^Game_State, text: string) {
	stat := Score_Stat {
		timestamp = time.now(),
		text      = strings.clone(text),
	}
	append(&state.score_stats, stat)
}

game_state_score_stats_update :: proc(state: ^Game_State) {
	for i := len(state.score_stats) - 1; i >= 0; i -= 1 {
		stat := &state.score_stats[i]
		diff := time.since(stat.timestamp)

		if diff > SCORE_DURATION {
			delete(stat.text)
			unordered_remove(&state.score_stats, i)
		}
	}
}

piece_make :: proc() -> Piece {
	return {
		is_color    = true,
		color_index = int(rand.int31_max(len(piece_colors))),
		//		state = .Hang,
	}
}

piece_get_color :: proc(piece: Piece, alpha: f32) -> [4]f32 {
	color := piece_colors[piece.color_index]
	return {color.x, color.y, color.z, alpha}
}

piece_set_current_color :: proc(piece: Piece, alpha: f32) {
	color := piece_get_color(piece, alpha)
	oc.set_color_rgba(color.r, color.g, color.b, color.a)
	//	 a := oc.color { color, .RGB }
	//	 b := oc.color { { 0, 0, 0, 1 }, .RGB }
	//	 oc.set_gradient(.LINEAR, b, b, a, a)
}

grid_check_clear_recursive :: proc(
	grid: ^[]Piece,
	check_clear: ^[dynamic]^Piece,
	piece: ^Piece,
) {
	root := hex.qdoubled_to_cube(piece.coord)
	for dir in hex.directions {
		custom_root := root + dir
		custom_coord := hex.qdoubled_from_cube(custom_root)

		other := grid_get_color(grid, custom_coord)
		if other != nil &&
		   other.state == .Idle &&
		   other.color_index == piece.color_index {
			append(check_clear, other)
			piece_set_state(other, .Clear_Counting)
			grid_check_clear_recursive(grid, check_clear, other)
		}
	}
}

grid_piece_check_clear :: proc(update: ^Update_State, piece: ^Piece) {
	clear(&update.check_clear)
	grid_check_clear_recursive(&update.state.grid, &update.check_clear, piece)

	if len(update.check_clear) > 3 {
		update.state.score += len(update.check_clear) * 100
		text := fmt.tprintf("Combo: %dx", len(update.check_clear))
		game_state_score_stats_append(update.state, text)

		for x in update.check_clear {
			piece_set_state(x, .Clearing)
		}
	} else {
		// back to origin
		for x in update.check_clear {
			piece_set_state(x, .Idle)
		}
	}
}

grid_set_coordinates :: proc(grid: ^[]Piece) {
	for &x, i in grid {
		x.array_index = i
		x.coord = i2coord(i)
	}
}

grid_update :: proc(state: ^Game_State) {
	update: Update_State
	update.state = state
	update.check_clear = make([dynamic]^Piece, 0, 64, context.temp_allocator)
	update.remove_list = make([dynamic]int, 0, 64, context.temp_allocator)

	// look to perform swaps
	for i := 0; i < len(state.grid); i += 1 {
		a := &state.grid[i]

		if a.state == .Swapping && a.swap_framecount == 0 {
			b_index := coord2i(a.swap_to)
			b := &state.grid[b_index]

			piece_set_state(a, .Idle)
			piece_set_state(b, .Idle)

			temp := a^
			a^ = b^
			b^ = temp
		}
	}

	for &x in &state.grid {
		piece_update(&x, &update)
	}

	if len(update.remove_list) > 0 {
		log.info("REMOVING %d pieces", len(update.remove_list))
	}
	for index in update.remove_list {
		piece := &state.grid[index]
		piece_clear_particles(piece)
		piece^ = {}
	}
}

game_mouse_check :: proc(
	state: ^Game_State,
	layout: hex.Layout,
	mouse: [2]f32,
	is_down: bool,
) {
	fx_snapped := hex.round(hex.pixel_to_hex(layout, mouse))

	if state.piece_dragging != nil {
		root := hex.qdoubled_to_cube(state.piece_dragging.coord)
		fx_snapped = root
	}

	exp_interpolate(
		&state.piece_dragging_cursor.x,
		f32(fx_snapped.x),
		core.dt,
		1e-6,
	)
	exp_interpolate(
		&state.piece_dragging_cursor.y,
		f32(fx_snapped.y),
		core.dt,
		1e-6,
	)
	exp_interpolate(
		&state.piece_dragging_cursor.z,
		f32(fx_snapped.z),
		core.dt,
		1e-6,
	)

	fx := hex.pixel_to_hex(layout, mouse)

	// drag action
	if !is_down {
		// action
		if state.piece_dragging != nil &&
		   state.piece_dragging_direction != -1 {
			direction := hex.directions[state.piece_dragging_direction]

			root := hex.qdoubled_to_cube(state.piece_dragging.coord)
			goal := root - direction
			coord := hex.qdoubled_from_cube(goal)

			other := grid_get_any(&state.grid, coord)
			piece_swap(state.piece_dragging, other, coord)
		}

		state.piece_dragging = nil
		state.piece_dragging_direction = -1
		return
	}

	// drag direction
	if state.piece_dragging != nil {
		// get direction info
		at_mouse := hex.round(fx)
		direction_index := -1
		root := hex.qdoubled_to_cube(state.piece_dragging.coord)

		if at_mouse != root {
			direction_index = hex.direction_towards(root, at_mouse)
		}
		state.piece_dragging_direction = direction_index
		return
	}

	// drag location
	for &x, i in &state.grid {
		if x.state != .Idle {
			continue
		}

		root := hex.qdoubled_to_cube(x.coord)
		if hex.round(fx) == root {
			state.piece_dragging = &x
			state.piece_dragging_direction = -1
			break
		}
	}
}

hexagon_path :: proc(corners: [6]hex.Point) {
	oc.move_to(corners[0].x, corners[0].y)
	for i := 1; i < len(corners); i += 1 {
		c := corners[i]
		oc.line_to(c.x, c.y)
	}
	oc.close_path()
}

piece_enter_state :: proc(piece: ^Piece, state: Piece_State) {
	switch state {
	case .Idle:
	case .Hang:
		piece.state_framecount = 30
	case .Fall:
	case .Clear_Counting:
	case .Clearing:
		piece.state_framecount = CLEAR_FRAMES
	case .Swapping:
		piece.swap_framecount = SWAP_FRAMES
	}
	piece.state = state
}

piece_clear_particles :: proc(piece: ^Piece) {
	root := hex.qdoubled_to_cube(piece.coord)
	center := hex.to_pixel(core.game.layout, root)

	for i in 0 ..< 10 {
		direction := [2]f32{rand.float32() * 2 - 1, rand.float32() * 2 - 1}
		lifetime := rand.int31_max(50)

		hue := rand.float64() * 360
		r, g, b := hsluv.hsluv_to_rgb(hue, 100, 50)
		size := rand.float32() * 15 + 5

		particle := Particle {
			pos       = center,
			direction = direction,
			lifetime  = int(lifetime),
			color     = {f32(r), f32(g), f32(b)},
			radius    = size,
		}

		append(&core.game.particles, particle)
	}
}

piece_exit_state :: proc(piece: ^Piece) {
	switch piece.state {
	case .Idle:
	case .Hang:
	case .Fall:
	case .Clear_Counting:
	case .Clearing:
	case .Swapping:
	}
}

piece_set_state :: proc(piece: ^Piece, new_state: Piece_State) {
	piece_exit_state(piece)
	piece_enter_state(piece, new_state)
}

Update_State :: struct {
	state:       ^Game_State,
	check_clear: [dynamic]^Piece,
	remove_list: [dynamic]int,
}

grid_get_color :: proc(grid: ^[]Piece, coord: hex.Doubled_Coord) -> ^Piece {
	if coord.x < 0 ||
	   coord.x >= GRID_WIDTH ||
	   coord.y < 0 ||
	   coord.y >= GRID_HEIGHT {
		return nil
	}

	index := coord2i(coord)
	piece := &grid[index]

	if piece.is_color {
		return piece
	}

	return nil
}

// bounds checked getter
grid_get_any :: proc(grid: ^[]Piece, coord: hex.Doubled_Coord) -> ^Piece {
	if coord.x < 0 ||
	   coord.x >= GRID_WIDTH ||
	   coord.y < 0 ||
	   coord.y >= GRID_HEIGHT {
		return nil
	}

	index := coord2i(coord)
	return &grid[index]
}

piece_fall_cascade :: proc(grid: ^[]Piece, piece: ^Piece) {
	// cascade fall upper
	for y := piece.coord.y; y >= 0; y -= 2 {
		a_index := xy2i(piece.coord.x, y)
		b_index := xy2i(piece.coord.x, y + 2)
		grid[a_index], grid[b_index] = grid[b_index], grid[a_index]
	}

	grid_set_coordinates(grid)
}

piece_at_end :: proc(coord: hex.Doubled_Coord) -> bool {
	return coord.y == GRID_HEIGHT || coord.y == GRID_HEIGHT - 1
}

piece_update :: proc(piece: ^Piece, update: ^Update_State) {
	if piece.state_framecount > 0 {
		piece.state_framecount -= 1
		return
	}

	if piece.swap_framecount > 0 {
		piece.swap_framecount -= 1
	}

	if !piece.is_color {
		piece.state = .Idle
		return
	}

	switch piece.state {
	case .Idle:
		below := coord_below(piece.coord)
		below_piece := grid_get_any(&update.state.grid, below)

		if below_piece != nil &&
		   !below_piece.is_color &&
		   !piece_at_end(piece.coord) {
			piece_set_state(piece, .Hang)
		}

		grid_piece_check_clear(update, piece)

	case .Hang:
		piece_set_state(piece, .Fall)

	case .Fall:
		below := coord_below(piece.coord)
		below_piece := grid_get_any(&update.state.grid, below)

		if piece_at_end(piece.coord) {
			piece_set_state(piece, .Idle)
			return
		}

		if below_piece != nil && !below_piece.is_color {
			piece_fall_cascade(&update.state.grid, piece)
		} else {
			piece_set_state(piece, .Idle)
		}

	case .Clear_Counting:
	case .Clearing:
		log.info("ADD TO CLEAR")
		append(&update.remove_list, piece.array_index)

	case .Swapping:
		unit := f32(piece.swap_framecount) / SWAP_FRAMES
		piece.swap_interpolated.x = math.lerp(
			f32(piece.swap_from.x),
			f32(piece.swap_to.x),
			1 - unit,
		)
		piece.swap_interpolated.y = math.lerp(
			f32(piece.swap_from.y),
			f32(piece.swap_to.y),
			1 - unit,
		)
	}
}

piece_swappable :: proc(a, b: ^Piece) -> bool {
	// dont allow two floaties to swap
	if !a.is_color && b != nil && !b.is_color {
		return false
	}

	if a.state != .Idle {
		return false
	}

	if b != nil && b.state != .Idle {
		return false
	}

	return true
}

piece_swap :: proc(a, b: ^Piece, goal: hex.Doubled_Coord) {
	if !piece_swappable(a, b) {
		return
	}

	if b != nil {
		piece_set_state(b, .Swapping)
		b.swap_from = b.coord
		b.swap_interpolated = {f32(b.swap_from.x), f32(b.swap_from.y)}
		b.swap_to = a.coord
	}

	piece_set_state(a, .Swapping)
	a.swap_from = a.coord
	a.swap_interpolated = {f32(a.swap_from.x), f32(a.swap_from.y)}
	a.swap_to = goal
}

piece_render_shape :: proc(
	piece: ^Piece,
	layout: hex.Layout,
) -> (
	corners: [6]hex.Point,
) {
	margin := f32(-1)
	alpha := f32(1)

	if piece.state == .Clearing {
		unit := f32(piece.state_framecount) / CLEAR_FRAMES
		margin = -1 + (1 - unit) * -core.game.hexagon_size
		alpha = unit
	}

	if piece.state == .Swapping {
		custom_root := hex.fqdoubled_to_cube(piece.swap_interpolated)
		corners = hex.fpolygon_corners(layout, custom_root, margin)
	} else {
		root := hex.qdoubled_to_cube(piece.coord)
		corners = hex.polygon_corners(layout, root, margin)
	}

	hexagon_path(corners)
	piece_set_current_color(piece^, alpha)

	oc.fill()
	return
}

particles_update :: proc(particles: ^[dynamic]Particle) {
	// update new
	for &particle in particles {
		particle.lifetime_framecount += 1
		particle.pos += particle.direction * 5
	}

	// remove old
	for i := len(particles) - 1; i >= 0; i -= 1 {
		particle := &particles[i]
		if particle.lifetime_framecount > particle.lifetime {
			unordered_remove(particles, i)
		}
	}
}

particles_render :: proc(particles: ^[dynamic]Particle) {
	for &particle in particles {
		unit := f32(particle.lifetime_framecount) / f32(particle.lifetime)
		alpha := (1 - unit * unit)
		radius := particle.radius * (1 - unit)
		oc.set_color_rgba(
			particle.color.r,
			particle.color.g,
			particle.color.b,
			alpha,
		)
		oc.circle_fill(particle.x, particle.y, radius)
	}
}

grid_spawn_update :: proc(state: ^Game_State) {
	if state.spawn_ticks > 0 {
		state.spawn_ticks -= 1
	} else {
		state.spawn_ticks = SPAWN_TIME

		for x in 0 ..< GRID_WIDTH {
			index := xy2i(x, 0)
			piece := &state.grid[index]

			if !piece.is_color {
				piece^ = piece_make()
			}
		}
	}
}
