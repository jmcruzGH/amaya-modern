#!/usr/bin/env bash
# fix-blanking.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# Root cause: GL_DrawAll() is the function that actually performs the
# deferred buffer swap (RedrawFrameBottom / GL_realize only set a
# "needs swap" flag; they don't swap the buffers themselves -- that is
# GL_DrawAll's job). It is explicitly called after each of the three
# keyboard-handling functions already fixed earlier (typing a character,
# arrow/navigation keys, shortcut keys), with a code comment stating
# plainly that it exists because otherwise "nothing is shown on the
# screen" after an edit.
#
# But AmayaCanvas::OnIdle -- documented as the general, catch-all place
# that flushes ANY pending redraw, from ANY source, on every idle moment
# -- is compiled out entirely (wrapped in #if 0), because it calls a
# function, IsParentFrameActive(), that does not exist anywhere in the
# codebase and would fail to compile. Without it, only the three
# keyboard handlers ever trigger a real buffer swap; mouse-driven edits
# (moving the cursor by clicking, drag-selecting/highlighting text,
# toolbar and menu actions) have no mechanism to reach the screen at all
# until something unrelated (like a window resize, which goes through
# the separately-fixed full-frame repaint path) happens to trigger one.
#
# Fix: restore the GL_DrawAll() call on idle, dropping the broken,
# undefined guard rather than reinventing it. GL_DrawAll() is cheap when
# there is nothing pending, so calling it on every idle tick is safe and
# matches how it is already used elsewhere in the code.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Restoring AmayaCanvas::OnIdle ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''void AmayaCanvas::OnIdle( wxIdleEvent& event )
{
  // idle events are no more used for animation. 
  // animation is managed by a timer
#if 0
  // Do not treat this event if the canvas is not active (hidden)
  if (!IsParentFrameActive())
    {
      event.Skip();
      return;
    }

#ifdef _GL
  GL_DrawAll();
#endif /* _GL */
#endif /* 0 */

}'''

new = '''void AmayaCanvas::OnIdle( wxIdleEvent& event )
{
  /* Flush any pending redraw (FrameTable[].DblBuffNeedSwap), from any
   * source -- not just the keyboard handlers, which each already have
   * their own explicit GL_DrawAll() call right after ThotInput(). Mouse-
   * driven edits (clicking to move the cursor, drag-selecting text,
   * toolbar/menu actions) have no other mechanism to reach the screen,
   * otherwise, until something unrelated (e.g. a window resize) happens
   * to trigger a repaint. GL_DrawAll() is a cheap per-frame flag check
   * when nothing is pending, so calling it on every idle tick is safe --
   * this was previously disabled only because it called a function,
   * IsParentFrameActive(), that does not exist anywhere in the codebase. */
#ifdef _GL
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
make -j$(nproc) 2>&1 | tee /tmp/build-blanking-fix.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-blanking-fix.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-blanking-fix.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: restore idle-driven redraw flush

GL_DrawAll() performs the deferred GL buffer swap for any frame whose
FrameTable[].DblBuffNeedSwap flag is set -- RedrawFrameBottom/GL_realize
only set that flag, they do not swap the buffers themselves. It is
already called explicitly after each of the three keyboard handlers
(character input, navigation keys, shortcuts), with a code comment
stating this is needed because otherwise nothing shows on screen after
an edit until the key is released.

AmayaCanvas::OnIdle -- documented as the general catch-all that flushes
any pending redraw on every idle moment, regardless of source -- was
entirely compiled out (#if 0) because it called a function,
IsParentFrameActive(), that does not exist anywhere in the codebase.
Without it, only the three keyboard handlers ever triggered a real
buffer swap; mouse-driven edits (clicking, drag-selecting/highlighting,
toolbar/menu actions) had no mechanism to reach the screen until
something unrelated (e.g. a resize) happened to trigger one.

Restores the GL_DrawAll() call on idle, dropping the broken, undefined
guard rather than reinventing it."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
