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
  - Iced
- C / C++:
  - Dear ImGui
  - GTK4
- Odin:
  - Raylib + Raygui
  - Dear ImGui
  - microui
- Zig:
  - DVUI
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

Criteria are TBD, but will include the following at a minimum:

- Displaying text
- Displaying images
- Buttons
- Animations
- Making a network call
- Interacting with disk both as raw files and through SQLite
