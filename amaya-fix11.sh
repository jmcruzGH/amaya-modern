#!/usr/bin/env bash
# amaya-fix11.sh -- fix source view by setting viewport in Init()
# SetGlPipelineState() doesn't set up the projection matrix.
# For the first canvas, FrameResizedCallback fires early and sets it.
# For secondary canvases (source view, split windows), the resize event
# may come after the first paint, leaving the projection uninitialized.
# Fix: call GLResize in Init() to set the viewport and projection.

set -e
cd ~/amaya-modern

echo "[fix11] AmayaCanvas.cpp: set up GL viewport and projection in Init()"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''  SetGlPipelineState ();
#endif /* _GL */'''

new = '''  SetGlPipelineState ();
  /* Set up the viewport and projection matrix for this canvas.
   * SetGlPipelineState() doesn't do this, and FrameResizedCallback
   * may not have fired yet for secondary canvases (source view etc.) */
  {
    int w, h;
    GetClientSize(&w, &h);
    if (w > 0 && h > 0)
      GLResize (w, h, 0, 0);
  }
#endif /* _GL */'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  Fixed: GLResize called in Init()")
else:
    print("  Pattern not found -- current state around SetGlPipelineState:")
    idx = code.find('SetGlPipelineState')
    if idx >= 0:
        print(code[idx-50:idx+200])
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
