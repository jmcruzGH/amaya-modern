#!/usr/bin/env bash
# disable-view-menu-items.sh
# Run from ~/amaya-modern on the amaya-basic branch.
# Makes the seven menu callbacks that create additional synchronized
# views (ShowStructure, ShowSource, ShowLinks, ShowAlternate, ShowToC,
# SplitHorizontally, SplitVertically) into no-ops, by inserting a
# single early "return;" right after each function's opening brace.
# The menu items themselves stay visible/clickable (we abandoned the
# EDITOR.A/generated-header route after hitting an unrelated,
# pre-existing batch-tool build bug), but clicking them now does
# nothing. The function signatures are untouched, so anything that
# calls them by name still compiles and links correctly -- this is
# the same safe "retire via early return / #if 0" pattern used
# throughout this whole project for dead/unwanted code paths.

set -e
cd ~/amaya-modern

python3 - << 'PYEOF'
path = 'amaya/init.c'
with open(path) as f:
    lines = f.readlines()

targets = [
    'void ShowStructure (Document doc, View view)',
    'void ShowSource (Document doc, View view)',
    'void ShowLinks (Document doc, View view)',
    'void ShowAlternate (Document doc, View view)',
    'void ShowToC (Document doc, View view)',
    'void SplitHorizontally (Document doc, View view)',
    'void SplitVertically (Document doc, View view)',
]

# Process in reverse line order so earlier insertions don't shift the
# line numbers we still need to find for functions later in the file.
matches = []
for target in targets:
    found = [i for i, l in enumerate(lines) if l.rstrip('\n') == target]
    assert len(found) == 1, f"expected 1 match for {target!r}, found {len(found)}"
    matches.append((target, found[0]))

matches.sort(key=lambda t: t[1], reverse=True)

for target, sig_line in matches:
    brace_line = None
    for j in range(sig_line, sig_line + 4):
        if lines[j].strip() == '{':
            brace_line = j
            break
    assert brace_line is not None, f"could not find opening brace for {target!r}"
    insertion = [
        '  /* amaya-basic: this action creates an additional synchronized\n',
        '   * view, which this trimmed-down branch deliberately does not\n',
        '   * support (see the branch\'s own notes). Left as a reachable\n',
        '   * no-op rather than removed, so the menu item and its callback\n',
        '   * wiring stay intact and nothing else needs to change. */\n',
        '  return;\n',
    ]
    lines[brace_line+1:brace_line+1] = insertion
    print(f"  disabled: {target}  (inserted after line {brace_line+1})")

with open(path, 'w') as f:
    f.writelines(lines)
print("OK")
PYEOF

echo ""
echo "=== Rebuild ==="
cd build
make -j1 2>&1 | tee /tmp/build-disable-views.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|undefined reference" /tmp/build-disable-views.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-disable-views.log !!!"
  exit 1
fi

echo ""
echo "=== Build succeeded ==="
