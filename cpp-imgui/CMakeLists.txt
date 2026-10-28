cmake_minimum_required(VERSION 3.20)
project(cpp-imgui CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# Dear ImGui has no CMakeLists, so fetch the source and list the
# files we need explicitly. Pinned to a release tag, not master.
FetchContent_Declare(
    imgui
    GIT_REPOSITORY https://github.com/ocornut/imgui.git
    GIT_TAG v1.93.0
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(imgui)

find_package(SDL2 REQUIRED)
find_package(OpenGL REQUIRED)
find_package(SQLite3 REQUIRED)

add_executable(cpp-imgui
    main.cpp
    db.cpp
    ${imgui_SOURCE_DIR}/imgui.cpp
    ${imgui_SOURCE_DIR}/imgui_draw.cpp
    ${imgui_SOURCE_DIR}/imgui_tables.cpp
    ${imgui_SOURCE_DIR}/imgui_widgets.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_sdl2.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp
)

target_include_directories(cpp-imgui PRIVATE
    ${imgui_SOURCE_DIR}
    ${imgui_SOURCE_DIR}/backends
)

target_link_libraries(cpp-imgui PRIVATE SDL2::SDL2 OpenGL::GL SQLite::SQLite3 dl)
