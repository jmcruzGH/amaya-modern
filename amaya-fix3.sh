#!/usr/bin/env bash
# amaya-fix3.sh -- fix XRC sizer flag conflicts for wx 3.x
# Run from ~/amaya-modern, then rebuild

set -e
cd ~/amaya-modern

echo "[fix3a] Panel_XML.xrc: remove wxEXPAND|wxALIGN_CENTRE_VERTICAL conflicts"
python3 - << 'PYEOF'
with open('resources/xrc/Panel_XML.xrc') as f:
    code = f.read()
# In a horizontal sizer, wxEXPAND and wxALIGN_CENTRE_VERTICAL are incompatible.
# Remove wxALIGN_CENTRE_VERTICAL from these flags (keep wxEXPAND):
code = code.replace(
    '<flag>wxRIGHT|wxEXPAND|wxALIGN_CENTRE_VERTICAL</flag>',
    '<flag>wxRIGHT|wxEXPAND</flag>'
)
code = code.replace(
    '<flag>wxEXPAND|wxALIGN_CENTRE_VERTICAL</flag>',
    '<flag>wxEXPAND</flag>'
)
with open('resources/xrc/Panel_XML.xrc', 'w') as f:
    f.write(code)
print("  Fixed Panel_XML.xrc")
PYEOF

echo "[fix3b] Toolbar.xrc: remove conflicting alignment flags"
python3 - << 'PYEOF'
with open('resources/xrc/Toolbar.xrc') as f:
    code = f.read()
# wxALIGN_LEFT|wxALIGN_RIGHT together are contradictory; in a horizontal
# sizer they have no effect anyway. Replace with wxALIGN_CENTRE_VERTICAL:
code = code.replace(
    '<flag>wxALIGN_LEFT|wxALIGN_RIGHT|wxALIGN_CENTRE_VERTICAL</flag>',
    '<flag>wxALIGN_CENTRE_VERTICAL</flag>'
)
with open('resources/xrc/Toolbar.xrc', 'w') as f:
    f.write(code)
print("  Fixed Toolbar.xrc")
PYEOF

echo "[fix3c] AmayaXMLPanel.cpp: add NULL checks before SetToolTip calls"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaXMLPanel.cpp') as f:
    code = f.read()

old = '''  m_pXMLList = XRCCTRL(*this,"wxID_LIST_XML",wxListBox);
  XRCCTRL(*this,"wxID_REFRESH",wxBitmapButton)->SetToolTip(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_REFRESH)));
  XRCCTRL(*this,"wxID_APPLY",wxBitmapButton)->SetToolTip(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_APPLY)));'''

new = '''  m_pXMLList = XRCCTRL(*this,"wxID_LIST_XML",wxListBox);
  { wxBitmapButton* b;
    b = XRCCTRL(*this,"wxID_REFRESH",wxBitmapButton);
    if(b) b->SetToolTip(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_REFRESH)));
    b = XRCCTRL(*this,"wxID_APPLY",wxBitmapButton);
    if(b) b->SetToolTip(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_APPLY)));
  }'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaXMLPanel.cpp', 'w') as f:
        f.write(code)
    print("  Fixed AmayaXMLPanel.cpp: NULL checks added")
elif 'if(b) b->SetToolTip' in code:
    print("  Already fixed")
else:
    print("  Pattern not found -- check manually")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
