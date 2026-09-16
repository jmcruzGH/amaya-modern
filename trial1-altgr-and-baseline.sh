#!/usr/bin/env bash
# trial1-altgr-and-baseline.sh
# Run from ~/amaya-modern with trial/option-a checked out.
#
# Fix 1 -- AltGr not working (verified against real wx-3.2 headers):
#   wxMOD_ALTGR == wxMOD_ALT | wxMOD_CONTROL on this build, i.e. AltGr is
#   reported to wx as Alt+Control held together, not as a distinct signal.
#   TtaHandleUnicodeKey's Linux-only guard rejects ANY character typed
#   while Alt is down (to avoid double-firing Alt+letter menu shortcuts),
#   which also silently rejects AltGr-composed characters. Fix: only
#   reject when Alt is down WITHOUT Control also being down (a real
#   plain-Alt menu-accelerator press); let Alt+Control (AltGr) through.
#
# Fix 2 -- some punctuation (", *, =...) rendering low, hugging the
#   baseline: the earlier glyph-overflow fix (needed to stop whole words
#   silently disappearing) was more aggressive than it needed to be. It
#   clamped the computed vertical position to 0 whenever the subtraction
#   came out negative -- but a negative result is the CORRECT, expected
#   value for small glyphs that float entirely above the baseline without
#   touching it (quote marks, asterisk, equals sign). Only bitmap->top
#   itself being negative was ever the genuine corruption case (that's
#   what caused the original whole-word-vanishes bug); a merely-negative
#   *result* of the subtraction is normal and must be preserved.

set -e
cd ~/amaya-modern
git checkout trial/option-a

echo "=== [1/2] Fix AltGr: let Alt+Control (AltGr) characters through ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/appdialogue_wx.c') as f:
    code = f.read()

old = '''      (!event.CmdDown() || event.AltDown())
#if !defined(_MACOS) && !defined(_WINDOWS)
       && !event.AltDown()
#endif /* _MACOS */
       )'''

new = '''      (!event.CmdDown() || event.AltDown())
#if !defined(_MACOS) && !defined(_WINDOWS)
       /* wx-3.x on Linux/GTK reports AltGr as Alt+Control held together
        * (wxMOD_ALTGR == wxMOD_ALT | wxMOD_CONTROL). Only reject a plain
        * Alt press (menu accelerator, e.g. Alt+F); let AltGr-composed
        * characters (needed for @ # $ ^ et al. on European keyboards)
        * through. */
       && !(event.AltDown() && !event.ControlDown())
#endif /* _MACOS */
       )'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/appdialogue_wx.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    exit(1)
PYEOF

echo "=== [2/2] Fix baseline: only clamp genuinely-corrupt (negative) bitmap->top ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/openglfont.c') as f:
    code = f.read()

old = '''      {
        long top_signed  = (long) bitmap->top;
        long rows_signed = (long) source->rows;
        long pos_y = rows_signed - top_signed;
        if (pos_y < 0)
          pos_y = 0;
        BitmapGlyph->pos.y = (FT_Pos) pos_y;
      }'''

new = '''      {
        long top_signed  = (long) bitmap->top;
        long rows_signed = (long) source->rows;
        long pos_y = rows_signed - top_signed;
        /* Only guard against bitmap->top itself being negative -- that is
         * the genuinely corrupt case that used to unsigned-underflow and
         * poison the whole text run. A negative pos_y is otherwise the
         * correct, expected value for glyphs that float entirely above
         * the baseline without touching it (e.g. " * =), and must be
         * preserved rather than flattened to 0, or those characters
         * render dragged down onto the baseline. */
        if (top_signed < 0)
          pos_y = 0;
        BitmapGlyph->pos.y = (FT_Pos) pos_y;
      }'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/openglfont.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-altgr-baseline.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-altgr-baseline.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-altgr-baseline.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "trial/option-a: fix AltGr input and glyph baseline offset

- appdialogue_wx.c: TtaHandleUnicodeKey's Linux guard rejected any
  character typed while Alt was down (to avoid double-firing Alt+letter
  menu shortcuts), which also silently swallowed AltGr-composed
  characters (@ # \$ ^ etc.) since wx reports AltGr as Alt+Control held
  together on this platform (verified: wxMOD_ALTGR == wxMOD_ALT |
  wxMOD_CONTROL). Now only rejects plain Alt (no Control).
- openglfont.c: the earlier glyph-overflow fix over-corrected by
  clamping to 0 whenever the computed vertical position came out
  negative. A negative result is normal for glyphs that float above the
  baseline (quote marks, asterisk, equals sign); only bitmap->top itself
  being negative is the genuine corruption case. Fixes those characters
  rendering low/baseline-hugging."

git push origin trial/option-a

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
