#!/usr/bin/env bash
# trial1-option-a.sh
# Run from an already-cloned ~/amaya-modern working copy.
# Creates a clean branch "trial/option-a" off origin/main and applies
# exactly two changes:
#   1. Fix the glyph vertical-position overflow (openglfont.c)
#   2. Real GL context sharing between canvases (AmayaCanvas.cpp / AmayaFrame.cpp)

set -e
cd ~/amaya-modern

git fetch origin
git checkout main
git pull origin main
git checkout -b trial/option-a

echo "=== [1/2] Fixing glyph vertical-position overflow in openglfont.c ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/openglfont.c') as f:
    code = f.read()

old = "      BitmapGlyph->pos.x = bitmap->left;\n      BitmapGlyph->pos.y = source->rows - bitmap->top;   \n      BitmapGlyph->dimension.x = w;\n      BitmapGlyph->dimension.y = h;  \t  \n      FT_Done_Glyph (Glyph);"

new = """      BitmapGlyph->pos.x = bitmap->left;
      /* bitmap->top (FT_Int, signed) is subtracted from source->rows
       * (unsigned int) in the original code. C's usual arithmetic
       * conversions silently convert a negative bitmap->top to a huge
       * unsigned value first, so the subtraction wraps around instead
       * of failing. That corrupted value then propagates as a huge
       * positive pos.y, gets negated in UnicodeFontRender, and rounds
       * to a huge negative float there -- corrupting that glyph's
       * height computation and causing the whole text run containing
       * it to silently not render. Do the subtraction in a signed,
       * sufficiently wide type to avoid the wraparound entirely. */
      {
        long top_signed  = (long) bitmap->top;
        long rows_signed = (long) source->rows;
        long pos_y = rows_signed - top_signed;
        if (pos_y < 0)
          pos_y = 0;
        BitmapGlyph->pos.y = (FT_Pos) pos_y;
      }
      BitmapGlyph->dimension.x = w;
      BitmapGlyph->dimension.y = h;  	  
      FT_Done_Glyph (Glyph);"""

if old in code:
    code = code.replace(old, new)
    with open('thotlib/dialogue/openglfont.c', 'w') as f:
        f.write(code)
    print("  OK")
else:
    print("  FAIL -- pattern not found, aborting")
    exit(1)
PYEOF

echo "=== [2/2] Real GL context sharing (AmayaCanvas.cpp) ==="
python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaCanvas.cpp') as f:
    code = f.read()

old = "  m_glContext = new wxGLContext(this);"
new = """  /* Real GL context sharing: each canvas keeps its OWN context object
   * (required on modern Mesa -- one context object cannot be handed to
   * two different windows without triggering BadMatch), but when a
   * sibling context is given, the new context shares its textures and
   * display lists with it via wx's standard share-list constructor. */
  if (p_shared_context)
    m_glContext = new wxGLContext(this, p_shared_context);
  else
    m_glContext = new wxGLContext(this);"""

if old in code and 'p_shared_context)' not in code.split(old)[0][-200:]:
    code = code.replace(old, new, 1)
    with open('thotlib/dialogue/AmayaCanvas.cpp', 'w') as f:
        f.write(code)
    print("  OK: AmayaCanvas.cpp")
else:
    print("  FAIL -- pattern not found or already modified, check manually")
    exit(1)
PYEOF

python3 - << 'PYEOF'
with open('thotlib/dialogue/AmayaFrame.cpp') as f:
    code = f.read()

old = "  p_canvas = new AmayaCanvas( this, this );\n  SetSharedContext( m_FrameId );"

new = """  if ( GetSharedContext() == -1 )
    {
      /* first canvas: create its context and register it as the one
       * all later canvases (source view, split views) will share with */
      p_canvas = new AmayaCanvas( this, this );
      SetSharedContext( m_FrameId );
    }
  else
    {
      wxASSERT( FrameTable[GetSharedContext()].WdFrame != NULL );
      wxGLContext * p_SharedContext =
          FrameTable[GetSharedContext()].WdFrame->GetCanvas()->GetGLContext();
      wxASSERT( p_SharedContext );
      p_canvas = new AmayaCanvas( this, this, p_SharedContext );
    }"""

if old in code:
    code = code.replace(old, new, 1)
    with open('thotlib/dialogue/AmayaFrame.cpp', 'w') as f:
        f.write(code)
    print("  OK: AmayaFrame.cpp")
else:
    print("  FAIL -- pattern not found, check manually")
    exit(1)
PYEOF

echo "=== Rebuild ==="
cd build
make -j$(nproc) 2>&1 | grep -E "error:|Built target|Linking" | \
  grep -v "command-line option"
cd ..

echo ""
echo "=== Commit ==="
git add -A
git commit -m "trial/option-a: fix glyph pos.y overflow + real GL context sharing

- openglfont.c: fix signed/unsigned overflow in glyph vertical position
  (was causing whole text runs, e.g. HTML attribute values, to silently
  not render -- confirmed root cause via FreeType header type analysis)
- AmayaCanvas.cpp / AmayaFrame.cpp: proper wxGLContext share-list sharing
  between canvases, instead of fully independent (no sharing) contexts.
  Each canvas still owns its own context object (avoids BadMatch), but
  contexts now share GL resources as originally intended."

git push -u origin trial/option-a

echo ""
echo "Done. Run: THOTDIR=\$(pwd) ./build/amaya/amaya"
