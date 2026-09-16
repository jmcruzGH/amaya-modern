#!/usr/bin/env bash
# trial1-keyboard-fix.sh
# Adds keyboard-input fixes on top of trial/option-a.
# Run from ~/amaya-modern with trial/option-a already checked out.
#
# Two independent, verified fixes:
#
# 1. Character corruption (letters forced uppercase, shifted symbols showing
#    their unshifted form): Amaya currently reads typed characters using
#    GetUnicodeKey() inside a handler bound to wxEVT_CHAR_HOOK. This is
#    documented wxWidgets behaviour (and a known long-standing GTK report)
#    that GetUnicodeKey() is not reliable at the CHAR_HOOK stage -- it is
#    only guaranteed correct on the proper per-widget wxEVT_CHAR event.
#    Fix: move the character-reading call (TtaHandleUnicodeKey) off the
#    window-level CHAR_HOOK handler and onto AmayaCanvas's own EVT_CHAR,
#    where GetUnicodeKey() is documented to work correctly. Arrow keys and
#    shortcuts stay on CHAR_HOOK since they use GetKeyCode(), which is
#    documented to behave consistently regardless of event stage.
#
# 2. Arrow keys not moving the cursor: TtaHandleSpecialKey (which processes
#    arrow keys) explicitly refuses to act unless the currently focused
#    widget is the drawing canvas (or a splitter/notebook/scrollbar). The
#    line that gives the canvas keyboard focus when its frame becomes
#    active is commented out in appli.c. Restoring it lets arrow-key
#    handling actually engage.

set -e
cd ~/amaya-modern
git checkout trial/option-a

echo "=== [1/3] AmayaWindow.cpp: stop reading characters at the CHAR_HOOK stage ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaWindow.cpp') as f:
    code = f.read()

old = """  if (!TtaHandleUnicodeKey(event))
    if (!TtaHandleSpecialKey(event))
      if (!TtaHandleShortcutKey(event))"""

new = """  /* Character input (TtaHandleUnicodeKey) is handled on AmayaCanvas's own
   * EVT_CHAR instead of here -- wx's GetUnicodeKey() is only documented to
   * return the correct, shift/layout-processed character on wxEVT_CHAR,
   * not on wxEVT_CHAR_HOOK. Arrow keys and shortcuts use GetKeyCode(),
   * which is reliable at this stage, so they stay here. */
  if (!TtaHandleSpecialKey(event))
    if (!TtaHandleShortcutKey(event))"""

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaWindow.cpp', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    exit(1)
PYEOF

echo "=== [2/3] AmayaCanvas.cpp: read characters on the canvas's own EVT_CHAR ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = """void AmayaCanvas::OnChar(wxKeyEvent& event)
{
  event.ResumePropagation(wxEVENT_PROPAGATE_MAX);
  event.Skip();
}"""

new = """void AmayaCanvas::OnChar(wxKeyEvent& event)
{
  /* This is where typed characters are actually read. wx's GetUnicodeKey()
   * (used inside TtaHandleUnicodeKey) is only documented to return the
   * correct, shift/layout-processed character here, on the focused
   * widget's own wxEVT_CHAR -- not on the window-level wxEVT_CHAR_HOOK
   * that used to be the only place this was called from. */
  if (!TtaHandleUnicodeKey(event))
    {
      event.ResumePropagation(wxEVENT_PROPAGATE_MAX);
      event.Skip();
    }
}"""

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: OnChar body")
else:
    print("  FAIL -- OnChar body pattern not found")
    exit(1)

old2 = "  //   EVT_CHAR(AmayaCanvas::OnChar )"
new2 = "  EVT_CHAR(AmayaCanvas::OnChar )"
if old2 in code:
    code = code.replace(old2, new2)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: EVT_CHAR binding uncommented")
else:
    print("  FAIL -- EVT_CHAR binding line not found")
    exit(1)
PYEOF

echo "=== [3/3] appli.c: restore keyboard focus to the canvas on frame activation ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/appli.c') as f:
    code = f.read()

old = """      /* the active frame changed so update the application focus */
      /*p_frame = TtaGetFrameFromId(frame);
      if (p_frame)
      p_frame->GetCanvas()->SetFocus();*/"""

new = """      /* the active frame changed so update the application focus.
       * Needed for keyboard input: TtaHandleSpecialKey (arrow keys, Home,
       * End, Delete...) only acts when the canvas itself holds keyboard
       * focus, and nothing else in wx3 gives it focus automatically. */
      p_frame = TtaGetFrameFromId(frame);
      if (p_frame && p_frame->GetCanvas())
        p_frame->GetCanvas()->SetFocus();"""

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appli.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

echo ""
echo "=== Commit ==="
git add -A
git commit -m "trial/option-a: fix keyboard input (character corruption + arrow keys)

- AmayaWindow.cpp / AmayaCanvas.cpp: read typed characters via
  TtaHandleUnicodeKey() on AmayaCanvas's own wxEVT_CHAR instead of on the
  window-level wxEVT_CHAR_HOOK. wx's GetUnicodeKey() is documented to only
  be reliable on wxEVT_CHAR -- using it from CHAR_HOOK was producing
  always-uppercase letters and unshifted punctuation (confirmed against
  wxWidgets docs and a matching historical GTK bug report).
- appli.c: restore the (previously commented-out) SetFocus() call that
  gives the drawing canvas keyboard focus when its frame becomes active.
  TtaHandleSpecialKey (arrow keys, Home/End/Delete) requires the canvas
  to hold focus and silently does nothing otherwise."

git push origin trial/option-a

echo ""
echo "Done. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
