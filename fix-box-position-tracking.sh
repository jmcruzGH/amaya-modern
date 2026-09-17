#!/usr/bin/env bash
# fix-box-position-tracking.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# Fixes: partial redraws even when a redraw is correctly triggered, and
# mouse clicks placing the text cursor in the wrong position relative to
# what is visually on screen.
#
# Both symptoms share one root cause. Amaya records each box's on-screen
# position and size (BxClipX/Y/W/H) using a legacy OpenGL trick: it
# renders the box invisibly into a "feedback buffer" (glRenderMode
# (GL_FEEDBACK)) and reads back where the resulting vertices landed.
# This mechanism is poorly supported on modern graphics drivers and can
# report "nothing was drawn" (size <= 0) for boxes that actually are
# visible.
#
# When that happens:
#   - ComputeBoundingBox falls back to an approximation using BxW/BxH
#     (the box's INNER content size, excluding margins/padding), which
#     can itself be 0 for many box types, causing the box to fail a
#     later visibility check and simply not be redrawn -- the "partial
#     redraw" symptom.
#   - ComputeFilledBox has NO fallback at all: on a failed feedback
#     read, BxClipX/Y/W/H are left completely untouched, i.e. stale or
#     garbage.
#   - Mouse click hit-testing (translating a screen click back into
#     "which box was that") uses this same BxClipX/Y bookkeeping, which
#     is now out of sync with where content is actually drawn on
#     screen -- the cursor-placed-in-the-wrong-spot symptom.
#
# The fix: stop depending on the unreliable feedback-mode readback
# entirely, and always compute BxClipX/Y/W/H directly from the box's own
# layout coordinates (BxXOrg/BxYOrg, BxWidth/BxHeight including margins,
# falling back to BxW/BxH only if those are zero) -- values the layout
# engine always sets correctly regardless of any GL quirks. This is
# already what ComputeBoundingBox's existing fallback path did for the
# "feedback failed" case; this just makes it the only path, for both
# functions.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Fixing ComputeBoundingBox and ComputeFilledBox in glbox.c ==="
python3 - << 'PYEOF'
with open('thotlib/view/glbox.c') as f:
    code = f.read()

# --- ComputeBoundingBox ---
old = '''void ComputeBoundingBox (PtrBox box, int frame, int xmin, int xmax, 
			 int ymin, int ymax)
{
#ifdef _GL
  GLfloat    feedBuffer[FEEDBUFFERSIZE];
  GLint      mode;
  int        size;
  ViewFrame  *pFrame;
 
  if (NotFeedBackMode)
    {
      glGetIntegerv (GL_RENDER_MODE, &mode);
       /* display into a temporary buffer */
      glFeedbackBuffer (FEEDBUFFERSIZE, GL_2D, feedBuffer);
      glRenderMode (GL_FEEDBACK);
      NotFeedBackMode = FALSE;
      /* display the box with transformation and clipping */
      DisplayBox (box, frame, xmin, xmax, ymin, ymax, NULL, FALSE);
      size = glRenderMode (mode);
      NotFeedBackMode = TRUE;
      if (size > 0)
        {
          /* the box is displayed */
          if (size > FEEDBUFFERSIZE)
            size = FEEDBUFFERSIZE;
          
          box->BxClipX = -1;
          box->BxClipY = -1;
          getboundingbox (size, feedBuffer, frame,
                          &box->BxClipX,
                          &box->BxClipY,
                          &box->BxClipW,
                          &box->BxClipH);    
          box->BxBoundinBoxComputed = TRUE; 
        }
      else
        {
          /* the box is not displayed */
          pFrame = &ViewFrameTable[frame - 1];
          /* */
          box->BxClipX = box->BxXOrg - (pFrame->FrXOrg?pFrame->FrXOrg:pFrame->OldFrXOrg);
          box->BxClipY = box->BxYOrg - (pFrame->FrYOrg?pFrame->FrYOrg:pFrame->OldFrYOrg);
          box->BxClipW = box->BxW;
          box->BxClipH = box->BxH;
          box->BxBoundinBoxComputed = FALSE; 
        }   
    }
#endif /* _GL */
}'''

new = '''void ComputeBoundingBox (PtrBox box, int frame, int xmin, int xmax, 
			 int ymin, int ymax)
{
#ifdef _GL
  ViewFrame  *pFrame;

  /* wx 3.x / modern Mesa: glRenderMode(GL_FEEDBACK) is unreliable and
   * can report "nothing drawn" for boxes that are genuinely visible,
   * which used to leave BxClipX/Y/W/H wrong or stale (see fix commit
   * for the full explanation). Always compute them directly from the
   * box's own layout coordinates instead, which the layout engine
   * always sets correctly regardless of any GL quirks. */
  if (NotFeedBackMode)
    {
      pFrame = &ViewFrameTable[frame - 1];
      box->BxClipX = box->BxXOrg - (pFrame->FrXOrg?pFrame->FrXOrg:pFrame->OldFrXOrg);
      box->BxClipY = box->BxYOrg - (pFrame->FrYOrg?pFrame->FrYOrg:pFrame->OldFrYOrg);
      box->BxClipW = box->BxWidth > 0 ? box->BxWidth : box->BxW;
      box->BxClipH = box->BxHeight > 0 ? box->BxHeight : box->BxH;
      box->BxBoundinBoxComputed = (box->BxClipW > 0 && box->BxClipH > 0);
    }
  (void)xmin; (void)xmax; (void)ymin; (void)ymax;
#endif /* _GL */
}'''

if old in code:
    code = code.replace(old, new)
    print("  OK: ComputeBoundingBox fixed")
else:
    print("  FAIL: ComputeBoundingBox pattern not found")
    exit(1)

# --- ComputeFilledBox ---
old2 = '''void ComputeFilledBox (PtrBox box, int frame, int xmin, int xmax,
                       int ymin, int ymax, ThotBool show_bgimage)
{
  GLfloat feedBuffer[4096];
  GLint   mode;
  int     size;
  
  if (NotFeedBackMode)
    {
      glGetIntegerv (GL_RENDER_MODE, &mode);
      box->BxBoundinBoxComputed = TRUE; 
      glFeedbackBuffer (4096, GL_2D, feedBuffer);
      glRenderMode (GL_FEEDBACK);
      NotFeedBackMode = FALSE;
      DrawFilledBox (box, box->BxAbstractBox, frame, NULL,
		     xmin, xmax, ymin, ymax, FALSE, TRUE, TRUE, show_bgimage);
      size = glRenderMode (mode);
      NotFeedBackMode = TRUE;
      if (size > 0)
        {
          box->BxClipX = -1;
          box->BxClipY = -1;
          getboundingbox (size, feedBuffer, frame,
                          &box->BxClipX,
                          &box->BxClipY,
                          &box->BxClipW,
                          &box->BxClipH);     
          box->BxBoundinBoxComputed = TRUE; 
          /* printBuffer (size, feedBuffer); */
        }
    }
}'''

new2 = '''void ComputeFilledBox (PtrBox box, int frame, int xmin, int xmax,
                       int ymin, int ymax, ThotBool show_bgimage)
{
  ViewFrame *pFrame;

  /* Same fix as ComputeBoundingBox above -- this function previously had
   * NO fallback at all for a failed feedback-mode read, leaving
   * BxClipX/Y/W/H completely untouched (stale/garbage) in that case. */
  if (NotFeedBackMode)
    {
      pFrame = &ViewFrameTable[frame - 1];
      box->BxClipX = box->BxXOrg - (pFrame->FrXOrg?pFrame->FrXOrg:pFrame->OldFrXOrg);
      box->BxClipY = box->BxYOrg - (pFrame->FrYOrg?pFrame->FrYOrg:pFrame->OldFrYOrg);
      box->BxClipW = box->BxWidth > 0 ? box->BxWidth : box->BxW;
      box->BxClipH = box->BxHeight > 0 ? box->BxHeight : box->BxH;
      box->BxBoundinBoxComputed = (box->BxClipW > 0 && box->BxClipH > 0);
    }
  (void)xmin; (void)xmax; (void)ymin; (void)ymax; (void)show_bgimage;
}'''

if old2 in code:
    code = code.replace(old2, new2)
    print("  OK: ComputeFilledBox fixed")
else:
    print("  FAIL: ComputeFilledBox pattern not found")
    exit(1)

with open('thotlib/view/glbox.c', 'w') as f:
    f.write(code)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-box-position.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-box-position.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-box-position.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: stop using unreliable GL feedback mode for box position

Fixes partial redraws even when a redraw is correctly triggered, and
mouse clicks placing the text cursor in the wrong position relative to
what is visually on screen -- both share one root cause.

Amaya records each box's on-screen position and size (BxClipX/Y/W/H)
using a legacy OpenGL trick: render the box invisibly into a 'feedback
buffer' (glRenderMode(GL_FEEDBACK)) and read back where the resulting
vertices landed. This mechanism is poorly supported on modern graphics
drivers and can report 'nothing was drawn' for boxes that are genuinely
visible.

When that happened, ComputeBoundingBox fell back to an approximation
using BxW/BxH (inner content size, excluding margins), which can itself
be 0 for many box types -- causing the box to fail a later visibility
check and simply not be redrawn. ComputeFilledBox had no fallback at
all: on a failed feedback read, BxClipX/Y/W/H were left completely
untouched. Mouse click hit-testing (translating a screen click back
into 'which box was that') uses this same bookkeeping, so once it goes
out of sync with what is actually drawn, clicks land on the wrong box.

Both functions now always compute BxClipX/Y/W/H directly from the
box's own layout coordinates (BxXOrg/BxYOrg, BxWidth/BxHeight including
margins, falling back to BxW/BxH only if those are zero) -- values the
layout engine always sets correctly regardless of any GL quirks. This
was already ComputeBoundingBox's own fallback for the failure case;
this makes it the only path, for both functions."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
