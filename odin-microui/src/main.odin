package main

import "core:strings"

import mu "vendor:microui"
import rl "vendor:raylib"

FONT_SIZE :: 20
WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600

// microUI only measures and emits draw commands; raylib does the
// actual drawing. These callbacks bridge the two, using raylib's
// default font, so no font file is needed.
text_width :: proc(font: mu.Font, str: string) -> i32 {
	cstr := strings.clone_to_cstring(str, context.temp_allocator)
	return rl.MeasureText(cstr, FONT_SIZE)
}

text_height :: proc(font: mu.Font) -> i32 {
	return FONT_SIZE
}

to_rl_color :: proc(c: mu.Color) -> rl.Color {
	return rl.Color{c.r, c.g, c.b, c.a}
}

main :: proc() {
	// microUI's context is ~270 KB of fixed-size state, so it lives
	// on the heap, not the stack.
	ctx := new(mu.Context)
	defer free(ctx)
	mu.init(ctx)
	ctx.text_width = text_width
	ctx.text_height = text_height

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Hello world")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	for !rl.WindowShouldClose() {
		// Feed raylib's input into microUI.
		mouse := rl.GetMousePosition()
		mu.input_mouse_move(ctx, i32(mouse.x), i32(mouse.y))
		if rl.IsMouseButtonPressed(.LEFT) {
			mu.input_mouse_down(ctx, i32(mouse.x), i32(mouse.y), .LEFT)
		}
		if rl.IsMouseButtonReleased(.LEFT) {
			mu.input_mouse_up(ctx, i32(mouse.x), i32(mouse.y), .LEFT)
		}
		if wheel := rl.GetMouseWheelMove(); wheel != 0 {
			mu.input_scroll(ctx, 0, i32(wheel * 20))
		}

		mu.begin(ctx)
		if mu.begin_window(ctx, "Hello world", mu.Rect{50, 50, 400, 200}) {
			mu.layout_row(ctx, {-1}, 0)
			mu.label(ctx, "Hello, world!")
			mu.end_window(ctx)
		}
		mu.end(ctx)

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		// Draw every command microUI produced this frame.
		cmd: ^mu.Command
		scissoring := false
		for mu.next_command(ctx, &cmd) {
			switch v in cmd.variant {
			case ^mu.Command_Rect:
				rl.DrawRectangle(v.rect.x, v.rect.y, v.rect.w, v.rect.h, to_rl_color(v.color))
			case ^mu.Command_Text:
				cstr := strings.clone_to_cstring(v.str, context.temp_allocator)
				rl.DrawText(cstr, v.pos.x, v.pos.y, FONT_SIZE, to_rl_color(v.color))
			case ^mu.Command_Icon:
				color := to_rl_color(v.color)
				switch v.id {
				case .CLOSE:
					rl.DrawLine(v.rect.x, v.rect.y, v.rect.x + v.rect.w, v.rect.y + v.rect.h, color)
					rl.DrawLine(v.rect.x + v.rect.w, v.rect.y, v.rect.x, v.rect.y + v.rect.h, color)
				case .CHECK:
					rl.DrawLine(v.rect.x, v.rect.y + v.rect.h / 2, v.rect.x + v.rect.w / 2, v.rect.y + v.rect.h, color)
					rl.DrawLine(v.rect.x + v.rect.w / 2, v.rect.y + v.rect.h, v.rect.x + v.rect.w, v.rect.y, color)
				case .COLLAPSED:
					rl.DrawTriangle(
						rl.Vector2{f32(v.rect.x), f32(v.rect.y)},
						rl.Vector2{f32(v.rect.x), f32(v.rect.y + v.rect.h)},
						rl.Vector2{f32(v.rect.x + v.rect.w), f32(v.rect.y + v.rect.h / 2)},
						color,
					)
				case .EXPANDED:
					rl.DrawTriangle(
						rl.Vector2{f32(v.rect.x), f32(v.rect.y)},
						rl.Vector2{f32(v.rect.x + v.rect.w), f32(v.rect.y)},
						rl.Vector2{f32(v.rect.x + v.rect.w / 2), f32(v.rect.y + v.rect.h)},
						color,
					)
				case .RESIZE:
					rl.DrawLine(v.rect.x + v.rect.w, v.rect.y, v.rect.x, v.rect.y + v.rect.h, color)
					rl.DrawLine(v.rect.x + v.rect.w, v.rect.y + v.rect.h / 2, v.rect.x + v.rect.w / 2, v.rect.y + v.rect.h, color)
				case .NONE:
				}
			case ^mu.Command_Clip:
				// microUI resets clipping with a huge "unclipped" rect.
				if v.rect.w >= 0x1000000 {
					if scissoring {
						rl.EndScissorMode()
						scissoring = false
					}
				} else {
					rl.BeginScissorMode(v.rect.x, v.rect.y, v.rect.w, v.rect.h)
					scissoring = true
				}
			case ^mu.Command_Jump:
				// next_command already follows jumps, so this is unreachable.
			}
		}
		if scissoring {
			rl.EndScissorMode()
		}

		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
}
