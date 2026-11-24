/*
 *  amaya-modern, 2026. Distributed under the same license as Amaya
 *  (see the files LICENSE and COPYRIGHT).
 *
 */

/*
 * svgtoeps.c: convert an SVG file into an Encapsulated PostScript file
 * with librsvg and cairo. It is used when a document is printed: each
 * SVG drawing is written as an EPS picture that the print program
 * includes in its PostScript output, as vector graphics.
 */
#include <librsvg/rsvg.h>
#include <cairo.h>
#include <cairo-ps.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "thot_gui.h"
#include "thot_sys.h"
#include "svgtoeps_f.h"

/*----------------------------------------------------------------------
  SetBoundingBox
  cairo gives an EPS file the bounding box of what is drawn. Set it to the
  whole drawing area (w x h points), so that the drawing keeps its own
  margins and proportions when the print program scales it to its box.
  ----------------------------------------------------------------------*/
static ThotBool SetBoundingBox (const char *epsName, double w, double h)
{
  FILE        *file;
  char        *buffer, *line, *next, *end;
  long         size;
  ThotBool     ok;

  file = fopen (epsName, "rb");
  if (file == NULL)
    return FALSE;
  fseek (file, 0, SEEK_END);
  size = ftell (file);
  fseek (file, 0, SEEK_SET);
  buffer = (char *) malloc (size + 1);
  ok = (buffer && size > 0 && fread (buffer, 1, size, file) == (size_t) size);
  fclose (file);
  if (!ok)
    {
      free (buffer);
      return FALSE;
    }
  buffer[size] = EOS;
  end = strstr (buffer, "%%EndComments");
  file = fopen (epsName, "wb");
  if (file == NULL)
    {
      free (buffer);
      return FALSE;
    }
  /* copy the file, changing the bounding boxes in the header comments */
  line = buffer;
  while (*line != EOS)
    {
      next = strchr (line, '\n');
      next = next ? next + 1 : line + strlen (line);
      if (end && line < end && !strncmp (line, "%%BoundingBox:", 14))
        fprintf (file, "%%%%BoundingBox: 0 0 %d %d\n",
                 (int) ceil (w), (int) ceil (h));
      else if (end && line < end && !strncmp (line, "%%HiResBoundingBox:", 19))
        fprintf (file, "%%%%HiResBoundingBox: 0 0 %f %f\n", w, h);
      else
        fwrite (line, 1, next - line, file);
      line = next;
    }
  ok = (fclose (file) == 0);
  free (buffer);
  return ok;
}

/*----------------------------------------------------------------------
  ReadSVGWithNamespaces reads the SVG file svgName and returns its content
  (to be freed with g_free), with the namespace declarations that the
  root element needs. A drawing exported from a compound document
  (<svg:svg> in XHTML) uses prefixes declared on the html element, not
  in the drawing itself.
  ----------------------------------------------------------------------*/
static char *ReadSVGWithNamespaces (const char *svgName, gsize *length)
{
  gchar      *content, *start, *end, *name, *result;
  GString    *decl;
  gsize       len, nameLen;

  if (!g_file_get_contents (svgName, &content, &len, NULL))
    return NULL;
  /* the start tag of the root element */
  start = content;
  while ((start = strchr (start, '<')) != NULL &&
         (start[1] == '?' || start[1] == '!'))
    start++;
  if (start == NULL || (end = strchr (start, '>')) == NULL)
    {
      *length = len;
      return content;
    }
  name = start + 1;
  nameLen = strcspn (name, " \t\r\n/>");
  decl = g_string_new (NULL);
  if (nameLen > 4 && name[nameLen - 4] == ':' &&
      !strncmp (&name[nameLen - 3], "svg", 3))
    {
      /* <prefix:svg ...>: declare the prefix */
      gchar *attr = g_strdup_printf ("xmlns:%.*s=", (int) (nameLen - 4), name);
      if (!g_strstr_len (start, end - start, attr))
        g_string_append_printf (decl, " %s\"http://www.w3.org/2000/svg\"", attr);
      g_free (attr);
    }
  else if (!g_strstr_len (start, end - start, "xmlns="))
    g_string_append (decl, " xmlns=\"http://www.w3.org/2000/svg\"");
  if (strstr (content, "xlink:") &&
      !g_strstr_len (start, end - start, "xmlns:xlink="))
    g_string_append (decl, " xmlns:xlink=\"http://www.w3.org/1999/xlink\"");
  if (decl->len == 0)
    {
      g_string_free (decl, TRUE);
      *length = len;
      return content;
    }
  /* insert the declarations after the element name */
  result = g_strdup_printf ("%.*s%s%s", (int) (name + nameLen - content),
                            content, decl->str, name + nameLen);
  *length = strlen (result);
  g_string_free (decl, TRUE);
  g_free (content);
  return result;
}

/*----------------------------------------------------------------------
  SVGFileToEPS
  Render the SVG file svgName into the EPS file epsName.
  width and height (in CSS pixels) give the size of the drawing when the
  SVG file does not specify it in absolute units.
  Return TRUE when the EPS file has been produced.
  ----------------------------------------------------------------------*/
ThotBool SVGFileToEPS (const char *svgName, const char *epsName,
                       double width, double height)
{
  RsvgHandle      *handle;
  RsvgRectangle    viewport;
  GError          *error = NULL;
  cairo_surface_t *surface;
  cairo_t         *cr;
  gdouble          w, h;
  gchar           *content;
  gsize            length;
  ThotBool         ok;

  content = ReadSVGWithNamespaces (svgName, &length);
  if (content == NULL)
    return FALSE;
  handle = rsvg_handle_new_from_data ((const guint8 *) content, length, &error);
  g_free (content);
  if (handle == NULL)
    {
      if (error)
        {
          fprintf (stderr, "Amaya: cannot read SVG for printing: %s\n",
                   error->message);
          g_error_free (error);
        }
      return FALSE;
    }
  rsvg_handle_set_dpi (handle, 96.);
  if (!rsvg_handle_get_intrinsic_size_in_pixels (handle, &w, &h) ||
      w <= 0. || h <= 0.)
    {
      /* relative size (percentages) or no size: use the layout size */
      w = width;
      h = height;
    }
  if (w <= 0. || h <= 0.)
    {
      g_object_unref (handle);
      return FALSE;
    }

  /* one CSS pixel gives one PostScript point; the print program scales
     the picture to the size of its box anyway */
  surface = cairo_ps_surface_create (epsName, w, h);
  cairo_ps_surface_set_eps (surface, TRUE);
  cr = cairo_create (surface);
  viewport.x = 0.;
  viewport.y = 0.;
  viewport.width = w;
  viewport.height = h;
  ok = rsvg_handle_render_document (handle, cr, &viewport, &error);
  if (!ok && error)
    {
      fprintf (stderr, "Amaya: cannot render SVG for printing: %s\n",
               error->message);
      g_error_free (error);
    }
  cairo_destroy (cr);
  cairo_surface_finish (surface);
  if (cairo_surface_status (surface) != CAIRO_STATUS_SUCCESS)
    ok = FALSE;
  cairo_surface_destroy (surface);
  g_object_unref (handle);
  if (ok)
    ok = SetBoundingBox (epsName, w, h);
  return ok;
}
