#!/usr/bin/env bash
# amaya-fix12.sh -- test: revert to original single shared context
# The BadMatch was caused by AmayaColorButton, not context sharing.
# Original code: all canvases use the SAME wxGLContext object.
# This guarantees all texture IDs are valid everywhere.

set -e
cd ~/amaya-modern

echo "[fix12] AmayaCanvas.cpp: revert to single shared context object"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    lines = f.readlines()

# Find the context creation block and replace with original sharing
result = []
i = 0
while i < len(lines):
    line = lines[i]
    # Look for the context creation block
    if 'wx 3.x: share context when available' in line or \
       'wx 3.x: create or share' in line or \
       'wx 3.x: always create independent' in line or \
       ('p_shared_context' in line and 'wxGLContext' in line):
        # Skip until we find the matching #endif or closing brace
        # Collect the whole block
        block = [line]
        j = i + 1
        while j < len(lines) and ('wxGLContext' in lines[j] or 
              'p_shared_context' in lines[j] or
              'else' in lines[j] or
              (lines[j].strip() in ('{', '}', '') and j < i + 10)):
            block.append(lines[j])
            j += 1
        print(f"  Found context block at lines {i+1}-{j}:")
        for b in block:
            print(f"    {b}", end='')
        # Replace with original single-context sharing
        indent = '  '
        new_block = [
            f'{indent}/* Original wx 2.8 approach: all canvases share ONE context object.\n',
            f'{indent} * Texture IDs are always valid since there is only one context. */\n',
            f'{indent}if ( p_shared_context )\n',
            f'{indent}  m_glContext = p_shared_context;  /* reuse same context */\n',
            f'{indent}else\n',
            f'{indent}  m_glContext = new wxGLContext(this);  /* first canvas owns it */\n',
        ]
        result.extend(new_block)
        i = j
        print(f"  Replaced with single shared context")
    else:
        result.append(line)
        i += 1

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.writelines(result)
PYEOF

echo ""
echo "Rebuild and test -- if BadMatch returns, we'll know the ColorButton fix was the problem:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
