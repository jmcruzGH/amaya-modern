#!/usr/bin/env bash
# fix-scroll-narrow-swap.sh
# Run from ~/amaya-modern. Discards all diagnostic-only instrumentation
# (never committed, safe to drop) and applies the real fix on top of the
# last clean commit on fix/gl-blanking.
#
# Root cause, finally pinned down with hard evidence: VerticalScroll and
# HorizontalScroll (thotlib/editing/scroll.c) -- used whenever content
# needs to scroll into view, including jumping to the line matching an
# edit in the other split window -- compute a NARROW clip region
# covering only the newly-revealed strip of the scroll, redraw just
# that strip, then call GL_Swap() DIRECTLY, completely bypassing
# GL_DrawAll() and the full-frame-redraw fix already applied there.
#
# This is a leftover optimisation from the original code: on old,
# single-buffered or "preserve on scroll" GL implementations, only the
# newly-revealed edge supposedly needed redrawing, since the rest of
# the frame could be assumed to still be correct. That assumption does
# not hold with true double buffering on modern graphics drivers -- the
# untouched part of the backbuffer is whatever was there before, not a
# shifted copy of the previous frame. Because the swap happens directly
# here, it also clears the "needs a redraw" flag as a side effect,
# silently consuming it while showing an incompletely-drawn frame --
# explaining every part of the symptom: the jumped-to line is correct
# (it is the strip that got redrawn), everything around it is stale
# (never touched), and nothing downstream (idle catch-up, our explicit
# keyboard/mouse redraw calls) ever gets a chance to fix it, since the
# pending flag was already cleared here. Only a genuine window resize
# fixes it, because that goes through the separate, always-reliable
# OnPaint path that never depended on this flag in the first place.
#
# Fix: use the same established full-frame "-1,-1,-1,-1" DefClip idiom
# already proven correct elsewhere in this project, instead of the
# narrow, calculated scroll-strip region.

set -e
cd ~/amaya-modern

echo "=== Discarding diagnostic-only changes, returning to last clean commit ==="
git checkout fix/gl-blanking
git reset --hard HEAD
git status

echo ""
echo "=== Fixing VerticalScroll and HorizontalScroll in scroll.c ==="
python3 - << 'PYEOF'
with open('thotlib/editing/scroll.c') as f:
    code = f.read()
changed = []

# VerticalScroll -- scroll forward (downward)
old1 = '''\t\t      height = pFrame->FrYOrg + hframe;
\t\t      DefClip (frame, pFrame->FrXOrg, height,
\t\t\t       pFrame->FrXOrg + lframe, 
\t\t\t       height + delta);
                      add = RedrawFrameBottom (frame, delta, NULL);'''
new1 = '''\t\t      /* wx 3.x / modern GL: always redraw the full frame here, not
\t\t       * just the newly-revealed scroll strip -- with true double
\t\t       * buffering the untouched part of the backbuffer is stale,
\t\t       * not a preserved shifted copy of the previous frame. The
\t\t       * GL_Swap() right after this bypasses GL_DrawAll entirely,
\t\t       * so this is the only chance to get the full picture right. */
\t\t      DefClip (frame, -1, -1, -1, -1);
                      add = RedrawFrameBottom (frame, delta, NULL);'''
if old1 in code:
    code = code.replace(old1, new1)
    changed.append("VerticalScroll forward")

# VerticalScroll -- scroll backward (upward)
old2 = '''                      height = pFrame->FrYOrg;
                      DefClip (frame, pFrame->FrXOrg, height + delta,
                               pFrame->FrXOrg + lframe, height);
                      add = RedrawFrameTop (frame, -delta);'''
new2 = '''                      height = pFrame->FrYOrg;
                      /* wx 3.x / modern GL: see comment on the forward-scroll
                       * branch above -- always redraw the full frame. */
                      DefClip (frame, -1, -1, -1, -1);
                      add = RedrawFrameTop (frame, -delta);'''
if old2 in code:
    code = code.replace(old2, new2)
    changed.append("VerticalScroll backward")

# HorizontalScroll
old3 = '''                  width = pFrame->FrXOrg;
                  DefClip (frame, width - x, pFrame->FrYOrg, width,
                           pFrame->FrYOrg + hframe);
                }
              
              /* display the rest of the window */
              pFrame->FrXOrg += delta;
              RedrawFrameBottom (frame, 0, NULL);'''
new3 = '''                  width = pFrame->FrXOrg;
                  /* wx 3.x / modern GL: always redraw the full frame -- see
                   * VerticalScroll above for the full explanation. */
                  DefClip (frame, -1, -1, -1, -1);
                }
              
              /* display the rest of the window */
              pFrame->FrXOrg += delta;
              RedrawFrameBottom (frame, 0, NULL);'''
if old3 in code:
    code = code.replace(old3, new3)
    changed.append("HorizontalScroll")

print(f"  Changed: {changed}")
if len(changed) != 3:
    print("  FAIL -- not all three patterns matched, aborting")
    exit(1)

with open('thotlib/editing/scroll.c', 'w') as f:
    f.write(code)
print("  OK: all three sites fixed")
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-scroll-fix.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-scroll-fix.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-scroll-fix.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: fix stale content after scrolling (VerticalScroll etc.)

Root cause of the main remaining redraw symptoms, pinned down with hard
evidence across several diagnostic rounds: VerticalScroll and
HorizontalScroll (thotlib/editing/scroll.c) -- used whenever content
scrolls into view, including jumping to the line matching an edit in a
split window -- compute a narrow clip region covering only the
newly-revealed strip of the scroll, redraw just that strip, then call
GL_Swap() directly, completely bypassing GL_DrawAll() and the
full-frame-redraw fix already applied there.

This is a leftover optimisation from the original code: on old,
single-buffered or 'preserve on scroll' GL implementations, only the
newly-revealed edge supposedly needed redrawing, since the rest of the
frame could be assumed to still be correct. That assumption does not
hold with true double buffering on modern graphics drivers -- the
untouched part of the backbuffer is whatever was there before, not a
shifted copy of the previous frame. Because the swap happens directly
here, it also clears the pending-redraw flag as a side effect, silently
consuming it while showing an incompletely-drawn frame: the jumped-to
line is correct (it is the strip that got redrawn), everything around
it is stale (never touched), and nothing downstream (idle catch-up, the
explicit keyboard/mouse redraw calls) ever gets a chance to fix it,
since the flag was already cleared here. Only a genuine window resize
fixed it, because that goes through the separate, always-reliable
OnPaint path that never depended on this flag.

Uses the same established full-frame '-1,-1,-1,-1' DefClip idiom already
proven correct elsewhere in this project, instead of the narrow,
calculated scroll-strip region, at all three affected call sites."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
