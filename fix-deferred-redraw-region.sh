#!/usr/bin/env bash
# fix-deferred-redraw-region.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# Fixes stale/incomplete redraws for complex content (tables not
# realigning, old highlight remnants) that self-correct on resize or
# extra clicking.
#
# The idle-driven flush (GL_DrawAll, restored earlier) performs its
# deferred redraw using whatever clip region was last set by the
# ORIGINAL edit event that requested it -- which, for something like a
# table needing to reflow many cells, may only cover the one cell that
# was actually typed into, not the wider area whose layout also changed
# as a result (e.g. columns shifting). GL_DrawAll already has protective
# code that forces a full-frame redraw instead -- "DefClip(frame,-1,-1,
# -1,-1)" is Amaya's own established idiom for "redraw everything",
# already used successfully elsewhere in the codebase -- but it is gated
# behind a "BadGLCard" flag meant to auto-detect problematic graphics
# cards from the 2000s. Tracing how that flag gets set shows it defaults
# to FALSE on every normal system (the auto-detection is gated behind
# other conditions, and even when it isn't, the env-var default value
# works out to leave it disabled) -- so this protective path has likely
# always been effectively dead code for the vast majority of users.
# This makes it unconditional, matching the project's established
# pattern: modern Mesa needs "always redraw the whole frame" as the
# normal case, not as a special case for old hardware.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Making full-frame clip unconditional in GL_DrawAll's deferred redraw ==="
python3 - << 'PYEOF'
with open('thotlib/view/gltimer.c') as f:
    code = f.read()

old = '''                        if (GL_prepare (frame))
                          {
                            if (BadGLCard)
                              DefClip (frame, -1, -1, -1, -1);
                            /* prevent flickering*/
                            GL_SwapStop (frame);'''

new = '''                        if (GL_prepare (frame))
                          {
                            /* Always redraw the full frame here, not just
                             * whatever narrow region the original edit
                             * event set. This is a deferred redraw (the
                             * triggering event has already finished), so
                             * the clip region left over from it may no
                             * longer match everything that actually needs
                             * to be shown (e.g. a table reflowing several
                             * cells after one was edited). This used to
                             * be gated behind BadGLCard, a legacy
                             * bad-hardware auto-detect that defaults to
                             * off on every normal system. */
                            DefClip (frame, -1, -1, -1, -1);
                            /* prevent flickering*/
                            GL_SwapStop (frame);'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/view/gltimer.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-deferred-clip.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-deferred-clip.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-deferred-clip.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: always full-frame redraw in GL_DrawAll's deferred path

GL_DrawAll (the idle-driven redraw flush) performed its deferred redraw
using whatever clip region was last set by the original edit event that
requested it, which for content whose layout affects a wider area than
where the edit happened (e.g. a table reflowing several cells after one
was typed into) can leave stale/incomplete content on screen -- old
highlight remnants, columns not realigning -- until something else
(resize, extra clicking) forces a proper full redraw.

GL_DrawAll already had code to force a full-frame redraw instead, using
Amaya's own established -1,-1,-1,-1 'redraw everything' idiom (already
used successfully elsewhere in the codebase), but only when a BadGLCard
flag is set. Tracing SetBadCard's callers shows this flag defaults to
FALSE on every normal system regardless of hardware, so this protective
path was very likely always effectively dead code. Made unconditional,
consistent with this project's established pattern that modern Mesa
needs full-frame redraws as the normal case."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
