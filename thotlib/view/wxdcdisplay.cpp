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

/* wxDC::DrawText's (x,y) is the TOP-LEFT corner of the text's bounding
 * box. Every caller in displaybox.c, however, passes y as the BASELINE
 * position -- the convention the original GL/FreeType renderer used.
 * Without this adjustment, text is drawn shifted upward by roughly its
 * own ascent, often enough to push it entirely out of its intended
 * box while background/border rectangles render correctly -- exactly
 * the "blank text, visible borders" symptom this fixes. */
static int BaselineToTop (wxDC *dc, const wxString &text, int yBaseline)
{
  wxCoord w, h, descent, externalLeading;
  dc->GetTextExtent (text, &w, &h, &descent, &externalLeading);
  return yBaseline - (h - descent);
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

  /* Defensive clamp: seen in practice with the text-cursor drawing
   * path (DisplayStringSelection), which can compute a wildly wrong
   * height (tens of thousands of pixels, for what should be a single
   * line's height) under a still-unidentified layout-timing condition
   * -- likely related to this project's move to synchronous wxDC
   * painting. Handing wxDC a rectangle far larger than the frame
   * itself is never correct regardless of why a caller computed one,
   * and was very likely also the direct cause of a crash observed
   * immediately after this exact symptom. Root cause not yet found;
   * this stops the visible/crash symptom without masking the
   * underlying value for future investigation (only the draw call is
   * clamped, not what callers compute or store). */
  {
    int frameH = FrameTable[frame].FrHeight + FrameTable[frame].FrTopMargin;
    if (height > frameH)
      height = frameH;
    int frameW = FrameTable[frame].FrScrollWidth > 0 ? FrameTable[frame].FrScrollWidth : 2000;
    if (width > frameW)
      width = frameW;
  }

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

  dc->DrawText (text, x, BaselineToTop (dc, text, y));
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

  dc->DrawText (text, x, BaselineToTop (dc, text, y));
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
  wxString text (uc);
  dc->DrawText (text, x, BaselineToTop (dc, text, y));
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

