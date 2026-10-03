#!/usr/bin/env bash
# Smoke test for Amaya's local-file WYSIWYG editing.
#
# Runs the built binary under a virtual X server (Xvfb), with an isolated
# $HOME, opens a small XHTML file, performs an editing session with the
# keyboard and mouse (via xdotool), saves with Ctrl+S, quits with Ctrl+Q,
# and checks the saved file and the exit status.
#
#   sudo apt install xvfb xdotool x11-apps imagemagick   # once
#   tools/smoke-test.sh [build-dir]                      # default: build
#
# Exit status 0 = all checks passed.  A screenshot of the window just before
# saving is left in $SMOKE_OUT (default: /tmp/amaya-smoke) for inspection.
#
# Limits: no window manager, software OpenGL (Mesa).  This catches crashes and
# gross editing regressions; it says nothing about look-and-feel on a real
# desktop session.  Mouse coordinates assume the default window placement at
# (0,0) and the default fonts of a stock Ubuntu 24.04.

set -u
BUILD=${1:-build}
BIN=$(cd "$BUILD/amaya" 2>/dev/null && pwd)/amaya
OUT=${SMOKE_OUT:-/tmp/amaya-smoke}
DISP=${SMOKE_DISPLAY:-:97}

for t in Xvfb xdotool xwd convert; do
  command -v $t >/dev/null || { echo "missing tool: $t"; exit 2; }
done
[ -x "$BIN" ] || { echo "no binary at $BIN"; exit 2; }

rm -rf "$OUT"; mkdir -p "$OUT/home/.amaya"
export HOME="$OUT/home" DISPLAY="$DISP"
printf '[amaya]\nTIP_OF_THE_DAY_STARTUP=no\n' > "$HOME/.amaya/thot.rc"

DOC="$OUT/doc.html"
cat > "$DOC" <<'EOF'
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" /><title>Smoke</title></head>
<body>
<h1>Heading One</h1>
<p>Paragraph with <em>emphasis</em> and <strong>bold</strong> text, ação çé.</p>
<ul><li>item a</li><li>item b</li></ul>
<table border="1"><tr><td>c1</td><td>c2</td></tr></table>
</body>
</html>
EOF

Xvfb "$DISP" -screen 0 1280x900x24 >/dev/null 2>&1 &
XPID=$!
cleanup() { kill $APID $XPID 2>/dev/null; }
trap cleanup EXIT
sleep 2

( cd "$(dirname "$BIN")" && exec ./amaya "$DOC" ) >"$OUT/stdout.log" 2>"$OUT/stderr.log" &
APID=$!

# wait for the main window
for i in $(seq 1 40); do
  xdotool search --name "Smoke" >/dev/null 2>&1 && break
  sleep 0.5
done
sleep 4

K() { xdotool key --delay 120 "$@"; sleep 0.4; }
T() { xdotool type --delay 120 "$1"; sleep 0.4; }

xdotool mousemove 196 145 click 1; sleep 1        # end of the heading
T " XYZ"                                          # typing
K Return                                          # new paragraph
T "New para"
K Left Left Left BackSpace                        # caret movement + delete -> "New ara"
K End; T "!"                                      # End key
K ctrl+z                                          # undo the "!"
sleep 1
xwd -root -silent | convert xwd:- -crop 800x600+0+0 "$OUT/screen.png" 2>/dev/null
K ctrl+s; sleep 2                                 # save
K ctrl+q                                          # quit

for i in $(seq 1 30); do kill -0 $APID 2>/dev/null || break; sleep 0.5; done
if kill -0 $APID 2>/dev/null; then QUIT=hung; kill $APID; wait $APID 2>/dev/null; RC=-1
else wait $APID; RC=$?; QUIT=ok; fi

fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
flat=$(tr -s ' \n\t' ' ' < "$DOC")
check "typing at end of heading"      'grep -q "Heading One XYZ" <<<"$flat"'
check "Enter creates new paragraph"   'grep -Eq "<p>New ara</p>|<p>New ara *</p>" <<<"$flat"'
check "arrow keys + Backspace"        '! grep -q "New para" <<<"$flat"'
check "End key + undo"                '! grep -q "New ara!" <<<"$flat"'
check "UTF-8 text preserved"          'grep -q "ação çé" <<<"$flat"'
check "Ctrl+Q quits"                  '[ "$QUIT" = ok ]'
check "clean exit status ($RC)"       '[ "$RC" = 0 ]'
check "no crash messages on stderr"   '! grep -Eqi "segmentation|abort|assert|core dumped" "$OUT/stderr.log"'
echo "screenshot: $OUT/screen.png   saved file: $DOC"
exit $fail
