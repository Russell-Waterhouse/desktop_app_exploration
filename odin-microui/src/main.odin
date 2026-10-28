package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

import mu "vendor:microui"
import rl "vendor:raylib"

FONT_SIZE :: 20
WINDOW_WIDTH :: 900
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

// Feed one raylib key into microUI as a pressed/released key.
// microUI clears the pressed bits at the end of each frame, so a
// key pressed this frame is seen exactly once.
feed_key :: proc(ctx: ^mu.Context, rl_key: rl.KeyboardKey, mu_key: mu.Key) {
	if rl.IsKeyPressed(rl_key) {
		mu.input_key_down(ctx, mu_key)
	}
	if rl.IsKeyReleased(rl_key) {
		mu.input_key_up(ctx, mu_key)
	}
}

// Wrap a paragraph into label lines that fit the detail pane.
// microUI's own mu.text wrapping does not line up with raylib's
// default-font measurements here (it wrapped some steps and
// clipped others at the pane edge), so wrap explicitly with
// MeasureText instead, at a conservative width inside the pane.
draw_wrapped :: proc(ctx: ^mu.Context, text: string, max_width: i32) {
	words := strings.split(text, " ", context.temp_allocator)
	current := ""
	for word in words {
		candidate := word
		if current != "" {
			candidate = fmt.tprintf("%s %s", current, word)
		}
		if current != "" && text_width(nil, candidate) > max_width {
			mu.label(ctx, current)
			current = word
		} else {
			current = candidate
		}
	}
	if current != "" {
		mu.label(ctx, current)
	}
}

// Case-insensitive title search, like the Rust version: an empty
// query matches everything, otherwise the title must contain it.
matches_search :: proc(title, query: string) -> bool {
	if len(query) == 0 {
		return true
	}
	return strings.contains(
		strings.to_lower(title, context.temp_allocator),
		strings.to_lower(query, context.temp_allocator),
	)
}

main :: proc() {
	// microUI's context is ~270 KB of fixed-size state, so it lives
	// on the heap, not the stack.
	ctx := new(mu.Context)
	defer free(ctx)
	mu.init(ctx)
	ctx.text_width = text_width
	ctx.text_height = text_height

	// Load from SQLite, seeding from recipes.odin on first run.
	// A load failure leaves recipes empty and db_error set, and
	// the detail pane shows that error instead of crashing,
	// like the Rust version.
	recipes: []Recipe
	db_error := ""
	db, db_open_err := open_database("recipes.db")
	defer close_database(db)
	if db_open_err != "" {
		db_error = db_open_err
	} else if err := ensure_schema_and_seed(db, RECIPES[:]); err != "" {
		db_error = err
	} else {
		loaded, load_err := load_recipes(db)
		if load_err != "" {
			db_error = load_err
		} else {
			recipes = loaded
		}
	}
	selected := -1
	if len(recipes) > 0 {
		selected = 0
	}
	search_buf: [256]u8
	search_len := 0

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Recipe Manager")
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
		// Typed characters go to microUI's text input (the search box).
		for ch := rl.GetCharPressed(); ch != 0; ch = rl.GetCharPressed() {
			buf, n := utf8.encode_rune(ch)
			mu.input_text(ctx, string(buf[:n]))
		}
		// Keys microUI's textbox understands.
		feed_key(ctx, .BACKSPACE, .BACKSPACE)
		feed_key(ctx, .DELETE, .DELETE)
		feed_key(ctx, .LEFT, .LEFT)
		feed_key(ctx, .RIGHT, .RIGHT)
		feed_key(ctx, .HOME, .HOME)
		feed_key(ctx, .END, .END)
		feed_key(ctx, .ENTER, .RETURN)
		feed_key(ctx, .LEFT_SHIFT, .SHIFT)
		feed_key(ctx, .RIGHT_SHIFT, .SHIFT)
		feed_key(ctx, .LEFT_CONTROL, .CTRL)
		feed_key(ctx, .RIGHT_CONTROL, .CTRL)
		feed_key(ctx, .LEFT_ALT, .ALT)
		feed_key(ctx, .RIGHT_ALT, .ALT)
		feed_key(ctx, .A, .A)
		feed_key(ctx, .X, .X)
		feed_key(ctx, .C, .C)
		feed_key(ctx, .V, .V)

		query := string(search_buf[:search_len])

		mu.begin(ctx)

		// Left pane: recipe list with title search. Close is
		// disabled so a pane cannot be lost by clicking its X;
		// the panes can still be dragged and resized.
		if mu.begin_window(ctx, "Recipes", mu.Rect{10, 10, 280, 580}, {.NO_CLOSE}) {
			mu.layout_row(ctx, {-1}, 0)
			mu.label(ctx, "Recipes")
			mu.label(ctx, "Search recipes:")
			mu.textbox(ctx, search_buf[:], &search_len)
			for recipe, i in recipes {
				if !matches_search(recipe.title, query) {
					continue
				}
				label := recipe.title
				if i == selected {
					label = strings.concatenate({"> ", recipe.title}, context.temp_allocator)
				}
				if res := mu.button(ctx, label, .NONE, {}); .SUBMIT in res {
					selected = i
				}
			}
			mu.end_window(ctx)
		}

		// Right pane: detail for the selected recipe. The
		// selection survives filtering, like the Rust version:
		// filtering the list does not change the detail.
		if mu.begin_window(ctx, "Detail", mu.Rect{300, 10, 590, 580}, {.NO_CLOSE}) {
			mu.layout_row(ctx, {-1}, 0)
			if db_error != "" {
				mu.label(ctx, "Database error:")
				draw_wrapped(ctx, db_error, 550)
			} else if selected >= 0 && selected < len(recipes) {
				recipe := recipes[selected]
				mu.label(ctx, recipe.title)
				draw_wrapped(ctx, recipe.description, 550)
				mu.label(ctx, fmt.tprintf("Servings: %d", recipe.servings))
				mu.label(ctx, "[No image yet]")
				mu.label(ctx, "Ingredients")
				for ingredient in recipe.ingredients {
					if ingredient.unit == "" {
						mu.label(ctx, fmt.tprintf("- %s %s", ingredient.amount, ingredient.name))
					} else {
						mu.label(ctx, fmt.tprintf("- %s %s %s", ingredient.amount, ingredient.unit, ingredient.name))
					}
				}
				mu.label(ctx, "Steps")
				for step, i in recipe.steps {
					// Wrapped, not a single label: labels never
					// wrap, so long steps were clipped at the
					// pane edge.
					draw_wrapped(ctx, fmt.tprintf("%d. %s", i + 1, step), 550)
				}
				mu.label(ctx, "Notes")
				draw_wrapped(ctx, recipe.notes, 550)
			} else {
				mu.label(ctx, "No recipe selected.")
			}
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
