# cpp-imgui

C++ + Dear ImGui version of the recipe manager test app, currently
with a recipe list/detail view using hard-coded mock data.
Backend is SDL2 + OpenGL3.

Dear ImGui source is fetched at build time by CMake (FetchContent,
pinned to v1.93.0) and is not checked in.

## Build

Ubuntu (this VM):

```sh
sudo apt install cmake g++ libsdl2-dev libgl1-mesa-dev
cmake -S . -B build
cmake --build build
./build/cpp-imgui
```

Fedora (target platform, package names only — not yet tested here):

```sh
sudo dnf install cmake gcc-c++ SDL2-devel mesa-libGL-devel
cmake -S . -B build
cmake --build build
./build/cpp-imgui
```

`build/` is git-ignored.
