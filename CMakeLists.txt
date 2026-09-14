cmake_minimum_required(VERSION 3.16)
project(amaya VERSION 11.4.7 LANGUAGES C CXX)

# ── C/C++ standards ──────────────────────────────────────────────────────────
set(CMAKE_C_STANDARD   11)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_C_STANDARD_REQUIRED   ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Build type ────────────────────────────────────────────────────────────────
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING "Build type" FORCE)
endif()

# ── Compiler flags ────────────────────────────────────────────────────────────
# Amaya was written for GCC 3-4; silence the categories of warnings that GCC
# 13/14 promote to errors for old C code, without hiding genuine new bugs.
add_compile_options(
  -Wall
  -Wno-implicit-function-declaration   # old C pattern; prototypes exist in _f.h
  -Wno-implicit-int                    # old K&R-ish code in thotlib
  -Wno-incompatible-pointer-types      # numerous legacy void* casts
  -Wno-int-conversion                  # similar
  -Wno-deprecated-declarations         # wxWidgets 2.8-style deprecations
  -Wno-unused-variable
  -Wno-unused-function
  -fno-strict-aliasing                 # thotlib uses aliased structs
)
# C++ additionally needs permissive mode for the old-style C++ in thotlib
add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-fpermissive>)

# ── Force-include the wx 2.8→3.2 compatibility shim into every TU ────────
# This avoids editing every .cpp file for the wxEVT_COMMAND_* renames.
add_compile_options(
  -include ${CMAKE_SOURCE_DIR}/compat/wx3compat.h
)

# ── Platform definition ───────────────────────────────────────────────────────
add_compile_definitions(
  _UNIX
  _WX
  _GL
  _SVG
  TEMPLATES
  XML_GENERIC
  AMAYA_UNIX
  HAVE_CONFIG_H
  # Disable optional subsystems we are not porting in Phase 1
  NO_ANNOT          # annotation library
  NO_DAV            # WebDAV library  
  # SSL kept conditional -- Phase 3 will replace libwww with libcurl
)

# ── Find packages ─────────────────────────────────────────────────────────────
find_package(PkgConfig REQUIRED)

# wxWidgets 3.2 (Ubuntu 24.04 universe)
find_package(wxWidgets REQUIRED COMPONENTS core base gl adv xrc aui net xml html)
include(${wxWidgets_USE_FILE})

# OpenGL (compatibility profile -- Amaya uses fixed-function GL)
find_package(OpenGL REQUIRED)
find_package(GLUT)   # optional, for Mesa fallback

# FreeType for font rendering
pkg_check_modules(FREETYPE REQUIRED freetype2)

# FontConfig
pkg_check_modules(FONTCONFIG REQUIRED fontconfig)

# GTK3 (wxWidgets on Linux uses GTK3 backend)
pkg_check_modules(GTK3 gtk+-3.0)

# zlib, libpng, libjpeg
find_package(ZLIB REQUIRED)
find_package(PNG  REQUIRED)
find_package(JPEG REQUIRED)

# expat (XML parsing)
find_package(EXPAT REQUIRED)

# raptor2 (RDF, used for schema metadata -- we keep it, it's small)
pkg_check_modules(RAPTOR2 raptor2)  # optional

# libcurl -- replaces libwww for HTTP (Phase 3)
# Required (not optional) from Phase 3 onwards.
find_package(CURL REQUIRED)
if(NOT CURL_FOUND)
  message(FATAL_ERROR "libcurl not found. Install: sudo apt install libcurl4-openssl-dev")
endif()

# ── Include paths common to all targets ──────────────────────────────────────
# These replicate the THOTINCLUDES variable from configure.in
set(THOT_INCLUDES
  ${CMAKE_SOURCE_DIR}/thotlib/include
  ${CMAKE_SOURCE_DIR}/thotlib/internals/h
  ${CMAKE_SOURCE_DIR}/thotlib/internals/var
  ${CMAKE_SOURCE_DIR}/thotlib/internals/f
  ${CMAKE_SOURCE_DIR}/amaya
  ${CMAKE_SOURCE_DIR}/amaya/f
  ${CMAKE_SOURCE_DIR}/compat           # our wx3 / GCC13 shim headers
  ${CMAKE_BINARY_DIR}                  # for generated config.h
)

# ── config.h generation ───────────────────────────────────────────────────────
include(CheckIncludeFile)
include(CheckFunctionExists)
check_include_file("unistd.h"    HAVE_UNISTD_H)
check_include_file("sys/stat.h"  HAVE_SYS_STAT_H)
check_include_file("dirent.h"    HAVE_DIRENT_H)
check_function_exists("strcasecmp"  HAVE_STRCASECMP)
check_function_exists("strncasecmp" HAVE_STRNCASECMP)

configure_file(cmake/config.h.in config.h @ONLY)

# ── Subdirectories ────────────────────────────────────────────────────────────
add_subdirectory(batch)    # host-only schema compilers (EXCLUDE_FROM_ALL)
add_subdirectory(thotlib)
add_subdirectory(amaya)
