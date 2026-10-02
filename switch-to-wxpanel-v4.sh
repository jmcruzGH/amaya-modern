#!/usr/bin/env bash
# switch-to-wxpanel-v4.sh
# Run from ~/amaya-modern with option-b-wxdc checked out.
# Fixes a real bug from v3: the class-declaration edit started removal
# at the "class AmayaCanvas : public wxGLCanvas" line itself, one line
# AFTER the preceding "#ifdef _GL" -- leaving that #ifdef orphaned with
# no matching #endif, which is exactly what produced the "unterminated
# #ifdef" error. Now starts with a hard reset so it always runs against
# a known-clean state, regardless of the previous (broken) attempt
# left sitting in the working tree.

set -e
cd ~/amaya-modern
git checkout option-b-wxdc
git reset --hard HEAD
echo "Working tree reset to the last commit on option-b-wxdc."

echo "=== [1/4] AmayaCanvas.h ==="
python3 - << 'PYEOF'
path = 'thotlib/internals/h/AmayaCanvas.h'
with open(path) as f:
    lines = f.readlines()

def find_line(needle, lines):
    matches = [i for i, l in enumerate(lines) if needle in l]
    assert len(matches) == 1, f"expected 1 match for {needle!r}, found {len(matches)}"
    return matches[0]

# --- class declaration: include the PRECEDING #ifdef _GL this time ---
i_class_gl = find_line('class AmayaCanvas : public wxGLCanvas', lines)
i_ifdef = None
for j in range(i_class_gl-2, i_class_gl):
    if lines[j].strip() == '#ifdef _GL':
        i_ifdef = j
        break
assert i_ifdef is not None, "could not find #ifdef _GL above class declaration"
i_endif = None
for j in range(i_class_gl, i_class_gl + 6):
    if lines[j].strip() == '{':
        i_endif = j - 1
        break
assert i_endif is not None
lines[i_ifdef:i_endif+1] = ['class AmayaCanvas : public wxPanel\n']
print(f"  class declaration: replaced lines {i_ifdef+1}-{i_endif+1}")

# --- constructor declaration ---
i_ctor_gl = find_line('wxGLContext * p_shared_context = NULL', lines)
i_start = None
for j in range(i_ctor_gl-3, i_ctor_gl):
    if lines[j].strip() == '#ifdef _GL':
        i_start = j
        break
assert i_start is not None
i_end = None
for j in range(i_ctor_gl, i_ctor_gl + 8):
    if lines[j].strip() == '#endif /* _GL */':
        i_end = j
        break
assert i_end is not None
lines[i_start:i_end+1] = [
    '  AmayaCanvas( wxWindow * p_parent_window = NULL,\n',
    '               AmayaFrame * p_parent_frame = NULL );\n',
]
print(f"  constructor declaration: replaced lines {i_start+1}-{i_end+1}")

# --- GL context members ---
i_member_gl = find_line('wxGLContext *  m_glContext;', lines)
i_start2 = None
for j in range(i_member_gl-2, i_member_gl):
    if lines[j].strip() == '#ifdef _GL':
        i_start2 = j
        break
assert i_start2 is not None
i_end2 = None
for j in range(i_member_gl, i_member_gl + 10):
    if lines[j].strip() == '#endif /* _GL */':
        i_end2 = j
        break
assert i_end2 is not None
k = i_end2 + 1
while lines[k].strip() == '':
    k += 1
lines[i_start2:k] = []
print(f"  GL context members: removed lines {i_start2+1}-{k}")

with open(path, 'w') as f:
    f.writelines(lines)
print("  OK: AmayaCanvas.h done")

# Sanity check: every #ifdef/#ifndef must now have a matching #endif
depth = 0
for i, l in enumerate(lines):
    s = l.strip()
    if s.startswith('#ifdef') or s.startswith('#ifndef'):
        depth += 1
    elif s.startswith('#endif'):
        depth -= 1
assert depth == 0, f"PREPROCESSOR NESTING STILL UNBALANCED: depth={depth}"
print("  Preprocessor nesting verified balanced.")
PYEOF

echo "=== [2/4] AmayaCanvas.cpp ==="
python3 - << 'PYEOF'
path = 'thotlib/dialogue/AmayaCanvas.cpp'
with open(path) as f:
    lines = f.readlines()

def find_line(needle, lines):
    matches = [i for i, l in enumerate(lines) if needle in l]
    assert len(matches) == 1, f"expected 1 match for {needle!r}, found {len(matches)}"
    return matches[0]

i_param = find_line('wxGLContext * p_shared_context )', lines)
i_ctor = None
for j in range(i_param-3, i_param):
    if 'AmayaCanvas::AmayaCanvas(' in lines[j]:
        i_ctor = j
        break
assert i_ctor is not None
i_start = None
for j in range(i_ctor-2, i_ctor):
    if lines[j].strip() == '#ifdef _GL':
        i_start = j
        break
assert i_start is not None
i_brace = None
for j in range(i_ctor, i_ctor + 25):
    if lines[j].strip() == '{':
        i_brace = j
        break
assert i_brace is not None
lines[i_start:i_brace] = [
    'AmayaCanvas::AmayaCanvas( wxWindow * p_parent_window,\n',
    '                         AmayaFrame * p_parent_frame )\n',
    ' : wxPanel( p_parent_window, wxID_ANY, wxDefaultPosition, wxDefaultSize,\n',
    '            wxWANTS_CHARS, _T("AmayaCanvas") ),\n',
    '   m_pAmayaFrame( p_parent_frame ),\n',
    '   m_Init( false ),\n',
    '   m_IsMouseSelecting( false ),\n',
    '   m_MouseGrab (false)\n',
]
print(f"  constructor signature/init-list: replaced lines {i_start+1}-{i_brace}")

with open(path, 'w') as f:
    f.writelines(lines)

with open(path) as f:
    lines = f.readlines()

i_sal = find_line('SetAutoLayout(TRUE);', lines)
i_start2 = None
for j in range(i_sal-20, i_sal):
    if lines[j].strip() == '#ifdef _GL':
        i_start2 = j
        break
assert i_start2 is not None
i_end2 = None
for j in range(i_start2, i_sal):
    if lines[j].strip() == '#endif /* _GL */':
        i_end2 = j
        break
assert i_end2 is not None
lines[i_start2:i_end2+1] = [
    '  /* Option B: AmayaCanvas no longer derives from wxGLCanvas, so there\n',
    '   * is no GL context to create or share here at all. */\n',
]
print(f"  context-creation body: replaced lines {i_start2+1}-{i_end2+1}")

with open(path, 'w') as f:
    f.writelines(lines)

depth = 0
for l in lines:
    s = l.strip()
    if s.startswith('#ifdef') or s.startswith('#ifndef'):
        depth += 1
    elif s.startswith('#endif'):
        depth -= 1
assert depth == 0, f"PREPROCESSOR NESTING STILL UNBALANCED: depth={depth}"
print("  Preprocessor nesting verified balanced.")
print("  OK: AmayaCanvas.cpp done")
PYEOF

echo "=== [3/4] AmayaFrame.cpp: CreateDrawingArea ==="
python3 - << 'PYEOF'
path = 'thotlib/dialogue/AmayaFrame.cpp'
with open(path) as f:
    lines = f.readlines()

matches = [i for i, l in enumerate(lines) if 'AmayaCanvas * AmayaFrame::CreateDrawingArea()' in l]
assert len(matches) == 1, f"expected 1 match, found {len(matches)}"
i_start = matches[0]
i_brace = None
for j in range(i_start, i_start+4):
    if lines[j].strip() == '{':
        i_brace = j
        break
assert i_brace is not None
depth = 0
i_end = None
for k in range(i_brace, len(lines)):
    depth += lines[k].count('{') - lines[k].count('}')
    if depth == 0 and k > i_brace:
        i_end = k
        break
assert i_end is not None

lines[i_start:i_end+1] = [
    'AmayaCanvas * AmayaFrame::CreateDrawingArea()\n',
    '{\n',
    '  /* Option B: no GL context to create or share -- every canvas is\n',
    '   * independent and cheap now, so there is nothing to decide here. */\n',
    '  AmayaCanvas * p_canvas = new AmayaCanvas( this, this );\n',
    '  return p_canvas;\n',
    '}\n',
]
print(f"  CreateDrawingArea: replaced lines {i_start+1}-{i_end+1}")

with open(path, 'w') as f:
    f.writelines(lines)
print("  OK")
PYEOF

echo "=== [4/4] AmayaFrame.cpp: disable SetCurrent() ==="
python3 - << 'PYEOF'
path = 'thotlib/dialogue/AmayaFrame.cpp'
with open(path, 'rb') as f:
    lines = f.readlines()

matches = [i for i, l in enumerate(lines) if l.strip() == b'bool AmayaFrame::SetCurrent()']
assert len(matches) == 1, f"expected 1 match, found {len(matches)}"
start = matches[0]
guard_idx = None
for j in range(max(0, start-10), start):
    if lines[j].strip() == b'#ifdef _GL':
        guard_idx = j
assert guard_idx is not None

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

lines[start:start] = [b'#if 0 /* disabled for Option B: references the removed GetGLContext(); its only caller was already inside the disabled old GL_prepare in glbox.c */\n']
lines[end+2:end+2] = [b'#endif\n']

with open(path, 'wb') as f:
    f.writelines(lines)
print(f"  OK: disabled SetCurrent (around lines {start+1}-{end+1})")

depth2 = 0
for l in lines:
    s = l.strip()
    if s.startswith(b'#ifdef') or s.startswith(b'#ifndef') or s.startswith(b'#if '):
        depth2 += 1
    elif s.startswith(b'#endif'):
        depth2 -= 1
assert depth2 == 0, f"PREPROCESSOR NESTING STILL UNBALANCED in AmayaFrame.cpp: depth={depth2}"
print("  Preprocessor nesting verified balanced.")
PYEOF

echo ""
echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-wxpanel4.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|undefined reference" /tmp/build-wxpanel4.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-wxpanel4.log !!!"
  exit 1
fi

echo ""
echo "=== Build succeeded ==="
