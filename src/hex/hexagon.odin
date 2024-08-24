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

directions := [?]Hex {
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

Doubled_Coord :: [2]int

// DOUBLE COORD COL/ROW
// https://www.redblobgames.com/grids/hexagons/#coordinates-doubled

qdoubled_from_cube :: proc(h: Hex) -> Doubled_Coord {
	col := h.x
	row := 2 * h.y + h.x
	return {col, row}
}

qdoubled_to_cube :: proc(h: Doubled_Coord) -> Hex {
	q := h.x
	r := int(f32(h.y - h.x) / 2)
	s := -q - r
	return {q, r, s}
}

rdoubled_from_cube :: proc(h: Hex) -> Doubled_Coord {
	col := 2 * h.x + h.y
	row := h.y
	return {col, row}
}

rdoubled_to_cube :: proc(h: Doubled_Coord) -> Hex {
	q := int(f32(h.x - h.y) / 2)
	r := h.y
	s := -q - r
	return {q, r, s}
}

// DISTANCE
// https://www.redblobgames.com/grids/hexagons/implementation.html#hex-distance

length :: proc "contextless" (hex: Hex) -> int {
	return int((abs(hex.x) + abs(hex.y) + abs(hex.z)) / 2)
	// return int((abs(hex.x) + abs(hex.y) + abs(hex.z)))
}

distance :: proc "contextless" (a, b: Hex) -> int {
	return length(a - b)
}

direction :: proc "contextless" (dir: int) -> Hex {
	return directions[dir]
}

center_direction :: proc "contextless" (a: Hex) -> Hex {
	center := Hex{}
	return {center.x - a.x, center.y - a.y, center.z - a.z}
}

update_z :: proc "contextless" (h: ^Hex) {
	h.z = -h.x - h.y
}

shifted_x :: proc(h: Hex, offset: int) -> Hex {
	goal := h.x + offset
	return {goal, h.y, -goal - h.y}
}

shifted_y :: proc(h: Hex, offset: int) -> Hex {
	goal := h.y + offset
	return {h.x, goal, -h.x - goal}
}

set_x :: proc "contextless" (h: ^Hex, to: int) {
	h.x = to
	update_z(h)
}

set_y :: proc "contextless" (h: ^Hex, to: int) {
	h.y = to
	update_z(h)
}

offset_x :: proc "contextless" (h: ^Hex, offset: int) {
	h.x += offset
	update_z(h)
}

offset_y :: proc "contextless" (h: ^Hex, offset: int) {
	h.y += offset
	update_z(h)
}

direction_towards :: proc "contextless" (a, b: Hex) -> int {
	closest_direction := -1
	diff := a - b
	closest_distance := f32(math.F32_MAX)

	for dir, direction_index in directions {
		dist := math.sqrt_f32(
			math.pow(f32(diff.x - dir.x), 2) +
			math.pow(f32(diff.y - dir.y), 2) +
			math.pow(f32(diff.z - dir.z), 2),
		)

		if dist < closest_distance {
			closest_direction = direction_index
			closest_distance = dist
		}
	}

	return closest_direction
}

neighbor :: proc "contextless" (hex: Hex, dir: int) -> Hex {
	return hex + direction(dir)
}

// HEX TO SCREEN
// https://www.redblobgames.com/grids/hexagons/implementation.html#hex-to-pixel

to_pixel :: proc "contextless" (layout: Layout, h: Hex) -> Point {
	m := layout.orientation.mat
	x := (m[0, 0] * f32(h.x) + m[0, 1] * f32(h.y)) * layout.size.x
	y := (m[0, 2] * f32(h.x) + m[0, 3] * f32(h.y)) * layout.size.y
	return {x + layout.origin.x, y + layout.origin.y}
}

to_float :: proc "contextless" (h: Hex) -> FHex {
	return {f32(h.x), f32(h.y), f32(h.z)}
}

fto_pixel :: proc "contextless" (layout: Layout, h: FHex) -> Point {
	m := layout.orientation.mat
	x := (m[0, 0] * h.x + m[0, 1] * h.y) * layout.size.x
	y := (m[0, 2] * h.x + m[0, 3] * h.y) * layout.size.y
	return {x + layout.origin.x, y + layout.origin.y}
}

// SCREEN TO HEX
// https://www.redblobgames.com/grids/hexagons/implementation.html#pixel-to-hex

pixel_to_hex :: proc "contextless" (layout: Layout, p: Point) -> FHex {
	m := layout.orientation.mat
	pt := Point {
		(p.x - layout.origin.x) / layout.size.x,
		(p.y - layout.origin.y) / layout.size.y,
	}
	q := m[1, 0] * pt.x + m[1, 1] * pt.y
	r := m[1, 2] * pt.x + m[1, 3] * pt.y
	return {q, r, -q - r}
}

// DRAWING
// https://www.redblobgames.com/grids/hexagons/implementation.html#hex-geometry

corner_offset :: proc "contextless" (layout: Layout, corner: int) -> Point {
	angle :=
		2.0 * math.PI * (layout.orientation.start_angle + f32(corner)) / 6.0
	return {
		layout.size.x * math.cos_f32(angle),
		layout.size.y * math.sin_f32(angle),
	}
}

corner_offset_margin :: proc "contextless" (
	layout: Layout,
	corner: int,
	margin: f32,
) -> Point {
	angle :=
		2.0 * math.PI * (layout.orientation.start_angle + f32(corner)) / 6.0
	return {
		(layout.size.x + margin) * math.cos_f32(angle),
		(layout.size.y + margin) * math.sin_f32(angle),
	}
}

polygon_corners :: proc "contextless" (
	layout: Layout,
	h: Hex,
	margin: f32,
) -> (
	corners: [6]Point,
) {
	center := to_pixel(layout, h)

	for i := 0; i < len(corners); i += 1 {
		offset := corner_offset_margin(layout, i, margin)
		corners[i] = {center.x + offset.x, center.y + offset.y}
	}

	return
}

fpolygon_corners :: proc "contextless" (
	layout: Layout,
	h: FHex,
	margin: f32 = -1,
) -> (
	corners: [6]Point,
) {
	center := fto_pixel(layout, h)

	for i := 0; i < len(corners); i += 1 {
		offset := corner_offset_margin(layout, i, margin)
		corners[i] = {center.x + offset.x, center.y + offset.y}
	}

	return
}

// HEX ROUNDING
// https://www.redblobgames.com/grids/hexagons/implementation.html#rounding

round :: proc "contextless" (h: FHex) -> Hex {
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

custom_lerp :: proc "contextless" (a, b, t: f32) -> f32 {
	return a * (1 - t) + b * t
}

lerp :: proc "contextless" (a, b: Hex, t: f32) -> FHex {
	return {
		custom_lerp(f32(a.x), f32(b.x), t),
		custom_lerp(f32(a.y), f32(b.y), t),
		custom_lerp(f32(a.z), f32(b.z), t),
	}
}

linedraw :: proc(output: ^[dynamic]Hex, a, b: Hex) {
	count := distance(a, b)
	clear(output)
	step := 1.0 / max(f32(count), 1)
	for i := 0; i < count; i += 1 {
		append(output, round(lerp(a, b, step * f32(i))))
	}
}

// linedraw :: proc "contextless" (output: ^[dynamic]Hex, a, b: Hex) {
// 	count := distance(a, b)
// 	a_nudge := FHex{f32(a.x) + 1e-6, f32(a.y) + 1e-6, f32(a.z) - 2e-6}
// 	b_nudge := FHex{f32(b.x) + 1e-6, f32(b.y) + 1e-6, f32(b.z) - 2e-6}
// 	clear(output)
// 	step := 1.0 / max(f32(count), 1)
// 	for i := 0; i < count; i += 1 {
// 		append(output, round(lerp(a_nudge, b_nudge, step * f32(i))))
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

			if rand.float32() < 0.75 && !is_center {
				continue
			}

			append(output, Hex{x, y, -x - y})
		}
	}
}

// ROTATION, may need to be swapped
// https://www.redblobgames.com/grids/hexagons/implementation.html#rotation

rotate_left :: proc "contextless" (a: Hex) -> Hex {
	return {-a.z, -a.x, -a.y}
}

rotate_right :: proc "contextless" (a: Hex) -> Hex {
	return {-a.y, -a.z, -a.x}
}
