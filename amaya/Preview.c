/*
 *
 *  Preview in browser
 *
 *  File > Preview in browser (F12) shows the current document in an
 *  external web browser (Firefox by default), which runs JavaScript and
 *  renders modern CSS that Amaya does not support.
 *
 *  - A document without unsaved changes is given to the browser directly
 *    (its local file, or its http/https URL).
 *  - A document with unsaved changes is first written to a preview copy,
 *    so that the browser shows exactly what is being edited, without
 *    saving the document itself:
 *      . for a local document, the copy is a hidden file next to it
 *        (".<name>.amaya-preview.<ext>"), so that relative links, images
 *        and style sheets work as in the original;
 *      . otherwise (remote document, or a folder that cannot be written)
 *        the copy goes into a preview folder and gets a <base href> that
 *        points back to the original location.
 *  - A local XHTML document that contains SVG or MathML is always given
 *    as a copy named .xhtml: written with namespace prefixes (<svg:svg>),
 *    it is only understood by the browser's XML parser, which is used for
 *    local files only when their name ends in .xhtml.
 *    Preview copies are removed when Amaya exits.
 *
 *  Settings (in ~/.amaya/thot.rc, section [amaya]):
 *    PREVIEW_BROWSER   command used to open the page (default: firefox);
 *                      it may contain arguments, and "%u" where the URL
 *                      or file name goes (otherwise it is appended).
 *    PREVIEW_DIR       folder for the preview copies of remote documents
 *                      (default: ~/snap/<browser>/common/amaya-preview when
 *                      the browser is a snap, which cannot read hidden
 *                      folders such as ~/.amaya; otherwise
 *                      ~/.amaya/preview).
 *
 */

#define THOT_EXPORT extern
#include "amaya.h"
#include "AHTURLTools_f.h"
#include "HTMLsave_f.h"

#ifndef _WINDOWS
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#endif /* _WINDOWS */

#define MAX_PREVIEW_FILES 64
static char *PreviewFiles[MAX_PREVIEW_FILES];
static int   NbPreviewFiles = 0;

/*----------------------------------------------------------------------
  RemovePreviewFiles removes the preview copies made in this session.
  ----------------------------------------------------------------------*/
static void RemovePreviewFiles (void)
{
  int i;

  for (i = 0; i < NbPreviewFiles; i++)
    {
      if (PreviewFiles[i])
        {
          unlink (PreviewFiles[i]);
          free (PreviewFiles[i]);
          PreviewFiles[i] = NULL;
        }
    }
  NbPreviewFiles = 0;
}

/*----------------------------------------------------------------------
  RememberPreviewFile records a preview copy, to be removed at exit.
  ----------------------------------------------------------------------*/
static void RememberPreviewFile (const char *name)
{
  static ThotBool registered = FALSE;
  int             i;

  for (i = 0; i < NbPreviewFiles; i++)
    if (!strcmp (PreviewFiles[i], name))
      return;
  if (!registered)
    {
      atexit (RemovePreviewFiles);
      registered = TRUE;
    }
  if (NbPreviewFiles < MAX_PREVIEW_FILES)
    PreviewFiles[NbPreviewFiles++] = strdup (name);
}

/*----------------------------------------------------------------------
  BrowserCommand returns the configured browser command line.
  ----------------------------------------------------------------------*/
static const char *BrowserCommand (void)
{
  char *s;

  TtaSetEnvString ("PREVIEW_BROWSER", "firefox", FALSE);
  s = TtaGetEnvString ("PREVIEW_BROWSER");
  if (s == NULL || *s == EOS)
    return "firefox";
  return s;
}

/*----------------------------------------------------------------------
  BrowserProgram copies into buf the program name (first word) of the
  browser command, without its directory.
  ----------------------------------------------------------------------*/
static void BrowserProgram (char *buf, int size)
{
  const char *cmd = BrowserCommand ();
  const char *start, *end, *slash;
  int         len;

  while (*cmd == ' ' || *cmd == '\t')
    cmd++;
  start = cmd;
  end = start;
  while (*end != EOS && *end != ' ' && *end != '\t')
    end++;
  for (slash = start; slash < end; slash++)
    if (*slash == '/')
      start = slash + 1;
  len = end - start;
  if (len >= size)
    len = size - 1;
  strncpy (buf, start, len);
  buf[len] = EOS;
}

/*----------------------------------------------------------------------
  MakeDirs creates a directory and its missing parents.
  ----------------------------------------------------------------------*/
static ThotBool MakeDirs (const char *path)
{
  char  tmp[MAX_LENGTH];
  char *p;

  if (strlen (path) >= MAX_LENGTH)
    return FALSE;
  strcpy (tmp, path);
  for (p = tmp + 1; *p != EOS; p++)
    if (*p == '/')
      {
        *p = EOS;
        mkdir (tmp, 0700);
        *p = '/';
      }
  mkdir (tmp, 0700);
  return (access (tmp, W_OK) == 0);
}

/*----------------------------------------------------------------------
  PreviewDirectory returns the folder used for the preview copies of
  documents that cannot be previewed next to their original.
  ----------------------------------------------------------------------*/
static ThotBool PreviewDirectory (char *dir, int size)
{
  char        prog[200], snapbin[300];
  const char *home;
  char       *s;
  struct stat st;

  s = TtaGetEnvString ("PREVIEW_DIR");
  if (s && *s != EOS)
    {
      if (s[0] == '~' && (home = getenv ("HOME")))
        snprintf (dir, size, "%s%s", home, s + 1);
      else
        snprintf (dir, size, "%s", s);
    }
  else
    {
      home = getenv ("HOME");
      BrowserProgram (prog, sizeof (prog));
      snprintf (snapbin, sizeof (snapbin), "/snap/bin/%s", prog);
      if (home && prog[0] != EOS && stat (snapbin, &st) == 0)
        /* a snap browser can only read non-hidden folders of the home
           directory: use the folder that the snap owns */
        snprintf (dir, size, "%s/snap/%s/common/amaya-preview", home, prog);
      else
        snprintf (dir, size, "%s%cpreview", TempFileDirectory, DIR_SEP);
    }
  return MakeDirs (dir);
}

/*----------------------------------------------------------------------
  LaunchBrowser starts the browser on target, without waiting for it.
  Returns 0 on success, or an errno value.
  ----------------------------------------------------------------------*/
static int LaunchBrowser (const char *target)
{
#ifdef _WINDOWS
  return ENOSYS;
#else /* _WINDOWS */
  char   *line, *p, *argv[64];
  int     argc = 0, fds[2], err = 0, status;
  ThotBool placed = FALSE;
  pid_t   pid;
  ssize_t n;

  line = strdup (BrowserCommand ());
  if (line == NULL)
    return ENOMEM;
  for (p = strtok (line, " \t"); p && argc < 62; p = strtok (NULL, " \t"))
    {
      if (!strcmp (p, "%u"))
        {
          argv[argc++] = (char *)target;
          placed = TRUE;
        }
      else
        argv[argc++] = p;
    }
  if (argc == 0)
    {
      free (line);
      return ENOENT;
    }
  if (!placed)
    argv[argc++] = (char *)target;
  argv[argc] = NULL;

  /* the pipe reports an exec failure; it is closed on a successful exec */
  if (pipe (fds) < 0)
    {
      err = errno;
      free (line);
      return err;
    }
  fcntl (fds[1], F_SETFD, FD_CLOEXEC);
  pid = fork ();
  if (pid < 0)
    {
      err = errno;
      close (fds[0]);
      close (fds[1]);
      free (line);
      return err;
    }
  if (pid == 0)
    {
      /* intermediate child: detach the browser so that it is neither a
         zombie nor killed with Amaya */
      close (fds[0]);
      if (fork () == 0)
        {
          int fd;

          setsid ();
          signal (SIGPIPE, SIG_DFL);
          fd = open ("/dev/null", O_RDWR);
          if (fd >= 0)
            {
              dup2 (fd, 0);
              if (fd > 2)
                close (fd);
            }
          execvp (argv[0], argv);
          err = errno;
          n = write (fds[1], &err, sizeof (err));
          (void)n;
          _exit (127);
        }
      _exit (0);
    }
  close (fds[1]);
  waitpid (pid, &status, 0);
  do
    n = read (fds[0], &err, sizeof (err));
  while (n < 0 && errno == EINTR);
  if (n != sizeof (err))
    err = 0;
  close (fds[0]);
  free (line);
  return err;
#endif /* _WINDOWS */
}

/*----------------------------------------------------------------------
  InsertBase inserts <base href="url"/> at the beginning of the head of
  the HTML file fileName, unless the document has its own base.
  ----------------------------------------------------------------------*/
static void InsertBase (const char *fileName, const char *url)
{
  FILE  *f;
  char  *buf, *head, *close_tag, *p, *out;
  long   len;
  size_t n, outlen;

  f = fopen (fileName, "rb");
  if (f == NULL)
    return;
  fseek (f, 0L, SEEK_END);
  len = ftell (f);
  fseek (f, 0L, SEEK_SET);
  if (len <= 0)
    {
      fclose (f);
      return;
    }
  buf = (char *)malloc (len + 1);
  if (buf == NULL)
    {
      fclose (f);
      return;
    }
  n = fread (buf, 1, len, f);
  fclose (f);
  buf[n] = EOS;

  head = NULL;
  for (p = buf; *p != EOS; p++)
    if (*p == '<' && !strncasecmp (p + 1, "head", 4) &&
        (p[5] == '>' || p[5] == ' ' || p[5] == '\t' ||
         p[5] == '\n' || p[5] == '\r'))
      {
        head = p;
        break;
      }
  if (head == NULL || (close_tag = strchr (head, '>')) == NULL)
    {
      free (buf);
      return;
    }
  close_tag++;
  /* keep the document's own base element */
  for (p = close_tag; *p != EOS; p++)
    {
      if (*p == '<' && !strncasecmp (p + 1, "/head", 5))
        break;
      if (*p == '<' && !strncasecmp (p + 1, "base", 4) &&
          (p[5] == ' ' || p[5] == '\t' || p[5] == '\n' || p[5] == '\r'))
        {
          free (buf);
          return;
        }
    }

  outlen = n + strlen (url) * 6 + 32;
  out = (char *)malloc (outlen);
  if (out)
    {
      size_t      pos = close_tag - buf, k = 0;
      const char *u;

      memcpy (out, buf, pos);
      k = pos;
      k += sprintf (out + k, "\n<base href=\"");
      for (u = url; *u != EOS; u++)
        {
          if (*u == '"')
            k += sprintf (out + k, "&quot;");
          else if (*u == '&')
            k += sprintf (out + k, "&amp;");
          else if (*u == '<')
            k += sprintf (out + k, "&lt;");
          else
            out[k++] = *u;
        }
      k += sprintf (out + k, "\" />");
      memcpy (out + k, close_tag, n - pos);
      k += n - pos;
      f = fopen (fileName, "wb");
      if (f)
        {
          fwrite (out, 1, k, f);
          fclose (f);
        }
      free (out);
    }
  free (buf);
}

/*----------------------------------------------------------------------
  ExportForPreview writes the current state of the document into
  fileName.  When source is not 0, the text of the source view is
  written.
  ----------------------------------------------------------------------*/
static ThotBool ExportForPreview (Document doc, Document source,
                                  const char *fileName)
{
  ThotBool ok = FALSE;

  if (source)
    return TtaExportDocument (source, fileName, "TextFileT");

  switch (DocumentTypes[doc])
    {
    case docHTML:
      SetNamespacesAndDTD (doc, FALSE);
      if (DocumentMeta[doc] && DocumentMeta[doc]->xmlformat)
        {
          if (TtaGetDocumentProfile (doc) == L_Xhtml11 ||
              TtaGetDocumentProfile (doc) == L_Basic)
            ok = TtaExportDocument (doc, fileName, "HTMLT11");
          else
            ok = TtaExportDocument (doc, fileName, "HTMLTX");
        }
      else
        ok = TtaExportDocument (doc, fileName, "HTMLT");
      break;
    case docSVG:
      SetNamespacesAndDTD (doc, FALSE);
      ok = TtaExportDocument (doc, fileName, "SVGT");
      break;
    case docMath:
      SetNamespacesAndDTD (doc, FALSE);
      ok = TtaExportDocument (doc, fileName, "MathMLT");
      break;
    case docXml:
      SetNamespacesAndDTD (doc, FALSE);
      ok = TtaExportDocument (doc, fileName, NULL);
      break;
    case docText:
    case docCSS:
      ok = TtaExportDocument (doc, fileName, "TextFileT");
      break;
    default:
      ok = FALSE;
      break;
    }
  return ok;
}

/*----------------------------------------------------------------------
  DefaultSuffix returns a file suffix matching the document type.
  ----------------------------------------------------------------------*/
static const char *DefaultSuffix (Document doc)
{
  switch (DocumentTypes[doc])
    {
    case docSVG:  return ".svg";
    case docMath: return ".mml";
    case docXml:  return ".xml";
    case docCSS:  return ".css";
    case docText: return ".txt";
    case docHTML:
      /* as most web servers do, let the browser parse XHTML as HTML */
      return ".html";
    default:      return ".html";
    }
}

/*----------------------------------------------------------------------
  KnownSuffix returns TRUE if browsers know how to show files with
  that suffix.
  ----------------------------------------------------------------------*/
static ThotBool KnownSuffix (const char *suffix)
{
  static const char *known[] = {".html", ".htm", ".xhtml", ".xht", ".svg",
                                ".mml", ".xml", ".css", ".txt", NULL};
  int i;

  for (i = 0; known[i]; i++)
    if (!strcasecmp (suffix, known[i]))
      return TRUE;
  return FALSE;
}

/*----------------------------------------------------------------------
  PreviewInBrowser
  Show the current document in an external web browser.
  ----------------------------------------------------------------------*/
void PreviewInBrowser (Document doc, View view)
{
  Document    source = 0, xmlDoc;
  char        path[MAX_LENGTH], dir[MAX_LENGTH], base[MAX_LENGTH / 2];
  char        previewName[MAX_LENGTH], msg[MAX_LENGTH + 100];
  char        prog[200];
  const char *url, *name, *suffix, *target;
  char       *p;
  ThotBool    modified, local, nextToOriginal = FALSE, needXml;
  int         stemlen;
  struct stat st;
  int         err;

  if (doc == 0 || DocumentURLs[doc] == NULL)
    return;
  xmlDoc = doc;
  if (DocumentTypes[doc] == docSource)
    {
      /* called from the source view */
      xmlDoc = GetDocFromSource (doc);
      if (xmlDoc == 0)
        return;
      if (TtaIsDocumentModified (doc))
        source = doc;
    }
  else if (DocumentSource[doc] && TtaIsDocumentModified (DocumentSource[doc]))
    /* the source view holds the latest changes */
    source = DocumentSource[doc];
  url = DocumentURLs[xmlDoc];
  modified = TtaIsDocumentModified (xmlDoc) || source != 0;
  local = !IsW3Path (url);

  path[0] = EOS;
  if (local)
    {
      if (!strncmp (url, "file://", 7))
        url += 7;
      if (strlen (url) >= MAX_LENGTH)
        return;
      strcpy (path, url);
    }

  /* XHTML with SVG or MathML written with namespace prefixes (<svg:svg>)
     is only understood by the XML parser, which browsers use for local
     files only when their name ends in .xhtml */
  needXml = (local && DocumentTypes[xmlDoc] == docHTML &&
             DocumentMeta[xmlDoc] && DocumentMeta[xmlDoc]->xmlformat &&
             (TtaGetSSchema ("SVG", xmlDoc) ||
              TtaGetSSchema ("MathML", xmlDoc)));
  if (needXml)
    {
      suffix = strrchr (path, '.');
      if (suffix && (!strcasecmp (suffix, ".xhtml") ||
                     !strcasecmp (suffix, ".xht") ||
                     !strcasecmp (suffix, ".xml")))
        needXml = FALSE;
    }

  if (!modified && !needXml && (!local || stat (path, &st) == 0))
    /* give the browser the original document */
    target = local ? path : url;
  else
    {
      /* write a preview copy of the current state of the document */
      if (local)
        {
          strcpy (dir, path);
          p = strrchr (dir, DIR_SEP);
          if (p)
            {
              *p = EOS;
              if (dir[0] == EOS)
                strcpy (dir, "/");
              nextToOriginal = (access (dir, W_OK) == 0);
              name = strrchr (path, DIR_SEP) + 1;
            }
          else
            name = path;
        }
      else
        {
          /* last component of the URL path, without query or fragment */
          strncpy (base, url, sizeof (base) - 1);
          base[sizeof (base) - 1] = EOS;
          p = strpbrk (base, "?#");
          if (p)
            *p = EOS;
          p = strrchr (base, '/');
          if (p && p[1] != EOS && p > strstr (base, "://") + 2)
            name = p + 1;
          else
            name = "index";
        }
      if (!nextToOriginal && !PreviewDirectory (dir, sizeof (dir)))
        {
          TtaSetStatus (doc, view,
                        "Preview: cannot create the preview folder %s", dir);
          return;
        }
      /* keep a suffix that browsers understand, otherwise use one that
         matches the document type */
      stemlen = strlen (name);
      suffix = strrchr (name, '.');
      if (suffix && KnownSuffix (suffix))
        stemlen = suffix - name;
      else
        suffix = DefaultSuffix (xmlDoc);
      if (needXml)
        suffix = ".xhtml";
      if (stemlen > 100)
        stemlen = 100;
      if (nextToOriginal)
        snprintf (previewName, sizeof (previewName),
                  "%s%c.%.*s.amaya-preview%s",
                  dir, DIR_SEP, stemlen, name, suffix);
      else
        snprintf (previewName, sizeof (previewName), "%s%cdoc%d-%.*s%s",
                  dir, DIR_SEP, (int)xmlDoc, stemlen, name, suffix);
      if (!modified && stat (path, &st) == 0)
        {
          /* same content as the file, under a name that the browser
             reads as XHTML */
          if (!TtaFileCopy (path, previewName))
            {
              TtaSetStatus (doc, view, "Preview: cannot write %s", previewName);
              return;
            }
        }
      else if (!ExportForPreview (xmlDoc, source, previewName))
        {
          TtaSetStatus (doc, view,
                        "Preview: this kind of document cannot be previewed%s", "");
          return;
        }
      RememberPreviewFile (previewName);
      if (!nextToOriginal && DocumentTypes[xmlDoc] == docHTML)
        {
          /* make relative links point to the original location */
          if (local)
            {
              snprintf (base, sizeof (base), "file://%s", path);
              InsertBase (previewName, base);
            }
          else
            InsertBase (previewName, url);
        }
      target = previewName;
    }

  BrowserProgram (prog, sizeof (prog));
  err = LaunchBrowser (target);
  if (err)
    {
      snprintf (msg, sizeof (msg), "Preview: cannot run \"%s\" (%s)",
                BrowserCommand (), strerror (err));
      TtaSetStatus (doc, view, "%s", msg);
    }
  else
    {
      snprintf (msg, sizeof (msg), "Preview opened in %s%s", prog,
                modified ? " (unsaved changes included)" : "");
      TtaSetStatus (doc, view, "%s", msg);
    }
}
