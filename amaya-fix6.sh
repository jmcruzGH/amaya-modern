#!/usr/bin/env bash
# amaya-fix6.sh -- fix GLX BadMatch + libpng duplicate call
set -e
cd ~/amaya-modern

echo "[fix6a] AmayaFrame.cpp: fix bare SetCurrent() calls for wx 3.x"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaFrame.cpp') as f:
    code = f.read()

# Fix 1: line 355 -- m_pCanvas->SetCurrent() -> SetCurrent(*m_pCanvas->GetGLContext())
code = code.replace(
    '      m_pCanvas->SetCurrent();\n      return TRUE;',
    '      m_pCanvas->SetCurrent(*m_pCanvas->GetGLContext());\n      return TRUE;'
)

with open('thotlib/dialogue/AmayaFrame.cpp', 'w') as f:
    f.write(code)
print("  Fixed AmayaFrame.cpp SetCurrent()")
PYEOF

echo "[fix6b] AmayaCanvas.cpp: fix bare SetCurrent() call for wx 3.x"
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

# Fix bare SetCurrent() in OnPaint
code = code.replace(
    '  SetCurrent();\n  SetGlPipelineState',
    '  SetCurrent(*m_glContext);\n  SetGlPipelineState'
)
# Also fix any other bare SetCurrent() calls
code = code.replace(
    '  SetCurrent();\n  SetGlPipeline',
    '  SetCurrent(*m_glContext);\n  SetGlPipeline'
)

with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
    f.write(code)
print("  Fixed AmayaCanvas.cpp SetCurrent()")
PYEOF

echo "[fix6c] pnghandler.c: remove duplicate png_start_read_image call"
python3 - << 'PYEOF'
with open('thotlib/image/pnghandler.c') as f:
    code = f.read()

# Remove png_start_read_image when it comes after png_read_update_info
# (libpng 1.6 treats this as a duplicate call)
code = code.replace(
    '    png_read_update_info (png_ptr, info_ptr);\n'
    '    /* get again width, height and the new bit-depth and color-type*/\n'
    '    png_get_IHDR (png_ptr, info_ptr, &lw, &lh, \n'
    '\t\t  &iBitDepth, \n'
    '\t\t  &iColorType, \n'
    '\t\t  NULL, NULL, NULL);\n'
    '    /* row_bytes is the width x number of channels => the length of a line */\n'
    '    ulRowBytes = png_get_rowbytes (png_ptr, info_ptr);\n'
    '    ulChannels = png_get_channels (png_ptr, info_ptr);\n'
    '    pixels = (png_byte *) TtaGetMemory (ulRowBytes * lh * sizeof(png_byte));\n'
    '    /* Row pointers give a pointer on each line */\n'
    '    ppbRowPointers = (png_bytepp) TtaGetMemory  (lh * sizeof(png_bytep));\n'
    '    /* Opengl Texture inversion */   \n'
    '    for (i = 0; i < lh; i++)\n'
    '      ppbRowPointers[i] = pixels + ((lh - (i+1)) * ulRowBytes * sizeof(png_byte));    \n'
    '    png_start_read_image (png_ptr); \n',

    '    png_read_update_info (png_ptr, info_ptr);\n'
    '    /* get again width, height and the new bit-depth and color-type*/\n'
    '    png_get_IHDR (png_ptr, info_ptr, &lw, &lh, \n'
    '\t\t  &iBitDepth, \n'
    '\t\t  &iColorType, \n'
    '\t\t  NULL, NULL, NULL);\n'
    '    /* row_bytes is the width x number of channels => the length of a line */\n'
    '    ulRowBytes = png_get_rowbytes (png_ptr, info_ptr);\n'
    '    ulChannels = png_get_channels (png_ptr, info_ptr);\n'
    '    pixels = (png_byte *) TtaGetMemory (ulRowBytes * lh * sizeof(png_byte));\n'
    '    /* Row pointers give a pointer on each line */\n'
    '    ppbRowPointers = (png_bytepp) TtaGetMemory  (lh * sizeof(png_bytep));\n'
    '    /* Opengl Texture inversion */   \n'
    '    for (i = 0; i < lh; i++)\n'
    '      ppbRowPointers[i] = pixels + ((lh - (i+1)) * ulRowBytes * sizeof(png_byte));\n'
    '    /* png_start_read_image removed: redundant after png_read_update_info (libpng 1.6) */\n'
)

with open('thotlib/image/pnghandler.c', 'w') as f:
    f.write(code)
print("  Fixed pnghandler.c: removed duplicate png_start_read_image")
PYEOF

echo ""
echo "Rebuild:"
echo "  cd build && make -j\$(nproc) 2>&1 | tee build.log"
echo "  cd .. && THOTDIR=\$(pwd) ./build/amaya/amaya"
