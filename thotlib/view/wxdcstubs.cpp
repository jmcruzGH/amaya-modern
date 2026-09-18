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

