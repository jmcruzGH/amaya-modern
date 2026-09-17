#!/usr/bin/env bash
# fix-logdebug-and-parsing-err.sh
# Run from ~/amaya-modern with fix/gl-blanking checked out.
#
# Two independent fixes:
#
# 1. The "LogDebug" window (Misc/Panels/Dialog/Init toggles, Close/
#    testcase buttons) is Amaya's own developer debug-log control panel.
#    It auto-shows whenever the system wx library happens to have been
#    built with debug assertions enabled (__WXDEBUG__), which is common
#    on Linux distro packages and has nothing to do with our own build
#    settings. Not something an end user should see. Disabled (code kept,
#    commented, in case it's useful for our own debugging later).
#
# 2. The PARSING.ERR log window sometimes appearing blank on creation:
#    it is shown via a more complex sequence than a normal document open
#    -- ShowLogFile() + ShowSource() are both called, immediately
#    followed by a MODAL confirmation dialog (InitConfirm3L). A modal
#    dialog runs its own nested event loop until dismissed, which can
#    leave a just-scheduled repaint for the windows shown right before
#    it sitting unprocessed until well after the moment it was meant to
#    happen. Adds a general TtaRefreshAllWindows() helper (iterates
#    every currently open Amaya window and forces a guaranteed correct
#    repaint) and calls it right after this specific sequence completes,
#    as a safety net for this class of "complex sequence including a
#    modal dialog" scenario.

set -e
cd ~/amaya-modern
git checkout fix/gl-blanking

echo "=== [1/3] Disable LogDebug window auto-show ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaWindow.cpp') as f:
    code = f.read()

old = '''#ifdef __WXDEBUG__
  AmayaLogDebug * p_logdebug = AmayaApp::GetAmayaLogDebug( wxDynamicCast(this,wxWindow) );
  wxPoint win_position = GetPosition();
  wxSize  win_size = GetSize();
  p_logdebug->SetPosition(wxPoint(win_position.x+win_size.GetWidth()+10,win_position.y));
  p_logdebug->Show();
#endif /* __WXDEBUG__ */'''

new = '''#ifdef __WXDEBUG__
  /* Amaya's own developer debug-log window (toggles for Misc/Panels/
   * Dialog/Init etc. log categories) used to auto-show here whenever
   * the system wx library happens to have debug assertions enabled
   * (__WXDEBUG__) -- common on Linux distro packages, unrelated to our
   * own build settings, and not something an end user should see.
   * Left disabled; uncomment the block below to bring it back for our
   * own debugging of this project.
  AmayaLogDebug * p_logdebug = AmayaApp::GetAmayaLogDebug( wxDynamicCast(this,wxWindow) );
  wxPoint win_position = GetPosition();
  wxSize  win_size = GetSize();
  p_logdebug->SetPosition(wxPoint(win_position.x+win_size.GetWidth()+10,win_position.y));
  p_logdebug->Show();
  */
#endif /* __WXDEBUG__ */'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaWindow.cpp', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    idx = code.find('__WXDEBUG__')
    print(repr(code[max(0,idx-20):idx+400]))
    exit(1)
PYEOF

echo "=== [2/3] Add TtaRefreshAllWindows() helper ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/appdialogue_wx.c') as f:
    code = f.read()

anchor = '    p_window->Refresh(true);\n}'
new_func = '''    p_window->Refresh(true);
}

/*----------------------------------------------------------------------
  TtaRefreshAllWindows: force a guaranteed correct repaint of every
  currently open Amaya window. Safety net for sequences that show
  several windows in a row followed by a modal dialog (e.g. the parsing-
  error report), where a modal dialog's own nested event loop can leave
  a just-scheduled repaint for windows shown right before it sitting
  unprocessed well past the moment it was meant to happen.
  ----------------------------------------------------------------------*/
void TtaRefreshAllWindows( void )
{
  int i;
  for (i = 1; i <= MAX_WINDOW; i++)
    if (WindowTable[i].WdWindow)
      WindowTable[i].WdWindow->Refresh(true);
}'''

if anchor in code:
    code = code.replace(anchor, new_func, 1)
    with open('thotlib/dialogue/appdialogue_wx.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- anchor not found, showing TtaShowWindow area for inspection:")
    idx = code.find('void TtaShowWindow')
    print(repr(code[idx:idx+700]))
    exit(1)
PYEOF

echo "=== [3/3] Call it after the parsing-error modal-dialog sequence ==="
python3 - << 'PYEOF'
with open('amaya/HTMLsave.c') as f:
    code = f.read()

old = '''      ShowLogFile (doc, 1);
      ShowSource (doc, 1);
      /* Ask for confirmation */
      InitConfirm3L (doc, 1,
                     TtaGetMessage (AMAYA, AM_CHANGE_DOCTYPE1),
                     TtaGetMessage (AMAYA, AM_CHANGE_DOCTYPE2),
                     NULL,
                     TRUE);
      ok =  UserAnswer;'''

new = '''      ShowLogFile (doc, 1);
      ShowSource (doc, 1);
      /* Ask for confirmation */
      InitConfirm3L (doc, 1,
                     TtaGetMessage (AMAYA, AM_CHANGE_DOCTYPE1),
                     TtaGetMessage (AMAYA, AM_CHANGE_DOCTYPE2),
                     NULL,
                     TRUE);
      /* The modal confirmation dialog above can leave a just-scheduled
       * repaint for the log/source windows shown right before it
       * unprocessed; force a guaranteed correct repaint of everything
       * now that the whole sequence has settled. */
      { extern void TtaRefreshAllWindows( void );
        TtaRefreshAllWindows(); }
      ok =  UserAnswer;'''

if old in code:
    code = code.replace(old, new)
    with open('amaya/HTMLsave.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found")
    idx = code.find('ShowLogFile (doc, 1)')
    print(repr(code[max(0,idx-20):idx+500]))
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-logdebug-parsing.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-logdebug-parsing.log; then
  echo "!!! BUILD FAILED -- see /tmp/build-logdebug-parsing.log !!!"
  exit 1
fi

echo ""
echo "=== Commit ==="
git add -A
git commit -m "fix/gl-blanking: disable debug LogDebug window; fix PARSING.ERR blank

1. AmayaWindow.cpp: the LogDebug window (Misc/Panels/Dialog/Init toggles)
   is Amaya's own developer debug-log panel, auto-shown whenever the
   system wx library has debug assertions enabled (__WXDEBUG__) -- common
   on Linux distro packages, unrelated to our build, not meant for end
   users. Disabled (code kept, commented, for our own future debugging).

2. appdialogue_wx.c / HTMLsave.c: the PARSING.ERR log window sometimes
   appeared blank because it is shown via a more complex sequence than a
   normal document open -- ShowLogFile() + ShowSource(), immediately
   followed by a MODAL confirmation dialog. A modal dialog runs its own
   nested event loop until dismissed, which can leave a just-scheduled
   repaint for windows shown right before it sitting unprocessed well
   past the moment it was meant to happen. Adds TtaRefreshAllWindows(),
   which forces a guaranteed correct repaint of every currently open
   Amaya window, and calls it right after this specific sequence
   completes."

git push origin fix/gl-blanking

echo ""
echo "Build succeeded and pushed. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
