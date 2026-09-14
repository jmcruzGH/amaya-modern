#!/usr/bin/env bash
# amaya-fix9.sh -- fix source view / split window rendering
# After switching GL contexts in GL_prepare, reset the viewport and projection
# matrix to match the current frame dimensions.

set -e
cd ~/amaya-modern

echo "[fix9] glbox.c: reset viewport after context switch in GL_prepare"
python3 - << 'PYEOF'
with open('thotlib/view/glbox.c') as f:
    code = f.read()

old = '''ThotBool GL_prepare (int frame)
{  
  if (frame >= 0 && frame < MAX_FRAME && NotFeedBackMode)
    {
      //#ifdef _TESTSWAP
      //FrameTable[frame].DblBuffNeedSwap = TRUE;
      //#endif /*_TESTSWAP*/

    if (FrameTable[frame].WdFrame)
      return FrameTable[frame].WdFrame->SetCurrent();
    }
  return FALSE;
}'''

new = '''ThotBool GL_prepare (int frame)
{  
  if (frame >= 0 && frame < MAX_FRAME && NotFeedBackMode)
    {
    if (FrameTable[frame].WdFrame &&
        FrameTable[frame].WdFrame->SetCurrent())
      {
        /* After switching to this frame's GL context, reset the viewport
         * and projection matrix. With independent GL contexts each context
         * has its own viewport state which may be uninitialized. */
        int w = FrameTable[frame].FrWidth;
        int h = FrameTable[frame].FrHeight;
        if (w > 0 && h > 0)
          {
            glViewport (0, 0, w, h);
            glMatrixMode (GL_PROJECTION);
            glLoadIdentity ();
            glOrtho (0, w, h, 0, -1, 1);
            glMatrixMode (GL_MODELVIEW);
            glLoadIdentity ();
          }
        return TRUE;
      }
    }
  return FALSE;
}'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glbox.c', 'w') as f:
        f.write(code)
    print("  Fixed: viewport reset after context switch")
else:
    print("  Pattern not found -- check current state:")
    for i, l in enumerate(code.split('\n')[200:220], 201):
        print(f"  {i}: {l}")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
