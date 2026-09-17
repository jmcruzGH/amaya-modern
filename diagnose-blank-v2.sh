#!/usr/bin/env bash
# diagnose-blank-v2.sh
# Diagnostic only -- no behaviour changes. Run from ~/amaya-modern with
# fix/gl-blanking checked out. Logs, for every relevant transition:
#   - documentDisplayMode changes (DeferredDisplay <-> DisplayImmediately)
#   - DblBuffNeedSwap being set (GL_realize)
#   - GL_DrawAll's pass/skip decision on every idle tick, and why

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Adding diagnostic logging ==="

python3 - << 'PYEOF'
with open('thotlib/view/gltimer.c') as f:
    code = f.read()

# Find the GL_DrawAll loop body -- log the decision for every frame that
# has DblBuffNeedSwap set, whether or not it actually gets drawn.
old = '''      if (FrameTable[frame].DblBuffNeedSwap &&
          doc && LoadedDocument[doc - 1] &&
          documentDisplayMode[doc - 1] == DisplayImmediately)
        {'''
new = '''      if (FrameTable[frame].DblBuffNeedSwap)
        fprintf(stderr, "DIAG3 idle-check: frame=%d doc=%d loaded=%d dispmode=%d shown=%d\\n",
                frame, doc,
                (doc ? LoadedDocument[doc - 1] : -1),
                (doc ? documentDisplayMode[doc - 1] : -1),
                (int)TtaFrameIsShown(frame));
      if (FrameTable[frame].DblBuffNeedSwap &&
          doc && LoadedDocument[doc - 1] &&
          documentDisplayMode[doc - 1] == DisplayImmediately)
        {
          fprintf(stderr, "DIAG3 idle-DRAW: frame=%d\\n", frame);'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/gltimer.c', 'w') as f:
        f.write(code)
    print("  OK: GL_DrawAll logging added")
else:
    print("  FAIL: GL_DrawAll pattern not found -- showing area for inspection")
    idx = code.find('DblBuffNeedSwap &&')
    print(repr(code[max(0,idx-100):idx+300]))
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/view/glwindowdisplay.c', 'rb') as f:
    code = f.read()

old = b'void GL_realize (int frame)\n{\n#ifdef _TESTSWAP\n  GL_Swap (frame);\n  FrameTable[frame].DblBuffNeedSwap = FALSE;\n#else /*_TESTSWAP*/\n  FrameTable[frame].DblBuffNeedSwap = TRUE;\n#endif /*_TESTSWAP*/\n  return;\n}'
new = b'void GL_realize (int frame)\n{\n  fprintf(stderr, "DIAG3 GL_realize: frame=%d\\n", frame);\n#ifdef _TESTSWAP\n  GL_Swap (frame);\n  FrameTable[frame].DblBuffNeedSwap = FALSE;\n#else /*_TESTSWAP*/\n  FrameTable[frame].DblBuffNeedSwap = TRUE;\n#endif /*_TESTSWAP*/\n  return;\n}'
if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
        f.write(code)
    print("  OK: GL_realize logging added")
else:
    print("  FAIL: GL_realize pattern not found")
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = 'void AmayaCanvas::OnPaint( wxPaintEvent& event )\n{'
new = '''void AmayaCanvas::OnPaint( wxPaintEvent& event )
{
  fprintf(stderr, "DIAG3 OnPaint: canvas=%p frame=%d\\n", (void*)this, m_pAmayaFrame ? m_pAmayaFrame->GetFrameId() : -1);'''
if old in code:
    code = code.replace(old, new, 1)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: OnPaint logging added")
else:
    print("  FAIL: OnPaint pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-diag3.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-diag3.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-diag3.log !!!"
  exit 1
fi

echo ""
echo "Done (diagnostic only -- do NOT commit)."
echo "Run:  THOTDIR=\$(pwd) ./build/amaya/amaya > /tmp/amaya-blank-diag.txt 2>&1"
echo ""
echo "Then reproduce EITHER case (whichever is easier to trigger):"
echo "  A) Start Amaya normally and watch for the main window opening blank"
echo "  B) Deliberately cause a parsing error (as before) and watch for"
echo "     PARSING.ERR opening blank"
echo ""
echo "As soon as you see the blank window, WITHOUT resizing/highlighting"
echo "yet, close Amaya (or just Ctrl+C the terminal) so the log captures"
echo "the stuck state. Then:"
echo "  grep '^DIAG3' /tmp/amaya-blank-diag.txt | tail -60"
