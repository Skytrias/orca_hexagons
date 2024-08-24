package src

import "core:fmt"
import "core:math/ease"
import "core:math/rand"
import "core:slice"
import "core:strings"
import oc "core:sys/orca"
import "core:time"
import "hex"
import "hsluv"

TICK_RATE :: 60
TICK_TIME :: 1.0 / TICK_RATE

SWAP_FRAMES :: 5
FALL_LIMIT :: 15
BOUNDS_LIMIT :: 10
CLEAR_FRAMES :: 30
SPAWN_TIME :: 60 * 2
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
	grid:                     [dynamic]Piece,
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
	using root:        hex.Hex,
	array_index:       int,
	ref_index:         int,
	color_index:       int,
	state:             Piece_State,
	state_framecount:  int,
	swap_framecount:   int,
	swap_from:         hex.Hex,
	swap_to:           hex.Hex,
	swap_interpolated: hex.FHex,
}

game_state_init :: proc(state: ^Game_State) {
	state.hexagon_size = 30
	state.grid = make([dynamic]Piece, 0, 32)
	grid_init(&state.grid)
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

grid_init :: proc(grid: ^[dynamic]Piece) {
	clear(grid)
	pieces := make([dynamic]hex.Hex, 0, 64, context.temp_allocator)
	hex.shape_hexagon_empty(&pieces, BOUNDS_LIMIT)

	for x in pieces {
		x := hex.shifted_y(x, -5)
		append(grid, piece_make(x))
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

piece_make :: proc(root: hex.Hex) -> Piece {
	return {
		root = root,
		color_index = int(rand.int31_max(len(piece_colors))),
		state = .Hang,
	}
}

ref_grid_find_index :: proc(pieces: []^Piece, search: hex.Hex) -> int {
	for x, i in pieces {
		if x.root == search {
			return i
		}
	}

	return -1
}

grid_find_index :: proc(pieces: []Piece, search: hex.Hex) -> int {
	for x, i in pieces {
		if x.root == search {
			return i
		}
	}

	return -1
}

piece_get_color :: proc(piece: Piece, alpha: f32) -> [4]f32 {
	color := piece_colors[piece.color_index]
	return {color.x, color.y, color.z, alpha}
}

piece_set_current_color :: proc(piece: Piece, alpha: f32) {
	color := piece_get_color(piece, alpha)
	oc.set_color_rgba(color.r, color.g, color.b, color.a)
	// a := oc.color { color, .RGB }
	// b := oc.color { { 0, 0, 0, 1 }, .RGB }
	// oc.set_gradient(.LINEAR, b, b, a, a)
}

grid_check_clear_recursive :: proc(
	grid: []^Piece,
	check_clear: ^[dynamic]^Piece,
	piece: ^Piece,
) {
	for dir in hex.directions {
		other_index := ref_grid_find_index(grid, piece.root + dir)
		if other_index != -1 {
			other := grid[other_index]
			if other.state == .Idle && other.color_index == piece.color_index {
				append(check_clear, other)
				piece_set_state(other, .Clear_Counting)
				grid_check_clear_recursive(grid, check_clear, other)
			}
		}
	}
}

grid_piece_check_clear :: proc(update: ^Update_State, piece: ^Piece) {
	clear(&update.check_clear)
	grid_check_clear_recursive(update.grid, &update.check_clear, piece)

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

Fall_Check :: struct {
	next_index: int,
	next_root:  hex.Hex,
	can_fall:   bool,
}

grid_piece_can_fall :: proc(
	grid: []^Piece,
	piece: ^Piece,
) -> (
	check: Fall_Check,
) {
	current_coord := hex.qdoubled_from_cube(piece.root)
	below_coord := hex.Doubled_Coord{current_coord.x, current_coord.y + 2}
	below_root := hex.qdoubled_to_cube(below_coord)
	check.next_root = below_root
	check.next_index = ref_grid_find_index(grid, check.next_root)

	check.can_fall = current_coord.y < FALL_LIMIT && check.next_index == -1
	return
}

grid_update :: proc(state: ^Game_State) {
	update: Update_State
	update.state = state
	update.grid = make([]^Piece, len(state.grid))
	for &x, i in &state.grid {
		x.array_index = i
		update.grid[i] = &x
	}

	slice.sort_by(update.grid, proc(a, b: ^Piece) -> bool {
		coord_a := hex.qdoubled_from_cube(a)
		coord_b := hex.qdoubled_from_cube(b)
		return coord_a.y < coord_b.y
	})

	// set ref index for info
	for &x, i in &update.grid {
		x.ref_index = i
	}

	update.check_clear = make([dynamic]^Piece, 0, 64, context.temp_allocator)
	update.remove_list = make([dynamic]int, 0, 64, context.temp_allocator)

	for x in &update.grid {
		piece_update(x, &update)
	}

	slice.sort_by_cmp(
		update.remove_list[:],
		proc(a, b: int) -> slice.Ordering {
			switch {
			case a < b:
				return .Greater
			case a > b:
				return .Less
			}
			return .Equal
		},
	)

	for index in update.remove_list {
		piece := state.grid[index]
		piece_clear_particles(piece)
		unordered_remove(&state.grid, index)
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
		fx_snapped = state.piece_dragging.root
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

			goal := state.piece_dragging.root - direction
			coord := hex.qdoubled_from_cube(goal)

			if coord.y < FALL_LIMIT {
				next_index := grid_find_index(state.grid[:], goal)
				other := next_index != -1 ? &state.grid[next_index] : nil
				piece_swap(state.piece_dragging, other, goal)
			}
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
		if at_mouse != state.piece_dragging.root {
			direction_index = hex.direction_towards(
				state.piece_dragging.root,
				at_mouse,
			)
		}
		state.piece_dragging_direction = direction_index
		return
	}

	// drag location
	for &x, i in &state.grid {
		if x.state != .Idle {
			continue
		}

		if hex.round(fx) == x.root {
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

piece_clear_particles :: proc(piece: Piece) {
	center := hex.to_pixel(core.game.layout, piece)
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
	grid:        []^Piece,
	check_clear: [dynamic]^Piece,
	remove_list: [dynamic]int,
}

coord_below :: proc(h: hex.Hex) -> hex.Doubled_Coord {
	temp := hex.qdoubled_from_cube(h)
	return {temp.x, temp.y + 2}
}

piece_fall_downwards :: proc(piece: ^Piece) -> (root: hex.Doubled_Coord) {
	root = hex.qdoubled_from_cube(piece.root)
	piece.root = hex.qdoubled_to_cube({root.x, root.y + 2})
	return
}

piece_fall_cascade :: proc(piece: ^Piece, update: ^Update_State) {
	origin := piece_fall_downwards(piece)

	// cascade fall upper
	for &other in update.grid {
		other_coord := hex.qdoubled_from_cube(other)

		if other == piece {
			continue
		}

		if other_coord.x == origin.x && other_coord.y < origin.y {
			piece_fall_downwards(other)
		}
	}
}

piece_update :: proc(piece: ^Piece, update: ^Update_State) {
	if piece.state_framecount > 0 {
		piece.state_framecount -= 1
		return
	}

	if piece.state == .Swapping && piece.swap_framecount == 0 {
		piece.root = piece.swap_to
		piece_set_state(piece, .Idle)
	}

	if piece.swap_framecount > 0 {
		piece.swap_framecount -= 1
	}

	switch piece.state {
	case .Idle:
		below := coord_below(piece)
		below_index := ref_grid_find_index(
			update.grid,
			hex.qdoubled_to_cube(below),
		)

		if below_index == -1 && below.y < FALL_LIMIT {
			piece_set_state(piece, .Hang)
		}

		grid_piece_check_clear(update, piece)

	case .Hang:
		piece_set_state(piece, .Fall)

	case .Fall:
		below := coord_below(piece)
		below_index := ref_grid_find_index(
			update.grid,
			hex.qdoubled_to_cube(below),
		)

		if below_index == -1 {
			if below.y < FALL_LIMIT {
				piece_fall_cascade(piece, update)
			} else {
				piece_set_state(piece, .Idle)
			}
		} else {
			piece_set_state(piece, .Idle)
		}

	case .Clear_Counting:
	case .Clearing:
		append(&update.remove_list, piece.array_index)

	case .Swapping:
		unit := f32(piece.swap_framecount) / SWAP_FRAMES
		piece.swap_interpolated = hex.lerp(
			piece.swap_from,
			piece.swap_to,
			1 - unit,
		)
	}
}

piece_swappable :: proc(a, b: ^Piece) -> bool {
	if a.state != .Idle {
		return false
	}

	if b != nil && b.state != .Idle {
		return false
	}

	return true
}

piece_swap :: proc(a, b: ^Piece, goal: hex.Hex) {
	if !piece_swappable(a, b) {
		return
	}

	if b != nil {
		piece_set_state(b, .Swapping)
		b.swap_from = b.root
		b.swap_interpolated = hex.to_float(b.root)
		b.swap_to = a.root
	}

	piece_set_state(a, .Swapping)
	a.swap_from = a.root
	a.swap_interpolated = hex.to_float(a.root)
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
		corners = hex.fpolygon_corners(layout, piece.swap_interpolated, margin)
	} else {
		corners = hex.polygon_corners(layout, piece, margin)
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

		for x in -BOUNDS_LIMIT ..= BOUNDS_LIMIT {
			root := hex.qdoubled_to_cube({x, -FALL_LIMIT})
			append(&state.grid, piece_make(root))
		}
	}
}
