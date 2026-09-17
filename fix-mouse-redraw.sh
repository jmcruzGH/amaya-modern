#!/usr/bin/env bash
# fix-mouse-redraw.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# The three keyboard-handling functions (character input, navigation
# keys, shortcuts) each already call GL_DrawAll() explicitly right after
# processing the key, so the screen updates immediately rather than
# waiting for the idle-driven catch-up mechanism. No equivalent call
# exists anywhere in the mouse-event handlers (click, release, double-
# click, drag-motion, wheel-scroll) -- every one of them relies purely on
# the idle mechanism catching up shortly afterwards. For simple content
# this catch-up is fast enough to go unnoticed; for heavier content
# (nested tables, rowspans/colspans needing real layout recalculation)
# the gap becomes wide enough that the on-screen cursor/highlight
# position can visibly lag behind where an edit actually lands -- which
# is exactly the "I can't trust where I'm about to type" problem
# reported when editing a complex table.
#
# Direct evidence this was already the original authors' intent for at
# least one case: OnMouseWheel ends with a commented-out "//GL_Swap
# (frame);" line -- the same class of fix as the disabled OnIdle handler
# found earlier, just for a different trigger.
#
# Adds the same explicit GL_DrawAll() call, in the same place relative
# to the action, to every mouse handler that changes cursor or selection
# state: OnMouseDown (click), OnMouseUp (release/end of drag-select),
# OnMouseDbClick (double-click word select), OnTimerMouseMove (live
# drag-select feedback, already throttled to ~100Hz so this is cheap),
# and OnMouseWheel (restoring the original, disabled intent, using
# GL_DrawAll instead of a bare GL_Swap so the scrolled content is
# actually freshly redrawn, not just whatever was already in the
# backbuffer).

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Adding explicit redraw calls to mouse handlers ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()
changed = []

# 1. OnMouseDown: after FrameButtonDownCallback
old = '''  FrameButtonDownCallback( frame,
                           event.GetButton(),
                           thot_mod_mask,
                           event.GetX(), event.GetY() );

#if !defined (_MACOS)'''
new = '''  FrameButtonDownCallback( frame,
                           event.GetButton(),
                           thot_mod_mask,
                           event.GetX(), event.GetY() );
#ifdef _GL
  /* Redraw immediately so the cursor position is trustworthy right
   * away, matching what the keyboard handlers already do -- otherwise
   * this waits for the next idle tick, which can visibly lag for
   * heavier content (e.g. tables needing layout recalculation). */
  GL_DrawAll();
#endif /* _GL */

#if !defined (_MACOS)'''
if old in code:
    code = code.replace(old, new)
    changed.append("OnMouseDown")

# 2. OnMouseUp: after FrameButtonUpCallback, inside the m_IsMouseSelecting block
old2 = '''      if (!FrameButtonUpCallback( frame, event.GetButton(),
                             thot_mod_mask,
                                 event.GetX(), event.GetY() ))
        event.Skip(false);
      else
        event.Skip();
      // force the focus when clicking on the canvas because the focus is locked on panel buttons
      TtaRedirectFocus();'''
new2 = '''      if (!FrameButtonUpCallback( frame, event.GetButton(),
                             thot_mod_mask,
                                 event.GetX(), event.GetY() ))
        event.Skip(false);
      else
        event.Skip();
#ifdef _GL
      /* Redraw immediately -- see OnMouseDown for why. This is the end
       * of a click or drag-selection, exactly when the user most needs
       * to trust what is on screen. */
      GL_DrawAll();
#endif /* _GL */
      // force the focus when clicking on the canvas because the focus is locked on panel buttons
      TtaRedirectFocus();'''
if old2 in code:
    code = code.replace(old2, new2)
    changed.append("OnMouseUp")

# 3. OnMouseDbClick: after FrameButtonDClickCallback
old3 = '''  FrameButtonDClickCallback( frame,
                             event.GetButton(),
                             thot_mod_mask,
                             event.GetX(), event.GetY() );

#ifndef _WINDOWS'''
new3 = '''  FrameButtonDClickCallback( frame,
                             event.GetButton(),
                             thot_mod_mask,
                             event.GetX(), event.GetY() );
#ifdef _GL
  /* Redraw immediately -- see OnMouseDown for why. */
  GL_DrawAll();
#endif /* _GL */

#ifndef _WINDOWS'''
if old3 in code:
    code = code.replace(old3, new3)
    changed.append("OnMouseDbClick")

# 4. OnTimerMouseMove: after FrameMotionCallback (live drag-select feedback)
old4 = '''  int frame = m_pAmayaFrame->GetFrameId();
  FrameMotionCallback( frame,
                       m_LastMouseMoveModMask,
                       m_LastMouseMoveX,
                       m_LastMouseMoveY );
}'''
new4 = '''  int frame = m_pAmayaFrame->GetFrameId();
  FrameMotionCallback( frame,
                       m_LastMouseMoveModMask,
                       m_LastMouseMoveX,
                       m_LastMouseMoveY );
#ifdef _GL
  /* Redraw immediately so the live selection highlight tracks the drag
   * without lag. This handler is already throttled to roughly once per
   * 10ms by the one-shot timer that calls it, so this is cheap. */
  GL_DrawAll();
#endif /* _GL */
}'''
if old4 in code:
    code = code.replace(old4, new4)
    changed.append("OnTimerMouseMove")

# 5. OnMouseWheel: restore the original, disabled intent
old5 = '''  FrameMouseWheelCallback( frame,
                           thot_mod_mask,
                           direction,
                           delta,
                           event.GetX(), event.GetY() );
  //GL_Swap( frame );
}'''
new5 = '''  FrameMouseWheelCallback( frame,
                           thot_mod_mask,
                           direction,
                           delta,
                           event.GetX(), event.GetY() );
#ifdef _GL
  /* Restores the original (disabled) intent of the line this replaces --
   * GL_DrawAll() is used instead of a bare GL_Swap so the scrolled
   * content is actually freshly redrawn, not just whatever was already
   * in the backbuffer. */
  GL_DrawAll();
#endif /* _GL */
}'''
if old5 in code:
    code = code.replace(old5, new5)
    changed.append("OnMouseWheel")

print(f"  Changed: {changed}")
if len(changed) != 5:
    print("  FAIL -- not all five patterns matched, aborting")
    exit(1)

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
print("  OK: all five mouse handlers updated")
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-mouse-redraw.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-mouse-redraw.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-mouse-redraw.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: immediate redraw on mouse actions, not just keyboard

The three keyboard-handling functions each already call GL_DrawAll()
explicitly right after processing a key, so the screen updates right
away rather than waiting for the idle-driven catch-up mechanism. No
equivalent existed anywhere in the mouse handlers (click, release,
double-click, drag-motion, wheel-scroll) -- all of them relied purely on
idle catching up shortly afterwards. For simple content this is fast
enough to go unnoticed; for heavier content (nested tables, rowspans/
colspans needing real layout recalculation) the gap is wide enough that
the on-screen cursor/highlight can visibly lag behind where an edit
actually lands.

Direct evidence this was already the original intent for at least one
case: OnMouseWheel ended with a commented-out '//GL_Swap(frame);' line,
the same class of gap as the disabled OnIdle handler found earlier.

Adds the same explicit GL_DrawAll() call to every mouse handler that
changes cursor or selection state: OnMouseDown, OnMouseUp,
OnMouseDbClick, OnTimerMouseMove (already throttled to ~100Hz, so this
is cheap), and OnMouseWheel (restoring the original disabled intent,
using GL_DrawAll instead of a bare GL_Swap so scrolled content is
actually freshly redrawn)."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
