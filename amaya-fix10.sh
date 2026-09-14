#!/usr/bin/env bash
# amaya-fix10.sh -- fix GL context sharing AND font reinitialization
set -e
cd ~/amaya-modern

echo "[fix10a] AmayaCanvas.cpp: enable proper GL context sharing"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    lines = f.readlines()

# Find line 102 and replace it
for i, line in enumerate(lines):
    if 'new wxGLContext(this);' in line and i > 95 and i < 115:
        print(f"  Found at line {i+1}: {line.rstrip()}")
        # Replace with sharing version
        indent = len(line) - len(line.lstrip())
        sp = ' ' * indent
        lines[i] = (
            f'{sp}/* wx 3.x: share resources with existing context if available */\n'
            f'{sp}if (p_shared_context)\n'
            f'{sp}  m_glContext = new wxGLContext(this, p_shared_context);\n'
            f'{sp}else\n'
            f'{sp}  m_glContext = new wxGLContext(this);\n'
        )
        print(f"  Replaced with sharing version")
        break

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.writelines(lines)
PYEOF

echo "[fix10b] AmayaCanvas.cpp: reinitialize GL fonts in each new context"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

# After SetGlPipelineState(), reinitialize fonts for this context
old = '  SetGlPipelineState ();\n'
new = ('  SetGlPipelineState ();\n'
       '  /* Reinitialize GL fonts for this context (each independent context\n'
       '   * needs its own font textures even with context sharing) */\n'
       '  extern void ReinitGLFonts ();\n'
       '  ReinitGLFonts ();\n')

# Only add if not already there
if 'ReinitGLFonts' not in code:
    code = code.replace(old, new, 1)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  Added ReinitGLFonts() call after SetGlPipelineState()")
else:
    print("  Already present")
PYEOF

echo "[fix10c] font.c: add ReinitGLFonts() function"
python3 - << 'PYEOF'
with open('thotlib/dialogue/font.c') as f:
    code = f.read()

if 'ReinitGLFonts' not in code:
    # Add before the closing of the file or after FreeAFont
    addition = '''
/*----------------------------------------------------------------------
  ReinitGLFonts: Reinitialize GL font textures for a new GL context.
  Called when Init() runs on a new canvas -- each GL context needs
  its own texture objects even when context sharing is enabled.
  ----------------------------------------------------------------------*/
void ReinitGLFonts ()
{
#ifdef _GL
  int i;
  /* Force reload of all cached fonts as GL textures */
  for (i = 0; i < MaxNumberOfFonts; i++)
    {
      if (TtFonts[i] && TtFonts[i] != (ThotFont) DefaultGLFont)
        {
          gl_font_delete (TtFonts[i]);
          TtFonts[i] = NULL;
        }
    }
  /* Reload the default GL font */
  if (DefaultGLFont)
    {
      gl_font_delete (DefaultGLFont);
      DefaultGLFont = NULL;
    }
  /* Reinitialize default font */
  int j = 1;
  while (DefaultGLFont == NULL && j < 3)
    {
      DefaultGLFont = (ThotFont)GL_LoadFont ('L', j, 1, LogicalPointsSizes[3]);
      if (!DefaultGLFont)
        DefaultGLFont = (ThotFont)GL_LoadFont ('L', j, 1, LogicalPointsSizes[4]);
      if (!DefaultGLFont)
        DefaultGLFont = (ThotFont)GL_LoadFont ('L', j, 1, LogicalPointsSizes[2]);
      if (!DefaultGLFont)
        DefaultGLFont = (ThotFont)GL_LoadFont ('L', j, 1, LogicalPointsSizes[1]);
      j++;
    }
#endif /* _GL */
}
'''
    # Add near end of file, before last function or at end
    code = code + addition
    with open('thotlib/dialogue/font.c', 'w') as f:
        f.write(code)
    print("  Added ReinitGLFonts() to font.c")
else:
    print("  Already present")
PYEOF

echo "[fix10d] AmayaFrame.cpp: restore context sharing in CreateDrawingArea"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaFrame.cpp') as f:
    code = f.read()

if 'GetSharedContext() == -1' not in code:
    # Find and replace the independent context block
    import re
    old = re.search(
        r'#ifdef _GL\s*/\* wx 3\.x.*?#endif /\* _GL \*/',
        code, re.DOTALL
    )
    if old:
        new_block = '''#ifdef _GL
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
#endif /* _GL */'''
        code = code[:old.start()] + new_block + code[old.end():]
        with open('thotlib/dialogue/AmayaFrame.cpp', 'w') as f:
            f.write(code)
        print("  Restored context sharing in AmayaFrame.cpp")
    else:
        print("  Pattern not found in AmayaFrame.cpp")
else:
    print("  Already correct")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
