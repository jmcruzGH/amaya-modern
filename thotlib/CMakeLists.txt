# thotlib/CMakeLists.txt
# Builds libThotEditor.a (the Thot rendering + wx UI engine)
# Linux/amd64 only; no Windows, no macOS, no print binary.

# ── source helper ─────────────────────────────────────────────────────────────
# Prefixes each filename with ${CMAKE_CURRENT_SOURCE_DIR}/
function(thot_sources OUT_VAR)
  set(_srcs)
  foreach(_f ${ARGN})
    list(APPEND _srcs "${CMAKE_CURRENT_SOURCE_DIR}/${_f}")
  endforeach()
  set(${OUT_VAR} ${_srcs} PARENT_SCOPE)
endfunction()

# ── THOTK sources (tree, documents, unicode -- no display) ────────────────────
thot_sources(THOTK_SRCS
  base/AmayaAppInstance.cpp
  base/AmayaLogDebug.cpp
  base/wxAmayaTimer.cpp
  base/wxAmayaSocketEvent.cpp
  base/wxAmayaSocketEventLoop.cpp
  base/global.c
  base/memory.c
  base/message.c
  base/platform.c
  base/registry.c
  base/registry_wx.c
  base/message_wx.c
  base/actions.c
  base/units.c
  base/logdebug.c
  base/testcase.c
  document/externalref.c
  document/language.c
  document/readprs.c
  document/readstr.c
  document/readtra.c
  document/schtrad.c
  document/writeprs.c
  document/writestr.c
  tree/exceptions.c
  tree/tree.c
  tree/checkaccess.c
  tree/labelalloc.c
  unicode/uconvert.c
  unicode/ustring.c
)

# ── DISPLAY sources (rendering, OpenGL, images) ───────────────────────────────
thot_sources(DISPLAY_SRCS
  base/fileaccess.c
  content/content.c
  content/dictionary.c
  image/encdec.c
  dialogue/fontserver.c
  dialogue/fontconfig.c
  dialogue/font.c
  dialogue/stix.c
  document/documentapi.c
  document/readpivot.c
  document/schemas.c
  document/translation.c
  editing/applicationapi.c
  image/abspictures.c
  image/epshandler.c
  image/gifhandler.c
  image/jpeghandler.c
  image/picture.c
  image/pnghandler.c
  image/xpmhandler.c
  presentation/attrpresent.c
  presentation/changepresent.c
  presentation/presrules.c
  presentation/presvariables.c
  presentation/pschemaapi.c
  presentation/style.c
  tree/attributes.c
  tree/pagecommands.c
  tree/references.c
  tree/structschema.c
  view/absboxes.c
  view/boxmoves.c
  view/boxpositions.c
  view/boxrelations.c
  view/buildboxes.c
  view/buildlines.c
  view/changeabsbox.c
  view/createabsbox.c
  view/createpages.c
  view/displaybox.c
  view/displayview.c
  view/frame.c
  view/hyphen.c
  view/tesse.c
  view/glgradient.c
  dialogue/glglyph.c
  dialogue/openglfont.c
  view/glwindowdisplay.c
  view/gldisplay.c
  view/spline.c
)

# ── EDITOR sources (wx widgets, editing logic) ────────────────────────────────
thot_sources(EDITOR_SRCS
  base/AmayaApp.cpp
  base/alloca.c
  base/config.c
  base/containers.c
  base/thotmsg.c
  base/structlist.c
  content/contentapi.c
  content/search.c
  content/searchref.c
  content/word.c
  dialogue/AmayaActionEvent.cpp
  dialogue/AmayaStatusBar.cpp
  dialogue/AmayaConfirmCloseTab.cpp
  dialogue/AmayaAddPointEvtHandler.cpp
  dialogue/AmayaMovePointEvtHandler.cpp
  dialogue/AmayaMovingBoxEvtHandler.cpp
  dialogue/AmayaResizingBoxEvtHandler.cpp
  dialogue/AmayaCreateShapeEvtHandler.cpp
  dialogue/AmayaCreatePathEvtHandler.cpp
  dialogue/AmayaTransformEvtHandler.cpp
  dialogue/AmayaEditPathEvtHandler.cpp
  dialogue/AmayaEditShapeEvtHandler.cpp
  dialogue/AmayaDialog.cpp
  dialogue/AmayaWindow.cpp
  dialogue/AmayaWindowIterator.cpp
  dialogue/AmayaSimpleWindow.cpp
  dialogue/AmayaNormalWindow.cpp
  dialogue/AmayaClassicWindow.cpp
  dialogue/AmayaClassicNotebook.cpp
  dialogue/AmayaAdvancedWindow.cpp
  dialogue/AmayaAdvancedNotebook.cpp
  dialogue/AmayaHelpWindow.cpp
  dialogue/AmayaQuickSplitButton.cpp
  dialogue/AmayaPanel.cpp
  dialogue/AmayaPopupList.cpp
  dialogue/AmayaApplyClassPanel.cpp
  dialogue/AmayaXHTMLPanel.cpp
  dialogue/AmayaElementPanel.cpp
  dialogue/AmayaStylePanel.cpp
  dialogue/AmayaExplorerPanel.cpp
  dialogue/AmayaAttributePanel.cpp
  dialogue/AmayaMathMLPanel.cpp
  dialogue/AmayaSVGPanel.cpp
  dialogue/AmayaXMLPanel.cpp
  dialogue/AmayaTemplatePanel.cpp
  dialogue/AmayaPage.cpp
  dialogue/AmayaFrame.cpp
  dialogue/AmayaCanvas.cpp
  dialogue/AmayaColorButton.cpp
  dialogue/AmayaToolBar.cpp
  dialogue/AmayaScrollBar.cpp
  dialogue/AmayaFileDropTarget.cpp
  dialogue/AmayaSpeCharPanel.cpp
  dialogue/AmayaStatsThread.cpp
  dialogue/AmayaPathControl.cpp
  dialogue/AmayaTipOfTheDay.cpp
  dialogue/appdialogue_wx.c
  dialogue/callback.c
  dialogue/callbackinit.c
  dialogue/appdialogue.c
  dialogue/appli.c
  dialogue/archives.c
  dialogue/attrmenu.c
  dialogue/base64.cpp
  dialogue/browser.c
  dialogue/closedoc.c
  dialogue/context.c
  dialogue/creationmenu.c
  dialogue/dialogapi.c
  dialogue/email.c
  dialogue/Elemlist.c
  dialogue/geom.c
  dialogue/input.c
  dialogue/interface.c
  dialogue/md5.cpp
  dialogue/modiftype.c
  dialogue/profiles.c
  dialogue/presentmenu.c
  dialogue/printmenu.c
  dialogue/searchmenu.c
  dialogue/SMTP.cpp
  document/docs.c
  document/views.c
  document/writedoc.c
  document/writepivot.c
  editing/checkermenu.c
  editing/editcommands.c
  editing/scroll.c
  editing/spellchecker.c
  editing/selectionapi.c
  editing/structcommands.c
  editing/structcreation.c
  editing/structmodif.c
  editing/structselect.c
  editing/textcommands.c
  editing/undo.c
  editing/undoapi.c
  editing/unstructchange.c
  image/pictureapi.c
  presentation/presentationapi.c
  tree/attributeapi.c
  tree/paginate.c
  tree/referenceapi.c
  tree/res.c
  tree/resmatch.c
  tree/resgen.c
  tree/treeapi.c
  view/animbox.c
  view/boxlocate.c
  view/boxparams.c
  view/boxselection.c
  view/displayselect.c
  view/glbox.c
  view/gltimer.c
  view/inites.c
  view/tableH.c
  view/unstructlocate.c
  view/viewapi.c
)

# ── Build the combined static library ────────────────────────────────────────
add_library(ThotEditor STATIC
  ${THOTK_SRCS}
  ${DISPLAY_SRCS}
  ${EDITOR_SRCS}
)

# Special compile flags for base/registry.c (it needs source-dir constants)
set_source_files_properties(
  ${CMAKE_CURRENT_SOURCE_DIR}/base/registry.c
  PROPERTIES COMPILE_DEFINITIONS
    "COMPILED_IN_THOTDIR=\"${CMAKE_SOURCE_DIR}\";COMPILED_IN_THOTDIR2=\"/usr/share/amaya\""
)

target_include_directories(ThotEditor PUBLIC
  ${CMAKE_SOURCE_DIR}/thotlib/include
  ${CMAKE_SOURCE_DIR}/thotlib/internals/h
  ${CMAKE_SOURCE_DIR}/thotlib/internals/var
  ${CMAKE_SOURCE_DIR}/thotlib/internals/f
  ${CMAKE_SOURCE_DIR}/compat
  ${CMAKE_BINARY_DIR}
  ${FREETYPE_INCLUDE_DIRS}
  ${FONTCONFIG_INCLUDE_DIRS}
  ${GTK3_INCLUDE_DIRS}
  ${wxWidgets_INCLUDE_DIRS}
)

target_compile_options(ThotEditor PRIVATE
  ${FREETYPE_CFLAGS_OTHER}
  ${FONTCONFIG_CFLAGS_OTHER}
  ${GTK3_CFLAGS_OTHER}
)

target_compile_definitions(ThotEditor PUBLIC
  ${wxWidgets_DEFINITIONS}
  WX_PRECOMP
  # Use OpenGL compatibility profile (Amaya uses fixed-function GL)
  GL_GLEXT_PROTOTYPES
)

# ── Compile ALL thotlib sources as C++ ───────────────────────────────────────
# The original Makefile.in uses g++ for .c files because thot_gui_wx.h
# contains unguarded C++ class declarations that C files include transitively.
get_target_property(THOTEDITOR_SOURCES ThotEditor SOURCES)
foreach(src ${THOTEDITOR_SOURCES})
  if(src MATCHES "\\.c$")
    set_source_files_properties(${src} PROPERTIES LANGUAGE CXX)
  endif()
endforeach()
