cmake_minimum_required(VERSION 3.20)
project(cpp-gtk4 CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# GTK4 through pkg-config: plain GTK4 C API, compiled with g++.
# No gtkmm, no fetched sources.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK4 REQUIRED gtk4)
pkg_check_modules(SQLite3 REQUIRED sqlite3)

add_executable(cpp-gtk4
    main.cpp
    db.cpp
    seed.cpp
    images.cpp
)

target_include_directories(cpp-gtk4 PRIVATE
    ${GTK4_INCLUDE_DIRS}
    ${SQLite3_INCLUDE_DIRS}
)

target_link_libraries(cpp-gtk4 PRIVATE
    ${GTK4_LIBRARIES}
    ${SQLite3_LIBRARIES}
)
