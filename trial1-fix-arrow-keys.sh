#!/usr/bin/env bash
# trial1-fix-arrow-keys.sh
# Run from ~/amaya-modern with trial/option-a checked out.
#
# Root cause (verified against the actual wx-3.2 headers used in this
# build, not guessed): TtaIsSpecialKey() only recognises key codes in the
# numeric range 300-308 (WXK_START..WXK_COMMAND) as "special", plus a
# short explicit list (Backspace/Tab/Enter/Escape/Delete/Numpad digits).
# On this wx version, WXK_COMMAND == WXK_CONTROL == 308. Arrow keys,
# Home, End, Insert, and Page Up/Down all have codes from 311 upward
# (WXK_LEFT is 314), so they fall just outside that range and get
# rejected before ever reaching the cursor-movement code -- even though
# that code explicitly lists WXK_LEFT/RIGHT/UP/DOWN/HOME/END as keys it
# wants to handle. This patch only ADDS the missing key codes to the
# recognised list; nothing existing is changed or removed.
#
# Also removes the temporary diagnostic logging added earlier.

set -e
cd ~/amaya-modern
git checkout trial/option-a

echo "=== [1/2] Remove temporary diagnostic logging ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaWindow.cpp') as f:
    code = f.read()
old = '''  {
    wxWindow *f = wxWindow::FindFocus();
    fprintf(stderr, "DIAG WindowOnChar: keycode=%d unicode=%d shift=%d caps=%d focus=%s\\n",
            event.GetKeyCode(), event.GetUnicodeKey(), (int)event.ShiftDown(),
            (int)wxGetKeyState(WXK_CAPITAL),
            f ? f->GetClassInfo()->GetClassName() : "NULL");
  }
'''
if old in code:
    code = code.replace(old, '')
    with open('thotlib/dialogue/AmayaWindow.cpp', 'w') as f:
        f.write(code)
    print("  OK: removed from AmayaWindow.cpp")
else:
    print("  (not present, skipping)")
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()
code = code.replace(
    '  fprintf(stderr, "DIAG CanvasOnChar: keycode=%d unicode=%d hasfocus=%d\\n",\n'
    '          event.GetKeyCode(), event.GetUnicodeKey(), (int)this->HasFocus());\n',
    ''
)
code = code.replace(
    '  fprintf(stderr, "DIAG OnMouseDown: canvas=%p hasfocus_before=%d\\n", (void*)this, (int)this->HasFocus());\n',
    ''
)
with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
print("  OK: removed from AmayaCanvas.cpp")
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/appli.c') as f:
    code = f.read()
old = '''      fprintf(stderr, "DIAG ActiveFrameChanged: frame=%d p_frame=%p canvas=%p\\n",
              frame, (void*)p_frame, p_frame ? (void*)p_frame->GetCanvas() : NULL);
      if (p_frame && p_frame->GetCanvas())
        {
          p_frame->GetCanvas()->SetFocus();
          fprintf(stderr, "DIAG SetFocus called, hasfocus_after=%d\\n",
                  (int)p_frame->GetCanvas()->HasFocus());
        }'''
new = '''      if (p_frame && p_frame->GetCanvas())
        p_frame->GetCanvas()->SetFocus();'''
if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appli.c', 'w') as f:
        f.write(code)
    print("  OK: removed from appli.c")
else:
    print("  (not present, skipping)")
PYEOF

echo "=== [2/2] Fix TtaIsSpecialKey: add the missing navigation keys ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/appdialogue_wx.c') as f:
    code = f.read()

old = '''ThotBool TtaIsSpecialKey( int wx_keycode )
{
  if (wx_keycode >= WXK_NUMPAD0 && wx_keycode <= WXK_NUMPAD9)
    return TRUE;
  else
    return ( wx_keycode == WXK_BACK ||
             wx_keycode == WXK_TAB  ||
             wx_keycode == WXK_RETURN ||
             wx_keycode == WXK_ESCAPE ||
             /*wx_keycode == WXK_INSERT  ||*/
             wx_keycode == WXK_DELETE ||
             (wx_keycode >= WXK_START && wx_keycode <= WXK_COMMAND)
           );'''

new = '''ThotBool TtaIsSpecialKey( int wx_keycode )
{
  if (wx_keycode >= WXK_NUMPAD0 && wx_keycode <= WXK_NUMPAD9)
    return TRUE;
  else
    return ( wx_keycode == WXK_BACK ||
             wx_keycode == WXK_TAB  ||
             wx_keycode == WXK_RETURN ||
             wx_keycode == WXK_ESCAPE ||
             /*wx_keycode == WXK_INSERT  ||*/
             wx_keycode == WXK_DELETE ||
             (wx_keycode >= WXK_START && wx_keycode <= WXK_COMMAND) ||
             /* wx-3.x: on this build WXK_COMMAND == WXK_CONTROL (308),
              * which leaves every navigation key (311 and up) outside
              * the range check above. TtaHandleSpecialKey's proceed_key
              * list explicitly wants these, so recognise them here too. */
             wx_keycode == WXK_CAPITAL ||
             wx_keycode == WXK_END ||
             wx_keycode == WXK_HOME ||
             wx_keycode == WXK_LEFT ||
             wx_keycode == WXK_UP ||
             wx_keycode == WXK_RIGHT ||
             wx_keycode == WXK_DOWN ||
             wx_keycode == WXK_INSERT ||
             wx_keycode == WXK_PRIOR ||
             wx_keycode == WXK_NEXT ||
             wx_keycode == WXK_PAGEUP ||
             wx_keycode == WXK_PAGEDOWN ||
             wx_keycode == WXK_NUMPAD_ENTER
           );'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appdialogue_wx.c', 'w') as f:
        f.write(code)
    print("  OK: TtaIsSpecialKey widened")
else:
    print("  FAIL -- pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-arrow-fix.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-arrow-fix.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-arrow-fix.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "trial/option-a: fix arrow keys not moving the cursor

Root cause (verified against the actual wx-3.2 headers): TtaIsSpecialKey()
gated recognised special keys with a numeric range WXK_START..WXK_COMMAND
(300-308 on this wx build, since WXK_COMMAND==WXK_CONTROL here). Arrow
keys, Home, End, Insert, and Page Up/Down all have codes from 311 upward,
so they were rejected before ever reaching the cursor-movement code, even
though that code explicitly lists them as keys it wants to handle. Adds
the missing key codes to the recognised list; nothing existing changed.

Also removes the temporary diagnostic logging used to confirm this."

git push origin trial/option-a

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
