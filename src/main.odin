package src

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import oc "core:sys/orca"
import "hex"

Core :: struct {
	surface:        oc.surface,
	renderer:       oc.canvas_renderer,
	canvas_context: oc.canvas_context,
	window_size:    oc.vec2,
	input:          oc.input_state,
	last_input:     oc.input_state,
	game:           Game_State,
}

core: Core

main :: proc() {
	oc.window_set_title("orca fun")
	core.window_size = {800, 1000}
	oc.window_set_size(core.window_size)

	core.renderer = oc.canvas_renderer_create()
	core.surface = oc.canvas_surface_create(core.renderer)
	core.canvas_context = oc.canvas_context_create()

	ranges := [?]oc.unicode_range {
		oc.UNICODE_BASIC_LATIN,
		oc.UNICODE_C1_CONTROLS_AND_LATIN_1_SUPPLEMENT,
		oc.UNICODE_LATIN_EXTENDED_A,
		oc.UNICODE_LATIN_EXTENDED_B,
		oc.UNICODE_SPECIALS,
	}

	context = runtime.default_context()
	game_state_init(&core.game)

	hex.shape_hexagon(&core.game.grid, 5)
}

@(export)
oc_on_resize :: proc "c" (width, height: u32) {
	core.window_size = {f32(width), f32(height)}
	g := core.game.grid
	// core.game.offset = {
	// 	f32(width / 2) - f32(g.width / 4 * g.piece_size),
	// 	f32(height / 2) - f32(g.height / 2 * g.piece_size),
	// }
}

@(export)
oc_on_frame_refresh :: proc "c" () {
	context = runtime.default_context()
	scratch := oc.scratch_begin()
	defer oc.scratch_end(scratch)

	oc.canvas_context_select(core.canvas_context)
	oc.set_color_rgba(0.1, 0.1, 0.1, 1)
	oc.clear()

	// oc.set_color_rgba(1, 0, 0, 1)
	// oc.rectangle_fill(0, 0, 100, 100)

	// grid_render(&core.game.grid, core.game.offset)

	layout := hex.Layout {
		orientation = hex.layout_pointy,
		size        = 30,
		origin      = 400,
	}
	for x in core.game.grid {
		corners := hex.polygon_corners(layout, x)

		oc.move_to(corners[0].x, corners[0].y)
		for i := 1; i < len(corners); i += 1 {
			c := corners[i]
			oc.line_to(c.x, c.y)
		}
		oc.close_path()

		r := x.x % 2 == 0 ? f32(1) : f32(0)
		g := x.y % 2 == 0 ? f32(1) : f32(0)
		b := x.z % 2 == 0 ? f32(1) : f32(0)

		oc.set_color_rgba(r, g, b, 1)
		oc.fill()
	}

	cursor := core.game.cursor
	// t1x := triangle_x(core.game.offset, f32(core.game.grid.piece_size), cursor.x)
	// t1y := triangle_y(core.game.offset, f32(core.game.grid.piece_size), cursor.y)
	// t2x := triangle_x(core.game.offset, f32(core.game.grid.piece_size), cursor.x + 1)
	// t2y := triangle_y(core.game.offset, f32(core.game.grid.piece_size), cursor.y)
	// even := cursor.x % 2 == 0 
	// oc.set_color_rgba(1, 0, 0, 1)
	// triangle_stroke(t1x, t1y, f32(core.game.grid.piece_size), even)
	// even = !even
	// oc.set_color_rgba(1, 0, 1, 1)
	// triangle_stroke(t2x, t2y, f32(core.game.grid.piece_size), even)

	oc.canvas_render(core.renderer, core.canvas_context, core.surface)
	oc.canvas_present(core.renderer, core.surface)
}

key_up :: proc "c" (core: ^Core, key: oc.key_code) -> bool {
	return !oc.key_down(&core.input, key) && oc.key_down(&core.last_input, key)
}

@(export)
oc_on_raw_event :: proc "c" (event: ^oc.event) {
	scratch := oc.scratch_begin()
	defer oc.scratch_end(scratch)

	core.last_input = core.input
	oc.input_process_event(scratch.arena, &core.input, event)

	// if oc.key_down(&core.input, .LEFT) {
	// 	if core.game.cursor.x > 0 {
	// 		core.game.cursor.x -= 1
	// 	}
	// }

	// if oc.key_down(&core.input, .RIGHT) {
	// 	if core.game.cursor.x < core.game.grid.width - 2 {
	// 		core.game.cursor.x += 1
	// 	}
	// }

	// if oc.key_down(&core.input, .UP) {
	// 	if core.game.cursor.y > 0 {
	// 		core.game.cursor.y -= 1
	// 	}
	// }

	// if oc.key_down(&core.input, .DOWN) {
	// 	if core.game.cursor.y < core.game.grid.height - 1 {
	// 		core.game.cursor.y += 1
	// 	}
	// }

	// editor := &core.editor
	// if oc.key_down(&core.input, ._5) || oc.key_down(&core.input, .ESCAPE) {
	// 	editor.cut_direction = nil
	// }
	// if oc.key_down(&core.input, ._1) {
	// 	editor.cut_direction = .Left
	// }
	// if oc.key_down(&core.input, ._2) {
	// 	editor.cut_direction = .Right
	// }
	// if oc.key_down(&core.input, ._3) {
	// 	editor.cut_direction = .Top
	// }
	// if oc.key_down(&core.input, ._4) {
	// 	editor.cut_direction = .Bottom
	// }
}
