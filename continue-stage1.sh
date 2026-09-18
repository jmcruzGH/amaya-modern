
echo "=== [4/6] Writing the disable-function helper ==="
cat > /tmp/disable_function.py << 'HELPER_EOF'
"""
Helper: find a C function by its signature (a distinctive substring of
its declaration line) in a file, and wrap its ENTIRE body (from the
matched line's opening brace to the correctly brace-counted matching
closing brace) in #if 0 / #endif. Used to disable old GL-based
functions whose names now live in the new wxDC replacement files,
without needing to know or match their exact body text (which may have
been edited this session and no longer matches the reference tree
exactly).
"""
import sys

def disable_function(path, signature_substr, label):
    with open(path, 'rb') as f:
        lines = f.readlines()

    start = None
    for i, line in enumerate(lines):
        if signature_substr.encode() in line:
            start = i
            break
    if start is None:
        print(f"  FAIL [{label}]: signature '{signature_substr}' not found in {path}")
        return False

    # Find the opening brace, which may be on the same line or a
    # following line (K&R vs Allman style -- this codebase uses Allman:
    # brace on its own line after the signature, possibly spanning
    # several lines of parameters first).
    brace_line = None
    for j in range(start, min(start + 15, len(lines))):
        if lines[j].strip() == b'{':
            brace_line = j
            break
    if brace_line is None:
        print(f"  FAIL [{label}]: opening brace not found near line {start+1}")
        return False

    depth = 0
    end = None
    for k in range(brace_line, len(lines)):
        depth += lines[k].count(b'{') - lines[k].count(b'}')
        if depth == 0 and k > brace_line:
            end = k
            break
        if depth == 0 and k == brace_line:
            # single-line body (unlikely here, but handle it)
            end = k
            break
    if end is None:
        print(f"  FAIL [{label}]: matching closing brace not found")
        return False

    lines[start:start] = [f'#if 0 /* disabled for Option B: replaced by wxdclifecycle.cpp -- {label} */\n'.encode()]
    lines[end+2:end+2] = [b'#endif\n']
    with open(path, 'wb') as f:
        f.writelines(lines)
    print(f"  OK [{label}]: disabled lines {start+1}-{end+1} in {path}")
    return True

if __name__ == '__main__':
    path, sig, label = sys.argv[1], sys.argv[2], sys.argv[3]
    ok = disable_function(path, sig, label)
    sys.exit(0 if ok else 1)

HELPER_EOF
echo "  OK"

echo "=== [5/6] Disabling old duplicate GL functions ==="
FAIL_COUNT=0
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "ThotBool GL_prepare (int frame)" "GL_prepare" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "void GL_Swap (int frame)" "GL_Swap" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "void GL_SwapStop (int frame)" "GL_SwapStop" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "ThotBool GL_SwapGet (int frame)" "GL_SwapGet" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glbox.c" "void GL_SwapEnable (int frame)" "GL_SwapEnable" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glwindowdisplay.c" "void GL_SetClipping (int x, int y, int width, int height)" "GL_SetClipping (old)" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glwindowdisplay.c" "void GL_UnsetClipping ()" "GL_UnsetClipping (old)" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/glwindowdisplay.c" "void GL_realize (int frame)" "GL_realize (old)" || FAIL_COUNT=$((FAIL_COUNT+1))
python3 /tmp/disable_function.py "thotlib/view/gltimer.c" "ThotBool GL_DrawAll ()" "GL_DrawAll" || FAIL_COUNT=$((FAIL_COUNT+1))
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "!!! $FAIL_COUNT function(s) could not be disabled -- see FAIL lines above !!!"
  echo "Not proceeding to build -- fix these manually first (each is a small,"
  echo "self-contained function; find it by name and wrap it in #if 0 / #endif)."
  exit 1
fi

echo "=== [6/6] Updating CMakeLists.txt ==="
python3 << 'PYEOF'
import re, sys

with open('CMakeLists.txt') as f:
    lines = f.readlines()

target_idx = None
indent = '  '
path_prefix = 'thotlib/view/'
for i, line in enumerate(lines):
    if 'gldisplay.c' in line and 'gl' + 'windowdisplay.c' not in line:
        target_idx = i
        # Derive indentation and path style from the matched line itself,
        # so the new lines look native to this CMakeLists.txt rather than
        # assuming a specific format.
        stripped = line.rstrip('\n')
        indent = stripped[:len(stripped) - len(stripped.lstrip())]
        if 'thotlib/view/' in stripped:
            path_prefix = 'thotlib/view/'
        break

if target_idx is None:
    print("  FAIL: no line containing 'gldisplay.c' found in CMakeLists.txt")
    print("  You will need to add the new source files to the build manually:")
    print("    thotlib/view/wxdcdisplay.cpp")
    print("    thotlib/view/wxdclifecycle.cpp")
    print("    thotlib/dialogue/wxdcfont.cpp")
    print("  and remove/comment out whatever line currently references")
    print("  thotlib/view/gldisplay.c, in the source file list used to")
    print("  build the 'amaya' target.")
    sys.exit(1)

original = lines[target_idx]
new_block = (
    f"{indent}# gldisplay.c commented out for Option B (replaced by wxDC-based\n"
    f"{indent}# rendering below) -- see OPTION-B-PLAN.md\n"
    f"{indent}# {original.strip()}\n"
    f"{indent}{path_prefix}wxdcdisplay.cpp\n"
    f"{indent}{path_prefix}wxdclifecycle.cpp\n"
    f"{indent}thotlib/dialogue/wxdcfont.cpp\n"
)
lines[target_idx] = new_block
with open('CMakeLists.txt', 'w') as f:
    f.writelines(lines)
print(f"  OK: replaced line {target_idx+1} (gldisplay.c) with the new file list")
print(f"  Please double-check this section of CMakeLists.txt looks right:")
print(new_block)
PYEOF

echo ""
echo "=== Rebuild (from scratch, since CMakeLists.txt changed) ==="
rm -rf build
mkdir build
cd build
cmake .. 2>&1 | tail -20
make -j$(nproc) 2>&1 | tee /tmp/build-optionb-stage1.log | grep -E "error:|Error|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|Error [0-9]" /tmp/build-optionb-stage1.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-optionb-stage1.log for full output !!!"
  echo "This is expected to need some iteration on a change this size --"
  echo "paste the error output back and we'll fix it precisely."
  exit 1
fi

echo ""
echo "=== Stage 1 build succeeded ==="
git add -A
git commit -m "Option B stage 1: wxDC drawing primitives compile and link

Adds thotlib/view/wxdcdisplay.cpp (drawing primitives), thotlib/view/
wxdclifecycle.cpp (GL_prepare/GL_Swap/GL_SetClipping/GL_realize
replacements), thotlib/dialogue/wxdcfont.cpp (wxFont-based font
loading), disables their direct old-code counterparts in gldisplay.c/
glbox.c/glwindowdisplay.c/gltimer.c to avoid duplicate symbols, updates
the six clipping call sites to pass an explicit frame number, and wires
everything into CMakeLists.txt.

AmayaCanvas/AmayaFrame are NOT yet changed -- they still use a GL
context and never call WxDC_SetCurrentFrameDC, so nothing actually
draws via the new code path yet. This commit only establishes that the
new code compiles and links correctly against the real project headers.
Stage 2 (next) wires AmayaCanvas to use wxDC instead of a GL context,
which is what will make this functional."

git push -u origin option-b-wxdc

echo ""
echo "Stage 1 complete and pushed to option-b-wxdc."
