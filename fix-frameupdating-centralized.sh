#!/usr/bin/env bash
# fix-frameupdating-centralized.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# The previous fix added a "clear a stuck FrameUpdating flag" safety
# check, but only inside AmayaCanvas::OnIdle. Every keyboard and mouse
# handler calls the same underlying GL_DrawAll() directly too (that is
# the whole point of those earlier fixes -- redraw right now, don't wait
# for idle), and none of those calls had the same protection. If the
# flag gets stuck, it silently blocks every one of them, not just the
# idle path -- explaining why further clicking/typing in the source view
# did nothing, while a resize (which goes through the completely
# separate, always-reliable OnPaint path) still worked.
#
# Moves the safety check from OnIdle into GL_DrawAll() itself, right
# before its own "already in progress" check -- since every caller
# (idle, all keyboard handlers, all mouse handlers) funnels through this
# one function, fixing it there once protects all of them, rather than
# duplicating the same check at every individual call site. This is safe
# because GL_DrawAll is never legitimately re-entered while already
# running: it does not pump the event loop internally (the original code
# even has this deliberately commented out -- "//TtaHandlePendingEvents
# ();" -- specifically to avoid that hazard).

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== [1/2] Move the self-heal check into GL_DrawAll() itself ==="
python3 - << 'PYEOF'
with open('thotlib/view/gltimer.c') as f:
    code = f.read()

old = '''  if (!FrameUpdating)
    {
      FrameUpdating = TRUE;     '''

new = '''  /* GL_DrawAll silently does nothing at all while FrameUpdating is TRUE
   * (see fix commit for the full explanation). It is never legitimately
   * re-entered while already running -- it does not pump the event loop
   * internally -- so if FrameUpdating is still TRUE right as we are
   * about to check it here, that can only be leaked state from some
   * other, unrelated place failing to restore it on some exit path.
   * Clear it here, centrally, so every caller (idle, keyboard handlers,
   * mouse handlers) is protected, not just whichever one happens to run
   * first. */
  if (FrameUpdating)
    FrameUpdating = FALSE;
  if (!FrameUpdating)
    {
      FrameUpdating = TRUE;     '''

if old in code:
    code = code.replace(old, new, 1)
    with open('thotlib/view/gltimer.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    idx = code.find('if (!FrameUpdating)')
    print(repr(code[max(0,idx-50):idx+150]))
    exit(1)
PYEOF

echo "=== [2/2] Remove the now-redundant duplicate check from OnIdle ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''#ifdef _GL
  /* GL_DrawAll() silently does nothing at all while FrameUpdating is
   * TRUE (a global "a redraw/rebuild is already in progress" guard set
   * and restored in many different places). We only ever get here once
   * wx's event queue is completely empty -- nothing should legitimately
   * still be mid-update at that exact moment, so if the flag says
   * otherwise it can only be leaked state from somewhere failing to
   * restore it on some exit path. Clear it before proceeding, rather
   * than leaving every subsequent redraw permanently inert until
   * something unrelated happens to reset it elsewhere. */
  extern ThotBool FrameUpdating;
  if (FrameUpdating)
    FrameUpdating = FALSE;
  GL_DrawAll();
#endif /* _GL */
  event.Skip();
}'''

new = '''#ifdef _GL
  /* GL_DrawAll() now self-heals a stuck FrameUpdating flag centrally
   * (see gltimer.c), covering every caller including this one. */
  GL_DrawAll();
#endif /* _GL */
  event.Skip();
}'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-frameupdating2.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-frameupdating2.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-frameupdating2.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: centralize FrameUpdating self-heal in GL_DrawAll itself

The previous fix added a 'clear a stuck FrameUpdating flag' safety
check, but only inside AmayaCanvas::OnIdle. Every keyboard and mouse
handler calls the same underlying GL_DrawAll() directly too -- that is
the whole point of those earlier fixes, redraw right now rather than
wait for idle -- and none of those calls had the same protection. If the
flag got stuck, it silently blocked every one of them, not just the
idle path: explains why further clicking/typing in an affected frame
did nothing at all, while a resize (the separate, always-reliable
OnPaint path) still worked.

Moves the check from OnIdle into GL_DrawAll() itself, right before its
own reentrancy check, so every caller is protected by the same, single
guard rather than duplicating it at every individual call site. Safe
because GL_DrawAll is never legitimately re-entered while already
running -- it does not pump the event loop internally, which the
original code's own commented-out '//TtaHandlePendingEvents();' line
shows was a deliberate design choice specifically to avoid that hazard."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
