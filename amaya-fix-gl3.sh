#!/usr/bin/env bash
# amaya-fix-gl3.sh -- fix source view rendering by ensuring continuous repaints
# 
# DIAGNOSIS: The source view (frame 2) canvas only gets wx paint events when
# first shown. After that, FrameExposeCallback is only called when Amaya's
# internal redraw system triggers it. The source view's canvas doesn't get
# mouse-driven expose events like the main canvas does.
#
# FIX: After GL_Swap for any frame, call Refresh() on that frame's canvas.
# This schedules a wx paint event, which calls OnPaint -> FrameExposeCallback.
# The result is a continuous redraw loop for all frames, not just frame 1.
# This is how most OpenGL applications work -- they render continuously.
# The CPU overhead is minimal since Amaya only redraws when content changes
# (GL_SwapStop/GL_SwapEnable gating prevents unnecessary redraws).

set -e
cd ~/amaya-modern

echo "[gl3-fix] glbox.c: call canvas Refresh() after GL_Swap to ensure repaints"
python3 - << 'PYEOF'
with open('thotlib/view/glbox.c') as f:
    code = f.read()

old = '''      FrameTable[frame].WdFrame->SwapBuffers();
      glEnable (GL_SCISSOR_TEST); 
      FrameTable[frame].DblBuffNeedSwap = FALSE;
    }
}'''

new = '''      FrameTable[frame].WdFrame->SwapBuffers();
      glEnable (GL_SCISSOR_TEST); 
      FrameTable[frame].DblBuffNeedSwap = FALSE;
      /* wx 3.x: schedule next repaint so all frames (including source view)
       * continue to receive paint events. Without this, secondary canvases
       * (split views) only draw once and then go stale. */
      if (FrameTable[frame].WdFrame->GetCanvas())
        FrameTable[frame].WdFrame->GetCanvas()->Refresh();
    }
}'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glbox.c', 'w') as f:
        f.write(code)
    print("  Fixed: Refresh() scheduled after GL_Swap")
else:
    print("  Pattern not found")
    idx = code.find('SwapBuffers')
    print(repr(code[max(0,idx-50):idx+200]))
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
