cmake_minimum_required(VERSION 3.24)
project(ShooterNavigation LANGUAGES CXX)

# godot-cpp uses the static MSVC runtime. Set this before creating any target
# so a fresh build cannot mix /MD core objects with /MT adapter objects.
if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

add_library(shooter_navigation STATIC src/pathfinding.cpp)
target_include_directories(shooter_navigation PUBLIC include)
target_compile_features(shooter_navigation PUBLIC cxx_std_17)
set_target_properties(shooter_navigation PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
    target_compile_options(shooter_navigation PRIVATE /W4)
else()
    target_compile_options(shooter_navigation PRIVATE -Wall -Wextra -Wpedantic)
endif()

enable_testing()
add_executable(navigation_tests tests/navigation_tests.cpp)
target_link_libraries(navigation_tests PRIVATE shooter_navigation)
add_test(NAME navigation_tests COMMAND navigation_tests)

option(BUILD_GODOT_EXTENSION "Build the Godot adapter as well as the standalone library" OFF)
if(BUILD_GODOT_EXTENSION)
    include(godot_adapter.cmake)
endif()
