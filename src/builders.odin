package src

import oc "core:sys/orca"

Style :: struct {
	using style: oc.ui_style,
	mask:        oc.ui_style_mask,
	box:         oc.ui_flags,
}

style_fullsize :: proc() -> (res: Style) {
	res.size = {{kind = .PARENT, value = 1}, {kind = .PARENT, value = 1}}
	res.mask += oc.SIZE
	return
}

style_sizex_full :: proc(style: ^Style, value: f32 = 1, relax: f32 = 0) {
	style.size.x = {
		kind  = .PARENT,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_WIDTH}
}

style_sizex :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.x = {
		kind  = .PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_WIDTH}
}

style_sizemx :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.x = {
		kind  = .PARENT_MINUS_PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_WIDTH}
}

style_sizey_full :: proc(style: ^Style, value: f32 = 1, relax: f32 = 0) {
	style.size.y = {
		kind  = .PARENT,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_HEIGHT}
}

style_sizey :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.y = {
		kind  = .PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_HEIGHT}
}

style_sizemy :: proc(style: ^Style, value: f32, relax: f32 = 0) {
	style.size.y = {
		kind  = .PARENT_MINUS_PIXELS,
		value = value,
		relax = relax,
	}
	style.mask += {.SIZE_HEIGHT}
}

style_layout :: proc(
	style: ^Style,
	axis: oc.ui_axis,
	margin: [2]f32 = {},
	spacing: f32 = 0,
) {
	style.layout.axis = axis
	style.mask += {.LAYOUT_AXIS}

	if margin.x != 0 {
		style.layout.margin.x = margin.x
		style.mask += {.LAYOUT_MARGIN_X}
	}

	if margin.y != 0 {
		style.layout.margin.y = margin.y
		style.mask += {.LAYOUT_MARGIN_Y}
	}

	if spacing != 0 {
		style.layout.spacing = spacing
		style.mask += {.LAYOUT_SPACING}
	}
}

style_align :: proc(style: ^Style, x, y: oc.ui_align) {
	style.layout.align = {x, y}
	style.mask += {.LAYOUT_ALIGN_X, .LAYOUT_ALIGN_Y}
}

style_alignx :: proc(style: ^Style, value: oc.ui_align) {
	style.layout.align.x = value
	style.mask += {.LAYOUT_ALIGN_X}
}

style_aligny :: proc(style: ^Style, value: oc.ui_align) {
	style.layout.align.y = value
	style.mask += {.LAYOUT_ALIGN_Y}
}

style_color :: proc(style: ^Style, color: oc.color) {
	style._color = color
	style.mask += {.COLOR}
}

style_bg_color :: proc(style: ^Style, color: oc.color) {
	style.bgColor = color
	style.mask += {.BG_COLOR}
	style.box += {.DRAW_BACKGROUND}
}

// time should be above 0!
style_animate :: proc(style: ^Style, time: f32, mask: oc.ui_style_mask) {
	style.animationTime = time
	style.animationMask = mask
	style.mask += {.ANIMATION_TIME, .ANIMATION_MASK}
	style.box += {.HOT_ANIMATION, .ACTIVE_ANIMATION}
}

style_border :: proc(style: ^Style, size: f32, color: Maybe(oc.color) = nil) {
	style.borderSize = size
	style.mask += {.BORDER_SIZE}

	if c, ok := color.?; ok {
		style.borderColor = c
		style.mask += {.BORDER_COLOR}
	}

	style.box += {.DRAW_BORDER}
}

style_roundness :: proc(style: ^Style, roundness: f32) {
	style.roundness = roundness
	style.mask += {.ROUNDNESS}
}

style_floatxy :: proc(style: ^Style, x, y: f32) {
	style.floatTarget = {x, y}
	style.floating = {true, true}
	style.mask += oc.FLOAT
}

style_next :: proc(style: Style) {
	oc.ui_style_next(style, style.mask)
}

style_before_on_hover :: proc(ui: ^oc.ui_context, style: Style) {
	pattern: oc.ui_pattern
	oc.ui_pattern_push(
		&ui.frameArena,
		&pattern,
		{kind = .STATUS, status = {.HOVER}},
	)
	oc.ui_style_match_before(pattern, style, style.mask)
}

style_before_on_hover_active :: proc(ui: ^oc.ui_context, style: Style) {
	pattern: oc.ui_pattern
	oc.ui_pattern_push(
		&ui.frameArena,
		&pattern,
		{kind = .STATUS, status = {.ACTIVE}},
	)
	oc.ui_pattern_push(
		&ui.frameArena,
		&pattern,
		{op = .AND, kind = .STATUS, status = {.HOVER}},
	)
	oc.ui_style_match_before(pattern, style, style.mask)
}

style_key_before :: proc(ui: ^oc.ui_context, key: string, style: Style) {
	pattern: oc.ui_pattern
	oc.ui_pattern_push(
		&ui.frameArena,
		&pattern,
		{kind = .KEY, key = oc.ui_key_make_str8(key)},
	)
	oc.ui_style_match_before(pattern, style, style.mask)
}

style_tag_before :: proc(ui: ^oc.ui_context, tag: oc.ui_tag, style: Style) {
	pattern: oc.ui_pattern
	oc.ui_pattern_push(&ui.frameArena, &pattern, {kind = .TAG, tag = tag})
	oc.ui_style_match_before(pattern, style, style.mask)
}

style_key_after :: proc(ui: ^oc.ui_context, key: string, style: Style) {
	pattern: oc.ui_pattern
	oc.ui_pattern_push(
		&ui.frameArena,
		&pattern,
		{kind = .KEY, key = oc.ui_key_make_str8(key)},
	)
	oc.ui_style_match_after(pattern, style, style.mask)
}

menu_label :: proc(ui: ^oc.ui_context, text: string) {
	style: Style
	style_sizey_full(&style)
	style_aligny(&style, .CENTER)
	style_key_after(ui, text, style)
	oc.ui_label_str8(text)
}
