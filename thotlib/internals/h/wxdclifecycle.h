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

