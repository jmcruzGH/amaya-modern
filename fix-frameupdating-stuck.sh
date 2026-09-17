#!/usr/bin/env bash
# fix-frameupdating-stuck.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# Removes the v2 diagnostic logging, and fixes the likely root cause of
# most remaining "redraw was triggered but nothing happened" symptoms
# across the whole program (main window, source view, tables,
# PARSING.ERR): GL_DrawAll() -- the function every one of our earlier
# fixes relies on to actually flush a pending redraw to the screen --
# refuses to do anything at all, silently, whenever a global "frame is
# currently being updated" flag (FrameUpdating) is still TRUE. That flag
# is set and restored in many different places across frame.c and
# buildboxes.c; if any one of them fails to restore it on some exit
# path, it gets stuck TRUE, and GL_DrawAll becomes permanently inert
# until something unrelated happens to reset it elsewhere -- explaining
# both the "sometimes" and the "resize/highlight fixes it" pattern.
#
# GL_DrawAll only ever runs from AmayaCanvas::OnIdle, which wx only
# fires once the entire event queue is completely empty. Nothing should
# legitimately still be "mid-update" at that exact moment -- so if
# FrameUpdating is TRUE right then, it can only be leaked/stuck state,
# not real work in progress. Clears it right there before proceeding,
# rather than trying to find and fix every possible leak across the
# many places that touch this flag.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== [1/2] Removing v2 diagnostic logging ==="
python3 - << 'PYEOF'
with open('thotlib/view/gltimer.c') as f:
    code = f.read()

old = '''                  if (FrameTable[frame].DblBuffNeedSwap)
                    fprintf(stderr, "DIAG3 idle-check: frame=%d doc=%d loaded=%d dispmode=%d shown=%d\\n",
                            frame, doc,
                            (doc ? !!LoadedDocument[doc - 1] : -1),
                            (doc ? documentDisplayMode[doc - 1] : -1),
                            (int)TtaFrameIsShown(frame));
                  if (FrameTable[frame].DblBuffNeedSwap &&
                      doc && LoadedDocument[doc - 1] &&
                      documentDisplayMode[doc - 1] == DisplayImmediately)
                    {
                      fprintf(stderr, "DIAG3 idle-DRAW: frame=%d\\n", frame);'''
new = '''                  if (FrameTable[frame].DblBuffNeedSwap &&
                      doc && LoadedDocument[doc - 1] &&
                      documentDisplayMode[doc - 1] == DisplayImmediately)
                    {'''
if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/gltimer.c', 'w') as f:
        f.write(code)
    print("  OK: gltimer.c cleaned")
else:
    print("  FAIL: gltimer.c diagnostic pattern not found")
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/view/glwindowdisplay.c', 'rb') as f:
    code = f.read()
old = b'  fprintf(stderr, "DIAG3 GL_realize: frame=%d\\n", frame);\n'
if old in code:
    code = code.replace(old, b'')
    with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
        f.write(code)
    print("  OK: glwindowdisplay.c cleaned")
else:
    print("  FAIL: glwindowdisplay.c diagnostic not found")
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()
old = '  fprintf(stderr, "DIAG3 OnPaint: canvas=%p frame=%d\\n", (void*)this, m_pAmayaFrame ? m_pAmayaFrame->GetFrameId() : -1);\n'
if old in code:
    code = code.replace(old, '')
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: AmayaCanvas.cpp OnPaint diagnostic cleaned")
else:
    print("  FAIL: OnPaint diagnostic not found")
    exit(1)
PYEOF

echo "=== [2/2] Self-heal a stuck FrameUpdating flag at the start of idle processing ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''#ifdef _GL
  GL_DrawAll();
#endif /* _GL */
  event.Skip();
}'''
new = '''#ifdef _GL
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

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    idx = code.find('GL_DrawAll();\n#endif /* _GL */\n  event.Skip();')
    print(repr(code[max(0,idx-50):idx+150]))
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-frameupdating.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-frameupdating.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-frameupdating.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: self-heal stuck FrameUpdating flag before idle redraw

Likely root cause of most remaining 'redraw was triggered but nothing
happened' symptoms (main window, source view, tables, PARSING.ERR):
GL_DrawAll() -- the function every earlier redraw-timing fix in this
branch relies on to actually flush a pending redraw to the screen --
silently does nothing at all whenever a global FrameUpdating flag is
still TRUE. That flag is set and restored in many different places
across frame.c and buildboxes.c; if any one of them fails to restore it
on some exit path, GL_DrawAll becomes permanently inert until something
unrelated happens to reset the flag elsewhere -- matching both the
'sometimes' and the 'resize/highlight fixes it' pattern across every
affected window.

Diagnostic logging confirmed GL_DrawAll's main loop was never being
entered at all during a captured blank-window session, despite content
clearly being marked as needing a redraw (GL_realize firing repeatedly)
-- consistent with FrameUpdating being stuck.

GL_DrawAll only ever runs from AmayaCanvas::OnIdle, which wx only fires
once its event queue is completely empty. Nothing should legitimately
still be mid-update at that exact moment, so if FrameUpdating is TRUE
right then it can only be leaked state, not real work in progress.
Clears it right there before proceeding, rather than auditing every
place that touches the flag for the one exit path with the bug."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
