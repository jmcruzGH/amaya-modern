#!/usr/bin/env bash
# diagnose-blank-v4.sh
# Diagnostic only -- no behaviour changes. Run from ~/amaya-modern with
# fix/gl-blanking checked out (on top of the v3 diagnostic, which stays
# in place -- this adds one more, simpler check).
#
# Logs every call to GL_realize(frame) -- the function that marks a
# frame as "needs a redraw" in the first place. If this never fires for
# the source-view frame while you click/type in it, the problem is
# upstream of everything we've been fixing in GL_DrawAll: the redraw is
# never even being requested, not just failing to be flushed.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Instrumenting GL_realize ==="
python3 - << 'PYEOF'
path = 'thotlib/view/glwindowdisplay.c'
with open(path) as f:
    lines = f.readlines()

anchor = 'void GL_realize (int frame)\n'
matches = [i for i, l in enumerate(lines) if l == anchor]
if len(matches) != 1:
    print(f"  FAIL: found {len(matches)} matches, expected 1")
    exit(1)
i = matches[0]
assert lines[i+1].strip() == '{', repr(lines[i+1])
insert_at = i + 2
lines[insert_at:insert_at] = [
    '  fprintf(stderr, "DIAG5 GL_realize: frame=%d\\n", frame);\n'
]
with open(path, 'w') as f:
    f.writelines(lines)
print(f"  OK: inserted at line {insert_at+1}")
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-diag5.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-diag5.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-diag5.log !!!"
  exit 1
fi

echo ""
echo "Done (diagnostic only -- do NOT commit)."
echo "Run:  THOTDIR=\$(pwd) ./build/amaya/amaya > /tmp/amaya-diag5.txt 2>&1"
echo ""
echo "Reproduce the source-view-stuck case again: edit in main window,"
echo "jump to source view, click/type there and watch it fail to update."
echo "Close Amaya as soon as you see it stuck. Then:"
echo "  grep '^DIAG5' /tmp/amaya-diag5.txt | tail -40"
