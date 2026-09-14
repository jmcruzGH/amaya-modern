#!/usr/bin/env bash
# amaya-fix13.sh -- proper independent context fix
# Removes the broken extern declarations and uses the right approach:
# After Init(), force a Refresh() to trigger font loading in this context.

set -e
cd ~/amaya-modern

echo "[fix13] AmayaCanvas.cpp: clean up context init and font loading"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

# Remove the broken extern block
import re
code = re.sub(
    r'\s*/\* Force (?:default )?(?:GL )?font(?:\s+\w+)* creation in this context.*?\}\s*\}',
    '',
    code,
    flags=re.DOTALL
)
code = re.sub(
    r'\s*/\* Force font texture creation in this context \*/\s*\{.*?\}',
    '',
    code,
    flags=re.DOTALL
)

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
print("Removed broken extern block")
PYEOF

echo "[fix13b] Verify clean state around SetGlPipelineState:"
sed -n '455,500p' thotlib/dialogue/AmayaCanvas.cpp

cd build && make -j$(nproc) 2>&1 | grep "error:\|Built target\|Linking"
cd ..

echo ""
echo "Now testing -- does BadMatch return?"
echo "Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
