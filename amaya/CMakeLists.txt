# amaya/CMakeLists.txt
# Builds libCSS (CSS/style parsing) and the amaya executable.
# Linux only; no WebDAV, no Annotations, no Windows resources.

# ── libCSS ────────────────────────────────────────────────────────────────────
# A small static library used by both amaya and thotlib/print.
add_library(CSS STATIC
  ${CMAKE_CURRENT_SOURCE_DIR}/css.c
  ${CMAKE_CURRENT_SOURCE_DIR}/fetchHTMLname.c
  ${CMAKE_CURRENT_SOURCE_DIR}/fetchXMLname.c
  ${CMAKE_CURRENT_SOURCE_DIR}/styleparser.c
)
target_include_directories(CSS PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/generated
  ${CMAKE_SOURCE_DIR}/thotlib/include
  ${CMAKE_SOURCE_DIR}/thotlib/internals/h
  ${CMAKE_SOURCE_DIR}/thotlib/internals/var
  ${CMAKE_SOURCE_DIR}/thotlib/internals/f
  ${CMAKE_SOURCE_DIR}/amaya
  ${CMAKE_SOURCE_DIR}/amaya/f
  ${CMAKE_SOURCE_DIR}/compat
  ${CMAKE_BINARY_DIR}
  ${FREETYPE_INCLUDE_DIRS}
  ${wxWidgets_INCLUDE_DIRS}
)
target_compile_definitions(CSS PRIVATE ${wxWidgets_DEFINITIONS})

# ── wxdialog sources ──────────────────────────────────────────────────────────
set(WXDIALOG_SRCS
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/AuthentDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/CheckedListDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/CreateTableDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/DocInfoDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/FontDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/HRefDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/ImageDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/InitConfirmDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/ListBoxBook.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/ListDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/ListEditDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/ListNSDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/MakeIdDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/MetaDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/ObjectDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/OpenDocDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/PreferenceDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/PrintDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/SaveAsDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/SearchDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/SelectFenceAttributesDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/SelectIntegralDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/SelectOperatorDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/SendByMailDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/SpellCheckDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/StyleDlgWX.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/StyleListToolPanel.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialog/TitleDlgWX.cpp
)

# ── HTTP layer (Phase 3: libcurl replacements) ────────────────────────────────
# AHTURLTools.c: pure URL string helpers -- unchanged from original.
# query.c, answer.c, AHTBridge.c, AHTInit.c, AHTMemConv.c, AHTFWrite.c,
# AHTEvntrg.c: replaced by libcurl versions in patches/curl/.
# apply-patches.sh copies them into amaya/ before the build.
set(HTTP_SRCS
  ${CMAKE_CURRENT_SOURCE_DIR}/AHTURLTools.c
  ${CMAKE_CURRENT_SOURCE_DIR}/query.c       # Phase 3: libcurl
  ${CMAKE_CURRENT_SOURCE_DIR}/answer.c      # Phase 3: stubs
  ${CMAKE_CURRENT_SOURCE_DIR}/AHTBridge.c   # Phase 3: stubs
  ${CMAKE_CURRENT_SOURCE_DIR}/AHTInit.c     # Phase 3: stubs
  ${CMAKE_CURRENT_SOURCE_DIR}/AHTMemConv.c  # Phase 3: stub
  ${CMAKE_CURRENT_SOURCE_DIR}/AHTFWrite.c   # Phase 3: stub
  ${CMAKE_CURRENT_SOURCE_DIR}/AHTEvntrg.c   # Phase 3: stub
)

# ── Core amaya sources ────────────────────────────────────────────────────────
# ── Generated APP.c files (from batch schema compilers) ──────────────────────
# These are committed in amaya/generated/ so a clean build works without
# running the schema compilers. Regenerate with: cmake --build . --target amaya_schemas
set(AMAYA_GENERATED_SRCS
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/EDITORAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/HTMLAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/MathMLAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/SVGAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/TextFileAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/XLinkAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/TimelineAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/TemplateAPP.c
  ${CMAKE_CURRENT_SOURCE_DIR}/generated/XMLAPP.c
)

set(AMAYA_CORE_SRCS
  ${CMAKE_CURRENT_SOURCE_DIR}/wxdialogapi.c

  ${CMAKE_CURRENT_SOURCE_DIR}/EDITORactions.c
  ${CMAKE_CURRENT_SOURCE_DIR}/EDITimage.c
  ${CMAKE_CURRENT_SOURCE_DIR}/EDITstyle.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLactions.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLbook.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLedit.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLform.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLhistory.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLimage.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLpresentation.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLsave.c
  ${CMAKE_CURRENT_SOURCE_DIR}/HTMLtable.c
  ${CMAKE_CURRENT_SOURCE_DIR}/html2thot.c
  ${CMAKE_CURRENT_SOURCE_DIR}/init.c
  ${CMAKE_CURRENT_SOURCE_DIR}/insertelem.c
  ${CMAKE_CURRENT_SOURCE_DIR}/MENUconf.c
  ${CMAKE_CURRENT_SOURCE_DIR}/XLinkbuilder.c
  ${CMAKE_CURRENT_SOURCE_DIR}/XLinkedit.c
  ${CMAKE_CURRENT_SOURCE_DIR}/templates.c
  ${CMAKE_CURRENT_SOURCE_DIR}/trans.c
  ${CMAKE_CURRENT_SOURCE_DIR}/transparse.c
  ${CMAKE_CURRENT_SOURCE_DIR}/UIcss.c
  ${CMAKE_CURRENT_SOURCE_DIR}/Xml2thot.c
  ${CMAKE_CURRENT_SOURCE_DIR}/Xmlbuilder.c
  ${CMAKE_CURRENT_SOURCE_DIR}/XHTMLbuilder.c
  ${CMAKE_CURRENT_SOURCE_DIR}/XPointer.c
  # MathML editing
  ${CMAKE_CURRENT_SOURCE_DIR}/MathMLbuilder.c
  ${CMAKE_CURRENT_SOURCE_DIR}/Mathedit.c
  ${CMAKE_CURRENT_SOURCE_DIR}/Mathedit_parser.cpp
  # SVG editing
  ${CMAKE_CURRENT_SOURCE_DIR}/SVGbuilder.c
  ${CMAKE_CURRENT_SOURCE_DIR}/SVGedit.c
  # Template system
  ${CMAKE_CURRENT_SOURCE_DIR}/Templatebuilder.c
  ${CMAKE_CURRENT_SOURCE_DIR}/templateDeclarations.c
  ${CMAKE_CURRENT_SOURCE_DIR}/templateInstantiate.c
  ${CMAKE_CURRENT_SOURCE_DIR}/templateLoad.c
  ${CMAKE_CURRENT_SOURCE_DIR}/templateUtils.c
  # Animation
  ${CMAKE_CURRENT_SOURCE_DIR}/anim.c
  ${CMAKE_CURRENT_SOURCE_DIR}/animbuilder.c
  # XPointer
  ${CMAKE_CURRENT_SOURCE_DIR}/XPointerparse.c
)

# ── amaya executable ──────────────────────────────────────────────────────────
add_executable(amaya
  ${AMAYA_CORE_SRCS}
  ${AMAYA_GENERATED_SRCS}
  ${WXDIALOG_SRCS}
  ${HTTP_SRCS}
)

# Generated headers need to be on the include path
target_include_directories(amaya PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/generated)

target_include_directories(amaya PRIVATE
  ${CMAKE_SOURCE_DIR}/thotlib/include
  ${CMAKE_SOURCE_DIR}/thotlib/internals/h
  ${CMAKE_SOURCE_DIR}/thotlib/internals/var
  ${CMAKE_SOURCE_DIR}/thotlib/internals/f
  ${CMAKE_SOURCE_DIR}/amaya
  ${CMAKE_SOURCE_DIR}/amaya/f
  ${CMAKE_SOURCE_DIR}/compat
  ${CMAKE_BINARY_DIR}
  ${FREETYPE_INCLUDE_DIRS}
  ${FONTCONFIG_INCLUDE_DIRS}
  ${GTK2_INCLUDE_DIRS}
  ${wxWidgets_INCLUDE_DIRS}
  ${EXPAT_INCLUDE_DIRS}
)

target_compile_definitions(amaya PRIVATE
  ${wxWidgets_DEFINITIONS}
  # Phase 1: local file + HTTP-only; SSL compiled out
  # Phase 3: add -DSSL once libcurl HTTPS is wired in
)

target_link_libraries(amaya PRIVATE
  ThotEditor
  CSS
  ${wxWidgets_LIBRARIES}
  OpenGL::GL
  OpenGL::GLU
  ${FREETYPE_LIBRARIES}
  ${FONTCONFIG_LIBRARIES}
  ${GTK2_LIBRARIES}
  ZLIB::ZLIB
  PNG::PNG
  ${JPEG_LIBRARIES}
  ${EXPAT_LIBRARIES}
  $<$<BOOL:${RAPTOR2_FOUND}>:${RAPTOR2_LIBRARIES}>
  $<$<BOOL:${CURL_FOUND}>:${CURL_LIBRARIES}>
  pthread
  dl
  m
)

install(TARGETS amaya DESTINATION bin)
install(DIRECTORY ${CMAKE_SOURCE_DIR}/amaya/
  DESTINATION share/amaya
  FILES_MATCHING
    PATTERN "*.css"
    PATTERN "*.html"
    PATTERN "*.png"
    PATTERN "*.gif"
    PATTERN "*.STR"
    PATTERN "*.PRS"
    PATTERN "*.TRA"
    PATTERN "*.A"
    PATTERN "config"
)

# ── Compile amaya/ C files as C++ (thot_gui_wx.h has unguarded class decls) ─
get_target_property(AMAYA_SOURCES amaya SOURCES)
foreach(src ${AMAYA_SOURCES})
  if(src MATCHES "\\.c$")
    set_source_files_properties(${src} PROPERTIES LANGUAGE CXX)
  endif()
endforeach()
get_target_property(CSS_SOURCES CSS SOURCES)
foreach(src ${CSS_SOURCES})
  if(src MATCHES "\\.c$")
    set_source_files_properties(${src} PROPERTIES LANGUAGE CXX)
  endif()
endforeach()
