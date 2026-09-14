# batch/CMakeLists.txt
#
# Builds two host tools (compiled for the BUILD machine, not the target):
#   amaya_str_compiler  -- compiles .S structure schema source → .STR binary
#   amaya_app_compiler  -- compiles .A application schema source → *APP.c + *.h
#
# Then uses them via add_custom_command() to generate the five *APP.c files
# that the amaya/ target needs as sources.
#
# These tools are NODISPLAY builds: no wxWidgets, no OpenGL, no GTK.
# They only need a small subset of thotlib (document reading + tree).
#
# NOTE: The generated *APP.c and *.h files are also committed to
#   amaya/generated/  so that a clean checkout can build without running
#   the schema compilers.  The custom commands below regenerate them only
#   when the .A or .S source schemas change.

cmake_minimum_required(VERSION 3.16)

# ── Compiler flags for host tools (NODISPLAY) ────────────────────────────────
set(BATCH_CFLAGS
  -DNODISPLAY
  -D_UNIX
  -DHAVE_CONFIG_H
  -DSTDC_HEADERS
  # Suppress old-C warnings -- batch/ code is 1990s vintage
  -Wno-implicit-function-declaration
  -Wno-implicit-int
  -Wno-incompatible-pointer-types
  -Wno-int-conversion
  -Wno-unused-result
  -Wno-format
  -Wno-pointer-to-int-cast
  # CPP invocation: -P strips line markers; -undef/-nostdinc block stdc-predef.h
  # which confuses the grammar parser
  "-DCPP=\"/usr/bin/cpp -P -C -undef -nostdinc\""
)

set(BATCH_INCLUDES
  ${CMAKE_BINARY_DIR}            # for config.h
  ${CMAKE_SOURCE_DIR}/thotlib/include
  ${CMAKE_SOURCE_DIR}/thotlib/internals/h
  ${CMAKE_SOURCE_DIR}/thotlib/internals/f
  ${CMAKE_SOURCE_DIR}/thotlib/internals/var
  ${CMAKE_SOURCE_DIR}/batch/f
)

# ── Common thotlib sources needed by both compilers ──────────────────────────
set(BATCH_THOTLIB_SRCS
  ${CMAKE_SOURCE_DIR}/thotlib/base/memory.c
  ${CMAKE_SOURCE_DIR}/thotlib/base/compilmsg.c
  ${CMAKE_SOURCE_DIR}/thotlib/base/fileaccess.c
  ${CMAKE_SOURCE_DIR}/thotlib/base/message.c
  ${CMAKE_SOURCE_DIR}/thotlib/base/platform.c
  ${CMAKE_SOURCE_DIR}/thotlib/base/structlist.c
  ${CMAKE_SOURCE_DIR}/thotlib/base/registry.c
  ${CMAKE_SOURCE_DIR}/thotlib/base/global.c
  ${CMAKE_SOURCE_DIR}/thotlib/unicode/ustring.c
  ${CMAKE_SOURCE_DIR}/thotlib/unicode/uconvert.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/readstr.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/readprs.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/readtra.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/schtrad.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/externalref.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/language.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/readpivot.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/schemas.c
  ${CMAKE_SOURCE_DIR}/thotlib/tree/tree.c
  ${CMAKE_SOURCE_DIR}/thotlib/tree/exceptions.c
  ${CMAKE_SOURCE_DIR}/thotlib/tree/labelalloc.c
  ${CMAKE_SOURCE_DIR}/thotlib/tree/checkaccess.c
  ${CMAKE_SOURCE_DIR}/thotlib/tree/structschema.c
  ${CMAKE_SOURCE_DIR}/thotlib/tree/references.c
  ${CMAKE_SOURCE_DIR}/thotlib/dialogue/nodisplay.c
  ${CMAKE_SOURCE_DIR}/thotlib/dialogue/callbackinit.c
  ${CMAKE_SOURCE_DIR}/batch/nodisplay_stubs.c
)

# ── amaya_str_compiler ───────────────────────────────────────────────────────
# Reads .S (structure schema source) → writes .STR (binary schema)
add_executable(amaya_str_compiler EXCLUDE_FROM_ALL
  ${CMAKE_SOURCE_DIR}/batch/str.c
  ${CMAKE_SOURCE_DIR}/batch/parser.c
  ${CMAKE_SOURCE_DIR}/thotlib/document/writestr.c
  ${BATCH_THOTLIB_SRCS}
)
target_compile_options(amaya_str_compiler PRIVATE ${BATCH_CFLAGS})
target_include_directories(amaya_str_compiler PRIVATE ${BATCH_INCLUDES})
target_link_libraries(amaya_str_compiler PRIVATE m)
set_target_properties(amaya_str_compiler PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/batch_tools
)

# ── amaya_app_compiler ───────────────────────────────────────────────────────
# Reads .A (application schema source) + .STR (binary schema) → *APP.c + *.h
add_executable(amaya_app_compiler EXCLUDE_FROM_ALL
  ${CMAKE_SOURCE_DIR}/batch/app.c
  ${CMAKE_SOURCE_DIR}/batch/writeapp.c
  ${CMAKE_SOURCE_DIR}/batch/parser.c
  ${BATCH_THOTLIB_SRCS}
)
target_compile_options(amaya_app_compiler PRIVATE ${BATCH_CFLAGS})
target_include_directories(amaya_app_compiler PRIVATE ${BATCH_INCLUDES})
target_link_libraries(amaya_app_compiler PRIVATE m)
set_target_properties(amaya_app_compiler PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/batch_tools
)

# ── Schema source files ───────────────────────────────────────────────────────
set(AMAYA_SRC ${CMAKE_SOURCE_DIR}/amaya)
set(BATCH_TOOLS ${CMAKE_BINARY_DIR}/batch_tools)
set(GEN_DIR ${CMAKE_SOURCE_DIR}/amaya/generated)
set(SCH_DIR ${CMAKE_SOURCE_DIR}/amaya/schemas)

# Common env for schema compiler runs
set(SCHEMA_ENV
  THOTDIR=${CMAKE_SOURCE_DIR}
  THOTSYSSCH=${SCH_DIR}
  PWD=${GEN_DIR}
)

# ── Step 1: compile .S → .STR for each structure schema ─────────────────────
# (Only needed if you want to regenerate the .STR files from .S source.
#  Pre-built .STR files are committed in amaya/schemas/ so this is optional.)
foreach(SCHEMA HTML TextFile XLink XML)
  add_custom_command(
    OUTPUT  ${SCH_DIR}/${SCHEMA}.STR
    COMMAND ${CMAKE_COMMAND} -E env ${SCHEMA_ENV}
            ${BATCH_TOOLS}/amaya_str_compiler ${AMAYA_SRC}/${SCHEMA}.S
    COMMAND ${CMAKE_COMMAND} -E rename ${GEN_DIR}/${SCHEMA}.STR ${SCH_DIR}/${SCHEMA}.STR
    DEPENDS amaya_str_compiler ${AMAYA_SRC}/${SCHEMA}.S
    WORKING_DIRECTORY ${GEN_DIR}
    COMMENT "Compiling structure schema ${SCHEMA}.S → ${SCHEMA}.STR"
  )
endforeach()

# ── Step 2: compile .A → *APP.c + *.h ───────────────────────────────────────
# Input: .A application schema + .STR binary structure schema
# Output: *APP.c and *.h (committed in amaya/generated/ for clean builds)

# EDITOR has no external schema dependency
add_custom_command(
  OUTPUT  ${GEN_DIR}/EDITORAPP.c ${GEN_DIR}/EDITOR.h
  COMMAND ${CMAKE_COMMAND} -E env ${SCHEMA_ENV}
          ${BATCH_TOOLS}/amaya_app_compiler ${AMAYA_SRC}/EDITOR.A
  DEPENDS amaya_app_compiler ${AMAYA_SRC}/EDITOR.A
  WORKING_DIRECTORY ${GEN_DIR}
  COMMENT "Generating EDITORAPP.c from EDITOR.A"
)

# HTML, TextFile, XLink, XML need their .STR schemas loaded
foreach(SCHEMA HTML TextFile XLink XML)
  add_custom_command(
    OUTPUT  ${GEN_DIR}/${SCHEMA}APP.c ${GEN_DIR}/${SCHEMA}.h
    COMMAND ${CMAKE_COMMAND} -E env ${SCHEMA_ENV}
            ${BATCH_TOOLS}/amaya_app_compiler ${AMAYA_SRC}/${SCHEMA}.A
    DEPENDS amaya_app_compiler
            ${AMAYA_SRC}/${SCHEMA}.A
            ${SCH_DIR}/${SCHEMA}.STR
    WORKING_DIRECTORY ${GEN_DIR}
    COMMENT "Generating ${SCHEMA}APP.c from ${SCHEMA}.A"
  )
endforeach()

# ── Convenience target: regenerate all APP.c files ───────────────────────────
add_custom_target(amaya_schemas
  DEPENDS
    ${GEN_DIR}/EDITORAPP.c
    ${GEN_DIR}/HTMLAPP.c
    ${GEN_DIR}/TextFileAPP.c
    ${GEN_DIR}/XLinkAPP.c
    ${GEN_DIR}/XMLAPP.c
)
