#!/usr/bin/env bash
# amaya-fix2.sh -- apply to ~/amaya-modern, then rebuild
# Fixes the crash in AmayaStylePanel (XRC + AttachUnknownControl wx 3.x)

set -e
cd ~/amaya-modern

echo "[fix2a] Panel_Style.xrc: grid sizer rows=2 -> rows=0 (wx 3.x fix)"
python3 - << 'PYEOF'
with open('resources/xrc/Panel_Style.xrc') as f:
    code = f.read()
old = '<cols>5</cols>\n              <rows>2</rows>'
new = '<cols>5</cols>\n              <rows>0</rows>'
if old in code:
    code = code.replace(old, new)
    with open('resources/xrc/Panel_Style.xrc', 'w') as f:
        f.write(code)
    print("  Fixed: rows=2 -> rows=0")
else:
    print("  Already fixed or pattern not found")
PYEOF

echo "[fix2b] AmayaStylePanel.cpp: move AttachUnknownControl before LoadPanel (wx 3.x)"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaStylePanel.cpp') as f:
    code = f.read()

old = '''  if(!wxXmlResource::Get()->LoadPanel((wxPanel*)this, parent, wxT("wxID_TOOLPANEL_STYLE")))
    return false;
  
#ifdef _WINDOWS
  SetFont(wxSystemSettings::GetFont(wxSYS_DEFAULT_GUI_FONT));
#endif /* _WINDOWS */

  /* SVG Style Panel */
  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_SVG_STROKE_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_SVG_STROKE_COLOR"), wxColour(0,0,0), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));
  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_SVG_FILL_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_SVG_FILL_COLOR"), wxColour(255,255,255), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));

  /* HTML Style Panel */
  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_PANEL_CSS_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_PANEL_CSS_COLOR"), wxColour(0,0,0), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));

  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_PANEL_CSS_BK_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_PANEL_CSS_BK_COLOR"), wxColour(255,255,255), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));'''

new = '''  /* wx 3.x: AttachUnknownControl must be called BEFORE LoadPanel */
  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_SVG_STROKE_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_SVG_STROKE_COLOR"), wxColour(0,0,0), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));
  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_SVG_FILL_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_SVG_FILL_COLOR"), wxColour(255,255,255), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));
  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_PANEL_CSS_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_PANEL_CSS_COLOR"), wxColour(0,0,0), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));
  wxXmlResource::Get()->AttachUnknownControl(wxT("wxID_PANEL_CSS_BK_COLOR"),
      new AmayaColorButton(this, XRCID("wxID_PANEL_CSS_BK_COLOR"), wxColour(255,255,255), wxDefaultPosition, wxSize(16,16), wxBORDER_RAISED));

  if(!wxXmlResource::Get()->LoadPanel((wxPanel*)this, parent, wxT("wxID_TOOLPANEL_STYLE")))
    return false;
  
#ifdef _WINDOWS
  SetFont(wxSystemSettings::GetFont(wxSYS_DEFAULT_GUI_FONT));
#endif /* _WINDOWS */'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaStylePanel.cpp', 'w') as f:
        f.write(code)
    print("  Fixed: AttachUnknownControl moved before LoadPanel")
elif 'wx 3.x: AttachUnknownControl must be called BEFORE' in code:
    print("  Already fixed")
else:
    print("  Pattern not found -- check thotlib/dialogue/AmayaStylePanel.cpp manually")
PYEOF

echo ""
echo "Now rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
