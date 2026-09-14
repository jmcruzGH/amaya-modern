#!/usr/bin/env bash
# amaya-fix8.sh -- fix GL blanking and SVG flicker
# 
# With OpenGL double buffering, partial region redraws cause blanking because
# the back buffer is undefined after SwapBuffers. Fix: always redraw the
# full canvas on paint events.

set -e
cd ~/amaya-modern

echo "[fix8a] AmayaCanvas.cpp: redraw full canvas on paint (fix GL blanking)"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''  int x,y,w,h;                             // Dimensions of client area in pixels
  wxRegionIterator upd(GetUpdateRegion()); // get the update rect list
  while (upd)
    {
      x = upd.GetX();
      y = upd.GetY();
      w = upd.GetW();
      h = upd.GetH();
    
      // call the generic callback to really display the frame
      FrameExposeCallback ( frame, x, y, w, h );
      TTALOGDEBUG_5( TTA_LOG_DRAW, _T("AmayaCanvas::OnPaint : frame=%d [x=%d, y=%d, w=%d, h=%d]"), m_pAmayaFrame->GetFrameId(), x, y, w, h );
    
      upd ++ ;
    }'''

new = '''  /* wx 3.x + OpenGL: with double buffering the back buffer is undefined
   * after SwapBuffers, so partial region redraws cause blanking.
   * Always redraw the entire canvas. */
  int x = 0, y = 0;
  int w, h;
  GetClientSize(&w, &h);
  if (w > 0 && h > 0)
    {
      FrameExposeCallback ( frame, x, y, w, h );
      TTALOGDEBUG_5( TTA_LOG_DRAW, _T("AmayaCanvas::OnPaint : frame=%d [x=%d, y=%d, w=%d, h=%d]"), m_pAmayaFrame->GetFrameId(), x, y, w, h );
    }'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  Fixed: full canvas redraw on paint")
else:
    print("  Pattern not found")
    for i, l in enumerate(code.split('\n')[178:210], 179):
        print(f"  {i}: {l}")
PYEOF

echo "[fix8b] AmayaCanvas.cpp: ensure SetCurrent before SwapBuffers"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

# Make sure Init() guard doesn't bail too early:
old = '''  /* wx 3.x: guard against BadMatch by checking the canvas is realized */
  if (IsShownOnScreen() && GetSize().GetWidth() > 0 && m_glContext) {
    if (!SetCurrent(*m_glContext)) {
      m_Init = false;  /* retry next paint */
      return;
    }
    SetGlPipelineState ();
  } else {
    m_Init = false;  /* not ready yet -- retry next paint */
    return;
  }'''

new = '''  /* wx 3.x: guard against BadMatch */
  if (!IsShownOnScreen() || GetSize().GetWidth() <= 0 || !m_glContext) {
    m_Init = false;  /* not ready yet -- retry next paint */
    return;
  }
  if (!SetCurrent(*m_glContext)) {
    m_Init = false;  /* retry next paint */
    return;
  }
  SetGlPipelineState ();'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  Fixed: cleaner SetCurrent guard")
else:
    print("  Pattern not found (may already be correct)")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
