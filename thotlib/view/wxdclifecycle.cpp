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
  /* If we're currently mid-paint for this frame (a DC is active via
   * WxDC_SetCurrentFrameDC), do NOT trigger another Refresh() here.
   * RedrawFrameBottom unconditionally calls GL_realize at the end of
   * EVERY invocation, including the one OnPaint itself just made.
   * Without this guard that creates an infinite self-perpetuating
   * repaint loop: OnPaint -> RedrawFrameBottom -> GL_realize ->
   * Refresh() -> schedules a NEW OnPaint -> repeat -- which is exactly
   * why only the very first piece of content ever became visible
   * (confirmed: diagnostic logging showed the same single text run
   * being redrawn tens of thousands of times), and very likely the
   * cause of the crashes too (runaway event flooding). Only trigger a
   * real repaint request when called from OUTSIDE an active paint
   * cycle -- e.g. directly from an edit/keyboard/mouse action. */
  if (GetFrameDC(frame) != NULL)
    return;
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

