cmake_minimum_required(VERSION 3.20)
project(cpp-gtk4 CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# GTK4 through pkg-config: plain GTK4 C API, compiled with g++.
# No gtkmm, no fetched sources.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK4 REQUIRED gtk4)
pkg_check_modules(SQLite3 REQUIRED sqlite3)
pkg_check_modules(ICU REQUIRED icu-uc icu-i18n)

add_executable(cpp-gtk4
    main.cpp
    db.cpp
    seed.cpp
    images.cpp
    json_import.cpp
    json_export.cpp
)

target_include_directories(cpp-gtk4 PRIVATE
    ${GTK4_INCLUDE_DIRS}
    ${SQLite3_INCLUDE_DIRS}
    ${ICU_INCLUDE_DIRS}
)

# The library directories matter when GTK/SQLite live outside
# the system paths (for example, extracted .debs under a prefix
# because apt could not complete in this VM); on a normal
# install these are the standard system directories and change
# nothing.
target_link_directories(cpp-gtk4 PRIVATE
    ${GTK4_LIBRARY_DIRS}
    ${SQLite3_LIBRARY_DIRS}
    ${ICU_LIBRARY_DIRS}
)

target_link_libraries(cpp-gtk4 PRIVATE
    ${GTK4_LIBRARIES}
    ${SQLite3_LIBRARIES}
    ${ICU_LIBRARIES}
)

# Unit tests: plain check mains, no test framework, no new
# dependencies except ICU for the JSON import tests. test-search
# links nothing but the search header (no GTK, no SQLite), so it
# also builds with plain g++:
#   g++ -std=c++17 -Wall -Wextra test_search.cpp -o /tmp/test_search
# test-json-import links only the importer and exporter plus ICU
# (no GTK, no SQLite), so it builds with plain g++ plus ICU:
#   g++ -std=c++17 -Wall -Wextra -pthread test_json_import.cpp json_import.cpp json_export.cpp $(pkg-config --cflags --libs icu-uc icu-i18n) -o /tmp/test_json_import
# test-db uses the stack's own DB layer against a throwaway
# database under /tmp; it never opens the real recipes.db.
add_executable(cpp-gtk4-test-search
    test_search.cpp
)

# test-text-undo links only the undo helper (no GTK, no SQLite),
# so it also builds with plain g++:
#   g++ -std=c++17 -Wall -Wextra test_text_undo.cpp -o /tmp/test_text_undo
add_executable(cpp-gtk4-test-text-undo
    test_text_undo.cpp
)

add_executable(cpp-gtk4-test-json-import
    test_json_import.cpp
    json_import.cpp
    json_export.cpp
)

target_include_directories(cpp-gtk4-test-json-import PRIVATE
    ${ICU_INCLUDE_DIRS}
)

target_link_directories(cpp-gtk4-test-json-import PRIVATE
    ${ICU_LIBRARY_DIRS}
)

target_link_libraries(cpp-gtk4-test-json-import PRIVATE
    ${ICU_LIBRARIES}
)

add_executable(cpp-gtk4-test-db
    test_db.cpp
    db.cpp
    seed.cpp
)

target_include_directories(cpp-gtk4-test-db PRIVATE
    ${SQLite3_INCLUDE_DIRS}
)

target_link_directories(cpp-gtk4-test-db PRIVATE
    ${SQLite3_LIBRARY_DIRS}
)

target_link_libraries(cpp-gtk4-test-db PRIVATE
    ${SQLite3_LIBRARIES}
)
