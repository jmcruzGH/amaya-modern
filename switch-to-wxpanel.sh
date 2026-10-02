#!/usr/bin/env bash
# switch-to-wxpanel.sh
# Run from ~/amaya-modern with option-b-wxdc checked out.
#
# Tests the core hypothesis from last session: that keeping wxGLCanvas
# as AmayaCanvas's base class -- a widget built specifically for OpenGL
# -- may not reliably propagate plain-DC repaints to the screen except
# via a genuine OS-level resize, even though drawing itself (confirmed
# via resize) is completely correct. Switches AmayaCanvas to the
# wxPanel variant the original header already had written and ready
# (the #else branch of its own #ifdef _GL), without touching the global
# _GL macro that everything else in the codebase still correctly
# depends on.
#
# Four files change:
#   - AmayaCanvas.h: hard-code the wxPanel branch (base class,
#     constructor signature, remove the GL-context members entirely)
#   - AmayaCanvas.cpp: matching constructor change
#   - AmayaFrame.cpp CreateDrawingArea(): drop context-sharing (nothing
#     to share anymore)
#   - AmayaFrame::SetCurrent(): disabled (#if 0) -- would no longer
#     compile against the new header, and its only caller is already
#     inside the disabled old GL_prepare in glbox.c, so nothing of
#     substance is lost.

set -e
cd ~/amaya-modern
git checkout option-b-wxdc

echo "=== [1/4] AmayaCanvas.h: hard-code the wxPanel branch ==="
python3 - << 'PYEOF'
path = 'thotlib/internals/h/AmayaCanvas.h'
with open(path) as f:
    code = f.read()

old1 = '''#ifdef _GL
class AmayaCanvas : public wxGLCanvas
#else // #ifdef _GL
class AmayaCanvas : public wxPanel
#endif // #ifdef _GL
{'''
new1 = '''class AmayaCanvas : public wxPanel
{'''
assert old1 in code, "class declaration pattern not found"
code = code.replace(old1, new1, 1)

old2 = '''#ifdef _GL
  AmayaCanvas( wxWindow * p_parent_window = NULL,
               AmayaFrame * p_parent_frame = NULL,
               wxGLContext * p_shared_context = NULL );
#else /* _GL */
  AmayaCanvas( wxWindow * p_parent_window = NULL,
               AmayaFrame * p_parent_frame = NULL );
#endif /* _GL */'''
new2 = '''  AmayaCanvas( wxWindow * p_parent_window = NULL,
               AmayaFrame * p_parent_frame = NULL );'''
assert old2 in code, "constructor declaration pattern not found"
code = code.replace(old2, new2, 1)

old3 = '''#ifdef _GL
  wxGLContext *  m_glContext;       /* owned when first canvas; shared otherwise */
  wxGLContext *  m_pSharedContext;  /* non-NULL when sharing an existing context */
public:
  wxGLContext * GetGLContext() const { return m_glContext; }
protected:
#endif /* _GL */


  bool m_Init;'''
new3 = '''  bool m_Init;'''
assert old3 in code, "GL context members pattern not found"
code = code.replace(old3, new3, 1)

with open(path, 'w') as f:
    f.write(code)
print("  OK: all three edits applied")
PYEOF

echo "=== [2/4] AmayaCanvas.cpp: matching constructor change ==="
python3 - << 'PYEOF'
path = 'thotlib/dialogue/AmayaCanvas.cpp'
with open(path) as f:
    code = f.read()

old = '''#ifdef _GL
AmayaCanvas::AmayaCanvas( wxWindow * p_parent_window,
                         AmayaFrame * p_parent_frame,
                         wxGLContext * p_shared_context )
 : wxGLCanvas( p_parent_window,
               wxID_ANY,
               AmayaApp::GetGL_AttrList(),
               wxDefaultPosition, wxDefaultSize,
               wxWANTS_CHARS, _T("AmayaCanvas") ),
#else // #ifdef _GL   
AmayaCanvas::AmayaCanvas( wxWindow * p_parent_window,
                         AmayaFrame * p_parent_frame )
 : wxPanel( p_parent_window ),
#endif // #ifdef _GL 
   m_pAmayaFrame( p_parent_frame ),
   m_Init( false ),
#ifdef _GL
   m_glContext( NULL ),
   m_pSharedContext( p_shared_context ),
#endif
   m_IsMouseSelecting( false ),
   m_MouseGrab (false)
{'''
new = '''AmayaCanvas::AmayaCanvas( wxWindow * p_parent_window,
                         AmayaFrame * p_parent_frame )
 : wxPanel( p_parent_window, wxID_ANY, wxDefaultPosition, wxDefaultSize,
            wxWANTS_CHARS, _T("AmayaCanvas") ),
   m_pAmayaFrame( p_parent_frame ),
   m_Init( false ),
   m_IsMouseSelecting( false ),
   m_MouseGrab (false)
{'''
assert old in code, "constructor header/init-list pattern not found"
code = code.replace(old, new, 1)

old2 = '''#ifdef _GL
  /* wx 3.x: independent context per canvas (shared context causes BadMatch).
   * Font textures are recreated per-context on first use. */
  (void)p_shared_context;
  /* Real GL context sharing: each canvas keeps its OWN context object
   * (required on modern Mesa -- one context object cannot be handed to
   * two different windows without triggering BadMatch), but when a
   * sibling context is given, the new context shares its textures and
   * display lists with it via wx's standard share-list constructor. */
  if (p_shared_context)
    m_glContext = new wxGLContext(this, p_shared_context);
  else
    m_glContext = new wxGLContext(this);
#endif /* _GL */

  SetAutoLayout(TRUE);'''
new2 = '''  /* Option B: AmayaCanvas no longer derives from wxGLCanvas, so there
   * is no GL context to create or share here at all -- see
   * switch-to-wxpanel.sh for the full reasoning. */
  SetAutoLayout(TRUE);'''
assert old2 in code, "context-creation body pattern not found"
code = code.replace(old2, new2, 1)

with open(path, 'w') as f:
    f.write(code)
print("  OK: both edits applied")
PYEOF

echo "=== [3/4] AmayaFrame.cpp: CreateDrawingArea, drop context sharing ==="
python3 - << 'PYEOF'
path = 'thotlib/dialogue/AmayaFrame.cpp'
with open(path) as f:
    code = f.read()

old = '''AmayaCanvas * AmayaFrame::CreateDrawingArea()
{
  AmayaCanvas * p_canvas = NULL;

#ifdef _GL
  if ( GetSharedContext() == -1 )
    {
      p_canvas = new AmayaCanvas( this, this );
      SetSharedContext( m_FrameId );
    }
  else
    {
      wxGLContext * p_SharedContext =
          FrameTable[GetSharedContext()].WdFrame->GetCanvas()->GetGLContext();
      p_canvas = new AmayaCanvas( this, this, p_SharedContext );
    }
#endif /* _GL */
  return p_canvas;
}'''
new = '''AmayaCanvas * AmayaFrame::CreateDrawingArea()
{
  /* Option B: no GL context to create or share -- every canvas is
   * independent and cheap now, so there is nothing to decide here. */
  AmayaCanvas * p_canvas = new AmayaCanvas( this, this );
  return p_canvas;
}'''
assert old in code, "CreateDrawingArea pattern not found"
code = code.replace(old, new, 1)
with open(path, 'w') as f:
    f.write(code)
print("  OK")
PYEOF

echo "=== [4/4] AmayaFrame.cpp: disable SetCurrent() (no longer compiles, no real caller) ==="
python3 - << 'PYEOF'
import sys
sys.path.insert(0, '/tmp')

path = 'thotlib/dialogue/AmayaFrame.cpp'
with open(path, 'rb') as f:
    lines = f.readlines()

anchor = b'bool AmayaFrame::SetCurrent()\n'
matches = [i for i, l in enumerate(lines) if l == anchor]
if len(matches) != 1:
    print(f"  FAIL: found {len(matches)} matches for SetCurrent signature, expected 1")
    sys.exit(1)
start = matches[0]
# The #ifdef _GL guard is a few lines above the signature; find it.
guard_idx = None
for j in range(max(0, start-10), start):
    if lines[j].strip() == b'#ifdef _GL':
        guard_idx = j
        break
if guard_idx is None:
    print("  FAIL: #ifdef _GL guard not found above SetCurrent")
    sys.exit(1)

# Find the function's closing brace via brace counting from the opening '{'
brace_line = None
for j in range(start, start+5):
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
print(f"  OK: disabled SetCurrent (lines {start+1}-{end+1} in the pre-edit file)")
PYEOF

echo ""
echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-wxpanel.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|undefined reference" /tmp/build-wxpanel.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-wxpanel.log !!!"
  exit 1
fi

echo ""
echo "=== Build succeeded ==="
