#!/usr/bin/env bash
# create-amaya-basic.sh
# Run from ~/amaya-modern.
# Creates the amaya-basic branch from option-b-wxdc (keeping all
# confirmed Option B fixes: wxPanel switch, validation-window fix,
# flicker improvement), then removes the seven menu lines in
# amaya/EDITOR.A that create additional synchronized views (structure,
# source, links, alternate, table of contents, split horizontal/
# vertical). Everything else in the Views menu (zoom, log file,
# document info, full-screen, toolbar toggles, ShowFormatted, map
# areas/targets) is left untouched, as is every other menu.
#
# This only removes the MENU ENTRIES that trigger these actions -- the
# underlying C functions (SplitHorizontally, ShowSource, etc.) are not
# touched, since with no menu item left to call them they simply
# become unreachable, the same safe pattern used throughout this
# project for retiring dead code paths without deleting anything that
# might still matter.

set -e
cd ~/amaya-modern

echo "=== Create amaya-basic from option-b-wxdc ==="
git checkout option-b-wxdc
git branch -D amaya-basic 2>/dev/null || true
git checkout -b amaya-basic

echo "=== Remove the seven view-creating menu lines from EDITOR.A ==="
python3 - << 'PYEOF'
path = 'amaya/EDITOR.A'
with open(path) as f:
    lines = f.readlines()

targets = [
    'Views button:BShowStructure -> ShowStructure;',
    'Views button:BShowSource -> ShowSource;',
    'Views button:BShowLinks -> ShowLinks;',
    'Views button:BShowAlternate -> ShowAlternate;',
    'Views button:BShowToC -> ShowToC;',
    'Views toggle:TSplitHorizontally -> SplitHorizontally;',
    'Views toggle:TSplitVertically -> SplitVertically;',
]

removed = 0
new_lines = []
for line in lines:
    stripped = line.strip()
    if stripped in targets:
        print(f"  removing: {stripped}")
        removed += 1
        continue
    new_lines.append(line)

assert removed == len(targets), f"expected to remove {len(targets)} lines, removed {removed}"

with open(path, 'w') as f:
    f.writelines(new_lines)
print(f"OK: removed {removed} lines")
PYEOF

echo ""
echo "=== Rebuild (this regenerates EDITOR.h from EDITOR.A) ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-amaya-basic.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|undefined reference" /tmp/build-amaya-basic.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-amaya-basic.log !!!"
  exit 1
fi

echo ""
echo "=== Build succeeded ==="
echo "Confirming the menu items are actually gone from the generated header:"
grep -c "TSplitHorizontally\|TSplitVertically\|BShowStructure\|BShowSource\|BShowLinks\|BShowAlternate\|BShowToC" amaya/generated/EDITOR.h || echo "0 (fully removed, as expected)"
