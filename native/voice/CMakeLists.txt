cmake_minimum_required(VERSION 3.20)
# libSRTP copies CMAKE_PROJECT_VERSION into its target properties.
project(rally_voice VERSION 1.0.0 LANGUAGES C CXX)
# Built by scripts/build-voice.mjs: it fetches the pinned sources below,
# installs Mbed TLS and Opus into VOICE_PREFIX and passes their locations.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(GODOT_CPP_DIR "" CACHE PATH "godot-cpp checkout matching Godot 4.4")
set(LIBDATACHANNEL_DIR "" CACHE PATH "libdatachannel checkout with submodules")
set(VOICE_PREFIX "" CACHE PATH "Prefix with Mbed TLS and Opus installed")
set(VOICE_SUFFIX "" CACHE STRING "Library suffix, e.g. linux.x86_64")
foreach(dir GODOT_CPP_DIR LIBDATACHANNEL_DIR VOICE_PREFIX)
  if(NOT EXISTS "${${dir}}")
    message(FATAL_ERROR "Set ${dir} (run scripts/build-voice.mjs)")
  endif()
endforeach()
list(PREPEND CMAKE_PREFIX_PATH "${VOICE_PREFIX}")

# libdatachannel and godot-cpp throw/catch internally; the extension catches
# every exception at the binding boundary.
set(GODOTCPP_DISABLE_EXCEPTIONS OFF CACHE BOOL "" FORCE)
set(GODOTCPP_TARGET template_release CACHE STRING "" FORCE)
add_subdirectory("${GODOT_CPP_DIR}" godot-cpp EXCLUDE_FROM_ALL)

# Mbed TLS's own package config links tls -> x509 -> crypto in the right order
# for static libraries; libdatachannel uses MbedTLS::MbedTLS when it exists.
find_package(MbedTLS 3 CONFIG REQUIRED)
add_library(MbedTLS::MbedTLS INTERFACE IMPORTED)
target_link_libraries(MbedTLS::MbedTLS INTERFACE MbedTLS::mbedtls MbedTLS::mbedx509 MbedTLS::mbedcrypto)
set(USE_MBEDTLS ON CACHE BOOL "" FORCE)
set(NO_WEBSOCKET ON CACHE BOOL "" FORCE)
set(NO_MEDIA OFF CACHE BOOL "" FORCE)
set(NO_EXAMPLES ON CACHE BOOL "" FORCE)
set(NO_TESTS ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory("${LIBDATACHANNEL_DIR}" libdatachannel EXCLUDE_FROM_ALL)
# libSRTP's find_package(MbedTLS) runs libdatachannel's find module, which
# rewrites this target's links with component names; put the real ones back.
set_property(TARGET MbedTLS::MbedTLS PROPERTY INTERFACE_LINK_LIBRARIES MbedTLS::mbedtls MbedTLS::mbedx509 MbedTLS::mbedcrypto)

find_package(Opus CONFIG REQUIRED)

add_library(rally_voice SHARED
  src/register_types.cpp
  src/voice_link.cpp
  src/voice_encoder.cpp
  src/radio_dsp.cpp)
target_include_directories(rally_voice PRIVATE src)
target_link_libraries(rally_voice PRIVATE godot::cpp LibDataChannel::LibDataChannelStatic Opus::opus)
set_target_properties(rally_voice PROPERTIES
  PREFIX "lib"
  OUTPUT_NAME "rally_voice.${VOICE_SUFFIX}"
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
if(MSVC)
  set_target_properties(rally_voice PROPERTIES PREFIX "" MSVC_RUNTIME_LIBRARY "MultiThreaded")
elseif(WIN32)
  # MinGW: no libstdc++/libgcc DLLs next to the game.
  target_link_options(rally_voice PRIVATE -static -static-libgcc -static-libstdc++)
elseif(NOT APPLE)
  target_link_options(rally_voice PRIVATE -static-libstdc++ -Wl,--exclude-libs,ALL -Wl,--no-undefined)
endif()
install(TARGETS rally_voice LIBRARY DESTINATION bin RUNTIME DESTINATION bin)
