#!/usr/bin/env bash
# amaya-render-fix.sh -- complete GL rendering fix
# 
# PROBLEM SUMMARY:
# Amaya uses partial GL redraws (glScissor) for efficiency.
# With GL double buffering, after SwapBuffers the backbuffer content
# is undefined. Partial redraws leave stale content in non-updated areas.
#
# SOLUTION:
# Track which frames need a full redraw. After each GL_Swap, if the frame
# had a partial redraw, schedule a full canvas Refresh() via wx.
# This triggers OnPaint -> FrameExposeCallback with full dimensions.
# The full redraw replaces all stale content.
# Also: when frame 1 fully redraws, trigger frame 2 (source view) too.

set -e
cd ~/amaya-modern

echo "[render-fix 1] glwindowdisplay.c: revert partial-clear hack"
python3 - << 'PYEOF'
with open('thotlib/view/glwindowdisplay.c', 'rb') as f:
    code = f.read()

# Revert our previous broken attempt:
old = b'     /* wx 3.x: clear full backbuffer before partial redraw to avoid\n      * stale content in non-redrawn areas (double-buffer artefact) */\n     if (raz > 0 && GL_prepare (frame))\n       { glDisable (GL_SCISSOR_TEST); glClear (GL_COLOR_BUFFER_BIT); glEnable (GL_SCISSOR_TEST); }\n     GL_SetClipping (clipx, '
new = b'     GL_SetClipping (clipx, '
if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
        f.write(code)
    print("  Reverted glwindowdisplay.c")
else:
    print("  Already clean")
PYEOF

echo "[render-fix 2] glbox.c: add per-frame dirty tracking"
python3 - << 'PYEOF'
with open('thotlib/view/glbox.c') as f:
    code = f.read()

# Add a dirty flag array after the existing statics:
old = 'static ThotBool NotFeedBackMode = TRUE;'
new = '''static ThotBool NotFeedBackMode = TRUE;
/* wx 3.x: track frames that had partial redraws and need a full refresh */
static ThotBool FrameNeedsFullRedraw[MAX_FRAME + 1];'''

if old in code and 'FrameNeedsFullRedraw' not in code:
    code = code.replace(old, new)
    print("  Added FrameNeedsFullRedraw array")
else:
    print("  Already present or pattern not found")

# In GL_Swap: after SwapBuffers, if frame had partial redraw,
# schedule a full canvas refresh:
old2 = '''      FrameTable[frame].WdFrame->SwapBuffers();
      glEnable (GL_SCISSOR_TEST); 
      FrameTable[frame].DblBuffNeedSwap = FALSE;
    }
}'''

new2 = '''      FrameTable[frame].WdFrame->SwapBuffers();
      glEnable (GL_SCISSOR_TEST); 
      FrameTable[frame].DblBuffNeedSwap = FALSE;
      /* wx 3.x: if this frame had a partial redraw, schedule a full refresh
       * so the next paint redraws the complete backbuffer */
      if (FrameNeedsFullRedraw[frame])
        {
          FrameNeedsFullRedraw[frame] = FALSE;
          FrameTable[frame].WdFrame->RefreshCanvas();
        }
    }
}'''

if old2 in code:
    code = code.replace(old2, new2)
    print("  Added full refresh trigger in GL_Swap")
else:
    print("  GL_Swap pattern not found")

with open('thotlib/view/glbox.c', 'w') as f:
    f.write(code)
PYEOF

echo "[render-fix 3] appli.c: mark partial redraws and trigger sibling frames"
python3 - << 'PYEOF'
with open('thotlib/dialogue/appli.c') as f:
    code = f.read()

# In FrameExposeCallback: after the full-frame redraw, also trigger
# sibling frames (same document, different view):
old = '''  /* wx 3.x: after redrawing this frame, refresh any other frames sharing
   * the same document so they also stay current (source view, split views) */
  {
    int doc = FrameTable[frame].FrDoc;
    int f2;
    for (f2 = 1; f2 < MAX_FRAME; f2++)
      if (f2 != frame && FrameTable[f2].FrDoc == doc &&
          FrameTable[f2].WdFrame != NULL)
        FrameTable[f2].WdFrame->RefreshCanvas();
  }
  Current_Expose = FALSE;'''

# Remove old broken sibling refresh if present:
if old in code:
    code = code.replace(old, '  Current_Expose = FALSE;')
    print("  Removed old sibling refresh")

# Mark frame as needing full redraw when DefineClipping uses partial region.
# We do this by checking if the clip region is smaller than the full frame:
old2 = '''          /* wx 3.x + GL: always redraw full frame */
          { int fw, fh; GetSizesFrame (frame, &fw, &fh);
            DefClip (frame, pFrame->FrXOrg, pFrame->FrYOrg,
                     pFrame->FrXOrg + fw, pFrame->FrYOrg + fh); }
          RedrawFrameBottom (frame, 0, NULL);'''

new2 = '''          /* wx 3.x + GL: always use full frame for clip region.
           * This ensures the complete backbuffer is redrawn each expose. */
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
          }'''

if old2 in code:
    code = code.replace(old2, new2)
    print("  Added sibling frame trigger after full redraw")
else:
    print("  Full-frame pattern not found -- checking:")
    idx = code.find('always redraw full frame')
    if idx >= 0:
        print(repr(code[idx:idx+300]))

with open('thotlib/dialogue/appli.c', 'w') as f:
    f.write(code)
PYEOF

echo "[render-fix 4] glwindowdisplay.c: mark frame dirty on partial redraw"
python3 - << 'PYEOF'
with open('thotlib/view/glwindowdisplay.c', 'rb') as f:
    code = f.read()

# After GL_SetClipping in DefineClipping, mark the frame as needing full refresh:
old = b'     GL_SetClipping (clipx, \n                     FrameTable[frame].FrHeight + FrameTable[frame].FrTopMargin \n                     - (clipy + clipheight), \n                     clipwidth, \n                     clipheight);  \n     if (raz > 0 && GL_prepare (frame))'

new = b'     GL_SetClipping (clipx, \n                     FrameTable[frame].FrHeight + FrameTable[frame].FrTopMargin \n                     - (clipy + clipheight), \n                     clipwidth, \n                     clipheight);\n     /* wx 3.x: mark this frame as having a partial redraw */\n     { extern ThotBool FrameNeedsFullRedraw[];\n       FrameNeedsFullRedraw[frame] = TRUE; }\n     if (raz > 0 && GL_prepare (frame))'

if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
        f.write(code)
    print("  Marked frame dirty on partial redraw")
else:
    print("  Pattern not found")
    idx = code.find(b'GL_SetClipping (clipx')
    print(repr(code[max(0,idx-20):idx+200]))
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
