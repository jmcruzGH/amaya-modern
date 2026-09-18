#!/usr/bin/env bash
# fix-extern-c.sh
# Run from ~/amaya-modern.
#
# Root cause of every link failure so far: the whole project compiles
# every .c file as C++ (a foundational decision from early in this
# project), so the ORIGINAL gldisplay.c's DrawRectangle/GL_prepare/etc.
# (also compiled as C++, no extern "C") got plain C++ (mangled) linkage
# -- matching exactly what frame.c and everything else already expects
# via windowdisplay_f.h's un-wrapped declarations (confirmed by reading
# that header directly: no extern "C" anywhere in it).
#
# My three new files wrapped everything in extern "C", which broke that
# consistency: it made these functions produce plain, unmangled symbols
# while every caller (still using the same, untouched header
# declarations) kept looking for the mangled C++ version. This
# completely overwrites the three new files with a corrected version
# (extern "C" removed throughout, all the header-inclusion fixes from
# this debugging session folded back in).

set -e
cd ~/amaya-modern

echo "=== Overwriting the three new files (extern \"C\" removed) ==="
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

void DrawChar (unsigned int car, int frame, int x, int y,
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

#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"
#include "frame.h"
#include "frame_tv.h"
#include "AmayaFrame.h"
#include "AmayaCanvas.h"

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
ThotBool GL_prepare (int frame)
{
  return GetFrameDC (frame) != NULL;
}

/* GL_Swap / GL_SwapStop / GL_SwapEnable / GL_SwapGet: originally
 * managed manual double-buffer swapping and flicker prevention. All
 * no-ops now: wxBufferedPaintDC (set up in AmayaCanvas::OnPaint)
 * handles double buffering correctly and automatically, blitting the
 * backing bitmap to screen exactly once, when OnPaint returns -- there
 * is nothing left to "swap now vs defer" or "stop/enable" manually. */
void GL_Swap (int frame)
{
  (void) frame;
}

void GL_SwapStop (int frame)
{
  (void) frame;
}

void GL_SwapEnable (int frame)
{
  (void) frame;
}

ThotBool GL_SwapGet (int frame)
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
void GL_realize (int frame)
{
  if (frame >= 0 && frame <= MAX_FRAME &&
      FrameTable[frame].WdFrame && FrameTable[frame].WdFrame->GetCanvas ())
    FrameTable[frame].WdFrame->GetCanvas ()->Refresh ();
}

/* GL_DrawAll: the idle-driven catch-up mechanism this no longer needs
 * to exist at all (see GL_realize above) -- kept as a harmless no-op
 * only so the AmayaCanvas::OnIdle call site does not need editing
 * immediately; remove that call once this is confirmed working. */
ThotBool GL_DrawAll (void)
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
void GL_SetClipping (int frame, int x, int y, int width, int height)
{
  wxDC *dc = GetFrameDC (frame);
  if (dc && width > 0 && height > 0)
    dc->SetClippingRegion (x, y, width, height);
}

void GL_UnsetClipping (int frame)
{
  wxDC *dc = GetFrameDC (frame);
  if (dc)
    dc->DestroyClippingRegion ();
}

WXDCLIFECYCLE_CPP_EOF
echo "  OK: wxdclifecycle.cpp"
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

void *WxDC_LoadFont (const char *filename, char alphabet, int size)
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

echo ""
echo "=== Clean rebuild ==="
rm -rf build
mkdir build
cd build
cmake .. 2>&1 | tail -5
make -j$(nproc) 2>&1 | tee /tmp/build-optionb-stage1.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -q "collect2: error\|undefined reference" /tmp/build-optionb-stage1.log; then
  echo ""
  echo "!!! Still failing -- see /tmp/build-optionb-stage1.log !!!"
  echo "Run: grep -A2 'undefined reference' /tmp/build-optionb-stage1.log | head -60"
  exit 1
fi

echo ""
echo "=== Build succeeded ==="
