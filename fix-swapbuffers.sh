#!/usr/bin/env bash
# fix-swapbuffers.sh
# Run from ~/amaya-modern, after switch-to-wxpanel-v6.sh has already
# applied successfully (confirmed: all 4 edits + preprocessor balance
# checks passed last time; only this one new issue surfaced at
# compile time). Disables AmayaFrame::SwapBuffers() the same way
# SetCurrent() was disabled: its only caller is the already-dead old
# GL_Swap in glbox.c (confirmed via direct inspection), and it calls
# m_pCanvas->SwapBuffers(), a wxGLCanvas-specific method a wxPanel
# does not have.

set -e
cd ~/amaya-modern

python3 - << 'PYEOF'
path = 'thotlib/dialogue/AmayaFrame.cpp'
with open(path, 'rb') as f:
    lines = f.readlines()

matches = [i for i, l in enumerate(lines) if l.strip() == b'bool AmayaFrame::SwapBuffers()']
assert len(matches) == 1, f"expected 1 match, found {len(matches)}"
start = matches[0]
guard_idx = None
for j in range(max(0, start-10), start):
    if lines[j].strip() == b'#ifdef _GL':
        guard_idx = j
# Not asserting guard_idx is not None here -- unlike SetCurrent(), we
# haven't directly confirmed this function has its own #ifdef _GL guard
# immediately above it, so we disable just the function itself either way.

brace_line = None
for j in range(start, start+4):
    if lines[j].strip() == b'{':
        brace_line = j
        break
assert brace_line is not None
depth = 0
end = None
for k in range(brace_line, len(lines)):
    depth += lines[k].count(b'{') - lines[k].count(b'}')
    if depth == 0 and k > brace_line:
        end = k
        break
assert end is not None

lines[start:start] = [b'#if 0 /* disabled for Option B: calls the removed wxGLCanvas-only SwapBuffers(); its only caller was already inside the disabled old GL_Swap in glbox.c */\n']
lines[end+2:end+2] = [b'#endif\n']

with open(path, 'wb') as f:
    f.writelines(lines)
print(f"OK: disabled AmayaFrame::SwapBuffers (around lines {start+1}-{end+1})")

depth2 = 0
for l in lines:
    s = l.strip()
    if s.startswith(b'#if'):
        depth2 += 1
    elif s.startswith(b'#endif'):
        depth2 -= 1
assert depth2 == 0, f"PREPROCESSOR NESTING UNBALANCED: depth={depth2}"
print("Preprocessor nesting verified balanced.")
PYEOF

echo ""
echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-swapbuffers.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|undefined reference" /tmp/build-swapbuffers.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-swapbuffers.log !!!"
  exit 1
fi

echo ""
echo "=== Build succeeded ==="
