#!/usr/bin/env bash
# diagnose-onidle-count.sh
# Diagnostic only. Run from ~/amaya-modern with fix/gl-blanking checked out.
# Simply counts and timestamps every OnIdle call, to see whether idle
# events keep firing throughout an interactive session or stop after
# the initial startup burst.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

python3 - << 'PYEOF'
path = 'thotlib/dialogue/AmayaCanvas.cpp'
with open(path) as f:
    lines = f.readlines()

anchor = 'void AmayaCanvas::OnIdle( wxIdleEvent& event )\n'
matches = [i for i, l in enumerate(lines) if l == anchor]
if len(matches) != 1:
    print(f"FAIL: found {len(matches)} matches, expected 1")
    exit(1)
i = matches[0]
assert lines[i+1].strip() == '{', repr(lines[i+1])
insert_at = i + 2
lines[insert_at:insert_at] = [
    '  static long idle_count = 0;\n',
    '  idle_count++;\n',
    '  if (idle_count % 20 == 1)\n',
    '    fprintf(stderr, "DIAG6 OnIdle count=%ld time=%ld\\n", idle_count, (long)time(NULL));\n',
]
with open(path, 'w') as f:
    f.writelines(lines)
print(f"OK: inserted at line {insert_at+1}")
PYEOF

cd build
make -j$(nproc) 2>&1 | tee /tmp/build-diag6.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-diag6.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-diag6.log !!!"
  exit 1
fi
echo ""
echo "Done. Run: THOTDIR=\$(pwd) ./build/amaya/amaya > /tmp/amaya-diag6.txt 2>&1"
echo "Interact normally for 30+ seconds (click, type, wait a bit, click again),"
echo "reproducing the stuck source-view case at some point, then close Amaya."
echo "Then: grep '^DIAG6' /tmp/amaya-diag6.txt"
