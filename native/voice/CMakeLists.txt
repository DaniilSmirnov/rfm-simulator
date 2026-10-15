cmake_minimum_required(VERSION 3.20)
project(rally_voice LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(GODOT_CPP_DIR "" CACHE PATH "Path to godot-cpp checkout")
if(NOT EXISTS "${GODOT_CPP_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "Set GODOT_CPP_DIR to a matching Godot 4.4 godot-cpp checkout")
endif()
add_subdirectory("${GODOT_CPP_DIR}" godot-cpp EXCLUDE_FROM_ALL)

include(FetchContent)
FetchContent_Declare(libdatachannel
  GIT_REPOSITORY https://github.com/paullouisageneau/libdatachannel.git
  GIT_TAG v0.22.2)
set(NO_MEDIA OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(libdatachannel)

add_library(rally_voice SHARED src/register_types.cpp src/voice_peer.cpp)
target_include_directories(rally_voice PRIVATE src)
target_link_libraries(rally_voice PRIVATE godot-cpp libdatachannel)
set_target_properties(rally_voice PROPERTIES PREFIX "" OUTPUT_NAME "rally_voice")
