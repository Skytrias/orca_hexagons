package src

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/ease"
import "core:math/rand"
import "core:strings"
import oc "core:sys/orca"
import "core:time"
import "hex"

Core :: struct {
	surface:            oc.surface,
	renderer:           oc.canvas_renderer,
	canvas_context:     oc.canvas_context,
	ui_context:         oc.ui_context,
	window_size:        oc.vec2,
	input:              oc.input_state,
	last_input:         oc.input_state,
	game:               Game_State,
	dt:                 f32,
	font:               oc.font,
	font_size:          f32,
	update_accumulator: f32,
	logger:             log.Logger,
}

core: Core

@(fini)
on_terminate :: proc() {
	game_state_destroy(&core.game)
}

main :: proc() {
	oc.window_set_title("orca fun")
	core.window_size = {1000, 1000}
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

	core.font = oc.font_create_from_path("liberation-mono.ttf", 5, &ranges[0])
	core.font_size = 24

	context = runtime.default_context()
	core.logger = oc.create_odin_logger()
	context.logger = core.logger

	game_state_init(&core.game)

	oc.ui_init(&core.ui_context)

	rand.reset(u64(time.now()._nsec))
}

@(export)
oc_on_resize :: proc "c" (width, height: u32) {
	core.window_size = {f32(width), f32(height)}
	g := core.game.grid
	core.game.offset = {f32(width / 2), f32(height / 2)}
}

update :: proc() {
	game_state_score_stats_update(&core.game)
	grid_update(&core.game)
	grid_spawn_update(&core.game)
	particles_update(&core.game.particles)
	ease.flux_update(&core.game.flux, f64(core.dt))
}

@(export)
oc_on_frame_refresh :: proc "c" () {
	context = runtime.default_context()
	context.logger = core.logger
	scratch := oc.scratch_begin()
	defer oc.scratch_end(scratch)

	oc.canvas_context_select(core.canvas_context)
	oc.set_color_rgba(0.1, 0.1, 0.1, 1)
	oc.clear()

	oc.ui_frame(core.window_size, {font = core.font}, {.FONT})

	if core.ui_context.lastFrameDuration < 10 {
		core.dt = min(1, f32(core.ui_context.lastFrameDuration))
		core.update_accumulator += core.dt
		//		log.infof("%v %v %v", core.dt, core.update_accumulator, core.ui_context.lastFrameDuration)
	}

	//	for core.update_accumulator >= TICK_TIME {
	update()
	//		core.update_accumulator -= TICK_TIME
	//	}

	core.game.layout = hex.Layout {
		orientation = hex.layout_flat,
		size        = core.game.hexagon_size,
		origin      = core.game.offset,
	}

	game_mouse_check(
		&core.game,
		core.game.layout,
		core.input.mouse.pos,
		oc.mouse_down(&core.input, .LEFT),
	)

	game_draw_grid(&core.game)
	game_draw_bottom(&core.game)

	particles_render(&core.game.particles)

	game_draw_cursor(&core.game)
	game_draw_stats_left(&core.game)
	game_draw_stats_right(&core.game)

	oc.ui_draw()

	oc.canvas_render(core.renderer, core.canvas_context, core.surface)
	oc.canvas_present(core.renderer, core.surface)
}

key_down :: proc "contextless" (
	keyboard_state: ^oc.keyboard_state,
	key: oc.key_code,
) -> bool {
	state := keyboard_state.keys[key]
	return state.down
}

key_pressed :: proc "contextless" (
	keyboard_state: ^oc.keyboard_state,
	last_keyboard_state: ^oc.keyboard_state,
	key: oc.key_code,
) -> bool {
	state := keyboard_state.keys[key]
	last_state := last_keyboard_state.keys[key]
	return state.down && !last_state.down
}

@(export)
oc_on_raw_event :: proc "c" (event: ^oc.event) {
	scratch := oc.scratch_begin()
	defer oc.scratch_end(scratch)

	ui := &core.ui_context
	oc.input_process_event(&ui.frameArena, &ui.input, event)

	core.last_input = core.input
	oc.input_process_event(scratch.arena, &core.input, event)

	keyboard_state := &core.input.keyboard
	last_keyboard_state := &core.last_input.keyboard
	keys := keyboard_state.keys

	if key_pressed(keyboard_state, last_keyboard_state, .ENTER) {
		context = runtime.default_context()
		grid_init(&core.game.grid)
	}
}

// ---

game_draw_grid :: proc(game: ^Game_State) {
	MARGIN :: 2
	for &x, i in &game.grid {
		corners := piece_render_shape(&x, game.layout)

		if x.state == .Hang || x.state == .Fall {
			one := corners[4]
			two := corners[5]
			oc.move_to(one.x, one.y + 2)
			oc.line_to(two.x, two.y + 2)

			if x.state == .Hang {
				oc.set_color_rgba(1, 1, 1, 1)
			} else {
				oc.set_color_rgba(0, 0, 0, 1)
			}
			oc.set_width(2)
			oc.stroke()
		}

		// small_font_size := core.font_size - 10
		// coord := hex.qdoubled_from_cube(x)
		// oc.set_font(core.font)
		// oc.set_color_rgba(0, 0, 0, 1)
		// oc.set_font_size(small_font_size)
		// center := hex.to_pixel(layout, x)
		// hex_text := fmt.tprintf("%d %d", coord.x, coord.y)
		// oc.text_fill(center.x - 15, center.y, hex_text)
		// hex_text = fmt.tprintf("%d", x.ref_index)
		// oc.text_fill(center.x - 15, center.y + small_font_size, hex_text)
	}
}

game_draw_bottom :: proc(game: ^Game_State) {
	for x in -BOUNDS_LIMIT ..= BOUNDS_LIMIT {
		root := hex.qdoubled_to_cube({x, FALL_LIMIT + 1})
		corners := hex.polygon_corners(game.layout, root, 0)
		hexagon_path(corners)
		oc.set_color_rgba(0, 0, 0, 1)
		oc.fill()
	}
}

game_draw_cursor :: proc(game: ^Game_State) {
	goal := game.piece_dragging_cursor
	corners := hex.fpolygon_corners(game.layout, goal, 0)
	hexagon_path(corners)

	fx := hex.pixel_to_hex(game.layout, core.input.mouse.pos)
	mouse_index := grid_find_index(game.grid[:], hex.round(fx))
	stroke_width := mouse_index != -1 ? f32(5) : f32(2)
	if game.piece_dragging != nil {
		stroke_width = 10
	}
	exp_interpolate(&game.cursor_width, stroke_width, core.dt, 1e-3)

	oc.set_width(game.cursor_width + 2)
	oc.set_color_rgba(0, 0, 0, 1)
	oc.stroke()

	hexagon_path(corners)
	oc.set_width(game.cursor_width)
	oc.set_color_rgba(1, 1, 1, 1)
	oc.stroke()

	if game.piece_dragging_direction != -1 {
		x := game.piece_dragging
		direction := hex.directions[game.piece_dragging_direction]
		x_offset := x.root - direction
		corners := hex.polygon_corners(game.layout, x_offset, 0)
		hexagon_path(corners)

		oc.set_width(game.cursor_width + 2)
		oc.set_color_rgba(0, 0, 0, 1)
		oc.stroke()

		hexagon_path(corners)
		oc.set_width(game.cursor_width)
		oc.set_color_rgba(1, 1, 1, 1)
		oc.stroke()
	}
}

game_draw_stats_left :: proc(game: ^Game_State) {
	y := f32(10) + core.font_size
	x := f32(10)

	oc.set_font(core.font)
	oc.set_font_size(core.font_size)
	oc.set_color_rgba(1, 1, 1, 1)

	text := fmt.tprintf("Score: %d", game.score)
	oc.text_fill(x, y, text)

	y += core.font_size

	text = fmt.tprintf("FPS: %.4f", core.dt)
	oc.text_fill(x, y, text)
}

game_draw_stats_right :: proc(game: ^Game_State) {
	oc.set_font(core.font)
	oc.set_font_size(core.font_size)

	offset := f32(0)
	for index := len(game.score_stats) - 1; index >= 0; index -= 1 {
		stat := game.score_stats[index]
		unit := time.duration_milliseconds(time.since(stat.timestamp)) / 2000

		oc.set_color_rgba(1, 1, 1, min(1, 1 - f32(unit)))
		oc.text_fill(
			core.window_size.x - 200,
			10 + f32(offset + 1) * core.font_size,
			stat.text,
		)

		offset += 1
	}
}
