package hex

import "core:math"
import "core:math/rand"

Point :: [2]f32
Hex :: [3]int // q r s
FHex :: [3]f32 // q r s

Orientation :: struct {
	mat:         matrix[2, 4]f32, // TODO use f64?
	start_angle: f32,
}

hex_directions := [?]Hex {
	Hex{1, 0, -1},
	Hex{1, -1, 0},
	Hex{0, -1, 1},
	Hex{-1, 0, 1},
	Hex{-1, 1, 0},
	Hex{0, 1, -1},
}

// LAYOUT
// https://www.redblobgames.com/grids/hexagons/implementation.html#layout

layout_pointy := Orientation {
	mat         = {
		math.sqrt_f32(3),
		math.sqrt_f32(3) / 2.0,
		0.0,
		3.0 / 2.0,
		math.sqrt_f32(3) / 3.0,
		-1.0 / 3.0,
		0.0,
		2.0 / 3.0,
	},
	start_angle = 0.5,
}

layout_flat := Orientation {
	mat         = {
		3.0 / 2.0,
		0.0,
		math.sqrt_f32(3) / 2.0,
		math.sqrt_f32(3),
		2.0 / 3.0,
		0.0,
		-1.0 / 3.0,
		math.sqrt_f32(3) / 3.0,
	},
	start_angle = 0,
}

Layout :: struct {
	orientation: Orientation,
	size:        Point,
	origin:      Point,
}

// DISTANCE
// https://www.redblobgames.com/grids/hexagons/implementation.html#hex-distance

hex_length :: proc(hex: Hex) -> int {
	return int((abs(hex.x) + abs(hex.y) + abs(hex.z)) / 2)
}

hex_distance :: proc(a, b: Hex) -> int {
	return hex_length(a - b)
}

hex_direction :: proc(direction: int) -> Hex {
	return hex_direction(direction)
}

hex_center_direction :: proc(a: Hex) -> Hex {
	center := Hex{}
	return {center.x - a.x, center.y - a.y, center.z - a.z}
}

closest_direction :: proc(diff: Hex) -> Hex {
	closest := hex_directions[0]
	min_dist := hex_distance(diff, closest)

	for dir in hex_directions {
		dist := hex_distance(diff, dir)
		if dist < min_dist {
			closest = dir
			min_dist = dist
		}
	}

	return closest
}

hex_neighbor :: proc(hex: Hex, direction: int) -> Hex {
	return hex + hex_direction(direction)
}

// HEX TO SCREEN
// https://www.redblobgames.com/grids/hexagons/implementation.html#hex-to-pixel

hex_to_pixel :: proc(layout: Layout, h: Hex) -> Point {
	m := layout.orientation.mat
	x := (m[0, 0] * f32(h.x) + m[0, 1] * f32(h.y)) * layout.size.x
	y := (m[0, 2] * f32(h.x) + m[0, 3] * f32(h.y)) * layout.size.y
	return {x + layout.origin.x, y + layout.origin.y}
}

// SCREEN TO HEX
// https://www.redblobgames.com/grids/hexagons/implementation.html#pixel-to-hex

pixel_to_hex :: proc(layout: Layout, p: Point) -> FHex {
	m := layout.orientation.mat
	pt := Point{(p.x - layout.origin.x) / layout.size.x, (p.y - layout.origin.y) / layout.size.y}
	q := m[1, 0] * pt.x + m[1, 1] * pt.y
	r := m[1, 2] * pt.x + m[1, 3] * pt.y
	return {q, r, -q - r}
}

// DRAWING
// https://www.redblobgames.com/grids/hexagons/implementation.html#hex-geometry

hex_corner_offset :: proc(layout: Layout, corner: int) -> Point {
	angle := 2.0 * math.PI * (layout.orientation.start_angle + f32(corner)) / 6.0
	return {layout.size.x * math.cos_f32(angle), layout.size.y * math.sin_f32(angle)}
}

hex_corner_offset_margin :: proc(layout: Layout, corner: int, margin: f32) -> Point {
	angle := 2.0 * math.PI * (layout.orientation.start_angle + f32(corner)) / 6.0
	return {
		(layout.size.x + margin) * math.cos_f32(angle),
		(layout.size.y + margin) * math.sin_f32(angle),
	}
}

polygon_corners :: proc(layout: Layout, h: Hex, margin: f32) -> (corners: [6]Point) {
	center := hex_to_pixel(layout, h)

	for i := 0; i < len(corners); i += 1 {
		offset := hex_corner_offset_margin(layout, i, margin)
		corners[i] = {center.x + offset.x, center.y + offset.y}
	}

	return
}

// HEX ROUNDING
// https://www.redblobgames.com/grids/hexagons/implementation.html#rounding

hex_round :: proc(h: FHex) -> Hex {
	q := int(math.round_f32(h.x))
	r := int(math.round_f32(h.y))
	s := int(math.round_f32(h.z))
	q_diff := abs(q - int(h.x))
	r_diff := abs(r - int(h.y))
	s_diff := abs(s - int(h.z))

	if q_diff > r_diff && q_diff > s_diff {
		q = -r - s
	} else if r_diff > s_diff {
		r = -q - s
	} else {
		s = -q - r
	}

	return {q, r, s}
}

// LINE DRAWING
// https://www.redblobgames.com/grids/hexagons/implementation.html#line-drawing

custom_lerp :: proc(a, b, t: f32) -> f32 {
	return a * (1 - t) + b * t
}

hex_lerp :: proc(a, b: Hex, t: f32) -> FHex {
	return {
		custom_lerp(f32(a.x), f32(b.x), t),
		custom_lerp(f32(a.y), f32(b.y), t),
		custom_lerp(f32(a.z), f32(b.z), t),
	}
}

hex_linedraw :: proc(output: ^[dynamic]Hex, a, b: Hex) {
	count := hex_distance(a, b)
	clear(output)
	step := 1.0 / max(f32(count), 1)
	for i := 0; i < count; i += 1 {
		append(output, hex_round(hex_lerp(a, b, step * f32(i))))
	}
}

// hex_linedraw :: proc(output: ^[dynamic]Hex, a, b: Hex) {
// 	count := hex_distance(a, b)
// 	a_nudge := FHex{f32(a.x) + 1e-6, f32(a.y) + 1e-6, f32(a.z) - 2e-6}
// 	b_nudge := FHex{f32(b.x) + 1e-6, f32(b.y) + 1e-6, f32(b.z) - 2e-6}
// 	clear(output)
// 	step := 1.0 / max(f32(count), 1)
// 	for i := 0; i < count; i += 1 {
// 		append(output, hex_round(hex_lerp(a_nudge, b_nudge, step * f32(i))))
// 	}
// }

// MAP SHAPES
// https://www.redblobgames.com/grids/hexagons/implementation.html#map-shapes

shape_parallelogram :: proc(output: ^[dynamic]Hex, x1, x2, y1, y2: int) {
	for x := x1; x <= x2; x += 1 {
		for y := y1; y <= y2; y += 1 {
			append(output, Hex{x, y, -x - y})
		}
	}
}

shape_triangle :: proc(output: ^[dynamic]Hex, size: int) {
	for x := 0; x <= size; x += 1 {
		for y := 0; y <= size; y += 1 {
			append(output, Hex{x, y, -x - y})
		}
	}
}

shape_hexagon :: proc(output: ^[dynamic]Hex, size: int) {
	for x := -size; x <= size; x += 1 {
		r1 := max(-size, -x - size)
		r2 := min(size, -x + size)

		for y := r1; y <= r2; y += 1 {
			append(output, Hex{x, y, -x - y})
		}
	}
}

shape_hexagon_empty :: proc(output: ^[dynamic]Hex, size: int) {
	for x := -size; x <= size; x += 1 {
		r1 := max(-size, -x - size)
		r2 := min(size, -x + size)

		for y := r1; y <= r2; y += 1 {
			is_center := x == 0 && y == 0

			if rand.float32() < 0.5 && !is_center {
				continue
			}

			append(output, Hex{x, y, -x - y})
		}
	}
}

// ROTATION, may need to be swapped
// https://www.redblobgames.com/grids/hexagons/implementation.html#rotation

hex_rotate_left :: proc(a: Hex) -> Hex {
	return {-a.z, -a.x, -a.y}
}

hex_rotate_right :: proc(a: Hex) -> Hex {
	return {-a.y, -a.z, -a.x}
}

hex_find_index :: proc(h: []Hex, search: Hex) -> int {
	for i := 0; i < len(h); i += 1 {
		if h[i] == search {
			return i
		}
	}

	return -1
}
