#!/usr/bin/env bash
# amaya-fix-gl2.sh -- bypass GL feedback mode for bounding box computation
# 
# ROOT CAUSE: ComputeBoundingBox uses glFeedbackBuffer/glRenderMode(GL_FEEDBACK)
# to compute the screen position of each box after GL transforms. When this
# fails (returns size=0, which happens unreliably with independent GL contexts),
# BxClipW/H are set to BxW/BxH which may be 0 for split boxes. Boxes with
# BxClipW=0 or BxClipH=0 are then culled as invisible -> missing text.
#
# FIX: Skip the GL feedback mode entirely and compute BxClip* directly from
# the layout coordinates (BxXOrg, BxYOrg, BxWidth, BxHeight). This is what
# the non-GL code path already does, and is always correct for non-transformed
# boxes (which is the vast majority in HTML source view).

set -e
cd ~/amaya-modern

echo "[gl2-fix] glbox.c: bypass GL feedback mode for bounding box computation"
python3 - << 'PYEOF'
with open('thotlib/view/glbox.c') as f:
    code = f.read()

old = '''void ComputeBoundingBox (PtrBox box, int frame, int xmin, int xmax, 
\t\t\t int ymin, int ymax)
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
\t\t\t int ymin, int ymax)
{
#ifdef _GL
  ViewFrame  *pFrame;

  /* wx 3.x: GL feedback mode (glRenderMode(GL_FEEDBACK)) is unreliable
   * with independent GL contexts on modern Mesa/GLX -- it may return size=0
   * even for visible boxes, causing them to be culled as invisible.
   * Compute bounding boxes directly from layout coordinates instead.
   * This is always correct for non-transformed boxes (HTML, source view). */
  if (NotFeedBackMode)
    {
      pFrame = &ViewFrameTable[frame - 1];
      box->BxClipX = box->BxXOrg - (pFrame->FrXOrg?pFrame->FrXOrg:pFrame->OldFrXOrg);
      box->BxClipY = box->BxYOrg - (pFrame->FrYOrg?pFrame->FrYOrg:pFrame->OldFrYOrg);
      /* Use BxWidth/BxHeight (layout dimensions) not BxW/BxH (which may be 0) */
      box->BxClipW = box->BxWidth > 0 ? box->BxWidth : box->BxW;
      box->BxClipH = box->BxHeight > 0 ? box->BxHeight : box->BxH;
      box->BxBoundinBoxComputed = (box->BxClipW > 0 && box->BxClipH > 0);
    }
#endif /* _GL */
}'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glbox.c', 'w') as f:
        f.write(code)
    print("  Fixed: GL feedback mode bypassed in ComputeBoundingBox")
else:
    print("  Pattern not found -- check current state:")
    idx = code.find('ComputeBoundingBox')
    print(repr(code[idx:idx+200]))
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
