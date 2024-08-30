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

update :: proc(game: ^Game_State) {
	game.total_ticks += 1
	game_state_score_stats_update(game)
	grid_update(game)
	grid_spawn_update(game)
	particles_update(&game.particles)
	game_speed_update(game)
	game_over_update(game)
	game_warn_update(game)
	ease.flux_update(&game.flux, f64(core.dt))
}

render :: proc(game: ^Game_State) {
	// draw top
	{
		oc.move_to(0, core.game.fixed_yoffset)
		oc.line_to(core.window_size.x, core.game.fixed_yoffset)
		oc.set_width(1)
		oc.set_color_rgba(1, 1, 1, 1)
		oc.stroke()
	}

	game_draw_grid(game)
	particles_render(&game.particles)

	game_draw_cursor(game)
	game_draw_stats_right(game)
}

game_draw_grid :: proc(game: ^Game_State) {
	for &x, i in &game.grid {
		if !x.is_color {
			continue
		}

		corners := piece_render_shape(game, &x, game.layout)

		if game.debug_text {
			small_font_size := core.font_size - 12
			xx := corners[4].x - 5
			yy := corners[4].y + game.hexagon_size / 2

			state_text := piece_state_text(x.state)
			hex_text := fmt.tprintf("%s %d", state_text, x.state_framecount)

			oc.set_font(core.font)
			oc.set_color_rgba(0, 0, 0, 1)
			oc.set_font_size(small_font_size)
			oc.text_fill(xx, yy, hex_text)

			hex_text = fmt.tprintf("%d %d", x.coord.x, x.coord.y)
			// hex_text = fmt.tprintf("%v", x.can_chain)
			oc.text_fill(xx, yy + small_font_size, hex_text)
		}
	}

	spawn_unit := game_speed_unit(game, .Spawn_Time, game.spawn_ticks)
	margin := (spawn_unit * 0.75) * game.hexagon_size
	alpha := 1 - spawn_unit * 0.75
	for x, i in &game.grid_incoming {
		root := hex.qdoubled_to_cube({i, GRID_HEIGHT + 1})
		corners := hex.polygon_corners(game.layout, root, -1 - margin)
		hexagon_path(corners)
		color := piece_outer_colors[x]
		oc.set_color_rgba(color.r, color.g, color.b, alpha)
		oc.fill()
	}
}

draw_cursor :: proc(game: ^Game_State, corners: [6]hex.Point) {
	hexagon_path(corners)
	oc.set_width(game.cursor_width + 2)
	oc.set_color_rgba(0, 0, 0, 1)
	oc.stroke()

	hexagon_path(corners)
	oc.set_width(game.cursor_width)
	oc.set_color_rgba(1, 1, 1, 1)
	oc.stroke()
}

game_draw_cursor :: proc(game: ^Game_State) {
	drag := &game.drag

	if drag.cursor_direction != drag.cursor {
		corners := hex.fpolygon_corners(game.layout, drag.cursor_direction, 0)
		draw_cursor(game, corners)
	}

	fx := hex.pixel_to_hex(game.layout, core.input.mouse.pos)
	mouse_root := hex.qdoubled_from_cube(hex.round(fx))
	mouse_piece := grid_get_color(game.grid, mouse_root)
	stroke_width := mouse_piece != nil ? f32(5) : f32(2)
	if drag.coord != nil {
		stroke_width = 10
	}
	exp_interpolate(&game.cursor_width, stroke_width, core.dt, 1e-3)

	corners := hex.fpolygon_corners(game.layout, drag.cursor, 0)
	draw_cursor(game, corners)
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

ui :: proc(game: ^Game_State) {
	style: Style

	style_font(&style, core.font)
	oc.ui_frame(core.window_size, style, style.mask)

	// ui_menus() 

	{
		oc.ui_panel("main panel", {})

		{
			// style = style_fullsize()
			style = {}
			style_sizex(&style, game.fixed_xoffset)
			style_sizey_full(&style)
			style_layout(&style, .Y)
			style_next(style)
			oc.ui_container("background", {.DRAW_BACKGROUND})

			{
				style = style_fullsize()
				style_layout(&style, .Y, {10, 10})
				style_next(style)
				oc.ui_container("padded", {})

				text := fmt.tprintf("Score: %d", game.score)
				oc.ui_label_str8(text)

				text = fmt.tprintf("DT: %.4f", core.dt)
				oc.ui_label_str8(text)

				text = fmt.tprintf("TICKS SPAWN: %d", game.spawn_ticks)
				oc.ui_label_str8(text)

				text = fmt.tprintf(
					"CHAIN: %d : %d",
					game.chain_count,
					game.chain_delay_framecount,
				)
				oc.ui_label_str8(text)

				text = fmt.tprintf(
					"Speed: %.2f : %d",
					game.speed,
					game.speed_last_increase_at,
				)
				oc.ui_label_str8(text)

				text = fmt.tprintf(
					"GameOver: %v : %d",
					game.lost,
					game.lose_framecount,
				)
				oc.ui_label_str8(text)

				if oc.ui_button("reset").clicked {
					game_state_zero(game)
					game_state_reset(game)
				}

				if oc.ui_button("debug").clicked {
					game.debug_text = !game.debug_text
				}
			}
		}
	}
}

ui_menus :: proc() {
	oc.ui_menu_bar("menubar")

	{
		oc.ui_menu("File")
		if oc.ui_menu_button("Quit").pressed {
			oc.request_quit()
		}
	}
}
