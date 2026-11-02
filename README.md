# desktop_app_exploration

This repo is for choosing a desktop application development stack. See `plan.md` for the full plan.

## Languages to be considered

- C
- C++
- Rust
- Odin
- Zig

## Frameworks to consider

- Rust:
  - Egui / Eframe
  - Iced — no longer under consideration (Nov 2026): Iced renders complex text correctly, but its `text()` widget has no selection support, and the read-only `text_editor` route that makes text selectable paints the selection highlight in the wrong place for RTL Arabic. The selection content and Ctrl+C copy are correct, but the highlight band renders over the empty left side of the field instead of over the glyphs (measured in the test app: band at x 306–558 while the Arabic glyphs sit at x ~609–939). The cause is inside iced: iced_graphics 0.14 computes selection rectangles with its own `highlight_line`, which sums glyph widths from the start of the line and assumes the line starts at x=0 — an LTR assumption that breaks for right-aligned RTL lines. There is no documented fix in iced: cosmic-text fixed its own `highlight()` in 0.19.0 (PR #491), but iced 0.14 pins cosmic-text 0.15.0 and does not use that function, and no iced issue, PR, or changelog entry addresses it. Fixing it would mean patching iced's internals or building a custom selectable widget. Running into a problem like this in a small spike means the stack is not mature enough yet.
- C / C++:
  - Dear ImGui — no longer under consideration (Nov 2026): ImGui renders complex text correctly via the KB plan (kb shaping plus stb rasterization plus FreeType CBDT emoji, baked into OpenGL textures), but that rendering is display-only. The detail title is a baked image and the rest of the detail pane is plain `ImGui::Text`, which ImGui does not make selectable; the only selectable text in the app is inside the add/edit form `InputText` fields, which is input, not displayed text. The bind is structural: shaped text is an image, so there is nothing to highlight, and the plain-text path cannot shape anyway (the default font renders the probes as `?`). It therefore fails the requirement that displayed text be highlightable to copy.
  - GTK4
- Odin:
  - Raylib + Raygui — no longer under consideration (Nov 2026): displayed text is not selectable — list titles are `GuiLabelButton` (a clickable button, not selectable text) and the detail pane is plain raylib `DrawText` (immediate-mode drawing with no interaction at all); the form `GuiTextBox` fields are inputs, not displayed text. Display itself also fails: the app loads no font, so everything renders in raylib's default font (which renders even "…" as "?"), and raylib's own README lists as a limitation that text drawing does not support RTL, ligatures, or emojis — so even with fonts loaded there is no shaping. Getting there would mean a shaping engine plus baked textures plus a custom selectable widget, with no read-only display widget to reuse. It therefore fails the requirement that displayed text be highlightable to copy.
  - microui — no longer under consideration (Nov 2026): microUI does no drawing itself; the app renders its draw commands with raylib's default font, and no font is loaded. Displayed text is `mu.label` in the detail pane and `mu.button` rows in the list — neither is selectable. The only widget with selection and clipboard support is `mu.textbox`, and those are single-line form inputs, not displayed text. And display itself was never even probed: raylib's text drawing does not support RTL, ligatures, or emojis, so there is no shaping even with a font loaded. Getting there would mean a shaping engine plus baked textures plus a custom selectable widget, on top of loading a font in the first place. It therefore fails the requirement that displayed text be highlightable to copy.
  - GTK4 via odin-gtk bindings — new candidate (Nov 2026), not yet evaluated: PucklaJ/odin-gtk provides generated Odin bindings to GTK4 and libadwaita, including pango and cairo, so this route stands on the same Pango text stack as cpp-gtk4.
- Zig:
  - DVUI — no longer under consideration (Nov 2026): DVUI cannot display selectable complex text, which the test app requires. Its text widgets either don't shape — plain labels and the selectable `textLayout` widget render one glyph per codepoint, so Arabic, Devanagari, and emoji fail — or render shaped text as images (via kb, HarfBuzz, or Pango), which the user can't highlight to copy. No solution in the Zig ecosystem was found that gives DVUI selectable shaped text: the shaping packages found (e.g. `ztypeset`, which vendors FreeType/HarfBuzz/SheenBidi) shape and rasterize but provide no selectable widget.
  - GTK4 via zig-gobject bindings — new candidate (Nov 2026), not yet evaluated: ianprime0509/zig-gobject provides GObject-introspection-generated Zig bindings to GTK4 and libadwaita, so this route stands on the same Pango text stack as cpp-gtk4.
- Backends underneath, not counted as UI frameworks:
  - SDL
  - Sokol
  - Raylib

Excluded: Qt (tried in the past, found buggy on Linux) and Slint (licensing).

## Targets

- Latest Fedora Linux to start
- Windows second
- Mac much later

Mobile is explicitly not considered.

## Reasoning

Most applications today are built as web applications, and we can do better.

## The test

Build the same application in all these languages/tech stacks and see what works well and what doesn't.

## The application

Recipe manager. See `plan.md` for the full spec.

The same app in each stack: recipe list and detail views, add/edit/delete, and search — covering text, images, buttons, animations, network import (recipe JSON and images from URLs), raw-file import/export, SQLite storage, multi-encoding text import, and complex-text rendering (Arabic, emoji, Devanagari, and Simplified Chinese).

## Out of scope

Packaging and distribution are explicitly not handled. The assumption is that if a stack can build a binary that runs, it could be signed and distributed and an installer made for it.
