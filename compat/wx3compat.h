
/* -----------------------------------------------------------------------
 * 12. Pre-define FALSE and TRUE as integer constants.
 *     thot_sys.h redefines them as C++ 'false'/'true' inside #ifndef guards,
 *     which breaks old C code that returns FALSE from pointer-returning
 *     functions (char* fn() { return FALSE; } -- C ok, C++ error).
 *     By defining them here first (before thot_sys.h), the #ifndef guards
 *     in thot_sys.h are satisfied and the bool versions are suppressed.
 * --------------------------------------------------------------------- */
#ifndef FALSE
#  define FALSE 0
#endif
#ifndef TRUE
#  define TRUE 1
#endif
/*
 * compat/wx3compat.h
 *
 * wxWidgets 2.8 → 3.2 compatibility shims for Amaya.
 * Injected into every translation unit via CMake forced-include:
 *   target_compile_options(... -include ${CMAKE_SOURCE_DIR}/compat/wx3compat.h)
 * No source file needs editing just for these renames.
 */

#ifndef AMAYA_WX3COMPAT_H
#define AMAYA_WX3COMPAT_H

/* -----------------------------------------------------------------------
 * 1.  wxEVT_COMMAND_* renamed to wxEVT_* in wx 3.x
 * --------------------------------------------------------------------- */
#ifndef wxEVT_COMMAND_BUTTON_CLICKED
#  define wxEVT_COMMAND_BUTTON_CLICKED       wxEVT_BUTTON
#endif
#ifndef wxEVT_COMMAND_MENU_SELECTED
#  define wxEVT_COMMAND_MENU_SELECTED        wxEVT_MENU
#endif
#ifndef wxEVT_COMMAND_TEXT_UPDATED
#  define wxEVT_COMMAND_TEXT_UPDATED         wxEVT_TEXT
#endif
#ifndef wxEVT_COMMAND_TEXT_ENTER
#  define wxEVT_COMMAND_TEXT_ENTER           wxEVT_TEXT_ENTER
#endif
#ifndef wxEVT_COMMAND_COMBOBOX_SELECTED
#  define wxEVT_COMMAND_COMBOBOX_SELECTED    wxEVT_COMBOBOX
#endif
#ifndef wxEVT_COMMAND_CHECKBOX_CLICKED
#  define wxEVT_COMMAND_CHECKBOX_CLICKED     wxEVT_CHECKBOX
#endif
#ifndef wxEVT_COMMAND_CHOICE_SELECTED
#  define wxEVT_COMMAND_CHOICE_SELECTED      wxEVT_CHOICE
#endif
#ifndef wxEVT_COMMAND_LISTBOX_SELECTED
#  define wxEVT_COMMAND_LISTBOX_SELECTED     wxEVT_LISTBOX
#endif
#ifndef wxEVT_COMMAND_LISTBOX_DOUBLECLICKED
#  define wxEVT_COMMAND_LISTBOX_DOUBLECLICKED wxEVT_LISTBOX_DCLICK
#endif
#ifndef wxEVT_COMMAND_RADIOBUTTON_SELECTED
#  define wxEVT_COMMAND_RADIOBUTTON_SELECTED wxEVT_RADIOBUTTON
#endif
#ifndef wxEVT_COMMAND_RADIOBOX_SELECTED
#  define wxEVT_COMMAND_RADIOBOX_SELECTED    wxEVT_RADIOBOX
#endif
#ifndef wxEVT_COMMAND_SLIDER_UPDATED
#  define wxEVT_COMMAND_SLIDER_UPDATED       wxEVT_SLIDER
#endif
#ifndef wxEVT_COMMAND_NOTEBOOK_PAGE_CHANGED
#  define wxEVT_COMMAND_NOTEBOOK_PAGE_CHANGED  wxEVT_NOTEBOOK_PAGE_CHANGED
#endif
#ifndef wxEVT_COMMAND_NOTEBOOK_PAGE_CHANGING
#  define wxEVT_COMMAND_NOTEBOOK_PAGE_CHANGING wxEVT_NOTEBOOK_PAGE_CHANGING
#endif
#ifndef wxEVT_COMMAND_SPINCTRL_UPDATED
#  define wxEVT_COMMAND_SPINCTRL_UPDATED     wxEVT_SPINCTRL
#endif
#ifndef wxEVT_COMMAND_TREE_ITEM_ACTIVATED
#  define wxEVT_COMMAND_TREE_ITEM_ACTIVATED  wxEVT_TREE_ITEM_ACTIVATED
#endif
#ifndef wxEVT_COMMAND_TREE_SEL_CHANGED
#  define wxEVT_COMMAND_TREE_SEL_CHANGED     wxEVT_TREE_SEL_CHANGED
#endif

/* -----------------------------------------------------------------------
 * 2.  DEFINE_EVENT_TYPE / DECLARE_EVENT_TYPE
 *     wx 3.x replaced these with wxDEFINE_EVENT / wxDECLARE_EVENT.
 *     ListBoxBook.h/.cpp use the old macros for custom events.
 * --------------------------------------------------------------------- */
#ifndef DEFINE_EVENT_TYPE
#  define DEFINE_EVENT_TYPE(name)  wxDEFINE_EVENT(name, wxCommandEvent);
#endif
#ifndef DECLARE_EVENT_TYPE
/* The second argument (id) was a hint for wx 2.x and is ignored in 3.x */
#  define DECLARE_EVENT_TYPE(name, id) \
     wxDECLARE_EXPORTED_EVENT(, name, wxCommandEvent);
#endif

/* -----------------------------------------------------------------------
 * 3.  AmayaWindow.cpp declares wxEVT_AMAYA_ACTION_EVENT with the old
 *     DECLARE/DEFINE pair.  The shim above handles it.
 *     AmayaActionEvent.cpp and AmayaColorButton.cpp define
 *     AMAYA_ACTION_EVENT and AMAYA_COLOR_CHANGED the same way.
 * --------------------------------------------------------------------- */

/* -----------------------------------------------------------------------
 * 4.  wxGLCanvas constructor changed in wx 3.0:
 *     Old: wxGLCanvas(parent, sharedContext, id, pos, size, style, name, attribs)
 *     New: wxGLCanvas(parent, id, attribs, pos, size, style, name)
 *          + separate wxGLContext object owned by the application.
 *
 *     AmayaCanvas.cpp is patched directly (see patches/AmayaCanvas.cpp.patch)
 *     because the constructor signature change cannot be shimmed.
 * --------------------------------------------------------------------- */

/* -----------------------------------------------------------------------
 * 5.  wxBookCtrlBase / wxBookCtrlBaseEvent  --  still in wx 3.2, no shim.
 *     wxFULL_REPAINT_ON_RESIZE              --  still in wx 3.2 as 0, no shim.
 *     wxSYS_DEFAULT_GUI_FONT                --  still accepted, no shim.
 * --------------------------------------------------------------------- */



/* -----------------------------------------------------------------------
 * 9.  C standard headers that old C code assumed were transitively included
 *     but C++ (stricter) requires explicitly.
 * --------------------------------------------------------------------- */
#ifdef __cplusplus
#  include <ctime>
#  include <cstring>
#  include <cstdio>
#  include <cstdlib>
#  include <cmath>
#  include <cctype>
#  include <cwctype>
#  include <cerrno>
#  include <cstdint>
#endif


/* -----------------------------------------------------------------------
 * 10. wx 3.x key code renames
 * --------------------------------------------------------------------- */
#ifndef WXK_PRIOR
#  define WXK_PRIOR   WXK_PAGEUP
#endif
#ifndef WXK_NEXT
#  define WXK_NEXT    WXK_PAGEDOWN
#endif


/* -----------------------------------------------------------------------
 * 11. wx 3.x file dialog flag renames
 *     (wxSAVE, wxOPEN etc. replaced by wxFD_* prefix in wx 2.9+)
 * --------------------------------------------------------------------- */
#ifndef wxFD_SAVE
#  define wxFD_SAVE          wxSAVE
#  define wxFD_OPEN          wxOPEN
#  define wxFD_OVERWRITE_PROMPT  wxOVERWRITE_PROMPT
#  define wxFD_FILE_MUST_EXIST   wxFILE_MUST_EXIST
#  define wxFD_MULTIPLE      wxMULTIPLE
#  define wxFD_CHANGE_DIR    wxCHANGE_DIR
#else
/* wx 3.x defines wxFD_* -- provide the old names as aliases */
#  ifndef wxSAVE
#    define wxSAVE           wxFD_SAVE
#  endif
#  ifndef wxOPEN
#    define wxOPEN            wxFD_OPEN
#  endif
#  ifndef wxCHANGE_DIR
#    define wxCHANGE_DIR      wxFD_CHANGE_DIR
#  endif
#  ifndef wxOVERWRITE_PROMPT
#    define wxOVERWRITE_PROMPT wxFD_OVERWRITE_PROMPT
#  endif
#  ifndef wxFILE_MUST_EXIST
#    define wxFILE_MUST_EXIST  wxFD_FILE_MUST_EXIST
#  endif
#  ifndef wxMULTIPLE
#    define wxMULTIPLE        wxFD_MULTIPLE
#  endif
#endif


/* -----------------------------------------------------------------------
 * 12. THOT_EXPORT -- declared in Elemlist.h but not pulled in by all
 *     source files. Define it here so it's always available.
 * --------------------------------------------------------------------- */
#ifndef THOT_EXPORT
#  define THOT_EXPORT extern
#endif


/* -----------------------------------------------------------------------
 * 13. Define AMAYA_UNDEF_WX_CLASHES so amaya.h undefines short constants
 *     (Align, Style, Inline, Block) that clash with wx member names.
 *     This runs when wx3compat.h is force-included (i.e. always).
 * --------------------------------------------------------------------- */
#define AMAYA_UNDEF_WX_CLASHES 1

#endif /* AMAYA_WX3COMPAT_H */
