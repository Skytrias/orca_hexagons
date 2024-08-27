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
	random_state:       rand.Default_Random_State,
	random_generator:   rand.Generator,
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
	core.random_state = rand.create(u64(time.now()._nsec))
	core.random_generator = rand.default_random_generator(&core.random_state)
	context.random_generator = core.random_generator

	game_state_init(&core.game)
	oc.ui_init(&core.ui_context)

}

@(export)
oc_on_resize :: proc "c" (width, height: u32) {
	core.window_size = {f32(width), f32(height)}
}

@(export)
oc_on_frame_refresh :: proc "c" () {
	context = runtime.default_context()
	context.logger = core.logger
	context.random_generator = core.random_generator
	scratch := oc.scratch_begin()
	defer oc.scratch_end(scratch)

	oc.canvas_context_select(core.canvas_context)
	oc.set_color_rgba(0.1, 0.1, 0.1, 1)
	oc.clear()

	if core.ui_context.lastFrameDuration < 10 {
		core.dt = min(1, f32(core.ui_context.lastFrameDuration))
		core.update_accumulator += core.dt
	}

	game_update_offset(&core.game)
	grid_set_coordinates(&core.game.grid)

	// TODO good or bad?
	for core.update_accumulator >= TICK_TIME {
		update(&core.game)
		core.update_accumulator -= TICK_TIME
	}

	key_down := oc.key_down(&core.input, .Q)
	is_down := oc.mouse_down(&core.input, .LEFT) || key_down
	game_mouse_check(
		&core.game,
		core.game.layout,
		core.input.mouse.pos,
		is_down,
	)

	render(&core.game)
	ui(&core.game)
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

	// ui := &core.ui_context
	// oc.input_process_event(&ui.frameArena, &ui.input, event)

	oc.ui_process_event(event)

	core.last_input = core.input
	oc.input_process_event(scratch.arena, &core.input, event)

	keyboard_state := &core.input.keyboard
	last_keyboard_state := &core.last_input.keyboard
	keys := keyboard_state.keys

	if key_pressed(keyboard_state, last_keyboard_state, .ENTER) {
		context = runtime.default_context()
		grid_init(core.game.grid)
	}

	core.game.spawn_speedup =
		oc.key_down(&core.input, .SPACE) ? SPAWN_SPEEDUP : 1
}
