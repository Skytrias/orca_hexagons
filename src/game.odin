package src

import oc "core:sys/orca"
import "hex"

Game_State :: struct {
	cursor: [2]int,
	offset: oc.vec2,
	grid:   [dynamic]hex.Hex,
}

// Piece_Type :: enum {
// 	Empty,
// 	Filled,
// }

// Piece :: struct {
// 	type:  Piece_Type,
// 	color: [3]f32,
// }

game_state_init :: proc(state: ^Game_State) {
	state.grid = make([dynamic]hex.Hex, 0, 32)
}

// i2xy :: proc(index: int, width: int) -> (x, y: int) {
// 	x = index % width
// 	y = index / width
// 	return
// }

// xy2i :: proc(x, y, width: int) -> (index: int) {
// 	index = x + y * width
// 	return
// }

// triangle_x :: proc(offset: oc.vec2, size: f32, x: int) -> f32 {
// 	return offset.x + f32(x) * size / 2
// }

// triangle_y :: proc(offset: oc.vec2, size: f32, y: int) -> f32 {
// 	return offset.y + f32(y) * size
// }

// grid_render :: proc(grid: ^Grid, offset: oc.vec2) {
// 	// for piece, i in grid.pieces {
// 	// 	x, y := i2xy(i, grid.width)
// 	// 	even := i % 2 == 0
// 	// 	if even {
// 	// 		oc.set_color_rgba(0, 0, 1, 1)
// 	// 	} else {
// 	// 		oc.set_color_rgba(0, 1, 0, 1)
// 	// 	}

// 	// 	triangle_fill(
// 	// 		triangle_x(offset, f32(grid.piece_size), x),
// 	// 		triangle_y(offset, f32(grid.piece_size), y),
// 	// 		f32(grid.piece_size),
// 	// 		even,
// 	// 	)
// 	// }
// }

// triangle_path :: proc(cx, cy: f32, size: f32, flip: bool) {
// 	// TODO could do matrix here?
// 	flipsign: f32 = flip ? 1 : -1
// 	oc.move_to(cx, cy + size / 2 * -flipsign)
// 	oc.line_to(cx - size / 2, cy + size / 2 * flipsign)
// 	oc.line_to(cx + size / 2, cy + size / 2 * flipsign)
// 	oc.close_path()
// }

// triangle_fill :: proc(cx, cy: f32, size: f32, flip: bool) {
// 	triangle_path(cx, cy, size, flip)
// 	oc.fill()
// }

// triangle_stroke :: proc(cx, cy: f32, size: f32, flip: bool) {
// 	triangle_path(cx, cy, size, flip)
// 	oc.stroke()
// }
