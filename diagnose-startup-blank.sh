#!/usr/bin/env bash
# diagnose-startup-blank.sh
# Diagnostic only -- no behaviour changes. Run from ~/amaya-modern with
# fix/gl-blanking checked out. Adds temporary logging around canvas
# creation, sizing, showing, and the first draw of a newly opened
# document, to see exactly what order things happen in for a small file
# that opens blank.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Adding diagnostic logging ==="

python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''void AmayaCanvas::Init()
{
  // do not initialize twice
  if (m_Init)
    return;
  m_Init = true;
'''
new = '''void AmayaCanvas::Init()
{
  {
    int w, h;
    GetClientSize(&w, &h);
    fprintf(stderr, "DIAG2 Init: canvas=%p shown=%d w=%d h=%d already_init=%d\\n",
            (void*)this, (int)IsShownOnScreen(), w, h, (int)m_Init);
  }
  // do not initialize twice
  if (m_Init)
    return;
  m_Init = true;
'''
if old in code:
    code = code.replace(old, new)
    print("  OK: Init() logging")
else:
    print("  FAIL: Init() pattern not found")
    exit(1)

old2 = "void AmayaCanvas::OnPaint( wxPaintEvent& event )\n{"
new2 = '''void AmayaCanvas::OnPaint( wxPaintEvent& event )
{
  {
    int w, h;
    GetClientSize(&w, &h);
    fprintf(stderr, "DIAG2 OnPaint: canvas=%p shown=%d w=%d h=%d\\n",
            (void*)this, (int)IsShownOnScreen(), w, h);
  }'''
if old2 in code:
    code = code.replace(old2, new2)
    print("  OK: OnPaint() logging")
else:
    print("  FAIL: OnPaint() pattern not found")
    exit(1)

old3 = "void AmayaCanvas::OnSize( wxSizeEvent& event )\n{"
new3 = '''void AmayaCanvas::OnSize( wxSizeEvent& event )
{
  {
    int w, h;
    GetClientSize(&w, &h);
    fprintf(stderr, "DIAG2 OnSize: canvas=%p shown=%d w=%d h=%d\\n",
            (void*)this, (int)IsShownOnScreen(), w, h);
  }'''
if old3 in code:
    code = code.replace(old3, new3)
    print("  OK: OnSize() logging")
else:
    print("  FAIL: OnSize() pattern not found")
    exit(1)

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/appdialogue_wx.c') as f:
    code = f.read()

old = '''void TtaShowWindow( int window_id, ThotBool show )
{
  AmayaWindow * p_window = WindowTable[window_id].WdWindow;
  if (p_window == NULL)
    return;

  p_window->Show( show );
}'''
new = '''void TtaShowWindow( int window_id, ThotBool show )
{
  AmayaWindow * p_window = WindowTable[window_id].WdWindow;
  if (p_window == NULL)
    return;
  fprintf(stderr, "DIAG2 TtaShowWindow: window_id=%d show=%d\\n", window_id, (int)show);
  p_window->Show( show );
}'''
if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appdialogue_wx.c', 'w') as f:
        f.write(code)
    print("  OK: TtaShowWindow logging")
else:
    print("  FAIL: TtaShowWindow pattern not found")
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/view/glwindowdisplay.c', 'rb') as f:
    code = f.read()

old = b'void GL_realize (int frame)\n{\n#ifdef _TESTSWAP\n  GL_Swap (frame);\n  FrameTable[frame].DblBuffNeedSwap = FALSE;\n#else /*_TESTSWAP*/\n  FrameTable[frame].DblBuffNeedSwap = TRUE;\n#endif /*_TESTSWAP*/\n  return;\n}'
new = b'void GL_realize (int frame)\n{\n  fprintf(stderr, "DIAG2 GL_realize: frame=%d\\n", frame);\n#ifdef _TESTSWAP\n  GL_Swap (frame);\n  FrameTable[frame].DblBuffNeedSwap = FALSE;\n#else /*_TESTSWAP*/\n  FrameTable[frame].DblBuffNeedSwap = TRUE;\n#endif /*_TESTSWAP*/\n  return;\n}'
if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
        f.write(code)
    print("  OK: GL_realize logging")
else:
    print("  FAIL: GL_realize pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-diag2.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-diag2.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-diag2.log !!!"
  exit 1
fi

echo ""
echo "Done (diagnostic only -- do NOT commit)."
echo "Run:  THOTDIR=\$(pwd) ./build/amaya/amaya > /tmp/amaya-startup-diag.txt 2>&1"
echo "Then: open a SMALL file that you know shows blank, wait for it to (not) appear, close Amaya."
echo "Then: grep '^DIAG2' /tmp/amaya-startup-diag.txt"
