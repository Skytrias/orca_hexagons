package src

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/ease"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:strings"
import oc "core:sys/orca"
import "core:time"
import "hex"
import "hsluv"

TICK_RATE :: 120
TICK_TIME :: 1.0 / TICK_RATE

SCORE_DURATION :: time.Second * 2
SPAWN_SPEEDUP :: 20

GRID_WIDTH :: 10
GRID_HEIGHT :: 12 * 2
BOUNCE_FRAMES :: 80
COMBO_LIMIT :: 4

Particle :: struct {
	using pos:           [2]f32,
	direction:           [2]f32,
	color:               [3]f32,
	width:               f32,
	size:                f32,
	lifetime_framecount: int,
	lifetime:            int,
}

Drag_State :: struct {
	coord:            Maybe(hex.Doubled_Coord),
	direction:        int,
	cursor:           hex.FHex,
	cursor_direction: hex.FHex,
}

Game_State :: struct {
	flux:                   ease.Flux_Map(f32),
	total_ticks:            int,

	// game sizing / layout
	fixed_yoffset:          f32,
	fixed_xoffset:          f32,
	offset:                 oc.vec2,
	hexagon_size:           f32,
	layout:                 hex.Layout,

	// grid data
	grid:                   []Piece,
	grid_copy:              []Piece,
	grid_incoming:          []int,

	// dragging + cursor
	drag:                   Drag_State,
	cursor_width:           f32,

	// pretty
	particles:              [dynamic]Particle,

	// spawning blocks
	spawn_ticks:            int,
	spawn_speedup:          int,

	// scoring
	score:                  int,
	score_stats:            [dynamic]Score_Stat,

	// chain tracking
	chain_count:            int,
	chain_delay_framecount: int,

	// speed of the game, all framecounts should use this
	speed:                  f32,
	speed_last_increase_at: int,
	framecounts:            [Game_Framecount]int,

	// game over state
	lose_framecount:        int,
	lost:                   bool,

	// warning for rows close to lose range
	warn_rows:              []bool,
	warn_framecount:        int,

	// debug
	debug_text:             bool,
}

Game_Framecount :: enum {
	Fall,
	Hang,
	Swap,
	Land,
	Clear_Flash,
	Clear_Delay,
	Clearing,
	Spawn_Time,
	Chain_Delay,
	Lose,
	Warn,
	Mouse_Hover,
}

Score_Stat :: struct {
	timestamp: time.Time,
	text:      string,
}

Piece_State :: enum {
	Idle,
	Hang,
	Fall,
	Clear_Flash,
	Clear_Delay,
	Clearing,
	Swapping,
	Landing,
}

Clear_State :: struct {
	grid:        []Piece,
	connections: [dynamic]^Piece,
	visited:     map[^Piece]bool,
	queue:       [dynamic]^Piece,
}

piece_colors := [?][3]f32 {
	color_flat(255, 5, 6),
	color_flat(0, 255, 1),
	color_flat(255, 255, 0),
	color_flat(0, 255, 255),
	color_flat(255, 10, 255),
}

piece_outer_colors := [?][3]f32 {
	color_flat(97, 0, 0),
	color_flat(0, 99, 3),
	color_flat(87, 66, 1),
	color_flat(2, 120, 120),
	color_flat(53, 2, 165),
}

piece_warn_colors := [?][3]f32 {
	color_flat_scaled(97, 0, 0, 0.5),
	color_flat_scaled(0, 99, 3, 0.5),
	color_flat_scaled(87, 66, 1, 0.5),
	color_flat_scaled(2, 120, 120, 0.5),
	color_flat_scaled(53, 2, 165, 0.5),
}

Piece :: struct {
	// Visual coordinate
	coord:                 hex.Doubled_Coord,

	// Color Info
	is_color:              bool,
	color_index:           int,

	// state data
	state:                 Piece_State,
	state_framecount:      int,
	state_total:           int, // wait for all clearing pieces to finish

	// Swapping
	swap_from:             hex.Doubled_Coord,
	swap_to:               hex.Doubled_Coord,
	swap_interpolated:     [2]f32,

	// Clearing
	clear_index:           int,
	clear_spawn_particles: bool,
	can_chain:             bool, // after blocks fall, they can be chained one after another

	// mouse hovering
	hover_framecount: int,
}

Fall_Check :: struct {
	next_index: int,
	next_root:  hex.Hex,
	can_fall:   bool,
}

game_state_init :: proc(state: ^Game_State) {
	state.framecounts = {
		.Fall        = 0,
		.Hang        = 30,
		.Swap        = 10,
		.Land        = 30,
		.Clear_Flash = 120,
		.Clear_Delay = 30,
		.Clearing    = 40,
		.Spawn_Time  = 60 * 25,
		.Chain_Delay = 100,
		.Lose        = 1000,
		.Warn        = 100,
		.Mouse_Hover = 100,
	}

	state.hexagon_size = 40
	state.grid = make([]Piece, GRID_WIDTH * GRID_HEIGHT)
	state.grid_copy = make([]Piece, GRID_WIDTH * GRID_HEIGHT)
	state.grid_incoming = make([]int, GRID_WIDTH)
	state.score_stats = make([dynamic]Score_Stat, 0, 64)
	state.particles = make([dynamic]Particle, 0, 64)
	state.flux = ease.flux_init(f32, 64)
	state.warn_rows = make([]bool, GRID_WIDTH)
	game_state_reset(state)
}

game_state_zero :: proc(state: ^Game_State) {
	mem.zero_slice(state.grid)
	mem.zero_slice(state.warn_rows)
	clear(&state.score_stats)
	clear(&state.particles)
}

game_state_reset :: proc(state: ^Game_State) {
	state.speed = 1
	grid_init(state.grid)
	grid_init_incoming(state.grid, state.grid_incoming)
	state.spawn_ticks = game_speed_apply(state, .Spawn_Time)
	state.spawn_speedup = 1
}

game_state_destroy :: proc(state: ^Game_State) {
	delete(state.score_stats)
	delete(state.grid)
	delete(state.grid_copy)
	delete(state.particles)
	delete(state.warn_rows)
}

// initialize the color at the bottom to not make the beginning
// ignores lowest color
grid_init_incoming :: proc(existing: []Piece, grid: []int) {
	last := -1

	for x := 0; x < GRID_WIDTH; x += 1 {
		current := int(rand.int31_max(len(piece_colors)))
		piece_index := xy2i_yoffset(x, GRID_HEIGHT - 2)
		piece := existing[piece_index]

		// Ensure the current value is not the same as the last one
		if x % 2 == 0 {
			for last == current ||
			    (piece.is_color && piece.color_index == current) {
				current = int(rand.int31_max(len(piece_colors)))
			}
		} else {
			for last == current {
				current = int(rand.int31_max(len(piece_colors)))
			}
		}

		grid[x] = current
		last = current
	}
}

grid_init :: proc(grid: []Piece) {
	for x := 0; x < GRID_WIDTH; x += 1 {
		for y := 0; y < 3 * 2; y += 1 {
			index := xy2i(x, y)
			grid[index] = piece_make()
			grid[index].state = .Fall
		}
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
		is_color = true,
		color_index = int(rand.int31_max(len(piece_colors))),
	}
}

piece_get_color :: proc(piece: Piece, alpha: f32) -> [4]f32 {
	color := piece_colors[piece.color_index]
	return {color.x, color.y, color.z, alpha}
}

piece_set_current_color :: proc(game: ^Game_State, piece: Piece, alpha: f32) {
	color := piece_get_color(piece, alpha)
	//	a := oc.color { color, .RGB }
	//	b := oc.color { { 0, 0, 0, 1 }, .RGB }
	// check for warning color

	if piece.state == .Clear_Flash {
		color = 1
		unit := game_speed_unit(game, .Clear_Flash, piece.state_framecount)
		color.a = math.sin(unit * math.PI * 10)
	} else if piece.state == .Clear_Delay {
		color = {0, 0, 0, 1}
	}

	if game.warn_rows[piece.coord.x] {
		color.xyz = piece_warn_colors[piece.color_index]
	}

	oc.set_color_rgba(color.r, color.g, color.b, color.a)
	//		outer := piece_outer_colors[piece.color_index]
	//		b = { { outer.x, outer.y, outer.z, alpha }, .RGB }
	//		oc.set_gradient(.LINEAR, b, b, a, a)
}

// non recursive version of checking through same colored pieces
grid_check_clear :: proc(state: ^Clear_State, piece: ^Piece) {
	clear(&state.connections)
	clear(&state.queue)
	clear(&state.visited)
	append(&state.queue, piece)
	append(&state.connections, piece)

	// as long as the queue is full
	for len(state.queue) > 0 {
		last_index := len(state.queue) - 1
		current_piece := state.queue[last_index]
		unordered_remove(&state.queue, last_index)

		// check for directions, only non visited pieces
		for dir in hex.directions {
			root := hex.qdoubled_to_cube(current_piece.coord)
			custom_coord := hex.qdoubled_from_cube(root + dir)

			// check for match
			other := grid_get_color(state.grid, custom_coord)
			if other != nil &&
			   state_swappable(other.state) &&
			   other.color_index == piece.color_index &&
			   other not_in state.visited {
				append(&state.queue, other)
				append(&state.connections, other)
				state.visited[other] = true
			}
		}
	}
}

grid_set_coordinates :: proc(grid: ^[]Piece) {
	for &x, i in grid {
		x.coord = i2coord(i)
	}
}


grid_update :: proc(state: ^Game_State) {
	copy(state.grid_copy, state.grid)

	// update all state machines
	for &x in &state.grid_copy {
		piece_update(state, &x, state.grid_copy)
	}

	// spawn particles
	for &x in &state.grid_copy {
		if x.clear_spawn_particles {
			piece_clear_particles(state, &x)
			x.clear_spawn_particles = false
		}
	}

	// check for fall actions upwards with offsets
	for x in 0 ..< GRID_WIDTH {
		yoffset := 0
		if x % 2 != 0 {
			yoffset = 1
		}

		for y := GRID_HEIGHT - 1 - yoffset; y >= yoffset; y -= 2 {
			index := xy2i(x, y)
			index_above := xy2i(x, y - 2)
			a := &state.grid_copy[index]
			b := &state.grid_copy[index_above]

			if b.state == .Fall && b.state_framecount == 0 && !a.is_color {
				a^, b^ = b^, a^
				a.state_framecount = game_speed_apply(state, .Fall)
			}
		}
	}

	grid_set_coordinates(&state.grid_copy)

	// look to perform actual swaps once they end
	for i := 0; i < len(state.grid_copy); i += 1 {
		a := &state.grid_copy[i]

		if a.state == .Swapping && a.state_framecount == 0 {
			b_index := coord2i(a.swap_to)
			b := &state.grid_copy[b_index]

			piece_set_state(
				state,
				a,
				piece_can_hang(state.grid_copy, a) ? .Hang : .Idle,
			)
			piece_set_state(
				state,
				b,
				piece_can_hang(state.grid_copy, b) ? .Hang : .Idle,
			)

			temp := a^
			a^ = b^
			b^ = temp
		}
	}

	grid_set_coordinates(&state.grid_copy)

	clear := Clear_State {
		grid        = state.grid_copy,
		connections = make([dynamic]^Piece, 0, 32, context.temp_allocator),
		queue       = make([dynamic]^Piece, 0, 32, context.temp_allocator),
		visited     = make(map[^Piece]bool, 32, context.temp_allocator),
	}

	// cechk for clear updates
	total_clear_count := 0
	for &x in state.grid_copy {
		if !x.is_color {
			continue
		}

		grid_check_clear(&clear, &x)
		if len(clear.connections) > COMBO_LIMIT {

			any_chains := false
			for other, i in clear.connections {
				piece_set_state(state, other, .Clear_Flash)
				other.clear_index = i + 1 + total_clear_count
				any_chains |= other.can_chain
			}

			if any_chains {
				state.chain_count += 1
				text := fmt.tprintf("Chain: %dx", state.chain_count + 1)
				game_state_score_stats_append(state, text)
				state.score += len(clear.connections) * 1000
			} else {
				state.score += len(clear.connections) * 100
				text := fmt.tprintf("Combo: %dx", len(clear.connections))
				game_state_score_stats_append(state, text)
			}

			total_clear_count += len(clear.connections)
		}
	}

	// update all just cleared pieces to set the total time to wait
	// TODO could be problematic
	clear_flash := game_speed_apply(state, .Clear_Flash)
	clear_delay := game_speed_apply(state, .Clear_Delay)
	clearing := game_speed_apply(state, .Clearing)
	for &x in state.grid_copy {
		if !x.is_color {
			continue
		}

		if x.state == .Clear_Flash && x.state_framecount == clear_flash {
			x.state_total =
				total_clear_count * clear_delay + clearing + clear_flash
		}
	}

	// reset cleared pieces
	for &x in state.grid_copy {
		if !x.is_color {
			continue
		}

		if x.state == .Clearing && x.state_total == 0 {
			x = {}
		}
	}

	// copy back and set coordinates properly
	copy(state.grid, state.grid_copy)
	grid_set_coordinates(&state.grid)

	// look to reset chain counts
	if !grid_any_clears_or_chains(state.grid) {
		if state.chain_count > 0 {
			state.chain_delay_framecount += 1

			if state.chain_delay_framecount >
			   game_speed_apply(state, .Chain_Delay) {
				state.chain_delay_framecount = 0
				state.chain_count = 0
			}
		}
	}
}

coord_out_of_range :: proc(coord: hex.Doubled_Coord) -> bool {
	yoffset := qdoubled_offset(coord.x)
	return(
		coord.x < 0 ||
		coord.y < yoffset ||
		coord.x > GRID_WIDTH - 1 ||
		coord.y > GRID_HEIGHT - 1 + yoffset \
	)
}

game_mouse_check :: proc(
	state: ^Game_State,
	layout: hex.Layout,
	mouse: [2]f32,
	is_down: bool,
) {
	drag := &state.drag

	fx_snapped := hex.round(hex.pixel_to_hex(layout, mouse))
	if mouse_root, ok := drag.coord.?; ok {
		root := hex.qdoubled_to_cube(mouse_root)
		fx_snapped = root
	}

	// clamp mouse coord
	{
		mouse_coord := hex.qdoubled_from_cube(fx_snapped)
		if coord_out_of_range(mouse_coord) {
			yoffset := qdoubled_offset(mouse_coord.x)
			mouse_coord.x = clamp(mouse_coord.x, 0, GRID_WIDTH - 1)
			mouse_coord.y = clamp(
				mouse_coord.y,
				yoffset,
				GRID_HEIGHT - 1 + yoffset,
			)
			fx_snapped = hex.qdoubled_to_cube(mouse_coord)
		}

		piece := grid_get_color(state.grid, mouse_coord)
		if piece != nil {
			piece.hover_framecount = game_speed_apply(state, .Mouse_Hover)
		}
	}

	exp_interpolate(&drag.cursor.x, f32(fx_snapped.x), core.dt, 1e-9)
	exp_interpolate(&drag.cursor.y, f32(fx_snapped.y), core.dt, 1e-9)
	exp_interpolate(&drag.cursor.z, f32(fx_snapped.z), core.dt, 1e-9)

	direction_snapped := fx_snapped
	if drag.direction != -1 {
		direction_snapped = fx_snapped - hex.directions[drag.direction]
	}

	exp_interpolate(
		&drag.cursor_direction.x,
		f32(direction_snapped.x),
		core.dt,
		1e-9,
	)
	exp_interpolate(
		&drag.cursor_direction.y,
		f32(direction_snapped.y),
		core.dt,
		1e-9,
	)
	exp_interpolate(
		&drag.cursor_direction.z,
		f32(direction_snapped.z),
		core.dt,
		1e-9,
	)

	fx := hex.pixel_to_hex(layout, mouse)

	// drag action
	if !is_down {
		// action
		if mouse_root, ok := drag.coord.?; ok && drag.direction != -1 {
			direction := hex.directions[drag.direction]

			root := hex.qdoubled_to_cube(mouse_root)
			goal := root - direction
			coord := hex.qdoubled_from_cube(goal)

			if !coord_out_of_range(coord) {
				a := grid_get_any(state.grid, mouse_root)
				b := grid_get_any(state.grid, coord)
				piece_swap(state, a, b, coord)
			}
		}

		drag.coord = nil
		drag.direction = -1
		return
	}

	// drag direction
	if mouse_root, ok := drag.coord.?; ok {
		// get direction info
		at_mouse := hex.round(fx)
		root := hex.qdoubled_to_cube(mouse_root)

		if at_mouse != root {
			drag.direction = hex.direction_towards(root, at_mouse)
		} else {
			drag.direction = -1
		}

		return
	}

	// drag location
	for &x, i in &state.grid {
		if !state_swappable(x.state) {
			continue
		}

		root := hex.qdoubled_to_cube(x.coord)
		if hex.round(fx) == root {
			drag.coord = x.coord
			drag.direction = -1
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

piece_enter_state :: proc(
	game: ^Game_State,
	piece: ^Piece,
	state: Piece_State,
) {
	piece.state_framecount = 0
	switch state {
	case .Idle:
	case .Hang:
		piece.state_framecount = game_speed_apply(game, .Hang)
	case .Fall:
		piece.state_framecount = game_speed_apply(game, .Fall)
	case .Clear_Flash:
		piece.state_framecount = game_speed_apply(game, .Clear_Flash)
	case .Clear_Delay:
		piece.state_framecount =
			piece.clear_index * game_speed_apply(game, .Clear_Delay)
	case .Clearing:
		piece.state_framecount = game_speed_apply(game, .Clearing)
	case .Swapping:
		piece.state_framecount = game_speed_apply(game, .Swap)
	case .Landing:
		piece.state_framecount = game_speed_apply(game, .Land)
	}
	piece.state = state
}

piece_clear_particles :: proc(state: ^Game_State, piece: ^Piece) {
	root := hex.qdoubled_to_cube(piece.coord)
	center := hex.to_pixel(state.layout, root)

	for i in 0 ..< 20 {
		direction := [2]f32{rand.float32() * 2 - 1, rand.float32() * 2 - 1}
		lifetime := rand.int31_max(150)

		color := piece_colors[piece.color_index]
		width := rand.float32() * 4 + 1
		size := (rand.float32() * 5 + 5) * 10

		particle := Particle {
			pos       = center,
			direction = direction,
			lifetime  = int(lifetime),
			color     = color.rgb,
			width     = width,
			size      = size,
		}

		append(&state.particles, particle)
	}
}

piece_exit_state :: proc(piece: ^Piece) {
	switch piece.state {
	case .Idle:
	case .Hang:
	case .Fall:
	case .Clear_Flash:
	case .Clear_Delay:
	case .Clearing:
	case .Swapping:
	case .Landing:
	}
}

piece_set_state :: proc(
	game: ^Game_State,
	piece: ^Piece,
	new_state: Piece_State,
) {
	piece_exit_state(piece)
	piece_enter_state(game, piece, new_state)
}

grid_get_color :: proc(grid: []Piece, coord: hex.Doubled_Coord) -> ^Piece {
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
grid_get_any :: proc(grid: []Piece, coord: hex.Doubled_Coord) -> ^Piece {
	if coord.x < 0 ||
	   coord.x >= GRID_WIDTH ||
	   coord.y < 0 ||
	   coord.y >= GRID_HEIGHT {
		return nil
	}

	index := coord2i(coord)
	return &grid[index]
}

piece_at_end :: proc(coord: hex.Doubled_Coord) -> bool {
	return coord.y == GRID_HEIGHT - 1 || coord.y == GRID_HEIGHT - 2
}

piece_update :: proc(game: ^Game_State, piece: ^Piece, grid: []Piece) {
	if piece.state_total > 0 {
		piece.state_total -= 1
	}

	if piece.hover_framecount > 0 {
		piece.hover_framecount -= 1
	}

	if piece.state_framecount > 0 {
		piece.state_framecount -= 1

		if piece.state_framecount == 0 && piece.state == .Clearing {
			piece.clear_spawn_particles = true
		}

		// allow swapping updates to interpolation
		if piece.state != .Swapping {
			return
		}
	}

	// skip empty pieces
	if !piece.is_color {
		piece.state = .Idle
		return
	}

	switch piece.state {
	case .Idle:
		if piece_can_hang(grid, piece) {
			piece_set_state(game, piece, .Hang)
		}

		piece.can_chain = false

	case .Hang:
		yoffset := 0
		if piece.coord.x % 2 != 0 {
			yoffset = 1
		}

		piece_set_state(game, piece, .Fall)
		piece.can_chain = true

		// set upper pieces to fall too
		for y := piece.coord.y - 2; y >= 0; y -= 2 {
			index := xy2i(piece.coord.x, y)
			other := &grid[index]

			if other.is_color && other.state == .Idle {
				piece_set_state(game, other, .Fall)
				other.can_chain = true
			} else {
				break
			}
		}

	case .Fall:
		below := coord_below(piece.coord)
		below_piece := grid_get_color(grid, below)

		if piece_at_end(piece.coord) {
			piece_set_state(game, piece, .Landing)
		}

		if below_piece != nil && !state_falling(below_piece.state) {
			piece_set_state(game, piece, .Landing)
		}

	case .Clear_Flash:
		piece_set_state(game, piece, .Clear_Delay)

	case .Clear_Delay:
		piece_set_state(game, piece, .Clearing)

	case .Clearing:

	case .Landing:
		piece_set_state(game, piece, .Idle)

	case .Swapping:
		unit := game_speed_unit(game, .Swap, piece.state_framecount)
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

state_falling :: proc(state: Piece_State) -> bool {
	return state == .Hang || state == .Fall
}

state_swappable :: proc(state: Piece_State) -> bool {
	return state == .Idle || state == .Landing
}

piece_swappable :: proc(a, b: ^Piece) -> bool {
	// dont allow two floaties to swap
	if !a.is_color && b != nil && !b.is_color {
		return false
	}

	if !state_swappable(a.state) {
		return false
	}

	if b != nil && !state_swappable(b.state) {
		return false
	}

	return true
}

piece_swap :: proc(game: ^Game_State, a, b: ^Piece, goal: hex.Doubled_Coord) {
	if !piece_swappable(a, b) {
		return
	}

	if b != nil {
		piece_set_state(game, b, .Swapping)
		b.swap_from = b.coord
		b.swap_interpolated = {f32(b.swap_from.x), f32(b.swap_from.y)}
		b.swap_to = a.coord
	}

	piece_set_state(game, a, .Swapping)
	a.swap_from = a.coord
	a.swap_interpolated = {f32(a.swap_from.x), f32(a.swap_from.y)}
	a.swap_to = goal
}

piece_corners :: proc(
	piece: ^Piece,
	layout: hex.Layout,
	margin: f32,
) -> (
	corners: [6]hex.Point,
) {
	if piece.state == .Swapping {
		custom_root := hex.fqdoubled_to_cube(piece.swap_interpolated)
		corners = hex.fpolygon_corners(layout, custom_root, margin)
	} else {
		root := hex.qdoubled_to_cube(piece.coord)
		corners = hex.polygon_corners(layout, root, margin)
	}

	return
}

piece_render_shape :: proc(
	game: ^Game_State,
	piece: ^Piece,
	layout: hex.Layout,
) -> [6]hex.Point {
	margin := f32(-1)
	alpha := f32(1)
	all_margin := f32(0)

	#partial switch piece.state {
	case .Clearing:
		unit := game_speed_unit(game, .Clearing, piece.state_framecount)
		margin = -1 + (1 - unit) * -core.game.hexagon_size
		alpha = unit

	// case .Hang:
	// 	unit := game_speed_unit(game, .Hang, piece.state_framecount)
	// 	all_margin = -10 * (1-unit)

	// case .Fall:
	// 	all_margin = -10

	case .Landing:
		unit := game_speed_unit(game, .Land, piece.state_framecount)
		actual_unit := ease.sine_in_out(1 - unit)
		all_margin = -10 * (math.sin(actual_unit * math.PI))
	}

	width := f32(10)
	layout := layout

	// bounce animation when losing
	if piece.state == .Idle && game.warn_rows[piece.coord.x] {
		tick_unit := f32(game.total_ticks % BOUNCE_FRAMES) / BOUNCE_FRAMES
		layout.origin.y -= abs(math.sin(tick_unit * math.PI)) * 10
	}

	// unit := game_speed_unit(game, .Mouse_Hover, piece.hover_framecount)
	// if unit > 0 {
	// 	width += (unit) * 10
	// 	// alpha *= (1-unit * 0.75)
	// }

	corners_outline := piece_corners(
		piece,
		layout,
		math.ceil(-1 - width / 2) + all_margin,
	)
	corners_inner := piece_corners(piece, layout, margin - width + all_margin)

	hexagon_path(corners_outline)
	color := piece_outer_colors[piece.color_index]
	oc.set_width(width)
	oc.set_color_rgba(color.r, color.g, color.b, alpha)
	oc.stroke()

	hexagon_path(corners_inner)
	piece_set_current_color(game, piece^, alpha)
	oc.fill()

	return corners_inner
}

particles_update :: proc(particles: ^[dynamic]Particle) {
	// update new
	for &particle in particles {
		particle.lifetime_framecount += 1
		particle.pos += particle.direction * 10
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
		alpha := (1 - (unit * unit * unit))

		oc.set_color_rgba(
			particle.color.r,
			particle.color.g,
			particle.color.b,
			alpha * 0.5,
		)
		xx := particle.x + particle.direction.x * particle.size
		yy := particle.y + particle.direction.y * particle.size

		oc.set_width(particle.width)
		oc.move_to(particle.x, particle.y)
		oc.line_to(xx, yy)
		oc.stroke()
		// oc.circle_fill(particle.x, particle.y, radius)
	}
}

grid_any_clears :: proc(grid: []Piece) -> bool {
	for x in grid {
		if x.state == .Clearing ||
		   x.state == .Clear_Flash ||
		   x.state == .Clear_Delay {
			return true
		}
	}

	return false
}

grid_any_clears_or_chains :: proc(grid: []Piece) -> bool {
	for x in grid {
		if x.state == .Clearing ||
		   x.state == .Clear_Flash ||
		   x.state == .Clear_Delay ||
		   x.can_chain ||
		   x.state == .Hang ||
		   x.state == .Fall {
			return true
		}
	}

	return false
}

grid_spawn_update :: proc(state: ^Game_State) {
	if state.spawn_ticks > 0 {
		any_clears := grid_any_clears(state.grid)
		any_top := game_any_top_pieces(state)

		if !any_clears && !any_top {
			state.spawn_ticks -= 1 * state.spawn_speedup
		}
	} else {
		state.spawn_ticks = game_speed_apply(state, .Spawn_Time)

		// shift upwards
		for x in 0 ..< GRID_WIDTH {
			for y := 1; y < GRID_HEIGHT - 1; y += 1 {
				a := xy2i(x, y)
				b := xy2i(x, y - 1)
				state.grid[a], state.grid[b] = state.grid[b], state.grid[a]
			}
		}

		// set bottom line
		for x in 0 ..< GRID_WIDTH {
			index := xy2i(x, GRID_HEIGHT - 1)
			piece := &state.grid[index]
			piece^ = piece_make()
			piece.color_index = state.grid_incoming[x]
		}

		// update positions
		grid_init_incoming(state.grid, state.grid_incoming)
		grid_set_coordinates(&state.grid)
		game_update_offset(state)

		// graphical pos
		if state.drag.cursor.y > 1 {
			state.drag.cursor.y -= 1
			state.drag.cursor_direction.y -= 1
		}
		if drag, ok := &state.drag.coord.?; ok {
			drag.y -= 2
		}
	}
}

game_update_offset :: proc(game: ^Game_State) {
	game.fixed_xoffset = 300
	game.offset.x = game.hexagon_size + 10 + game.fixed_xoffset
	spawn_unit := game_speed_unit(game, .Spawn_Time, game.spawn_ticks)

	game.fixed_yoffset = game.hexagon_size + 50
	// -ease.cubic_in(1 - spawn_unit) * game.hexagon_size * 1.75 +
	game.offset.y =
		-(1 - spawn_unit) * game.hexagon_size * 1.75 + game.fixed_yoffset


	game.layout = hex.Layout {
		orientation = hex.layout_flat,
		size        = game.hexagon_size,
		origin      = game.offset,
	}
}

piece_state_text :: proc(state: Piece_State) -> (result: string) {
	switch state {
	case .Idle:
		result = "IDLE"
	case .Hang:
		result = "HANG"
	case .Fall:
		result = "FALL"
	case .Clear_Flash:
		result = "Flash"
	case .Clear_Delay:
		result = "Delay"
	case .Clearing:
		result = "Clearing"
	case .Swapping:
		result = "SWAP"
	case .Landing:
		result = "LAND"
	}
	return
}

piece_can_hang :: proc(grid: []Piece, piece: ^Piece) -> bool {
	below := coord_below(piece.coord)
	below_piece := grid_get_any(grid, below)

	if below_piece != nil &&
	   !below_piece.is_color &&
	   !piece_at_end(piece.coord) {
		return true
	}

	return false
}

game_speed_update :: proc(game: ^Game_State) {
	if grid_any_clears(game.grid) {
		return
	}

	diff := game.score - game.speed_last_increase_at
	if diff >= 10_000 {
		game.speed += 0.1
		game.speed_last_increase_at = game.score
	}
}

game_speed_apply :: proc(
	game: ^Game_State,
	framecount: Game_Framecount,
) -> int {
	return int(math.ceil(f32(game.framecounts[framecount]) / game.speed))
}

game_speed_unit :: proc(
	game: ^Game_State,
	framecount: Game_Framecount,
	frames: int,
) -> f32 {
	count := game.framecounts[framecount]
	return f32(frames) / math.ceil(f32(count) / game.speed)
}

game_any_top_pieces :: proc(game: ^Game_State) -> bool {
	for x in 0 ..< GRID_WIDTH {
		index := xy2i_yoffset(x, 0)
		piece := game.grid[index]

		if piece.is_color && piece.state_framecount == 0 {
			return true
		}
	}

	return false
}

game_warn_update :: proc(game: ^Game_State) {
	for x in 0 ..< GRID_WIDTH {
		offset := qdoubled_offset(x)
		index := xy2i(x, 2 + offset)
		piece := game.grid[index]
		game.warn_rows[x] = piece.is_color
	}
}

game_over_update :: proc(game: ^Game_State) {
	if !game_any_top_pieces(game) {
		game.lose_framecount = 0
		return
	}

	if grid_any_clears(game.grid) {
		game.lose_framecount = 0
		return
	}

	if game.lose_framecount < game_speed_apply(game, .Lose) {
		game.lose_framecount += 1
	} else {
		game.lost = true
		game.lose_framecount = 0
	}
}
