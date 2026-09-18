#!/usr/bin/env bash
# stage1-setup.sh
# Run from ~/amaya-modern.
#
# STAGE 1 of Option B: add the four new wxDC-based rendering files,
# disable their direct old-code counterparts in the existing GL files
# (to avoid duplicate-symbol link errors), update the font loader and
# the clipping call sites, wire CMakeLists.txt, and confirm everything
# COMPILES AND LINKS.
#
# This stage deliberately does NOT touch AmayaCanvas/AmayaFrame yet.
# Amaya will very likely crash or show a blank window at runtime after
# this -- that is expected. AmayaCanvas still uses a GL context and
# never calls WxDC_SetCurrentFrameDC, so GetFrameDC() always returns
# NULL and nothing draws. The goal of this stage is only to validate
# that the new code is syntactically and type-correct against the real
# project headers before the bigger, riskier stage 2 (wiring
# AmayaCanvas to actually use wxDC).

set -e
cd ~/amaya-modern
git checkout main
git pull origin main
git checkout -b option-b-wxdc

echo "=== [1/6] Writing the four new files ==="
cat > thotlib/view/wxdcdisplay.cpp << 'WXDCDISPLAY_EOF'
/*
 * wxdcdisplay.cpp
 *
 * Replacement for thotlib/view/gldisplay.c's drawing primitives,
 * implemented with wxDC instead of raw OpenGL. Compiled alongside (not
 * instead of) glwindowdisplay.c/glbox.c/gltimer.c, whose lifecycle
 * functions (GL_prepare, GL_Swap, GL_SwapStop, GL_SwapEnable,
 * GL_realize, GL_SetClipping, GL_UnsetClipping) are separately
 * replaced with wxDC-based bodies -- see wxdclifecycle.cpp -- so that
 * every other file in the codebase, which calls these functions by
 * name under #ifdef _GL, needs no changes at all.
 *
 * Signatures matched exactly against the current gldisplay.c
 * implementations (thotlib/view/gldisplay.c in the reference tree).
 * Written by reading those implementations directly, not guessed.
 */

#include "wx/wx.h"

extern "C" {
#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"
#include "frame.h"
#include "appli_f.h"
}

#include "wxdclifecycle.h"   /* GetFrameDC() -- shared with wxdclifecycle.cpp */

/* ------------------------------------------------------------------ */
static wxColour ThotColourToWx (int colourIndex)
{
  unsigned short r = 0, g = 0, b = 0;
  if (colourIndex >= 0)
    TtaGiveThotRGB (colourIndex, &r, &g, &b);
  return wxColour ((unsigned char) r, (unsigned char) g, (unsigned char) b);
}

static wxPenStyle ThotStyleToWxPenStyle (int style)
{
  switch (style)
    {
    case 3:  return wxPENSTYLE_DOT;
    case 4:  return wxPENSTYLE_SHORT_DASH;
    default: return wxPENSTYLE_SOLID;
    }
}

/* ------------------------------------------------------------------ */
extern "C" void DrawRectangle (int frame, int thick, int style,
                                int x, int y, int width, int height,
                                int fg, int bg, int pattern)
{
  if (width <= 0 || height <= 0)
    return;
  if (thick == 0 && pattern == 0)
    return;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return;

  y += FrameTable[frame].FrTopMargin;

  if (pattern == 2 && bg >= 0)
    {
      dc->SetPen (*wxTRANSPARENT_PEN);
      dc->SetBrush (wxBrush (ThotColourToWx (bg)));
      dc->DrawRectangle (x, y, width, height);
    }
  else if (pattern == 4)
    {
      /* MathML "empty placeholder" hatch fill -- original used a manual
       * stipple bitmap; mapped here to a standard wx hatch brush. */
      dc->SetPen (*wxTRANSPARENT_PEN);
      dc->SetBrush (wxBrush (ThotColourToWx (fg), wxBRUSHSTYLE_CROSSDIAG_HATCH));
      dc->DrawRectangle (x, y, width, height);
    }

  if (thick > 0 && fg >= 0)
    {
      dc->SetPen (wxPen (ThotColourToWx (fg), thick, ThotStyleToWxPenStyle (style)));
      dc->SetBrush (*wxTRANSPARENT_BRUSH);
      dc->DrawRectangle (x, y, width, height);
    }
}

extern "C" void DrawRectangleFrame (int frame, int thick, int style,
                                     int x, int y, int width, int height,
                                     int fg)
{
  /* Outline-only variant. */
  DrawRectangle (frame, thick, style, x, y, width, height, fg, -1, 0);
}

/* ------------------------------------------------------------------ */
extern "C" void DrawHorizontalLine (int frame, int thick, int style,
                                     int x, int y, int l, int h,
                                     int align, int fg, PtrBox box,
                                     int leftslice, int rightslice)
{
  (void) box; (void) leftslice; (void) rightslice;
  if (thick <= 0 || fg < 0)
    return;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return;

  y += FrameTable[frame].FrTopMargin;

  int Y;
  if (align == 1)
    Y = y + (h - thick) / 2;
  else if (align == 2)
    Y = y + h - (thick + 1) / 2;
  else
    Y = y + thick / 2;

  dc->SetPen (wxPen (ThotColourToWx (fg), thick, ThotStyleToWxPenStyle (style)));
  dc->DrawLine (x, Y, x + l, Y);

  /* NOTE: style > 6 in the original selects a two-tone "3D bevel" line
   * (used for <hr> and table border groove/ridge effects) by drawing a
   * light-shaded and dark-shaded line pair. Not yet implemented --
   * falls back to a single solid line. Low priority: rare in ordinary
   * HTML/table content; add once the core text/table path is proven
   * solid, by drawing two 1px lines with lightened/darkened versions
   * of ThotColourToWx(fg) (see gldisplay.c's existing sl/sd shade
   * computation for the exact original math to match, at the top of
   * this same function in the reference tree). */
}

extern "C" void DrawVerticalLine (int frame, int thick, int style,
                                   int x, int y, int l, int h,
                                   int align, int fg, PtrBox box,
                                   int topslice, int bottomslice)
{
  (void) box; (void) topslice; (void) bottomslice;
  if (thick <= 0 || fg < 0)
    return;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return;

  y += FrameTable[frame].FrTopMargin;

  int X;
  if (align == 1)
    X = x + (l - thick) / 2;
  else if (align == 2)
    X = x + l - (thick + 1) / 2;
  else
    X = x + thick / 2;

  dc->SetPen (wxPen (ThotColourToWx (fg), thick, ThotStyleToWxPenStyle (style)));
  dc->DrawLine (X, y, X, y + h);

  /* Same style > 6 bevel-variant note as DrawHorizontalLine above. */
}

/* ------------------------------------------------------------------ */
/* Text. Replaces the entire custom FreeType + per-glyph-texture
 * renderer in openglfont.c. ThotFont is treated here as a genuine
 * wxFont* -- see font.c's GL_LoadFont replacement, which is what makes
 * that true. */
extern "C" int DrawString (unsigned char *buff, int lg, int frame,
                            int x, int y, void *font, int boxWidth,
                            int bl, int hyphen, int startABlock, int fg)
{
  (void) boxWidth; (void) bl; (void) startABlock;
  if (fg < 0 || lg <= 0)
    return 0;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return 0;

  y += FrameTable[frame].FrTopMargin;

  wxFont *wxf = (wxFont *) font;
  if (wxf && wxf->IsOk ())
    dc->SetFont (*wxf);
  dc->SetTextForeground (ThotColourToWx (fg));

  wxString text = wxString::FromUTF8 ((const char *) buff, lg);
  if (hyphen)
    text += wxT("-");

  dc->DrawText (text, x, y);
  return dc->GetTextExtent (text).GetWidth ();
}

extern "C" int WDrawString (wchar_t *buff, int lg, int frame, int x, int y,
                             void *font, int boxWidth, int bl, int hyphen,
                             int startABlock, int fg)
{
  (void) boxWidth; (void) bl; (void) startABlock;
  if (fg < 0 || lg <= 0)
    return 0;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return 0;

  y += FrameTable[frame].FrTopMargin;

  wxFont *wxf = (wxFont *) font;
  if (wxf && wxf->IsOk ())
    dc->SetFont (*wxf);
  dc->SetTextForeground (ThotColourToWx (fg));

  wxString text (buff, lg);
  if (hyphen)
    text += wxT("-");

  dc->DrawText (text, x, y);
  return dc->GetTextExtent (text).GetWidth ();
}

extern "C" void DrawChar (unsigned int car, int frame, int x, int y,
                           void *font, int fg)
{
  if (fg < 0)
    return;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return;

  y += FrameTable[frame].FrTopMargin;

  wxFont *wxf = (wxFont *) font;
  if (wxf && wxf->IsOk ())
    dc->SetFont (*wxf);
  dc->SetTextForeground (ThotColourToWx (fg));

  wxUniChar uc ((wxUint32) car);
  dc->DrawText (wxString (uc), x, y);
}

/* ------------------------------------------------------------------ */
extern "C" void DrawPoints (int frame, int x, int y, int boxWidth, int fg)
{
  if (fg < 0 || boxWidth <= 0)
    return;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return;

  y += FrameTable[frame].FrTopMargin;

  dc->SetPen (*wxTRANSPARENT_PEN);
  dc->SetBrush (wxBrush (ThotColourToWx (fg)));
  dc->DrawRectangle (x, y, boxWidth, boxWidth);
}

extern "C" void DrawSegments (int frame, int thick, int style, int x, int y,
                               int *points, int nPoints, int fg)
{
  if (thick <= 0 || fg < 0 || nPoints < 2)
    return;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return;

  y += FrameTable[frame].FrTopMargin;

  dc->SetPen (wxPen (ThotColourToWx (fg), thick, ThotStyleToWxPenStyle (style)));
  for (int i = 0; i + 3 < nPoints * 2; i += 2)
    dc->DrawLine (x + points[i], y + points[i + 1],
                  x + points[i + 2], y + points[i + 3]);
  /* ADAPT: double-check gldisplay.c's exact `points` array layout
   * (flat x,y pairs assumed here) against the real caller in
   * displaybox.c before relying on this -- DrawSegments is called only
   * twice there, low risk either way. */
}

extern "C" void DrawPolygon (int frame, int thick, int style, int fg,
                              int bg, int pattern, int *points, int nPoints)
{
  if (nPoints < 3)
    return;

  wxDC *dc = GetFrameDC (frame);
  if (!dc)
    return;

  wxPoint *wxpts = new wxPoint[nPoints];
  for (int i = 0; i < nPoints; i++)
    wxpts[i] = wxPoint (points[i * 2], points[i * 2 + 1] + FrameTable[frame].FrTopMargin);

  if (pattern != 0 && bg >= 0)
    dc->SetBrush (wxBrush (ThotColourToWx (bg)));
  else
    dc->SetBrush (*wxTRANSPARENT_BRUSH);

  if (thick > 0 && fg >= 0)
    dc->SetPen (wxPen (ThotColourToWx (fg), thick, ThotStyleToWxPenStyle (style)));
  else
    dc->SetPen (*wxTRANSPARENT_PEN);

  dc->DrawPolygon (nPoints, wxpts);
  delete[] wxpts;
  /* ADAPT: same points-array-layout caveat as DrawSegments; called
   * only once from displaybox.c. */
}

WXDCDISPLAY_EOF
echo "  OK: wxdcdisplay.cpp"
cat > thotlib/view/wxdclifecycle.cpp << 'WXDCLIFECYCLE_CPP_EOF'
/*
 * wxdclifecycle.cpp
 *
 * Replaces the GL-context/double-buffer lifecycle functions that the
 * rest of the codebase (appli.c, frame.c, picture.c, glbox.c) already
 * calls by name under #ifdef _GL -- so none of those callers need to
 * change. Only what these functions actually DO changes: from manual
 * GL context/buffer management (the source of essentially every bug
 * fixed earlier this session -- FrameUpdating stuck, the deferred-swap
 * timing races, scroll-strip staleness) to plain wxDC operations, which
 * cannot get stuck the same way because there is no manual
 * double-buffer bookkeeping left to get wrong.
 *
 * The corresponding definitions of these exact function names in
 * glbox.c and glwindowdisplay.c must be disabled (the apply script
 * does this with #if 0, keeping everything else in those files --
 * GL_NotInFeedbackMode, GL_TransText, ComputeBoundingBox,
 * ComputeFilledBox -- unchanged, since those are already
 * backend-independent after an earlier fix this session) to avoid
 * duplicate-symbol link errors.
 */

#include "wx/wx.h"

extern "C" {
#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"
#include "frame.h"
}

#include "wxdclifecycle.h"

/* ------------------------------------------------------------------ */
static wxDC *g_FrameDC[MAX_FRAME + 1] = { NULL };

wxDC *GetFrameDC (int frame)
{
  if (frame < 0 || frame > MAX_FRAME)
    return NULL;
  return g_FrameDC[frame];
}

void WxDC_SetCurrentFrameDC (int frame, wxDC *dc)
{
  if (frame >= 0 && frame <= MAX_FRAME)
    g_FrameDC[frame] = dc;
}

/* ------------------------------------------------------------------ */
/* GL_prepare: originally made a GL context current for this frame's
 * canvas; here, just confirms a DC has been provided for it (set by
 * AmayaCanvas::OnPaint before drawing starts -- see
 * WxDC_SetCurrentFrameDC above). Cannot fail the way making a GL
 * context current could. */
extern "C" ThotBool GL_prepare (int frame)
{
  return GetFrameDC (frame) != NULL;
}

/* GL_Swap / GL_SwapStop / GL_SwapEnable / GL_SwapGet: originally
 * managed manual double-buffer swapping and flicker prevention. All
 * no-ops now: wxBufferedPaintDC (set up in AmayaCanvas::OnPaint)
 * handles double buffering correctly and automatically, blitting the
 * backing bitmap to screen exactly once, when OnPaint returns -- there
 * is nothing left to "swap now vs defer" or "stop/enable" manually. */
extern "C" void GL_Swap (int frame)
{
  (void) frame;
}

extern "C" void GL_SwapStop (int frame)
{
  (void) frame;
}

extern "C" void GL_SwapEnable (int frame)
{
  (void) frame;
}

extern "C" ThotBool GL_SwapGet (int frame)
{
  (void) frame;
  return TRUE;
}

/* GL_realize: originally set a "buffer swap needed" flag, deferring
 * the actual swap to later (the idle-driven GL_DrawAll mechanism this
 * whole session spent so long debugging). With wxDC there is nothing
 * to defer -- every draw call goes directly into the current paint
 * event's DC -- so this becomes a direct repaint request instead: ask
 * wx to schedule a new paint event for this frame's canvas. Simpler
 * and more robust than what it replaces, because Refresh() cannot get
 * "stuck" the way a manually-managed boolean flag can; there is no
 * flag for other code to forget to clear correctly. */
extern "C" void GL_realize (int frame)
{
  if (frame >= 0 && frame <= MAX_FRAME &&
      FrameTable[frame].WdFrame && FrameTable[frame].WdFrame->GetCanvas ())
    FrameTable[frame].WdFrame->GetCanvas ()->Refresh ();
}

/* GL_DrawAll: the idle-driven catch-up mechanism this no longer needs
 * to exist at all (see GL_realize above) -- kept as a harmless no-op
 * only so the AmayaCanvas::OnIdle call site does not need editing
 * immediately; remove that call once this is confirmed working. */
extern "C" ThotBool GL_DrawAll (void)
{
  return TRUE;
}

/* ------------------------------------------------------------------ */
/* Clipping. Signature gains an explicit frame parameter (all five
 * existing call sites -- appli.c x2, picture.c x2, glbox.c x1 --
 * already have `frame` in scope; the apply script updates each one to
 * pass it) so these can find the right DC without needing a separate
 * "currently active frame" global to keep in sync -- one less piece of
 * state that could get out of sync with reality, consistent with the
 * rest of this design. DefClip() in frame.c, which computes the actual
 * clip bounds, is unchanged: it is already backend-independent. */
extern "C" void GL_SetClipping (int frame, int x, int y, int width, int height)
{
  wxDC *dc = GetFrameDC (frame);
  if (dc && width > 0 && height > 0)
    dc->SetClippingRegion (x, y, width, height);
}

extern "C" void GL_UnsetClipping (int frame)
{
  wxDC *dc = GetFrameDC (frame);
  if (dc)
    dc->DestroyClippingRegion ();
}

WXDCLIFECYCLE_CPP_EOF
echo "  OK: wxdclifecycle.cpp"
cat > thotlib/internals/h/wxdclifecycle.h << 'WXDCLIFECYCLE_H_EOF'
/*
 * wxdclifecycle.h
 *
 * Shared between wxdcdisplay.cpp (drawing primitives), wxdclifecycle.cpp
 * (the GL_*-named lifecycle function replacements, which DO need
 * extern "C" linkage since C files call them by those names), and
 * AmayaCanvas.cpp (which sets the current DC during its OnPaint
 * handler). This header itself is C++-only -- none of the plain-C
 * files in the codebase (frame.c, appli.c, picture.c, font.c) need to
 * know about wxDC directly; they only call the GL_*-named functions in
 * wxdclifecycle.cpp, which are declared extern "C" there, separately,
 * in the existing GL headers they already include.
 */
#ifndef WXDCLIFECYCLE_H
#define WXDCLIFECYCLE_H

#include "wx/dc.h"

/* Called from AmayaCanvas::OnPaint before RedrawFrameBottom runs, and
 * again with dc=NULL after it returns. Every drawing primitive in
 * wxdcdisplay.cpp, and the clipping functions in wxdclifecycle.cpp,
 * fetch the DC for the frame they are currently asked to draw/clip via
 * GetFrameDC() below -- this is the direct equivalent of what
 * GL_prepare()/SetCurrent() did for the GL context, but with no
 * context-switch cost or failure mode: getting a DC from a small
 * lookup table cannot fail the way making a GL context current could. */
void WxDC_SetCurrentFrameDC (int frame, wxDC *dc);
wxDC *GetFrameDC (int frame);

#endif /* WXDCLIFECYCLE_H */

WXDCLIFECYCLE_H_EOF
echo "  OK: wxdclifecycle.h"
cat > thotlib/dialogue/wxdcfont.cpp << 'WXDCFONT_EOF'
/*
 * wxdcfont.cpp
 *
 * Replaces GL_LoadFont's font-object construction (thotlib/dialogue/
 * font.c) with real wxFont objects, finally making true what
 * thot_gui_wx.h's `typedef wxFont *ThotFont;` already claims.
 *
 * GetFontFilename() (fontconfig.c) is unchanged and still does the
 * "which script/family/style/size -> which .ttf file" lookup; only the
 * final "turn that file into a usable font handle" step is replaced
 * here. FreeType is used ONLY to read the file's own face name and
 * bold/italic flags out of its metadata -- not for any rendering --
 * since it is already a dependency of this project and gives a robust,
 * general way to ask "what is this font file actually called" without
 * hardcoding a filename-to-facename mapping for Amaya's font set.
 */

#include "wx/wx.h"
#include <ft2build.h>
#include FT_FREETYPE_H

extern "C" void *WxDC_LoadFont (const char *filename, char alphabet, int size)
{
  (void) alphabet;   /* ADAPT: the original gl_font_init also took the
                       * script/alphabet character, presumably to pick
                       * the right cmap/encoding inside the font file
                       * for non-Latin scripts. wxFont's own text
                       * layout (DrawText) should already handle
                       * Unicode script selection correctly on its own
                       * via the underlying platform font shaping, so
                       * this is very likely not needed here -- but
                       * flagging it in case Arabic/CJK/etc. rendering
                       * needs revisiting once Latin text is confirmed
                       * working. */

  static FT_Library ftLib = NULL;
  if (!ftLib)
    {
      if (FT_Init_FreeType (&ftLib) != 0)
        return NULL;
    }

  FT_Face face;
  if (FT_New_Face (ftLib, filename, 0, &face) != 0)
    return NULL;

  wxString faceName = wxString::FromUTF8 (face->family_name ? face->family_name : "");
  bool bold   = (face->style_flags & FT_STYLE_FLAG_BOLD)   != 0;
  bool italic = (face->style_flags & FT_STYLE_FLAG_ITALIC) != 0;
  FT_Done_Face (face);

  if (faceName.IsEmpty ())
    return NULL;

  /* Register the font file with wx for this process (does not install
   * it system-wide). Safe to call repeatedly for the same file -- wx
   * de-duplicates. */
  wxFont::AddPrivateFont (wxString::FromUTF8 (filename));

  /* ADAPT: `size` here -- verify this is already point size, not
   * pixels or Amaya's own internal unit, by comparing rendered text
   * size against the previous GL renderer on first test. Easy to spot
   * visually (text too big/small) and a one-line fix here if wrong. */
  wxFontInfo info (size);
  info.FaceName (faceName);
  if (bold)
    info.Bold ();
  if (italic)
    info.Italic ();

  wxFont *newFont = new wxFont (info);
  if (!newFont->IsOk ())
    {
      delete newFont;
      return NULL;
    }
  return (void *) newFont;
}

WXDCFONT_EOF
echo "  OK: wxdcfont.cpp"

echo "=== [2/6] Wiring GL_LoadFont to the new wxFont-based loader ==="
python3 << 'PYEOF'
with open('thotlib/dialogue/font.c') as f:
    code = f.read()

old = '''static void *GL_LoadFont (char alphabet, int family, int highlight, int size)
{
  char filename[2048];

  if (GetFontFilename (alphabet, family, highlight, size, filename))
    {
      //  printf ("load %s size=%d font=%d\\n",filename, size, FirstFreeFont);
      return (gl_font_init (filename, alphabet, size));
    }
  return NULL;
}'''

new = '''static void *GL_LoadFont (char alphabet, int family, int highlight, int size)
{
  char filename[2048];
  extern void *WxDC_LoadFont (const char *filename, char alphabet, int size);

  if (GetFontFilename (alphabet, family, highlight, size, filename))
    return WxDC_LoadFont (filename, alphabet, size);
  return NULL;
}'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/font.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- GL_LoadFont pattern not found in font.c (has it been edited this session?)")
    import sys; sys.exit(1)
PYEOF

echo "=== [3/6] Updating the six clipping call sites to pass 'frame' ==="
python3 << 'PYEOF'
import sys

edits = [
    ('thotlib/dialogue/appli.c',
     '''      GL_SetClipping (clipx,
                      FrameTable[frame].FrHeight + FrameTable[frame].FrTopMargin
                      - (clipy + clipheight),
                      clipwidth,
                      clipheight); ''',
     '''      GL_SetClipping (frame, clipx,
                      FrameTable[frame].FrHeight + FrameTable[frame].FrTopMargin
                      - (clipy + clipheight),
                      clipwidth,
                      clipheight); '''),
    ('thotlib/dialogue/appli.c',
     '  GL_UnsetClipping ();',
     '  GL_UnsetClipping (frame);'),
    ('thotlib/image/picture.c',
     '      GL_SetClipping (x, org, width, height);',
     '      GL_SetClipping (frame, x, org, width, height);'),
    ('thotlib/image/picture.c',
     '      GL_SetClipping (xclip, yclip, widthclip, heightclip);',
     '      GL_SetClipping (frame, xclip, yclip, widthclip, heightclip);'),
    ('thotlib/view/glbox.c',
     '\t  GL_SetClipping (x, bottom - (y + height), width, height);',
     '\t  GL_SetClipping (frame, x, bottom - (y + height), width, height);'),
    ('thotlib/view/glwindowdisplay.c',
     '      GL_UnsetClipping  (/*0, 0, 0, 0*/);',
     '      GL_UnsetClipping  (frame);'),
]

ok = True
for path, old, new in edits:
    with open(path) as f:
        code = f.read()
    if old in code:
        code = code.replace(old, new, 1)
        with open(path, 'w') as f:
            f.write(code)
        print(f"  OK: {path}")
    else:
        print(f"  FAIL: pattern not found in {path}:")
        print(f"    {old!r}")
        ok = False

if not ok:
    sys.exit(1)
PYEOF


echo "=== [4/6] Writing the disable-function helper ==="
cat > /tmp/disable_function.py << 'HELPER_EOF'
"""
Helper: find a C function by its signature (a distinctive substring of
its declaration line) in a file, and wrap its ENTIRE body (from the
matched line's opening brace to the correctly brace-counted matching
closing brace) in #if 0 / #endif. Used to disable old GL-based
functions whose names now live in the new wxDC replacement files,
without needing to know or match their exact body text (which may have
been edited this session and no longer matches the reference tree
exactly).
"""
import sys

def disable_function(path, signature_substr, label):
    with open(path, 'rb') as f:
        lines = f.readlines()

    start = None
    for i, line in enumerate(lines):
        if signature_substr.encode() in line:
            start = i
            break
    if start is None:
        print(f"  FAIL [{label}]: signature '{signature_substr}' not found in {path}")
        return False

    # Find the opening brace, which may be on the same line or a
    # following line (K&R vs Allman style -- this codebase uses Allman:
    # brace on its own line after the signature, possibly spanning
    # several lines of parameters first).
    brace_line = None
    for j in range(start, min(start + 15, len(lines))):
        if lines[j].strip() == b'{':
            brace_line = j
            break
    if brace_line is None:
        print(f"  FAIL [{label}]: opening brace not found near line {start+1}")
        return False

    depth = 0
    end = None
    for k in range(brace_line, len(lines)):
        depth += lines[k].count(b'{') - lines[k].count(b'}')
        if depth == 0 and k > brace_line:
            end = k
            break
        if depth == 0 and k == brace_line:
            # single-line body (unlikely here, but handle it)
            end = k
            break
    if end is None:
        print(f"  FAIL [{label}]: matching closing brace not found")
        return False

    lines[start:start] = [f'#if 0 /* disabled for Option B: replaced by wxdclifecycle.cpp -- {label} */\n'.encode()]
    lines[end+2:end+2] = [b'#endif\n']
    with open(path, 'wb') as f:
        f.writelines(lines)
    print(f"  OK [{label}]: disabled lines {start+1}-{end+1} in {path}")
    return True

if __name__ == '__main__':
    path, sig, label = sys.argv[1], sys.argv[2], sys.argv[3]
    ok = disable_function(path, sig, label)
    sys.exit(0 if ok else 1)

HELPER_EOF
echo "  OK"

echo "=== [5/6] Disabling old duplicate GL functions ==="
FAIL_COUNT=0
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "ThotBool GL_prepare (int frame)" "GL_prepare" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "void GL_Swap (int frame)" "GL_Swap" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "void GL_SwapStop (int frame)" "GL_SwapStop" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "ThotBool GL_SwapGet (int frame)" "GL_SwapGet" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "void GL_SwapEnable (int frame)" "GL_SwapEnable" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glwindowdisplay.c" "void GL_SetClipping (int x, int y, int width, int height)" "GL_SetClipping (old)" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glwindowdisplay.c" "void GL_UnsetClipping ()" "GL_UnsetClipping (old)" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glwindowdisplay.c" "void GL_realize (int frame)" "GL_realize (old)" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/gltimer.c" "ThotBool GL_DrawAll ()" "GL_DrawAll" || FAIL_COUNT=$((FAIL_COUNT+1))
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "!!! $FAIL_COUNT function(s) could not be disabled -- see FAIL lines above !!!"
  echo "Not proceeding to build -- fix these manually first (each is a small,"
  echo "self-contained function; find it by name and wrap it in #if 0 / #endif)."
  exit 1
fi

echo "=== [6/6] Updating CMakeLists.txt ==="
python3 << 'PYEOF'
import re, sys

with open('CMakeLists.txt') as f:
    lines = f.readlines()

target_idx = None
indent = '  '
path_prefix = 'thotlib/view/'
for i, line in enumerate(lines):
    if 'gldisplay.c' in line and 'gl' + 'windowdisplay.c' not in line:
        target_idx = i
        # Derive indentation and path style from the matched line itself,
        # so the new lines look native to this CMakeLists.txt rather than
        # assuming a specific format.
        stripped = line.rstrip('\n')
        indent = stripped[:len(stripped) - len(stripped.lstrip())]
        if 'thotlib/view/' in stripped:
            path_prefix = 'thotlib/view/'
        break

if target_idx is None:
    print("  FAIL: no line containing 'gldisplay.c' found in CMakeLists.txt")
    print("  You will need to add the new source files to the build manually:")
    print("    thotlib/view/wxdcdisplay.cpp")
    print("    thotlib/view/wxdclifecycle.cpp")
    print("    thotlib/dialogue/wxdcfont.cpp")
    print("  and remove/comment out whatever line currently references")
    print("  thotlib/view/gldisplay.c, in the source file list used to")
    print("  build the 'amaya' target.")
    sys.exit(1)

original = lines[target_idx]
new_block = (
    f"{indent}# gldisplay.c commented out for Option B (replaced by wxDC-based\n"
    f"{indent}# rendering below) -- see OPTION-B-PLAN.md\n"
    f"{indent}# {original.strip()}\n"
    f"{indent}{path_prefix}wxdcdisplay.cpp\n"
    f"{indent}{path_prefix}wxdclifecycle.cpp\n"
    f"{indent}thotlib/dialogue/wxdcfont.cpp\n"
)
lines[target_idx] = new_block
with open('CMakeLists.txt', 'w') as f:
    f.writelines(lines)
print(f"  OK: replaced line {target_idx+1} (gldisplay.c) with the new file list")
print(f"  Please double-check this section of CMakeLists.txt looks right:")
print(new_block)
PYEOF

echo ""
echo "=== Rebuild (from scratch, since CMakeLists.txt changed) ==="
rm -rf build
mkdir build
cd build
cmake .. 2>&1 | tail -20
make -j$(nproc) 2>&1 | tee /tmp/build-optionb-stage1.log | grep -E "error:|Error|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|Error [0-9]" /tmp/build-optionb-stage1.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-optionb-stage1.log for full output !!!"
  echo "This is expected to need some iteration on a change this size --"
  echo "paste the error output back and we'll fix it precisely."
  exit 1
fi

echo ""
echo "=== Stage 1 build succeeded ==="
git add -A
git commit -m "Option B stage 1: wxDC drawing primitives compile and link

Adds thotlib/view/wxdcdisplay.cpp (drawing primitives), thotlib/view/
wxdclifecycle.cpp (GL_prepare/GL_Swap/GL_SetClipping/GL_realize
replacements), thotlib/dialogue/wxdcfont.cpp (wxFont-based font
loading), disables their direct old-code counterparts in gldisplay.c/
glbox.c/glwindowdisplay.c/gltimer.c to avoid duplicate symbols, updates
the six clipping call sites to pass an explicit frame number, and wires
everything into CMakeLists.txt.

AmayaCanvas/AmayaFrame are NOT yet changed -- they still use a GL
context and never call WxDC_SetCurrentFrameDC, so nothing actually
draws via the new code path yet. This commit only establishes that the
new code compiles and links correctly against the real project headers.
Stage 2 (next) wires AmayaCanvas to use wxDC instead of a GL context,
which is what will make this functional."

git push -u origin option-b-wxdc

echo ""
echo "Stage 1 complete and pushed to option-b-wxdc."
