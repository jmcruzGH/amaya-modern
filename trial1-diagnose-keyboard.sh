#!/usr/bin/env bash
# trial1-diagnose-keyboard.sh
# Adds temporary diagnostic logging (no behaviour changes) to find out:
#   1. Does AmayaCanvas ever actually receive keyboard focus?
#   2. Does AmayaWindow::OnChar (CHAR_HOOK) fire, and with what values?
#   3. Does AmayaCanvas::OnChar (the new EVT_CHAR) ever fire at all?
# Run from ~/amaya-modern with trial/option-a checked out.

set -e
cd ~/amaya-modern
git checkout trial/option-a

echo "=== Adding diagnostic logging ==="

python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaWindow.cpp') as f:
    code = f.read()

old = '''void AmayaWindow::OnChar(wxKeyEvent& event)
{
  TTALOGDEBUG_0( TTA_LOG_KEYINPUT, _T("AmayaWindow::OnChar key=")+wxString(event.GetUnicodeKey()) );
'''

new = '''void AmayaWindow::OnChar(wxKeyEvent& event)
{
  TTALOGDEBUG_0( TTA_LOG_KEYINPUT, _T("AmayaWindow::OnChar key=")+wxString(event.GetUnicodeKey()) );
  {
    wxWindow *f = wxWindow::FindFocus();
    fprintf(stderr, "DIAG WindowOnChar: keycode=%d unicode=%d shift=%d caps=%d focus=%s\\n",
            event.GetKeyCode(), event.GetUnicodeKey(), (int)event.ShiftDown(),
            (int)wxGetKeyState(WXK_CAPITAL),
            f ? f->GetClassInfo()->GetClassName() : "NULL");
  }
'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaWindow.cpp', 'w') as f:
        f.write(code)
    print("  OK: AmayaWindow::OnChar logging added")
else:
    print("  FAIL: AmayaWindow::OnChar pattern not found")
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''void AmayaCanvas::OnChar(wxKeyEvent& event)
{
  /* This is where typed characters are actually read.'''

new = '''void AmayaCanvas::OnChar(wxKeyEvent& event)
{
  fprintf(stderr, "DIAG CanvasOnChar: keycode=%d unicode=%d hasfocus=%d\\n",
          event.GetKeyCode(), event.GetUnicodeKey(), (int)this->HasFocus());
  /* This is where typed characters are actually read.'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: AmayaCanvas::OnChar logging added")
else:
    print("  FAIL: AmayaCanvas::OnChar pattern not found")
    exit(1)

# Also log every time OnMouseDown runs and what focus looks like right after
old2 = "void AmayaCanvas::OnMouseDown( wxMouseEvent& event )\n{"
new2 = '''void AmayaCanvas::OnMouseDown( wxMouseEvent& event )
{
  fprintf(stderr, "DIAG OnMouseDown: canvas=%p hasfocus_before=%d\\n", (void*)this, (int)this->HasFocus());
'''
if old2 in code:
    code = code.replace(old2, new2)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: OnMouseDown logging added")
else:
    print("  FAIL: OnMouseDown pattern not found")
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/appli.c') as f:
    code = f.read()

old = '''      p_frame = TtaGetFrameFromId(frame);
      if (p_frame && p_frame->GetCanvas())
        p_frame->GetCanvas()->SetFocus();'''

new = '''      p_frame = TtaGetFrameFromId(frame);
      fprintf(stderr, "DIAG ActiveFrameChanged: frame=%d p_frame=%p canvas=%p\\n",
              frame, (void*)p_frame, p_frame ? (void*)p_frame->GetCanvas() : NULL);
      if (p_frame && p_frame->GetCanvas())
        {
          p_frame->GetCanvas()->SetFocus();
          fprintf(stderr, "DIAG SetFocus called, hasfocus_after=%d\\n",
                  (int)p_frame->GetCanvas()->HasFocus());
        }'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appli.c', 'w') as f:
        f.write(code)
    print("  OK: appli.c ActiveFrameChanged logging added")
else:
    print("  FAIL: appli.c pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

echo ""
echo "Done -- do NOT commit this (diagnostic only)."
echo "Run:  THOTDIR=\$(pwd) ./build/amaya/amaya > /tmp/amaya-kbd-diag.txt 2>&1"
echo "Then: click into a document, press a few plain letter keys, press an arrow key, then close Amaya."
echo "Then: grep '^DIAG' /tmp/amaya-kbd-diag.txt"
