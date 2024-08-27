package src

import "core:math"
import oc "core:sys/orca"
import "hex"

exp_interpolate :: proc(cur: ^f32, nxt, dt, rate: f32) {
	cur^ += (nxt - cur^) * (1 - math.pow_f32(rate, dt))
}

xy2i_yoffset :: proc(x, y: int) -> int {
	y := y
	if x % 2 != 0 {
		y += 1
	}
		
	row := y / 2
	return row * GRID_WIDTH + x
}

xy2i :: proc(x, y: int) -> int {
	row := y / 2
	return row * GRID_WIDTH + x
}

coord2i :: proc(coord: hex.Doubled_Coord) -> int {
	row := coord.y / 2
	return row * GRID_WIDTH + coord.x
}

//i2xy :: proc(index: int) -> (x, y: int) {
//	y = index / GRID_WIDTH
//	x = index % GRID_WIDTH
//	return
//}
//

i2coord :: proc(index: int) -> (coord: hex.Doubled_Coord) {
	coord.x = index % GRID_WIDTH
	coord.y = (index / GRID_WIDTH) * 2

	if coord.x % 2 != 0 {
		coord.y += 1
	}

	return
}

coord_below :: proc(coord: hex.Doubled_Coord) -> hex.Doubled_Coord {
	return {coord.x, coord.y + 2}
}

color_flat :: proc(r, g, b: u8) -> [3]f32 {
	return {f32(r) / 255, f32(g) / 255, f32(b) / 255}
}
