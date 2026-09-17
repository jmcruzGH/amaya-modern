#!/usr/bin/env bash
# fix-throttle-redraw.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# Addresses wheel-scroll flicker and general "rendering can't keep up"
# lag on slower machines/GPUs, per direct user diagnosis: continuous,
# rapid-fire input (wheel-scroll, drag-selection) was triggering a full,
# expensive redraw on every single raw event, with no pacing at all.
#
# Amaya's own code already has exactly the right pattern working
# correctly for one case: mouse-drag-selection motion is coalesced
# through a one-shot timer (m_MouseMoveTimer) so that, no matter how
# many raw mouse-move events arrive, at most one redraw happens per
# throttle window. This replicates that same, already-proven mechanism
# for wheel-scroll (which currently has no throttling at all), and
# widens the existing drag-selection throttle window, since 10ms
# (~100Hz) is likely too aggressive for the reported hardware.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== [1/3] AmayaCanvas.h: declare the wheel-redraw timer and handler ==="
python3 - << 'PYEOF'
with open('thotlib/internals/h/AmayaCanvas.h') as f:
    code = f.read()

old = '  void OnTimerMouseMove( wxTimerEvent& event );\n'
new = ('  void OnTimerMouseMove( wxTimerEvent& event );\n'
       '  void OnTimerWheelRedraw( wxTimerEvent& event );\n')
if old in code:
    code = code.replace(old, new)
    print("  OK: handler declared")
else:
    print("  FAIL: OnTimerMouseMove declaration not found")
    exit(1)

old2 = '  wxTimer m_MouseMoveTimer;\n'
new2 = '  wxTimer m_MouseMoveTimer;\n  wxTimer m_WheelRedrawTimer;\n'
if old2 in code:
    code = code.replace(old2, new2)
    print("  OK: timer member declared")
else:
    print("  FAIL: m_MouseMoveTimer member not found")
    exit(1)

with open('thotlib/internals/h/AmayaCanvas.h', 'w') as f:
    f.write(code)
PYEOF

echo "=== [2/3] AmayaCanvas.cpp: wire up the timer, throttle wheel, widen drag-select throttle ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

# ID constant, defined locally in this file (both uses are in this same
# translation unit, so no header change needed for the ID itself).
if '#define ID_WHEEL_REDRAW_TIMER' not in code:
    marker = '#include "AmayaApp.h"'
    if marker in code:
        code = code.replace(marker, marker + '\n\n#define ID_WHEEL_REDRAW_TIMER (wxID_HIGHEST + 9001)', 1)
        print("  OK: ID constant added")
    else:
        print("  FAIL: include marker for ID constant insertion not found")
        exit(1)

# Wire up SetOwner alongside the existing timer's setup
old = '  m_MouseMoveTimer.SetOwner(this);\n}'
new = ('  m_MouseMoveTimer.SetOwner(this);\n'
       '  m_WheelRedrawTimer.SetOwner(this, ID_WHEEL_REDRAW_TIMER);\n}')
if old in code:
    code = code.replace(old, new, 1)
    print("  OK: timer owner set")
else:
    print("  FAIL: constructor pattern not found")
    exit(1)

# Add the handler implementation, right after OnTimerMouseMove's body
old2 = '''  FrameMotionCallback( frame,
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
new2 = '''  FrameMotionCallback( frame,
                       m_LastMouseMoveModMask,
                       m_LastMouseMoveX,
                       m_LastMouseMoveY );
#ifdef _GL
  /* Redraw immediately so the live selection highlight tracks the drag.
   * This handler is throttled by the one-shot timer that calls it (see
   * the Start() call in OnMouseMove) so this does not run on every raw
   * mouse-move event. */
  GL_DrawAll();
#endif /* _GL */
}

/*----------------------------------------------------------------------
  Class:  AmayaCanvas
  Method:  OnTimerWheelRedraw
  Description:  fires shortly after wheel activity, coalescing any
                number of raw wheel events in that window into a single
                redraw -- mirrors OnTimerMouseMove's existing throttle
                for drag-selection, applied to wheel-scroll, which
                previously had no throttling at all.
  -----------------------------------------------------------------------*/
void AmayaCanvas::OnTimerWheelRedraw( wxTimerEvent& WXUNUSED(event) )
{
#ifdef _GL
  GL_DrawAll();
#endif /* _GL */
}'''
if old2 in code:
    code = code.replace(old2, new2, 1)
    print("  OK: OnTimerWheelRedraw added")
else:
    print("  FAIL: OnTimerMouseMove body pattern not found")
    exit(1)

# Widen the existing drag-selection throttle: 10ms -> 40ms
old3 = 'm_MouseMoveTimer.Start( 10, wxTIMER_ONE_SHOT );'
new3 = 'm_MouseMoveTimer.Start( 40, wxTIMER_ONE_SHOT );  /* was 10ms; widened for slower hardware */'
if old3 in code:
    code = code.replace(old3, new3, 1)
    print("  OK: drag-select throttle widened to 40ms")
else:
    print("  FAIL: mouse-move Start() call not found")
    exit(1)

# Replace the un-throttled GL_DrawAll() added in the previous fix with
# the throttled version
old4 = '''  FrameMouseWheelCallback( frame,
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
new4 = '''  FrameMouseWheelCallback( frame,
                           thot_mod_mask,
                           direction,
                           delta,
                           event.GetX(), event.GetY() );
#ifdef _GL
  /* Coalesce rapid wheel events (a single physical scroll gesture can
   * generate many) into at most one redraw per throttle window, instead
   * of a full expensive redraw per tick -- this was the direct cause of
   * flicker and the renderer falling behind during scrolling. Mirrors
   * the same, already-proven pattern used for drag-selection motion. */
  if (!m_WheelRedrawTimer.IsRunning())
    m_WheelRedrawTimer.Start( 40, wxTIMER_ONE_SHOT );
#endif /* _GL */
}'''
if old4 in code:
    code = code.replace(old4, new4, 1)
    print("  OK: wheel redraw throttled")
else:
    print("  FAIL: OnMouseWheel's GL_DrawAll() call not found")
    exit(1)

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
PYEOF

echo "=== [3/3] Register the new timer's event-table entry ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '  EVT_TIMER( -1,AmayaCanvas::OnTimerMouseMove)\n'
new = ('  EVT_TIMER( ID_WHEEL_REDRAW_TIMER, AmayaCanvas::OnTimerWheelRedraw)\n'
       '  EVT_TIMER( -1,AmayaCanvas::OnTimerMouseMove)\n')
if old in code:
    code = code.replace(old, new, 1)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: event table entry added (before the wildcard -1 entry)")
else:
    print("  FAIL: event table pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-throttle.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-throttle.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-throttle.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: throttle rapid-fire redraws (wheel flicker, slow HW)

Per direct diagnosis: continuous, rapid input (wheel-scroll especially,
also drag-selection) was triggering a full, expensive redraw on every
single raw event, with no pacing -- fine on fast hardware, but visibly
flickers and falls behind on slower machines/GPUs, which can desync the
on-screen cursor position from where an edit actually lands until the
next full redraw catches up.

Amaya's own code already has exactly this pattern working correctly for
drag-selection motion (m_MouseMoveTimer, a one-shot timer that coalesces
any number of raw mouse-move events into at most one redraw per throttle
window). This replicates that same mechanism for wheel-scroll, which
previously had no throttling at all, and widens the existing
drag-selection throttle from 10ms (~100Hz) to 40ms (~25Hz) -- still
smooth to a human, much lighter on the renderer."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
