#!/usr/bin/env bash
# fix-startup-blank.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# Removes the temporary diagnostic logging, and fixes small files
# sometimes opening blank.
#
# What the diagnostic run showed: while a document is first being loaded
# and laid out, Amaya deliberately sets documentDisplayMode to
# DeferredDisplay (so partially-built content doesn't flash on screen),
# then restores it once loading finishes. Our idle-driven flush
# (GL_DrawAll, restored earlier) correctly refuses to draw while that
# flag says "deferred" -- but the exact moment the flag flips back to
# "draw immediately" versus the exact moment the very last piece of
# startup content becomes ready is a tight race that, for a small/fast
# file, can land the wrong way: a pending redraw gets requested but the
# next idle tick doesn't pick it up in time, and nothing else asks for
# one afterwards.
#
# Rather than trying to perfectly time that race, this uses a mechanism
# we already know is unconditionally reliable: a genuine window resize
# always produces a correct full redraw, because that path (OnPaint ->
# FrameExposeCallback) doesn't depend on DisplayMode or the idle flag at
# all. So: explicitly ask for one such guaranteed real repaint at the one
# moment that matters -- right when a newly loaded document's window is
# first shown.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Removing diagnostic logging ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

code = code.replace(
    '''  {
    int w, h;
    GetClientSize(&w, &h);
    fprintf(stderr, "DIAG2 Init: canvas=%p shown=%d w=%d h=%d already_init=%d\\n",
            (void*)this, (int)IsShownOnScreen(), w, h, (int)m_Init);
  }
''', '')

code = code.replace(
    '''  {
    int w, h;
    GetClientSize(&w, &h);
    fprintf(stderr, "DIAG2 OnPaint: canvas=%p shown=%d w=%d h=%d\\n",
            (void*)this, (int)IsShownOnScreen(), w, h);
  }''', '')

code = code.replace(
    '''  {
    int w, h;
    GetClientSize(&w, &h);
    fprintf(stderr, "DIAG2 OnSize: canvas=%p shown=%d w=%d h=%d\\n",
            (void*)this, (int)IsShownOnScreen(), w, h);
  }''', '')

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
print("  OK: AmayaCanvas.cpp cleaned")
PYEOF

python3 - << 'PYEOF'
with open('thotlib/view/glwindowdisplay.c', 'rb') as f:
    code = f.read()
code = code.replace(
    b'  fprintf(stderr, "DIAG2 GL_realize: frame=%d\\n", frame);\n', b''
)
with open('thotlib/view/glwindowdisplay.c', 'wb') as f:
    f.write(code)
print("  OK: glwindowdisplay.c cleaned")
PYEOF

echo "=== Fixing TtaShowWindow: force one guaranteed repaint on first show ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/appdialogue_wx.c') as f:
    code = f.read()

old = '''void TtaShowWindow( int window_id, ThotBool show )
{
  AmayaWindow * p_window = WindowTable[window_id].WdWindow;
  if (p_window == NULL)
    return;
  fprintf(stderr, "DIAG2 TtaShowWindow: window_id=%d show=%d\\n", window_id, (int)show);
  p_window->Show( show );
}'''

new = '''void TtaShowWindow( int window_id, ThotBool show )
{
  AmayaWindow * p_window = WindowTable[window_id].WdWindow;
  if (p_window == NULL)
    return;
  p_window->Show( show );
  if (show)
    /* Guarantee one correct, complete repaint right when a newly loaded
     * document's window first becomes visible. A genuine wx paint event
     * (unlike the idle-driven DblBuffNeedSwap flush) always produces a
     * full, correct redraw regardless of documentDisplayMode timing --
     * this avoids a startup race where the very last piece of loaded
     * content becomes ready right around when display mode switches
     * back to immediate, and the next idle tick doesn't catch it before
     * the user is already looking at the (still blank) window. */
    p_window->Refresh(true);
}'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appdialogue_wx.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found (checking for non-diagnostic original)")
    old2 = '''void TtaShowWindow( int window_id, ThotBool show )
{
  AmayaWindow * p_window = WindowTable[window_id].WdWindow;
  if (p_window == NULL)
    return;

  p_window->Show( show );
}'''
    new2 = '''void TtaShowWindow( int window_id, ThotBool show )
{
  AmayaWindow * p_window = WindowTable[window_id].WdWindow;
  if (p_window == NULL)
    return;
  p_window->Show( show );
  if (show)
    /* Guarantee one correct, complete repaint right when a newly loaded
     * document's window first becomes visible. See commit message for
     * why this is needed. */
    p_window->Refresh(true);
}'''
    if old2 in code:
        code = code.replace(old2, new2)
        with open('thotlib/dialogue/appdialogue_wx.c', 'w') as f:
            f.write(code)
        print("  OK (matched original, non-diagnostic form)")
    else:
        print("  FAIL -- neither form found, aborting")
        exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-startup-fix.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-startup-fix.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-startup-fix.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: fix small files opening blank on startup

Diagnostic logging showed that while a document is first loaded and laid
out, documentDisplayMode is deliberately set to DeferredDisplay (so
partially-built content doesn't flash on screen) and restored once
loading finishes. The idle-driven redraw flush restored earlier
correctly refuses to draw while that flag says deferred -- but the exact
moment it flips back versus the exact moment the last piece of startup
content becomes ready is a tight race that can land the wrong way for a
small/fast-loading file: a pending redraw gets requested, but the next
idle tick doesn't catch it before the user is already looking at the
(still blank) window, and nothing else asks for one afterwards.

Rather than chase that timing race, use a mechanism already proven
reliable: a genuine wx paint event (OnPaint -> FrameExposeCallback)
always produces a correct full redraw regardless of DisplayMode or the
idle flag. TtaShowWindow now explicitly requests one such repaint right
when a newly loaded document's window is first shown."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
