# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(remote_storage LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cloud-volume")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Build the Go bridge as part of the Windows runner so both flutter run and
# flutter build produce a launchable output directory.
set(REPO_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(BRIDGE_OUTPUT_DIR "${REPO_ROOT_DIR}/bin/bridge")
set(WINDOWS_BRIDGE_OUTPUT "${BRIDGE_OUTPUT_DIR}/remote_storage_bridge.dll")

find_program(GO_EXECUTABLE NAMES go REQUIRED)

set(WINDOWS_BRIDGE_CC "$ENV{BRIDGE_CC}")
if(NOT WINDOWS_BRIDGE_CC)
  if(EXISTS "C:/msys64/ucrt64/bin/gcc.exe")
    set(WINDOWS_BRIDGE_CC "C:/msys64/ucrt64/bin/gcc.exe")
  elseif(EXISTS "C:/msys64/mingw64/bin/gcc.exe")
    set(WINDOWS_BRIDGE_CC "C:/msys64/mingw64/bin/gcc.exe")
  elseif(EXISTS "C:/msys64/clang64/bin/gcc.exe")
    set(WINDOWS_BRIDGE_CC "C:/msys64/clang64/bin/gcc.exe")
  endif()
endif()
if(NOT WINDOWS_BRIDGE_CC)
  find_program(WINDOWS_BRIDGE_CC NAMES gcc
    HINTS
      "C:/msys64/ucrt64/bin"
      "C:/msys64/mingw64/bin"
      "C:/msys64/clang64/bin")
endif()
if(NOT WINDOWS_BRIDGE_CC)
  message(FATAL_ERROR
    "Windows Go bridge builds require gcc. Install the MSYS2 UCRT64 toolchain or set BRIDGE_CC.")
endif()

set(WINDOWS_BRIDGE_CXX "$ENV{BRIDGE_CXX}")
if(NOT WINDOWS_BRIDGE_CXX)
  if(EXISTS "C:/msys64/ucrt64/bin/g++.exe")
    set(WINDOWS_BRIDGE_CXX "C:/msys64/ucrt64/bin/g++.exe")
  elseif(EXISTS "C:/msys64/mingw64/bin/g++.exe")
    set(WINDOWS_BRIDGE_CXX "C:/msys64/mingw64/bin/g++.exe")
  elseif(EXISTS "C:/msys64/clang64/bin/g++.exe")
    set(WINDOWS_BRIDGE_CXX "C:/msys64/clang64/bin/g++.exe")
  endif()
endif()
if(NOT WINDOWS_BRIDGE_CXX)
  find_program(WINDOWS_BRIDGE_CXX NAMES g++
    HINTS
      "C:/msys64/ucrt64/bin"
      "C:/msys64/mingw64/bin"
      "C:/msys64/clang64/bin")
endif()
if(NOT WINDOWS_BRIDGE_CXX)
  message(FATAL_ERROR
    "Windows Go bridge builds require g++. Install the MSYS2 UCRT64 toolchain or set BRIDGE_CXX.")
endif()

get_filename_component(WINDOWS_BRIDGE_TOOLCHAIN_DIR "${WINDOWS_BRIDGE_CC}" DIRECTORY)
get_filename_component(WINDOWS_BRIDGE_CXX_DIR "${WINDOWS_BRIDGE_CXX}" DIRECTORY)
if(NOT WINDOWS_BRIDGE_TOOLCHAIN_DIR STREQUAL WINDOWS_BRIDGE_CXX_DIR)
  message(FATAL_ERROR
    "BRIDGE_CC and BRIDGE_CXX must come from the same toolchain directory.")
endif()
get_filename_component(WINDOWS_BRIDGE_CC_NAME "${WINDOWS_BRIDGE_CC}" NAME)
get_filename_component(WINDOWS_BRIDGE_CXX_NAME "${WINDOWS_BRIDGE_CXX}" NAME)

add_custom_target(remote_storage_bridge ALL
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BRIDGE_OUTPUT_DIR}"
  COMMAND ${CMAKE_COMMAND} -E env
    "PATH=${WINDOWS_BRIDGE_TOOLCHAIN_DIR}"
    "CGO_ENABLED=1"
    "CC=${WINDOWS_BRIDGE_CC_NAME}"
    "CXX=${WINDOWS_BRIDGE_CXX_NAME}"
    ${GO_EXECUTABLE} build -buildmode=c-shared -o "${WINDOWS_BRIDGE_OUTPUT}" ./bridge
  BYPRODUCTS
    "${WINDOWS_BRIDGE_OUTPUT}"
    "${BRIDGE_OUTPUT_DIR}/remote_storage_bridge.h"
  WORKING_DIRECTORY "${REPO_ROOT_DIR}"
  COMMENT "Building Windows Go bridge"
  VERBATIM)

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")
add_dependencies(${BINARY_NAME} remote_storage_bridge)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${WINDOWS_BRIDGE_OUTPUT}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
