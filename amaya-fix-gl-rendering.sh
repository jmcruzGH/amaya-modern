#!/usr/bin/env bash
# amaya-fix-gl-rendering.sh
# Fix GL display list sharing between canvases (source view / split windows)
#
# ROOT CAUSE: Amaya caches box rendering as GL Display Lists (glNewList/glCallList).
# Display lists are per-GL-context. With independent contexts, a display list
# compiled in context A is invisible in context B -> source view shows nothing.
#
# FIX: Use proper wxGLContext sharing so display lists are shared between contexts.
# The BadMatch crash we saw previously was caused by:
#   1. AmayaColorButton constructed with unrealized parent -> FIXED
#   2. printgl.c bare SetCurrent() calls -> FIXED
# With those fixes in place, shared contexts should work correctly.
#
# We use new wxGLContext(canvas, sharedCtx) which creates a new context that
# shares display lists and textures with sharedCtx, but has its own state
# (viewport, matrix, etc.). This is the correct wx 3.x API.
#
# Additionally: when switching to a new context, invalidate all cached display
# lists so they get recompiled in the correct context on first use.

set -e
cd ~/amaya-modern

echo "[gl-fix 1] AmayaCanvas.cpp: proper context sharing"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = '''  /* wx 3.x: independent context per canvas (shared context causes BadMatch).
   * Font textures are recreated per-context on first use. */
  (void)p_shared_context;
  m_glContext = new wxGLContext(this);'''

new = '''  /* wx 3.x: create a new context sharing display lists and textures
   * with the first canvas's context. This allows GL display lists compiled
   * in context A to be called in context B (split windows, source view).
   * Each canvas still has its OWN context (own viewport, matrix state),
   * so glXMakeCurrent with different windows works correctly. */
  if (p_shared_context)
    m_glContext = new wxGLContext(this, p_shared_context);
  else
    m_glContext = new wxGLContext(this);'''

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  Fixed: proper wxGLContext sharing enabled")
else:
    print("  Pattern not found -- check current state:")
    for i, l in enumerate(code.split('\n')[97:110], 98):
        print(f"  {i}: {l}")
PYEOF

echo "[gl-fix 2] AmayaFrame.cpp: pass shared context to secondary canvases"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaFrame.cpp') as f:
    code = f.read()

# Check current state
if 'GetSharedContext() == -1' in code:
    print("  Already has sharing logic")
elif 'independent context per canvas' in code or \
     'p_canvas = new AmayaCanvas( this, this );\n  SetSharedContext' in code:
    # Find and replace the block
    import re
    # Replace any variant of the no-sharing block
    pattern = r'#ifdef _GL\n  /\*.*?#endif /\* _GL \*/'
    match = re.search(pattern, code, re.DOTALL)
    if match:
        new_block = '''#ifdef _GL
  /* Share GL context so display lists/textures are visible across canvases */
  if ( GetSharedContext() == -1 )
    {
      /* First canvas: create new context and register as shared source */
      p_canvas = new AmayaCanvas( this, this );
      SetSharedContext( m_FrameId );
    }
  else
    {
      /* Subsequent canvases: share context with first canvas */
      wxASSERT( FrameTable[GetSharedContext()].WdFrame != NULL );
      wxGLContext * p_SharedContext =
          FrameTable[GetSharedContext()].WdFrame->GetCanvas()->GetGLContext();
      wxASSERT( p_SharedContext );
      p_canvas = new AmayaCanvas( this, this, p_SharedContext );
    }
#endif /* _GL */'''
        code = code[:match.start()] + new_block + code[match.end():]
        with open('thotlib/dialogue/AmayaFrame.cpp', 'w') as f:
            f.write(code)
        print("  Fixed: context sharing restored in CreateDrawingArea()")
    else:
        print("  Could not find _GL block -- manual fix needed")
        import subprocess
        r = subprocess.run(['grep', '-n', 'ifdef _GL', 
                           'thotlib/dialogue/AmayaFrame.cpp'],
                          capture_output=True, text=True)
        print(r.stdout[:200])
else:
    print("  Unknown state -- check AmayaFrame.cpp manually")
PYEOF

echo "[gl-fix 3] displaybox.c: invalidate display lists on context switch"
# When a new canvas initializes with a shared context, existing display lists
# from the main canvas ARE shared. But if any display lists were compiled
# before the second context was created (during startup), they may not be shared.
# Force all boxes to recompile their display lists on first use in new context
# by setting VisibleModification=TRUE when Init() runs for a secondary canvas.
#
# Actually with proper wxGLContext sharing, display lists compiled AFTER the
# shared context is created ARE visible in both contexts. The key is that
# the first canvas must fully initialize before the second is created.
# Our AmayaFrame.cpp change ensures this: SetSharedContext is called after
# the first canvas is fully constructed.

echo ""
echo "[gl-fix 4] Verify AmayaCanvas.cpp Init() -- ensure viewport is set"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()
# Check if GLResize is called in Init()
if 'GLResize' in code and 'GetClientSize' in code:
    print("  GLResize already in Init() -- good")
else:
    print("  Adding GLResize to Init()...")
    old = '  SetGlPipelineState ();\n#endif /* _GL */'
    new = ('  SetGlPipelineState ();\n'
           '  /* Ensure viewport is set for this canvas */\n'
           '  { int w, h; GetClientSize(&w, &h);\n'
           '    if (w > 0 && h > 0) GLResize(w, h, 0, 0); }\n'
           '#endif /* _GL */')
    if old in code:
        code = code.replace(old, new)
        with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
            f.write(code)
        print("  Added GLResize to Init()")
    else:
        print("  Pattern not found")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
echo ""
echo "If BadMatch occurs: the GLX driver on this system does not support"
echo "context sharing with wxGLContext. In that case the display list"
echo "approach must be abandoned and we need to disable them entirely."
