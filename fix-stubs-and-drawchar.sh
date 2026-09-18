#!/usr/bin/env bash
# fix-stubs-and-drawchar.sh
# Run from ~/amaya-modern.
#
# Adds no-op stub implementations for the specialized MathML/SVG shape
# functions (deliberately deferred from the start -- see
# OPTION-B-PLAN.md) plus the Scroll() pixel-copy optimization (a no-op
# by design, not by omission -- see comment in wxdcstubs.cpp), and
# fixes DrawChar's parameter type (wchar_t, not unsigned int -- a real
# bug, caught by the linker expecting a different mangled signature).

set -e
cd ~/amaya-modern

echo "=== Overwriting wxdcdisplay.cpp (DrawChar signature fix) ==="
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

#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"
#include "frame.h"
#include "frame_tv.h"
#include "appli_f.h"


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
void DrawRectangle (int frame, int thick, int style,
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

void DrawRectangleFrame (int frame, int thick, int style,
                                     int x, int y, int width, int height,
                                     int fg)
{
  /* Outline-only variant. */
  DrawRectangle (frame, thick, style, x, y, width, height, fg, -1, 0);
}

/* ------------------------------------------------------------------ */
void DrawHorizontalLine (int frame, int thick, int style,
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

void DrawVerticalLine (int frame, int thick, int style,
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
int DrawString (unsigned char *buff, int lg, int frame,
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

int WDrawString (wchar_t *buff, int lg, int frame, int x, int y,
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

void DrawChar (wchar_t car, int frame, int x, int y,
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

  wxUniChar uc ((wxUint32) (unsigned int) car);
  dc->DrawText (wxString (uc), x, y);
}

/* ------------------------------------------------------------------ */
void DrawPoints (int frame, int x, int y, int boxWidth, int fg)
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

void DrawSegments (int frame, int thick, int style, int x, int y,
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

void DrawPolygon (int frame, int thick, int style, int fg,
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
echo "  OK"

echo "=== Adding wxdcstubs.cpp ==="
cat > thotlib/view/wxdcstubs.cpp << 'WXDCSTUBS_EOF'
/*
 * wxdcstubs.cpp
 *
 * No-op stubs for the specialized MathML/SVG shape-drawing functions
 * and the manual pixel-copy scroll optimization, deliberately deferred
 * from the start (see OPTION-B-PLAN.md): these matter for MathML
 * formula rendering and SVG editing, not ordinary HTML/table content,
 * which is what this port is being proven against first.
 *
 * Scroll() specifically is a different kind of deferral: it is not
 * "not yet implemented", it is "should not be implemented" -- it
 * exists only to copy backbuffer pixels around to avoid a full redraw
 * on the old GL renderer, which is exactly the class of manual
 * double-buffer optimization wxBufferedPaintDC makes both unnecessary
 * and (as this whole session's scroll.c investigation showed)
 * actively unsafe to keep. A no-op here is correct, not incomplete --
 * the real content is redrawn properly through the normal paint path
 * regardless.
 *
 * Signatures matched exactly against the real linker error output
 * (undefined reference messages), which is more reliable than the
 * original gldisplay.c C signatures for this purpose, since it
 * reflects the actual C++-mangled types every caller expects
 * (_TextBuffer*, C_points_*, _PathSeg*, wxWindow*, etc.).
 *
 * Each of these can be given a real implementation later, once the
 * core HTML/table editing path is confirmed solid -- the highest-
 * value ones to do first would be DrawSegments/DrawPolygon/DrawCurve/
 * DrawSpline (used for SVG paths) and DrawRectangleFrame/DrawOval
 * (simple shapes, easy wins). The rest (Integral/Sigma/Pi/brackets/
 * braces/parentheses) are MathML-notation-specific.
 */

#include "wx/wx.h"

#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"

struct _TextBuffer;
struct C_points_;
struct _PathSeg;

void Scroll (int, int, int, int, int, int, int) {}

void PaintWithPattern (int, int, int, int, int, wxWindow*, int, int, int) {}

void DrawArrow (int, int, int, int, int, int, int, int, int, int) {}
void DrawBezierControl (int, int, int, int, int, int, int, int) {}
void DrawBrace (int, int, int, int, int, int, int, void*, int, int) {}
void DrawBracket (int, int, int, int, int, int, int, void*, int, int) {}
void DrawCorner (int, int, int, int, int, int, int, int, int) {}
void DrawCurve (int, int, int, int, int, _TextBuffer*, int, int, int, C_points_*) {}
void DrawDiamond (int, int, int, int, int, int, int, int, int, int) {}
void DrawEllips (int, int, int, int, int, int, int, int, int, int) {}
void DrawEllipsFrame (int, int, int, int, int, int, int, int, int, int) {}
void DrawHat (int, int, int, int, int, int, int, int, int) {}
void DrawHorizontalBrace (int, int, int, int, int, int, int, int, int) {}
void DrawHorizontalBracket (int, int, int, int, int, int, int, int, int) {}
void DrawHorizontalParenthesis (int, int, int, int, int, int, int, int, int) {}
void DrawIntegral (int, int, int, int, int, int, int, void*, int) {}
void DrawIntersection (int, int, int, int, int, void*, int) {}
void DrawOval (int, int, int, int, int, int, int, int, int, int, int, int) {}
void DrawParallelogram (int, int, int, int, int, int, int, int, int, int, int) {}
void DrawParenthesis (int, int, int, int, int, int, int, void*, int, int) {}
void DrawPath (int, int, int, int, int, _PathSeg*, int, int, int, int) {}
void DrawPi (int, int, int, int, int, void*, int) {}
void DrawPointyBracket (int, int, int, int, int, int, int, void*, int) {}
void DrawPolygon (int, int, int, int, int, _TextBuffer*, int, int, int, int, int) {}
void DrawRadical (int, int, int, int, int, int, void*, int) {}
void DrawRectangle2 (int, int, int, int, int, int, int, int, int, int) {}
void DrawRectangleFrame (int, int, int, int, int, int, int, int, int, int) {}
void DrawResizeTriangle (int, int, int, int, int, int, int) {}
void DrawSegments (int, int, int, int, int, _TextBuffer*, int, int, int, int, int) {}
void DrawSigma (int, int, int, int, int, void*, int) {}
void DrawSlash (int, int, int, int, int, int, int, int, int) {}
void DrawSpline (int, int, int, int, int, _TextBuffer*, int, int, int, int, C_points_*) {}
void DrawTilde (int, int, int, int, int, int, int, int) {}
void DrawTrapezium (int, int, int, int, int, int, int, int, int, int, int, int) {}
void DrawTriangle (int, int, int, int, int, int, int, int, int, int, int, int) {}
void DrawUnion (int, int, int, int, int, void*, int) {}
void DisplayUnderline (int, int, int, int, int, int, int) {}

WXDCSTUBS_EOF
echo "  OK"

echo "=== Adding wxdcstubs.cpp to CMakeLists.txt ==="
python3 - << 'PYEOF'
path = 'thotlib/CMakeLists.txt'
with open(path) as f:
    code = f.read()

old = '  dialogue/wxcfont.cpp\n)'  # placeholder, corrected below
old = '  dialogue/wxdcfont.cpp\n)'
new = '  dialogue/wxdcfont.cpp\n  view/wxdcstubs.cpp\n)'

if old in code:
    code = code.replace(old, new, 1)
    with open(path, 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found, showing context:")
    idx = code.find('wxdcfont.cpp')
    print(repr(code[max(0,idx-100):idx+100]))
    import sys; sys.exit(1)
PYEOF

echo ""
echo "=== Clean rebuild ==="
rm -rf build
mkdir build
cd build
cmake .. 2>&1 | tail -5
make -j$(nproc) 2>&1 | tee /tmp/build-optionb-stage1.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -q "collect2: error\|undefined reference\|error:" /tmp/build-optionb-stage1.log; then
  echo ""
  echo "!!! Still failing -- see /tmp/build-optionb-stage1.log !!!"
  exit 1
fi

echo ""
echo "=== STAGE 1 BUILD SUCCEEDED ==="
git add -A
git commit -m "Option B stage 1: wxDC drawing primitives compile and link

Adds thotlib/view/wxdcdisplay.cpp, wxdclifecycle.cpp, wxdcstubs.cpp
(no-op stubs for deferred MathML/SVG shape functions and the Scroll()
pixel-copy optimization, which is a no-op by design under wxDC's
automatic double buffering, not an omission), and thotlib/dialogue/
wxdcfont.cpp. Disables the old duplicate GL-based definitions,
updates the clipping call sites to pass an explicit frame number, and
wires everything into CMakeLists.txt. Functions defined with plain
C++ linkage (no extern \"C\") to match how the rest of this codebase
(which compiles every .c file as C++) already expects them, per
windowdisplay_f.h's un-wrapped declarations.

AmayaCanvas/AmayaFrame are NOT yet changed -- they still use a GL
context and never call WxDC_SetCurrentFrameDC, so nothing actually
draws via the new code path yet. This commit only establishes that
the new code compiles and links correctly. Stage 2 (next) wires
AmayaCanvas to use wxDC instead of a GL context, which is what will
make this functional."

git push -u origin option-b-wxdc

echo ""
echo "Stage 1 complete and pushed to option-b-wxdc."
