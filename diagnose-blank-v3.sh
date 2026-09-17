#!/usr/bin/env bash
# diagnose-blank-v3.sh
# Diagnostic only -- no behaviour changes. Run from ~/amaya-modern with
# fix/gl-blanking checked out.
#
# Unlike the previous diagnostic rounds, this finds each insertion point
# by searching for a short, unique line of existing code and inserting
# relative to whatever it actually finds there -- immune to whitespace
# differences from earlier edits, rather than trying to match a whole
# multi-line block verbatim.
#
# Logs, for every frame that has a pending redraw:
#   - FrameUpdating, DblBuffNeedSwap, doc, LoadedDocument, documentDisplayMode
#   - TtaFrameIsShown's own internal breakdown: does GetPageParent()
#     return non-NULL, and what does IsShown() actually return -- this
#     specifically targets whether the source-view frame's "am I shown"
#     check is the thing silently blocking it.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== Instrumenting TtaFrameIsShown ==="
python3 - << 'PYEOF'
path = 'thotlib/dialogue/appdialogue_wx.c'
with open(path) as f:
    lines = f.readlines()

anchor = 'ThotBool TtaFrameIsShown (int frame)\n'
matches = [i for i, l in enumerate(lines) if l == anchor]
if len(matches) != 1:
    print(f"  FAIL: found {len(matches)} matches for anchor, expected 1")
    exit(1)
i = matches[0]
# function body starts 2 lines down: signature, then '{'
assert lines[i+1].strip() == '{', repr(lines[i+1])

insert_at = i + 2
new_lines = [
    '  {\n',
    '    wxWindow *pp = FrameTable[frame].WdFrame ? FrameTable[frame].WdFrame->GetPageParent() : NULL;\n',
    '    fprintf(stderr, "DIAG4 TtaFrameIsShown: frame=%d wdframe=%p pageparent=%p pp_isshown=%d\\n",\n',
    '            frame, (void*)FrameTable[frame].WdFrame, (void*)pp, pp ? (int)pp->IsShown() : -1);\n',
    '  }\n',
]
lines[insert_at:insert_at] = new_lines
with open(path, 'w') as f:
    f.writelines(lines)
print(f"  OK: inserted at line {insert_at+1}")
PYEOF

echo "=== Instrumenting GL_DrawAll's per-frame check ==="
python3 - << 'PYEOF'
path = 'thotlib/view/gltimer.c'
with open(path) as f:
    lines = f.readlines()

anchor_candidates = [l for l in lines if 'documentDisplayMode[doc - 1] == DisplayImmediately)' in l]
if len(anchor_candidates) != 1:
    print(f"  FAIL: found {len(anchor_candidates)} matches for documentDisplayMode anchor, expected 1")
    exit(1)

idx = lines.index(anchor_candidates[0])
# find the opening '{' of this if-block, a line or two after
brace_idx = None
for j in range(idx, idx+3):
    if lines[j].strip() == '{':
        brace_idx = j
        break
if brace_idx is None:
    print("  FAIL: could not find opening brace after documentDisplayMode check")
    exit(1)

indent = '                      '
new_lines = [
    indent + 'fprintf(stderr, "DIAG4 GL_DrawAll ENTERED-branch: frame=%d doc=%d\\n", frame, doc);\n',
]
lines[brace_idx+1:brace_idx+1] = new_lines

# Also log every time this outer if is evaluated (regardless of outcome),
# by inserting right before it. Find start of the "if (FrameTable[frame].DblBuffNeedSwap &&" block.
before_candidates = [k for k, l in enumerate(lines) if 'if (FrameTable[frame].DblBuffNeedSwap &&' in l]
if len(before_candidates) != 1:
    print(f"  FAIL: found {len(before_candidates)} matches for DblBuffNeedSwap anchor, expected 1")
    exit(1)
b = before_candidates[0]
pre_lines = [
    '                  if (FrameTable[frame].DblBuffNeedSwap)\n',
    '                    fprintf(stderr, "DIAG4 pending: frame=%d frameupdating=%d doc=%d loaded=%d dispmode=%d\\n",\n',
    '                            frame, (int)FrameUpdating, doc,\n',
    '                            (doc ? !!LoadedDocument[doc - 1] : -1),\n',
    '                            (doc ? documentDisplayMode[doc - 1] : -1));\n',
]
lines[b:b] = pre_lines

with open(path, 'w') as f:
    f.writelines(lines)
print(f"  OK: inserted pending-check log before line {b+1}, entered-branch log after line {brace_idx+1}")
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-diag4.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-diag4.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-diag4.log !!!"
  exit 1
fi

echo ""
echo "Done (diagnostic only -- do NOT commit)."
echo "Run:  THOTDIR=\$(pwd) ./build/amaya/amaya > /tmp/amaya-diag4.txt 2>&1"
echo ""
echo "Reproduce the source-view case specifically (edit in main window,"
echo "jump to source view via the red triangle, click/type there and see"
echo "it not update). As soon as you see it NOT updating, close Amaya."
echo "Then:"
echo "  grep '^DIAG4' /tmp/amaya-diag4.txt | tail -80"
