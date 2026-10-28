# cpp-imgui

C++ + Dear ImGui version of the recipe manager test app, currently
with a recipe list/detail view loaded from SQLite.
Backend is SDL2 + OpenGL3.

Dear ImGui source is fetched at build time by CMake (FetchContent,
pinned to v1.93.0) and is not checked in.

Recipes are stored in `recipes.db` in the current working directory,
created on first run and seeded with 3 recipes. `recipes.db` is
git-ignored.

## Build

Ubuntu (this VM):

```sh
sudo apt install cmake g++ libsdl2-dev libgl1-mesa-dev libsqlite3-dev
cmake -S . -B build
cmake --build build
./build/cpp-imgui
```

Fedora (not yet tested here — `install_dependencies_fedora.sh`
is the Fedora equivalent of `install_dependencies_ubuntu.sh`):

```sh
./install_dependencies_fedora.sh
cmake -S . -B build
cmake --build build
./build/cpp-imgui
```

`build/` is git-ignored.
