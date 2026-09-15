#!/usr/bin/env bash
# amaya-gl-rewrite.sh -- complete rewrite of GL rendering coordinator
#
# ROOT CAUSE (definitively identified):
# Amaya uses GL double buffering. After SwapBuffers(), the backbuffer
# content is UNDEFINED. The original code assumed single-buffered GL
# (common in 2005-era Linux) where the framebuffer was preserved.
# On modern Mesa/GTK3, the backbuffer is truly undefined after each swap.
#
# ORIGINAL DESIGN (broken on modern Mesa):
#   partial_dirty_area -> DefineClipping(small_region) -> glScissor(small)
#   -> draw only dirty region -> SwapBuffers
#   -> backbuffer now has ONLY the small region, rest is garbage
#   -> next swap shows garbage around the drawn region
#
# NEW DESIGN (correct for modern Mesa):
#   ANY dirty area -> always draw FULL FRAME -> SwapBuffers
#   The scissor test is kept only to CLIP OUTPUT, never to skip drawing.
#   Before each full redraw: glClear(COLOR_BUFFER_BIT) with no scissor.
#   After SwapBuffers: backbuffer = complete correct frame.
#   Next dirty area: clear again, draw full frame, swap.
#
# This is how all modern GL applications work (games, browsers, etc.)
# The performance cost is negligible for a text editor.

set -e
cd ~/amaya-modern
git checkout fix/gl-rendering

echo "=== Writing new GL rendering coordinator ==="

# Step 1: Rewrite FrameExposeCallback in appli.c
# Always do a full-frame redraw, never partial
echo "[1] appli.c: full-frame always"
python3 - << 'PYEOF'
with open('thotlib/dialogue/appli.c') as f:
    code = f.read()

# Find the GL block in FrameExposeCallback
old = '''#ifdef _GL
  /* THIS JUST DOESN'T WORK !!!
     even when storing successive x,y and so on...
     it's just gtk and opengl mix bad...
     so the Xfree and gtk guys that tells us 
     it work, just have to come here and code it here
     with an hardware opengl implementation on their PC...
     They will see the Speed problem...*/
  if (GL_prepare (frame))
    {
//      if ( g_NeedRedisplayAllTheFrame[frame] || glhard() || GetBadCard() )
        {
          /* prevent flickering*/
          GL_SwapStop (frame);
          // we need to recalculate the glcanvas only once : after the RESIZE event
          // because GTK&GL clear automaticaly the GL canvas just after the frame is resized.
          // (it appends only on some hardware opengl implementations on Linux)
          //g_NeedRedisplayAllTheFrame[frame] = FALSE;
          
          // refresh the invalide frame content
          /* wx 3.x + GL: always redraw full frame */
          { int fw, fh; GetSizesFrame (frame, &fw, &fh);
            DefClip (frame, pFrame->FrXOrg, pFrame->FrYOrg,
                     pFrame->FrXOrg + fw, pFrame->FrYOrg + fh); }
          RedrawFrameBottom (frame, 0, NULL);
          /* After full redraw, also trigger sibling frames (source view) */
          { extern ThotBool FrameNeedsFullRedraw[];
            int doc = FrameTable[frame].FrDoc, f2;
            for (f2 = 1; f2 < MAX_FRAME; f2++)
              if (f2 != frame && FrameTable[f2].FrDoc == doc &&
                  FrameTable[f2].WdFrame != NULL)
                FrameTable[f2].WdFrame->RefreshCanvas();
          }
          GL_SwapEnable (frame);
        }
      // display the backbuffer
      GL_Swap (frame);
     }
#else /* _GL */
  x += pFrame->FrXOrg;
  y += pFrame->FrYOrg;
  DefClip (frame, x, y, x + w, y + h);
  RedrawFrameBottom (frame, 0, NULL);
#endif /* _GL */'''

new = '''#ifdef _GL
  /* wx 3.x + modern Mesa: always redraw the COMPLETE frame.
   * With double buffering, the backbuffer is undefined after SwapBuffers.
   * Partial redraws leave stale content. We clear and redraw everything. */
  if (GL_prepare (frame))
    {
      GL_SwapStop (frame);

      /* Set clip region to full frame dimensions */
      { int fw, fh;
        GetSizesFrame (frame, &fw, &fh);
        DefClip (frame, pFrame->FrXOrg, pFrame->FrYOrg,
                 pFrame->FrXOrg + fw, pFrame->FrYOrg + fh);
      }

      /* Clear the full backbuffer before drawing */
      glDisable (GL_SCISSOR_TEST);
      ClearAll (frame);
      glEnable (GL_SCISSOR_TEST);

      /* Redraw the complete frame */
      RedrawFrameBottom (frame, 0, NULL);

      GL_SwapEnable (frame);
      GL_Swap (frame);

      /* Trigger sibling frames sharing the same document (source/split views) */
      { int doc = FrameTable[frame].FrDoc, f2;
        for (f2 = 1; f2 < MAX_FRAME; f2++)
          if (f2 != frame && FrameTable[f2].FrDoc == doc &&
              FrameTable[f2].WdFrame != NULL)
            FrameTable[f2].WdFrame->RefreshCanvas();
      }
    }
#else /* _GL */
  x += pFrame->FrXOrg;
  y += pFrame->FrYOrg;
  DefClip (frame, x, y, x + w, y + h);
  RedrawFrameBottom (frame, 0, NULL);
#endif /* _GL */'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appli.c', 'w') as f:
        f.write(code)
    print("  OK: FrameExposeCallback rewritten")
else:
    print("  FAIL: pattern not found")
    # Show what's there
    idx = code.find('THIS JUST DOESN')
    if idx < 0:
        idx = code.find('GL_prepare (frame)')
    print(repr(code[max(0,idx-20):idx+200]))
PYEOF

# Step 2: Rewrite DefineClipping in glwindowdisplay.c
# Remove the partial-redraw path for GL -- always use full dimensions
echo "[2] glwindowdisplay.c: remove partial GL scissor optimisation"
python3 - << 'PYEOF'
with open('thotlib/view/glwindowdisplay.c', 'rb') as f:
    code = f.read()

# Find DefineClipping's GL block which sets the scissor to a partial region
# We want to keep the scissor for SVG/shape clipping but ensure the
# REDRAW AREA covers the full frame. The scissor will be set to full frame.
old = (
    b'     GL_SetClipping (clipx, \n'
    b'                     FrameTable[frame].FrHeight + FrameTable[frame].FrTopMargin \n'
    b'                     - (clipy + clipheight), \n'
    b'                     clipwidth, \n'
    b'                     clipheight);\n'
    b'     /* wx 3.x: mark this frame as having a partial redraw */\n'
    b'     { extern ThotBool FrameNeedsFullRedraw[];\n'
    b'       FrameNeedsFullRedraw[frame] = TRUE; }\n'
    b'     if (raz > 0 && GL_prepare (frame))'
)

new = (
    b'     /* wx 3.x: set scissor to FULL FRAME not just the dirty region.\n'
    b'      * With double buffering we always redraw everything, so the\n'
    b'      * scissor should not restrict the drawing area. */\n'
    b'     GL_SetClipping (0,\n'
    b'                     FrameTable[frame].FrTopMargin,\n'
    b'                     FrameTable[frame].FrWidth,\n'
    b'                     FrameTable[frame].FrHeight);\n'
    b'     if (raz > 0 && GL_prepare (frame))'
)

if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
        f.write(code)
    print("  OK: DefineClipping GL scissor uses full frame")
else:
    # Try without the dirty-tracking lines we added:
    old2 = (
        b'     GL_SetClipping (clipx, \n'
        b'                     FrameTable[frame].FrHeight + FrameTable[frame].FrTopMargin \n'
        b'                     - (clipy + clipheight), \n'
        b'                     clipwidth, \n'
        b'                     clipheight);  \n'
        b'     if (raz > 0 && GL_prepare (frame))'
    )
    new2 = (
        b'     /* wx 3.x: full-frame scissor for double-buffer correctness */\n'
        b'     GL_SetClipping (0,\n'
        b'                     FrameTable[frame].FrTopMargin,\n'
        b'                     FrameTable[frame].FrWidth,\n'
        b'                     FrameTable[frame].FrHeight);\n'
        b'     if (raz > 0 && GL_prepare (frame))'
    )
    if old2 in code:
        code = code.replace(old2, new2)
        with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
            f.write(code)
        print("  OK: DefineClipping GL scissor uses full frame (alt pattern)")
    else:
        print("  FAIL: pattern not found")
        idx = code.find(b'GL_SetClipping (clipx')
        print(repr(code[max(0,idx-20):idx+300]))
PYEOF

# Step 3: Clean up glbox.c -- remove dirty tracking we added, simplify GL_Swap
echo "[3] glbox.c: clean up dirty tracking, simplify GL_Swap"
python3 - << 'PYEOF'
with open('thotlib/view/glbox.c') as f:
    code = f.read()

# Remove dirty tracking array
code = code.replace(
    '/* wx 3.x: track frames that had partial redraws and need a full refresh */\n'
    'static ThotBool FrameNeedsFullRedraw[MAX_FRAME + 1];\n',
    ''
)

# Remove dirty tracking in GL_Swap
old = (
    '      /* wx 3.x: if this frame had a partial redraw, schedule a full refresh\n'
    '       * so the next paint redraws the complete backbuffer */\n'
    '      if (FrameNeedsFullRedraw[frame])\n'
    '        {\n'
    '          FrameNeedsFullRedraw[frame] = FALSE;\n'
    '          FrameTable[frame].WdFrame->RefreshCanvas();\n'
    '        }\n'
)
code = code.replace(old, '')

# Also remove the old Refresh-after-swap we tried earlier:
code = code.replace(
    '      /* wx 3.x: schedule next repaint so all frames (including source view)\n'
    '       * continue to receive paint events. Without this, secondary canvases\n'
    '       * (split views) only draw once and then go stale. */\n'
    '      if (FrameTable[frame].WdFrame->GetCanvas())\n'
    '        FrameTable[frame].WdFrame->GetCanvas()->Refresh();\n',
    ''
)

with open('thotlib/view/glbox.c', 'w') as f:
    f.write(code)
print("  OK: glbox.c cleaned up")
PYEOF

# Step 4: Simplify AmayaCanvas::Init() -- remove viewport fix attempt
echo "[4] AmayaCanvas.cpp: clean up Init()"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

# Remove GLResize from Init if present
code = code.replace(
    '  /* Ensure viewport is set for this canvas */\n'
    '  { int w, h; GetClientSize(&w, &h);\n'
    '    if (w > 0 && h > 0) GLResize(w, h, 0, 0); }\n',
    ''
)

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
print("  OK: AmayaCanvas.cpp cleaned")
PYEOF

echo ""
echo "=== Rebuild ==="
cd build && make -j$(nproc) 2>&1 | grep "error:\|warning: .*error\|Built target\|Linking" | \
  grep -v "command-line option\|set but not used\|Wreorder\|Wstringop\|Wmisleading"
