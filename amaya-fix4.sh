#!/usr/bin/env bash
# amaya-fix4.sh -- fix NULL dereferences in AmayaPanel.cpp for wx 3.x
# Run from ~/amaya-modern, then rebuild

set -e
cd ~/amaya-modern

echo "[fix4a] AmayaPanel.cpp: add NULL checks after XRCCTRL calls"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaPanel.cpp') as f:
    code = f.read()

# Fix 1: AmayaToolPanelBar::Create -- add NULL checks
old1 = '''  XRCCTRL(*this, "wxID_LABEL_TOOLS", wxStaticText)->SetLabel(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_TOOLS)));
  XRCCTRL(*this, "wxID_BUTTON_CLOSE", wxBitmapButton)->SetToolTip(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_DONE)));

  m_scwin = XRCCTRL(*this, "wxID_PANEL_SWIN", wxScrolledWindow);'''
new1 = '''  { wxStaticText* lbl = XRCCTRL(*this, "wxID_LABEL_TOOLS", wxStaticText);
    if(lbl) lbl->SetLabel(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_TOOLS)));
    wxBitmapButton* btn = XRCCTRL(*this, "wxID_BUTTON_CLOSE", wxBitmapButton);
    if(btn) btn->SetToolTip(TtaConvMessageToWX(TtaGetMessage(LIB,TMSG_DONE)));
  }
  m_scwin = XRCCTRL(*this, "wxID_PANEL_SWIN", wxScrolledWindow);'''

# Fix 2: AmayaToolPanelItem constructor -- add NULL check
old2 = '  XRCCTRL(*this, "wxID_LABEL_TITLE", wxStaticText)->SetLabel(panel->GetToolPanelName());'
new2 = '''  { wxStaticText* lbl = XRCCTRL(*this, "wxID_LABEL_TITLE", wxStaticText);
    if(lbl) lbl->SetLabel(panel->GetToolPanelName());
  }'''

# Fix 3: AmayaToolPanelItem::Minimize -- add NULL checks for BUTTON_EXPAND
old3 = '        XRCCTRL(*this, "wxID_BUTTON_EXPAND", wxBitmapButton)->SetBitmapLabel( s_Bitmap_Minimized );\n'
new3 = '''        { wxBitmapButton* b = XRCCTRL(*this, "wxID_BUTTON_EXPAND", wxBitmapButton);
          if(b) b->SetBitmapLabel( s_Bitmap_Minimized ); }\n'''

old4 = '        XRCCTRL(*this, "wxID_BUTTON_EXPAND", wxBitmapButton)->SetBitmapLabel( s_Bitmap_Expanded );\n'
new4 = '''        { wxBitmapButton* b = XRCCTRL(*this, "wxID_BUTTON_EXPAND", wxBitmapButton);
          if(b) b->SetBitmapLabel( s_Bitmap_Expanded ); }\n'''

changed = False
for old, new in [(old1,new1),(old2,new2),(old3,new3),(old4,new4)]:
    if old in code:
        code = code.replace(old, new)
        changed = True
        print(f"  Fixed: {old[:60].strip()!r}...")
    else:
        print(f"  Already fixed or not found: {old[:60].strip()!r}...")

if changed:
    with open('thotlib/dialogue/AmayaPanel.cpp', 'w') as f:
        f.write(code)
    print("  AmayaPanel.cpp updated")
PYEOF

echo "[fix4b] AmayaExplorerPanel.cpp: add NULL checks after XRCCTRL"
# The Explorer panel is also loaded and may have similar issues
python3 - << 'PYEOF'
import os
path = 'thotlib/dialogue/AmayaExplorerPanel.cpp'
if not os.path.exists(path):
    print(f"  {path} not found, skipping")
    exit(0)
with open(path) as f:
    code = f.read()
# Find any direct XRCCTRL()->Method() calls without NULL check
import re
# Pattern: XRCCTRL(...)->SomeMethod but NOT already in an if() or assignment
matches = re.findall(r'XRCCTRL\([^)]+\)->\w+\([^;]*\);', code)
print(f"  Found {len(matches)} direct XRCCTRL dereferences in {path}")
print("  (These will crash if control not found; add NULL checks if needed)")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
