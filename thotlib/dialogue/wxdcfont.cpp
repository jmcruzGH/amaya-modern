/*
 * wxdcfont.cpp
 *
 * Replaces GL_LoadFont's font-object construction (thotlib/dialogue/
 * font.c) with real wxFont objects, finally making true what
 * thot_gui_wx.h's `typedef wxFont *ThotFont;` already claims.
 *
 * GetFontFilename() (fontconfig.c) is unchanged and still does the
 * "which script/family/style/size -> which .ttf file" lookup; only the
 * final "turn that file into a usable font handle" step is replaced
 * here. FreeType is used ONLY to read the file's own face name and
 * bold/italic flags out of its metadata -- not for any rendering --
 * since it is already a dependency of this project and gives a robust,
 * general way to ask "what is this font file actually called" without
 * hardcoding a filename-to-facename mapping for Amaya's font set.
 */

#include "wx/wx.h"
#include <ft2build.h>
#include FT_FREETYPE_H

void *WxDC_LoadFont (const char *filename, char alphabet, int size)
{
  (void) alphabet;   /* ADAPT: the original gl_font_init also took the
                       * script/alphabet character, presumably to pick
                       * the right cmap/encoding inside the font file
                       * for non-Latin scripts. wxFont's own text
                       * layout (DrawText) should already handle
                       * Unicode script selection correctly on its own
                       * via the underlying platform font shaping, so
                       * this is very likely not needed here -- but
                       * flagging it in case Arabic/CJK/etc. rendering
                       * needs revisiting once Latin text is confirmed
                       * working. */

  static FT_Library ftLib = NULL;
  if (!ftLib)
    {
      if (FT_Init_FreeType (&ftLib) != 0)
        return NULL;
    }

  FT_Face face;
  if (FT_New_Face (ftLib, filename, 0, &face) != 0)
    return NULL;

  wxString faceName = wxString::FromUTF8 (face->family_name ? face->family_name : "");
  bool bold   = (face->style_flags & FT_STYLE_FLAG_BOLD)   != 0;
  bool italic = (face->style_flags & FT_STYLE_FLAG_ITALIC) != 0;
  FT_Done_Face (face);

  if (faceName.IsEmpty ())
    return NULL;

  /* Register the font file with wx for this process (does not install
   * it system-wide). Safe to call repeatedly for the same file -- wx
   * de-duplicates. */
  wxFont::AddPrivateFont (wxString::FromUTF8 (filename));

  /* ADAPT: `size` here -- verify this is already point size, not
   * pixels or Amaya's own internal unit, by comparing rendered text
   * size against the previous GL renderer on first test. Easy to spot
   * visually (text too big/small) and a one-line fix here if wrong. */
  wxFontInfo info (size);
  info.FaceName (faceName);
  if (bold)
    info.Bold ();
  if (italic)
    info.Italic ();

  wxFont *newFont = new wxFont (info);
  if (!newFont->IsOk ())
    {
      delete newFont;
      return NULL;
    }
  return (void *) newFont;
}


/*
 * WxDC_CharWidth
 *
 * Replaces gl_font_char_width (openglfont.c) for text-layout width
 * measurement -- a separate code path from actually drawing text
 * (DrawString/DrawChar in wxdcdisplay.cpp, already replaced). This one
 * is used constantly during layout (word wrap, box sizing) to ask "how
 * wide is this character in this font", independent of any paint
 * event, so it cannot rely on the per-frame DC that OnPaint sets up --
 * needs its own small, reusable, standalone measurement DC, a standard
 * wx pattern for measuring text without an active window.
 */
int WxDC_CharWidth (void *font, wchar_t c)
{
  wxFont *wxf = (wxFont *) font;
  if (!wxf || !wxf->IsOk ())
    return 0;

  static wxBitmap   s_measureBitmap (1, 1);
  static wxMemoryDC s_measureDC (s_measureBitmap);

  s_measureDC.SetFont (*wxf);
  wxUniChar uc ((wxUint32) c);
  return s_measureDC.GetTextExtent (wxString (uc)).GetWidth ();
}
