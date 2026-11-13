include(FetchContent)
# Official godot-4.5-stable bindings, targeting the 4.5 API on Godot 4.7.2.
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE PATH "" FORCE)
FetchContent_Declare(godotcpp
    URL https://codeload.github.com/godotengine/godot-cpp/zip/e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
    URL_HASH SHA256=579af30c5f62c1084edb28216788188227d80a583f0114463699ac4edd22140f
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(godotcpp)
add_library(shooter_extension SHARED src/godot_adapter.cpp)
target_link_libraries(shooter_extension PRIVATE shooter_navigation godot::cpp)
if(GODOTCPP_TARGET STREQUAL "template_release")
    set(SHOOTER_RUNTIME_SUFFIX release)
else()
    set(SHOOTER_RUNTIME_SUFFIX debug)
endif()
set_target_properties(shooter_extension PROPERTIES
    PREFIX "" OUTPUT_NAME "shooter_navigation.${SHOOTER_RUNTIME_SUFFIX}" ARCHIVE_OUTPUT_NAME "shooter_extension_import"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    set_target_properties(shooter_extension PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY_${config} "${CMAKE_CURRENT_SOURCE_DIR}/../bin"
        LIBRARY_OUTPUT_DIRECTORY_${config} "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
endforeach()
