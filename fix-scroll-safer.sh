#!/usr/bin/env bash
# fix-scroll-safer.sh
# Run from ~/amaya-modern.
#
# Reverts the previous scroll.c fix (fix-scroll-narrow-swap.sh), which
# widened the clip region passed to RedrawFrameBottom without accounting
# for the "scroll" parameter (delta) also passed to it -- likely causing
# a mismatch between "redraw everything" and "but also shift by this
# amount", producing garbled/misplaced repaints.
#
# Safer replacement: leave VerticalScroll/HorizontalScroll's own drawing
# logic completely untouched (narrow clip, scroll delta, immediate swap,
# exactly as the original code does it -- whatever that does today is
# preserved as-is). Instead, right after each of their existing GL_Swap()
# calls, separately request ONE MORE deferred, full-frame redraw via
# GL_realize(). This does not change how the scroll itself draws or
# behaves at all; it just ensures that shortly afterward (via the
# already-working idle-driven GL_DrawAll, or the next explicit redraw
# call), a proper, complete, full-frame redraw happens on top, cleaning
# up whatever the narrow scroll-strip redraw left stale -- without
# touching the scroll math itself.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Reverting the previous (regressive) scroll.c fix ==="
git log --oneline -5
git revert --no-edit HEAD
echo "  Reverted. Current HEAD:"
git log --oneline -3

echo ""
echo "=== Applying safer fix: follow-up full-frame redraw, scroll logic untouched ==="
python3 - << 'PYEOF'
with open('thotlib/editing/scroll.c') as f:
    code = f.read()
changed = []

# VerticalScroll: after the GL_Swap in this function
old1 = '''#ifdef _GL
\t      /* to be sure the scrolled page has been displayed */
\t      GL_Swap( frame );
#endif /* _GL */
            }
        }
    }
}'''
new1 = '''#ifdef _GL
\t      /* to be sure the scrolled page has been displayed */
\t      GL_Swap( frame );
\t      /* The redraw just above only covers the newly-revealed scroll
\t       * strip (a narrow clip region), not the full frame -- with true
\t       * double buffering on modern GL, whatever it didn't touch is
\t       * stale, not a preserved shifted copy. Rather than change this
\t       * function's own scroll/clip/redraw logic (risks breaking the
\t       * scroll math itself), separately request one more, deferred,
\t       * full-frame redraw on top: this does not affect what just
\t       * happened above, it only ensures a proper complete repaint
\t       * follows shortly after via the existing idle-driven mechanism. */
\t      GL_realize( frame );
#endif /* _GL */
            }
        }
    }
}'''
if old1 in code:
    code = code.replace(old1, new1, 1)
    changed.append("VerticalScroll")

# HorizontalScroll: after its GL_Swap
old2 = '''          /* to be sure the scrolled page has been displayed */
          GL_Swap( frame );
#endif /* _GL */
        }
    }'''
new2 = '''          /* to be sure the scrolled page has been displayed */
          GL_Swap( frame );
          /* See the comment on the equivalent point in VerticalScroll
           * above -- request a follow-up full-frame redraw without
           * touching this function's own scroll/clip/redraw logic. */
          GL_realize( frame );
#endif /* _GL */
        }
    }'''
if old2 in code:
    code = code.replace(old2, new2, 1)
    changed.append("HorizontalScroll")

print(f"  Changed: {changed}")
if len(changed) != 2:
    print("  FAIL -- not both patterns matched, aborting")
    exit(1)

with open('thotlib/editing/scroll.c', 'w') as f:
    f.write(code)
print("  OK")
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-scroll-safer.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-scroll-safer.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-scroll-safer.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: safer fix for stale content after scrolling

The previous attempt widened the clip region passed to
RedrawFrameBottom inside VerticalScroll/HorizontalScroll without
accounting for the scroll delta also passed to the same call, causing a
mismatch between 'redraw everything' and 'but also shift by this
amount' -- this produced garbled, badly-positioned repaints (regression
confirmed by testing).

Reverted. This safer replacement leaves the scroll functions' own
drawing logic completely untouched (narrow clip, scroll delta,
immediate swap, exactly as before). Instead, right after each existing
GL_Swap() call, separately requests one more deferred, full-frame
redraw via GL_realize(). This does not change how the scroll itself
draws or behaves; it only ensures a proper, complete repaint follows
shortly after via the already-working idle-driven GL_DrawAll, cleaning
up whatever the narrow scroll-strip redraw left stale, without risking
the scroll math itself."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
