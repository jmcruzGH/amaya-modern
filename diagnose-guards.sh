#!/usr/bin/env bash
# diagnose-guards.sh
# Diagnostic only. Run from ~/amaya-modern with fix/gl-blanking checked out.
# Logs the value of FrameUpdating and frame_animating at the very top of
# GL_DrawAll, but only on calls where at least one frame actually has a
# pending redraw -- this filters out the thousands of "nothing to do"
# idle ticks and shows us specifically what the guards look like at the
# moments that matter.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

python3 - << 'PYEOF'
path = 'thotlib/view/gltimer.c'
with open(path) as f:
    lines = f.readlines()

anchor = 'ThotBool GL_DrawAll ()\n'
matches = [i for i, l in enumerate(lines) if l == anchor]
if len(matches) != 1:
    print(f"FAIL: found {len(matches)} matches, expected 1")
    exit(1)
i = matches[0]
assert lines[i+1].strip() == '{', repr(lines[i+1])

# Find the end of the local variable declarations: the first blank line
# or non-declaration line after the opening brace. We know from earlier
# reads the last declaration is "static double lastime;" -- find it.
decl_end = None
for j in range(i+2, i+20):
    if 'lastime' in lines[j] and 'static' in lines[j]:
        decl_end = j
        break
if decl_end is None:
    print("FAIL: could not find end of declarations")
    exit(1)

insert_at = decl_end + 1
new_lines = [
    '\n',
    '  {\n',
    '    int f2, any_pending = 0;\n',
    '    for (f2 = 1; f2 < MAX_FRAME; f2++)\n',
    '      if (FrameTable[f2].WdFrame != 0 && FrameTable[f2].DblBuffNeedSwap)\n',
    '        any_pending = f2;\n',
    '    if (any_pending)\n',
    '      fprintf(stderr, "DIAG7 GL_DrawAll top: pending_frame=%d FrameUpdating=%d frame_animating=%d\\n",\n',
    '              any_pending, (int)FrameUpdating, (int)frame_animating);\n',
    '  }\n',
]
lines[insert_at:insert_at] = new_lines
with open(path, 'w') as f:
    f.writelines(lines)
print(f"OK: inserted at line {insert_at+1}")
PYEOF

cd build
make -j$(nproc) 2>&1 | tee /tmp/build-diag7.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-diag7.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-diag7.log !!!"
  exit 1
fi
echo ""
echo "Done. Run: THOTDIR=\$(pwd) ./build/amaya/amaya > /tmp/amaya-diag7.txt 2>&1"
echo "Reproduce the stuck source-view case, interact for a bit after it's"
echo "stuck too (don't close immediately), then close Amaya. Then:"
echo "  grep '^DIAG7' /tmp/amaya-diag7.txt | tail -60"
