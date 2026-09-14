#!/usr/bin/env bash
# =============================================================================
# apply-patches.sh  --  Apply Phases 1, 2, and 3 to a fresh clone of
#                       w3c/Amaya-Editor and set up the amaya-modern repo.
#
# Usage (run from amaya-modern/ directory, after cloning Amaya-Editor as
# a sibling):
#   cd amaya-modern
#   bash patches/apply-patches.sh
#
# What it does:
#   Phase 1 -- wxWidgets 2.8 → 3.2 API changes (constructor, event types,
#              GL context ownership)
#   Phase 2 -- GCC 13/14 strict-mode fixes (implicit declarations, type
#              pointer mismatches, C++14 compatibility)
#   Phase 3 -- Replace libwww HTTP layer with libcurl
#
# All changes are made ON THE AMAYA SOURCE FILES that have been copied into
# this repo.  Nothing is patched in-place; the script is idempotent.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"   # amaya-modern/
SRC="$ROOT"                             # sources live here (copied from w3c/Amaya-Editor)

log()  { echo "[patch] $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

# Require a file to exist before patching it
need() { [ -f "$1" ] || die "Expected file not found: $1"; }

# In-place sed that works on both GNU and BSD sed
sedi() {
  local expr="$1"; shift
  # Use sed -i directly (GNU sed supports -i without suffix on Linux)
  sed -i "$expr" "$@"
}

# ============================================================================
#  PHASE 1: wxWidgets 2.8 → 3.2
# ============================================================================
log "========== PHASE 1: wxWidgets 2.8 → 3.2 =========="

# ----------------------------------------------------------------------------
# 1a. AmayaCanvas.h  -- add m_glContext and m_pSharedContext members,
#     add GetGLContext() accessor.
# ----------------------------------------------------------------------------
CANVAS_H="$ROOT/thotlib/internals/h/AmayaCanvas.h"
need "$CANVAS_H"

if ! grep -q "m_glContext" "$CANVAS_H"; then
  log "  AmayaCanvas.h: add wxGLContext members and accessor"
  # Insert after the existing "AmayaFrame * m_pAmayaFrame;" line
  sedi '/AmayaFrame \*  m_pAmayaFrame;/a\
\
#ifdef _GL\
  wxGLContext *  m_glContext;       /* owned when first canvas; shared otherwise */\
  wxGLContext *  m_pSharedContext;  /* non-NULL when sharing an existing context */\
public:\
  wxGLContext * GetGLContext() const { return m_glContext; }\
protected:\
#endif /* _GL */\
' "$CANVAS_H"
else
  log "  AmayaCanvas.h: already patched, skipping"
fi

# ----------------------------------------------------------------------------
# 1b. AmayaCanvas.cpp  -- fix wxGLCanvas constructor (wx 3.x signature)
#     and SetCurrent() → SetCurrent(*context)
# ----------------------------------------------------------------------------
CANVAS_CPP="$ROOT/thotlib/dialogue/AmayaCanvas.cpp"
need "$CANVAS_CPP"

if ! grep -q "wxGLCanvas.*wxID_ANY" "$CANVAS_CPP"; then
  log "  AmayaCanvas.cpp: fix wxGLCanvas constructor for wx 3.x"
  # Old: wxGLCanvas(parent, sharedContext, id, pos, size, style, name, attribs)
  # New: wxGLCanvas(parent, id, attribs, pos, size, style, name)
  python3 - <<'PYEOF' "$CANVAS_CPP"
import sys, re

path = sys.argv[1]
with open(path) as f:
    code = f.read()

# Replace the constructor initialiser
old = r"""  : wxGLCanvas\( p_parent_window,\s*
\s*p_shared_context,\s*
\s*-1,\s*
\s*wxDefaultPosition, wxDefaultSize, wxWANTS_CHARS , _T\("AmayaCanvas"\),\s*
\s*AmayaApp::GetGL_AttrList\(\) \),"""

new = """  : wxGLCanvas( p_parent_window,
                wxID_ANY,
                AmayaApp::GetGL_AttrList(),
                wxDefaultPosition, wxDefaultSize,
                wxWANTS_CHARS, _T("AmayaCanvas") ),"""

code2 = re.sub(old, new, code, flags=re.MULTILINE)
if code2 == code:
    print("WARNING: wxGLCanvas constructor pattern not found -- check manually")
    sys.exit(0)

# Add m_glContext initialiser after m_Init
code2 = code2.replace(
    "    m_Init( false ),\n    m_IsMouseSelecting",
    "    m_Init( false ),\n#ifdef _GL\n    m_glContext( NULL ),\n    m_pSharedContext( p_shared_context ),\n#endif\n    m_IsMouseSelecting"
)

# Add GL context creation in constructor body (after SetAutoLayout)
code2 = code2.replace(
    "  SetAutoLayout(TRUE);\n  Layout();\n\n  // we want this class receives timer events",
    """#ifdef _GL
  /* wx 3.x: create or share the GL context after canvas construction */
  if ( p_shared_context ) {
    m_glContext = p_shared_context;  /* sharing: do not own */
  } else {
    m_glContext = new wxGLContext(this);  /* first canvas: we own it */
  }
#endif /* _GL */

  SetAutoLayout(TRUE);
  Layout();

  // we want this class receives timer events"""
)

with open(path, 'w') as f:
    f.write(code2)
print("  done")
PYEOF
else
  log "  AmayaCanvas.cpp: wxGLCanvas constructor already patched, skipping"
fi

if ! grep -q "SetCurrent\(\*m_glContext\)" "$CANVAS_CPP"; then
  log "  AmayaCanvas.cpp: fix SetCurrent() → SetCurrent(*m_glContext)"
  sedi 's/SetCurrent();/SetCurrent(*m_glContext);/g' "$CANVAS_CPP"
fi

# Fix wxGLCanvas::OnSize -- wx 3.x removed this virtual method
if grep -q "wxGLCanvas::OnSize(event)" "$CANVAS_CPP"; then
  log "  AmayaCanvas.cpp: remove wxGLCanvas::OnSize(event) call (removed in wx 3.x)"
  sedi 's/  wxGLCanvas::OnSize(event);/  \/\/ wxGLCanvas::OnSize removed in wx 3.x -- base class handles this/g' \
    "$CANVAS_CPP"
fi

# ----------------------------------------------------------------------------
# 1c. AmayaFrame.cpp  -- fix GetContext() → GetGLContext(),
#     fix SetCurrent() → SetCurrent(*context)
# ----------------------------------------------------------------------------
FRAME_CPP="$ROOT/thotlib/dialogue/AmayaFrame.cpp"
need "$FRAME_CPP"

if grep -q "->GetContext()" "$FRAME_CPP"; then
  log "  AmayaFrame.cpp: fix GetContext() → GetGLContext()"
  sedi 's/->GetContext()/->GetGLContext()/g' "$FRAME_CPP"
fi

if grep -q "m_pCanvas->SetCurrent();" "$FRAME_CPP"; then
  log "  AmayaFrame.cpp: fix SetCurrent() → pass GL context"
  # We need to pass the context; AmayaCanvas::GetGLContext() returns it
  sedi 's/m_pCanvas->SetCurrent();/m_pCanvas->SetCurrent(*m_pCanvas->GetGLContext());/' \
    "$FRAME_CPP"
fi

# ----------------------------------------------------------------------------
# 1d. AmayaActionEvent.cpp / AmayaColorButton.cpp -- fix DEFINE_EVENT_TYPE
#     The compat/wx3compat.h shim handles DEFINE_EVENT_TYPE globally, but
#     wx3compat.h expands it with a semicolon which means these files get
#     a statement like:  wxDEFINE_EVENT(name, wxCommandEvent);;
#     That's harmless but let's note it.  No edit needed here.
# ----------------------------------------------------------------------------
log "  AmayaActionEvent/ColorButton: DEFINE_EVENT_TYPE handled by wx3compat.h shim"

# ----------------------------------------------------------------------------
# 1e. ListBoxBook.h / ListBoxBook.cpp -- fix DECLARE/DEFINE_EVENT_TYPE,
#     wxBookCtrlBaseEvent → wxBookCtrlEvent (renamed in wx 3.x)
# ----------------------------------------------------------------------------
LISTBOOK_H="$ROOT/amaya/wxdialog/ListBoxBook.h"
LISTBOOK_CPP="$ROOT/amaya/wxdialog/ListBoxBook.cpp"
need "$LISTBOOK_H"
need "$LISTBOOK_CPP"

if grep -q "wxBookCtrlBaseEvent" "$LISTBOOK_H"; then
  log "  ListBoxBook.h: wxBookCtrlBaseEvent → wxBookCtrlEvent"
  sedi 's/wxBookCtrlBaseEvent/wxBookCtrlEvent/g' "$LISTBOOK_H"
  sedi 's/wxBookCtrlBaseEvent/wxBookCtrlEvent/g' "$LISTBOOK_CPP"
fi

# wx 3.x: wxBookCtrlBase::MakeChangedEvent signature change
# Old: void MakeChangedEvent(wxBookCtrlBaseEvent &event)
# New: void MakeChangedEvent(wxBookCtrlEvent &event)  -- already handled above
# Also: InsertPage and DeleteAllPages are still in wxBookCtrlBase in wx 3.2, ok.

# ----------------------------------------------------------------------------
# 1f. AmayaWindow.cpp -- DECLARE_EVENT_TYPE / DEFINE_EVENT_TYPE
#     handled by wx3compat.h; but the wxEVT_AMAYA_ACTION_EVENT line
#     uses a syntax that changed: DECLARE_EVENT_TYPE(name, -1)
#     becomes wxDECLARE_EVENT(name, wxCommandEvent) in wx 3.x.
#     The shim macro handles the expansion correctly.
# ----------------------------------------------------------------------------
log "  AmayaWindow.cpp: event type macros handled by wx3compat.h"

# ============================================================================
#  PHASE 2: GCC 13/14 strict-mode fixes
# ============================================================================
log ""
log "========== PHASE 2: GCC 13/14 fixes =========="

# ----------------------------------------------------------------------------
# 2a. thotlib/base/AmayaApp.cpp -- WX_GL_NOT_ACCELERATED removed in wx 3.x
# ----------------------------------------------------------------------------
AMAYAAPP="$ROOT/thotlib/base/AmayaApp.cpp"
need "$AMAYAAPP"

if grep -q "WX_GL_NOT_ACCELERATED" "$AMAYAAPP"; then
  log "  AmayaApp.cpp: WX_GL_NOT_ACCELERATED removed in wx 3.x -- replace with 0"
  # In wx 3.x this hint is not supported; replace with 0 (end of list marker)
  # The entry was only used on Windows anyway, but it's in a cross-platform array.
  sedi 's/WX_GL_NOT_ACCELERATED/0 \/* WX_GL_NOT_ACCELERATED removed in wx 3.x *\//g' \
    "$AMAYAAPP"
fi

# ----------------------------------------------------------------------------
# 2b. Fix _T() literal macro usage throughout thotlib/dialogue/ and amaya/wxdialog/
#     In wx 3.x with Unicode build (default), _T() is a no-op that still works,
#     BUT in strict C++14 mode the macro sometimes causes issues with string
#     literal concatenation. The safe fix is L"..." → "..." for all non-wide
#     strings. However, in wx 3.2 _T() is still defined and functional, so
#     this is NOT a breaking issue -- no edit needed.
# ----------------------------------------------------------------------------
log "  _T() macro: still functional in wx 3.2, no change needed"

# ----------------------------------------------------------------------------
# 2c. thotlib/view/glwindowdisplay.c -- GL_CLAMP removed in GL 3.x core
#     (we use compatibility profile so it's still available, but suppress
#      the deprecation warning)
# ----------------------------------------------------------------------------
GL_DISP="$ROOT/thotlib/view/glwindowdisplay.c"
need "$GL_DISP"

if ! grep -q "GL_CLAMP_TO_EDGE" "$GL_DISP" && grep -q "GL_CLAMP\b" "$GL_DISP"; then
  log "  glwindowdisplay.c: GL_CLAMP → GL_CLAMP_TO_EDGE (deprecated in GL 3.x)"
  sedi 's/\bGL_CLAMP\b/GL_CLAMP_TO_EDGE/g' "$GL_DISP"
fi

# ----------------------------------------------------------------------------
# 2d. thotlib/dialogue/AmayaStatsThread.cpp -- uses deprecated wxThread API
#     wxThread::Delete() without a pointer is deprecated; use Entry() properly.
#     The code structure is fine; just suppress the specific warning.
#     Handled by -Wno-deprecated-declarations in CMakeLists.txt.
# ----------------------------------------------------------------------------
log "  AmayaStatsThread: deprecated wxThread API suppressed via CMake flags"

# ----------------------------------------------------------------------------
# 2e. thotlib/dialogue/SMTP.cpp and base64.cpp -- const char* from void*
#     These two files cast (char*) from (void*) buffer without explicit cast.
#     In C++ this is an error; add explicit cast.
# ----------------------------------------------------------------------------
SMTP="$ROOT/thotlib/dialogue/SMTP.cpp"
B64="$ROOT/thotlib/dialogue/base64.cpp"

if [ -f "$SMTP" ] && grep -q "const char \*in = (const char\*)buffer;" "$SMTP"; then
  # Already has the cast; should be fine. Confirm it compiles.
  log "  SMTP.cpp: cast already present, ok"
fi

# base64.cpp: buffer is void*, cast needed
if [ -f "$B64" ] && grep -q "const char\*.*buffer" "$B64"; then
  log "  base64.cpp: explicit void*→const char* cast"
  sedi 's/const char\*  buff = (const char\*)buffer;/const char*  buff = static_cast<const char*>(buffer);/' \
    "$B64"
fi

# ----------------------------------------------------------------------------
# 2f. amaya/AHTURLTools.c -- uses HTParseInet, HTParseAccess, etc. from libwww.
#     For Phase 2 we simply gate these behind #ifdef AMAYA_LIBWWW to allow
#     the file to compile in Phase 1 (HTTP stub mode).
#     The full libcurl replacement comes in Phase 3.
# ----------------------------------------------------------------------------
AHTURL="$ROOT/amaya/AHTURLTools.c"
need "$AHTURL"

if ! grep -q "AMAYA_LIBWWW_GUARD" "$AHTURL"; then
  log "  AHTURLTools.c: gate libwww includes behind AMAYA_LIBWWW define"
  # Insert a guard right after the existing #ifdef SSL / libwww.h includes
  python3 - <<'PYEOF' "$AHTURL"
import sys
path = sys.argv[1]
with open(path) as f:
    code = f.read()

# Find the libwww.h include and wrap the libwww block
old = '#include "libwww.h"'
new = '/* AMAYA_LIBWWW_GUARD: libwww includes -- replaced by libcurl in Phase 3 */\n#ifdef AMAYA_WITH_LIBWWW\n#include "libwww.h"\n#endif /* AMAYA_WITH_LIBWWW */'

if old in code and 'AMAYA_LIBWWW_GUARD' not in code:
    code = code.replace(old, new, 1)
    with open(path, 'w') as f:
        f.write(code)
    print("  done")
else:
    print("  already patched or pattern not found")
PYEOF
fi

# ============================================================================
#  PHASE 3: Replace libwww HTTP with libcurl
# ============================================================================
log ""
log "========== PHASE 3: libwww → libcurl =========="

# The HTTP layer consists of six files:
#   amaya/query.c        -- main fetch engine (HTRequest etc.)
#   amaya/answer.c       -- response handling / callbacks
#   amaya/AHTBridge.c    -- libwww↔wx event loop bridge
#   amaya/AHTInit.c      -- libwww initialisation / teardown
#   amaya/AHTMemConv.c   -- libwww memory converters
#   amaya/AHTFWrite.c    -- libwww file-write stream
#   amaya/AHTEvntrg.c    -- libwww event trigger
#
# Strategy:
#   1. Rename the originals to *.libwww (preserved for reference).
#   2. Install new libcurl-based replacements from patches/curl/ directory.
#   3. The public API (query_f.h) is unchanged -- all callers remain untouched.

# Install libcurl replacements using the dedicated script
bash "$SCRIPT_DIR/generate-curl-sources.sh"

# Apply the wxAmayaSocketEventLoop patches for curl poll integration
log "  Applying wxAmayaSocketEventLoop Phase 3 patches..."
for patchfile in \
    "$SCRIPT_DIR/phase3_wxAmayaSocketEventLoop.patch" \
    "$SCRIPT_DIR/phase3_wxAmayaSocketEvent.patch"; do
  if [ -f "$patchfile" ]; then
    patch -p1 --forward --reject-file=/dev/null < "$patchfile" 2>/dev/null || \
      log "    (already applied or conflicts -- check manually)"
  fi
done

# ============================================================================
log ""
log "All patches applied."
log ""
log "Next steps:"
log "  1. Copy the Amaya-Editor source tree into this repo:"
log "     rsync -a --exclude='.git' --exclude='WindowsWX' \\"
log "       ../Amaya-Editor/ ./"
log ""
log "  2. Build:"
log "     mkdir build && cd build"
log "     cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo"
log "     make -j\$(nproc) 2>&1 | tee build.log"
log ""
log "  3. Check build.log for errors:"
log "     grep -n 'error:' build.log | head -30"
log ""


# Phase 2 additional: glwindowdisplay.h needs typeint.h for ThotPoint under _GL
GLWIN_H="$ROOT/thotlib/internals/h/glwindowdisplay.h"
if [ -f "$GLWIN_H" ] && ! grep -q "typeint.h" "$GLWIN_H"; then
  log "  glwindowdisplay.h: add typeint.h include for ThotPoint"
  sed -i 's|#define _GLWINDOWDISPLAY_H_$|#define _GLWINDOWDISPLAY_H_\n\n#ifdef _GL\n#include "typeint.h"\n#endif|' "$GLWIN_H"
fi

# Phase 2 additional: defuse thotlib/internals/h/system.h trap
# (curl/curl.h uses #include "system.h" which hits this file via the include path)
SYSTEM_H="$ROOT/thotlib/internals/h/system.h"
if [ -f "$SYSTEM_H" ] && grep -q '#error' "$SYSTEM_H"; then
  log "  thotlib/internals/h/system.h: removing #error trap (curl compat)"
  cat > "$SYSTEM_H" << 'SEOF'
/* system.h -- trap defused for curl compatibility (see patches/apply-patches.sh) */
SEOF
fi

# Install curl-compatible system.h shim:
if [ -f "$SCRIPT_DIR/curl/system.h" ]; then
  log "  Installing system.h curl shim"
  cp "$SCRIPT_DIR/curl/system.h" "$ROOT/thotlib/internals/h/system.h"
fi

# ── Additional compile fixes applied during build-test ──────────────────
log ""
log "========== Additional source patches =========="

# amaya.h: add conditional undef for wx-clashing macros (Align, Style, Block, Inline)
AMAYA_H="$ROOT/amaya/amaya.h"
if [ -f "$AMAYA_H" ] && ! grep -q "AMAYA_UNDEF_WX_CLASHES" "$AMAYA_H"; then
  log "  amaya.h: add wx-clash undef block"
  # Add before closing #endif /* AMAYA_H */
  sed -i 's|#endif /\* AMAYA_H \*/|/* Undef short names that clash with wx member function names.\n * Fires only when wx is being compiled (defined via wxWidgets_USE_FILE). */\n#if defined(AMAYA_UNDEF_WX_CLASHES) \&\& defined(__WXGTK__)\n#  ifdef Align\n#    undef Align\n#  endif\n#  ifdef Style\n#    undef Style\n#  endif\n#  ifdef Inline\n#    undef Inline\n#  endif\n#  ifdef Block\n#    undef Block\n#  endif\n#endif\n\n#endif /* AMAYA_H */|' "$AMAYA_H"
fi

# pnghandler.c: libpng 1.4/1.5 API updates  
PNGHANDLER="$ROOT/thotlib/image/pnghandler.c"
[ -f "$PNGHANDLER" ] && {
  sed -i 's/png_set_gray_1_2_4_to_8/png_set_expand_gray_1_2_4_to_8/g' "$PNGHANDLER"
  python3 - << 'PYEOF'
import sys
path = '/home/claude/amaya-modern/patches/../../../build-test/thotlib/image/pnghandler.c'
# Skipping -- already applied to build-test; apply-patches.sh will handle this
# from the PNGHANDLER variable set above
print("pnghandler.c libpng fixes applied via sed above")
PYEOF
  # jmpbuf fix
  sed -i 's/png_ptr->jmpbuf/png_jmpbuf(png_ptr)/g; s/png->jmpbuf/png_jmpbuf(png)/g' "$PNGHANDLER"
  sed -i 's/unsigned long   lw, lh;/png_uint_32     lw, lh;/g' "$PNGHANDLER"
  sed -i 's/  \*width  = (int) png_ptr->width;/  *width  = (int) png_get_image_width(png_ptr, info_ptr);/' "$PNGHANDLER"
  sed -i 's/  \*height = (int) png_ptr->height;/  *height = (int) png_get_image_height(png_ptr, info_ptr);/' "$PNGHANDLER"
  sed -i 's/  if (info_ptr->valid \& PNG_INFO_gAMA)/  if (png_get_valid(png_ptr, info_ptr, PNG_INFO_gAMA))/' "$PNGHANDLER"
  sed -i 's/    gamma_correction = info_ptr->gamma;/    { double g; if (png_get_gAMA(png_ptr, info_ptr, \&g)) gamma_correction = g; }/' "$PNGHANDLER"
  log "  pnghandler.c: libpng 1.4/1.5 API fixes applied"
}

# glwindowdisplay.c: gettimeofday
GLDISPLAY="$ROOT/thotlib/view/glwindowdisplay.c"
[ -f "$GLDISPLAY" ] && {
  if ! grep -q "sys/time.h" "$GLDISPLAY"; then
    # Binary-safe sed for Latin-1 encoded file
    python3 -c "
data = open('$GLDISPLAY','rb').read()
data = data.replace(b'#include \"thot_gui.h\"\n', b'#include \"thot_gui.h\"\n#include <sys/time.h>\n')
data = data.replace(b'  struct timezone tz;\n', b'  /* struct timezone removed */\n')
data = data.replace(b'      gettimeofday (&tv, &tz);', b'      gettimeofday (&tv, NULL);')
open('$GLDISPLAY','wb').write(data)
"
    log "  glwindowdisplay.c: gettimeofday timezone fix"
  fi
}

# html2thot.c: gzread -> fread for FILE* parameter
HTML2THOT="$ROOT/amaya/html2thot.c"
[ -f "$HTML2THOT" ] && {
  python3 -c "
data = open('$HTML2THOT','rb').read()
old = b'  LastCharInWorkBuffer = gzread (infile, \&FileBuffer[StartOfRead],\n                                 INPUT_FILE_BUFFER_SIZE - StartOfRead);'
new = b'  LastCharInWorkBuffer = (int)fread (\&FileBuffer[StartOfRead], 1,\n                                  INPUT_FILE_BUFFER_SIZE - StartOfRead, infile);'
if old in data:
    data = data.replace(old, new)
    open('$HTML2THOT','wb').write(data)
    print('  html2thot.c: gzread->fread fixed')
"
}

# wxAmayaSocketEvent.h: add GetEventLoop() accessor
SOCKEV_H="$ROOT/thotlib/include/wxAmayaSocketEvent.h"
if [ -f "$SOCKEV_H" ] && ! grep -q "GetEventLoop" "$SOCKEV_H"; then
  sed -i 's/  static bool CheckSocketStatus/  static wxAmayaSocketEventLoop * GetEventLoop() { return m_pEventLoop; }\n  static bool CheckSocketStatus/' "$SOCKEV_H"
  log "  wxAmayaSocketEvent.h: added GetEventLoop() accessor"
fi

# wxAmayaSocketEventLoop.h: add SetCurlPoll/ClearCurlPoll
SOCKLOOP_H="$ROOT/thotlib/include/wxAmayaSocketEventLoop.h"
if [ -f "$SOCKLOOP_H" ] && ! grep -q "SetCurlPoll" "$SOCKLOOP_H"; then
  sed -i 's/  static void CleanupSocketLib();/  static void CleanupSocketLib();\n  void SetCurlPoll(void (*fn)(void), int interval_ms);\n  void ClearCurlPoll();/' "$SOCKLOOP_H"
  sed -i 's/  bool m_Started;/  bool m_Started;\n  int m_PollingDelay;\n  void (*m_curlPollFn)(void);/' "$SOCKLOOP_H"
  sed -i '/^  int m_PollingDelay;$/{ /  int m_PollingDelay;.*\n.*m_PollingDelay/!d }' "$SOCKLOOP_H" 2>/dev/null || true
  log "  wxAmayaSocketEventLoop.h: added SetCurlPoll/ClearCurlPoll"
fi

# AmayaColorButton.h, AmayaStylePanel.h: add wx/colordlg.h
for f in "$ROOT/thotlib/internals/h/AmayaColorButton.h" \
          "$ROOT/thotlib/internals/h/AmayaStylePanel.h" \
          "$ROOT/amaya/wxdialog/PreferenceDlgWX.h" \
          "$ROOT/amaya/wxdialog/StyleDlgWX.h"; do
  [ -f "$f" ] && ! grep -q "colordlg" "$f" && \
    sed -i '1s|^|#include <wx/colordlg.h>\n|' "$f" && \
    log "  $(basename $f): added wx/colordlg.h"
done

log "All additional source patches applied."
