#!/usr/bin/env bash
# amaya-fix7.sh -- fix GLX BadMatch by using _NOSHARELIST mode
# In wx 3.x on modern Mesa/GLX, sharing contexts between canvases with
# different visuals causes BadMatch. The safest fix is to give each
# canvas its own independent GL context (_NOSHARELIST mode).

set -e
cd ~/amaya-modern

echo "[fix7a] AmayaFrame.cpp: force _NOSHARELIST (independent GL context per canvas)"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaFrame.cpp') as f:
    code = f.read()

# Replace the shared context block with simple independent context creation
old = '''#ifdef _GL
#ifdef _NOSHARELIST
  p_canvas = new AmayaCanvas( this, this );
#else /*_NOSHARELIST*/
  // If opengl is used then try to share the context
  if ( GetSharedContext () == -1/* || GetSharedContext () == m_FrameId */)\
    {
      /* there is no existing context, I need to create a first one and share it with others canvas */
      p_canvas = new AmayaCanvas( this, this );
      SetSharedContext( m_FrameId );
    }
  else
    {
      wxASSERT( FrameTable[GetSharedContext()].WdFrame != NULL );
      wxGLContext * p_SharedContext = FrameTable[GetSharedContext()].WdFrame->GetCanvas()->GetGLContext();
      wxASSERT( p_SharedContext );
      // create the new canvas with the opengl shared context
      p_canvas = new AmayaCanvas( this, this, p_SharedContext );
    }
#endif /* _NOSHARELIST */
#endif /* _GL */'''

new = '''#ifdef _GL
  /* wx 3.x on modern Mesa/GLX: context sharing between canvases causes
   * GLX BadMatch when visuals differ. Use independent context per canvas. */
  p_canvas = new AmayaCanvas( this, this );
  SetSharedContext( m_FrameId );
#endif /* _GL */'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaFrame.cpp', 'w') as f:
        f.write(code)
    print("  Fixed: each canvas gets its own GL context")
else:
    # Try alternative pattern (already partially patched)
    print("  Pattern not found - trying alternative")
    old2 = '''#ifdef _GL
#ifdef _NOSHARELIST
  p_canvas = new AmayaCanvas( this, this );
#else /*_NOSHARELIST*/'''
    if old2 in code:
        # Find and replace the whole block
        import re
        code = re.sub(
            r'#ifdef _GL\s*#ifdef _NOSHARELIST.*?#endif /\* _NOSHARELIST \*/\s*#endif /\* _GL \*/',
            '''#ifdef _GL
  /* wx 3.x: independent context per canvas (avoids GLX BadMatch) */
  p_canvas = new AmayaCanvas( this, this );
  SetSharedContext( m_FrameId );
#endif /* _GL */''',
            code, flags=re.DOTALL
        )
        with open('thotlib/dialogue/AmayaFrame.cpp', 'w') as f:
            f.write(code)
        print("  Fixed via regex")
    else:
        print("  Could not find pattern -- check manually")
        import subprocess
        result = subprocess.run(['grep', '-n', 'NOSHARELIST\|SharedContext\|p_SharedContext',
                               'thotlib/dialogue/AmayaFrame.cpp'],
                              capture_output=True, text=True)
        print(result.stdout[:500])
PYEOF

echo "[fix7b] AmayaCanvas.cpp: don't pass shared context to wxGLContext"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

# When we stopped sharing, AmayaCanvas still accepts p_shared_context.
# Now always create a new context:
old = '''  if ( p_shared_context ) {
    m_glContext = p_shared_context;  /* sharing: do not own */
  } else {
    m_glContext = new wxGLContext(this);  /* first canvas: we own it */
  }'''

new = '''  /* wx 3.x: always create independent context (no sharing) */
  (void)p_shared_context;  /* ignored */
  m_glContext = new wxGLContext(this);'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  Fixed: always create independent wxGLContext")
else:
    print("  Pattern not found in AmayaCanvas.cpp -- checking current state")
    for i, l in enumerate(code.split('\n')[98:115], 99):
        print(f"  {i}: {l}")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
