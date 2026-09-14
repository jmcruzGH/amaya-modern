#!/usr/bin/env bash
# amaya-fix1.sh -- apply to ~/amaya-modern BEFORE re-running make
# Fixes two bugs found during first build on Kubuntu 24.04:
#   1. m_PollingDelay duplicated in wxAmayaSocketEventLoop.h
#   2. Block/Inline undefined in styleparser.c

set -e
cd "$(dirname "$0")"

echo "[fix1] wxAmayaSocketEventLoop.h: remove duplicate m_PollingDelay"
H="thotlib/include/wxAmayaSocketEventLoop.h"
if grep -q "m_curlPollFn" "$H"; then
  echo "  Phase 3 patch already applied -- checking for duplicate"
  # Remove any duplicate m_PollingDelay (second occurrence)
  python3 - << 'PYEOF'
import re
with open('thotlib/include/wxAmayaSocketEventLoop.h') as f:
    code = f.read()
# Count occurrences
n = code.count('  int m_PollingDelay;')
if n > 1:
    # Keep only the first occurrence followed by m_curlPollFn, remove the bare duplicate
    code = code.replace(
        '  int m_PollingDelay;\n  void (*m_curlPollFn)(void);\n  int m_PollingDelay;\n',
        '  int m_PollingDelay;\n  void (*m_curlPollFn)(void);\n'
    )
    with open('thotlib/include/wxAmayaSocketEventLoop.h', 'w') as f:
        f.write(code)
    print("  Duplicate removed")
else:
    print("  No duplicate found, ok")
PYEOF
else
  echo "  Phase 3 patch not yet applied, nothing to fix here"
fi

echo "[fix2] amaya.h: change undef trigger from __WXGTK__ to _WX_WX_H_"
AH="amaya/amaya.h"
if grep -q "__WXGTK__" "$AH"; then
  sed -i 's/defined(__WXGTK__)/defined(_WX_WX_H_)/g' "$AH"
  echo "  Fixed: styleparser.c will keep Block/Inline now"
else
  echo "  Already correct or patch not applied yet"
fi

echo ""
echo "Both fixes applied. Now run:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
