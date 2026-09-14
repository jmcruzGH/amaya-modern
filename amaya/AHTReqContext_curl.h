/*
 * AHTReqContext_curl.h
 *
 * Phase 3: libcurl replacement for the libwww AHTReqContext struct.
 *
 * The public API (query_f.h, amaya.h) is UNCHANGED.
 * Only the internal struct definition and the six implementation files
 * (query.c, answer.c, AHTBridge.c, AHTInit.c, AHTMemConv.c, AHTFWrite.c)
 * are replaced.
 *
 * Callers outside the HTTP layer see:
 *   - AHTReqContext*  (opaque, allocated/freed by AHTReqContext_new/delete)
 *   - GetObjectWWW()  (unchanged signature)
 *   - PutObjectWWW()  (unchanged signature)
 *   - StopRequest()   (unchanged)
 *   - QueryInit()     (unchanged)
 *   - QueryClose()    (unchanged)
 */

#ifndef AHT_REQCONTEXT_CURL_H
#define AHT_REQCONTEXT_CURL_H

#include <curl/curl.h>
#include "amaya.h"      /* AHTHeaders, TIcbf, TTcbf, AHTHeaderName */
#include "thot_sys.h"   /* ThotBool, Document */

/* Request status -- mirrors the old libwww AHTReqStatus */
typedef enum {
  HT_NEW       = 0,   /* just allocated */
  HT_WAITING   = 1,   /* enqueued, not yet started */
  HT_BUSY      = 2,   /* curl easy handle is in the multi handle */
  HT_IDLE      = 3,   /* completed, result delivered */
  HT_ABORT     = 4    /* cancelled by StopRequest */
} AHTReqStatus;

/*
 * AHTReqContext -- one per in-flight or pending request.
 * The fields that the rest of amaya reads are preserved verbatim.
 * libwww-specific fields (HTRequest*, HTParentAnchor*, etc.) are replaced
 * by their libcurl equivalents.
 */
typedef struct _AHTReqContext {

  /* ── public fields read by the rest of amaya/ (unchanged names) ── */
  int            docid;           /* Document this request belongs to    */
  AHTReqStatus   reqStatus;       /* current lifecycle state             */
  int            mode;            /* AMAYA_SYNC / AMAYA_ASYNC / ...      */
  char          *urlName;         /* URL being fetched (heap-allocated)  */
  char          *outputfile;      /* path to write body into             */
  FILE          *output;          /* open handle to outputfile           */
  AHTHeaders     http_headers;    /* response headers, filled on completion */
  char          *error_stream;    /* error message (heap, may be NULL)   */
  int            error_stream_size;
  ThotBool       error_html;      /* TRUE → display error as HTML        */

  /* callbacks -- unchanged signatures */
  TIcbf         *incremental_cbf;
  void          *context_icbf;
  TTcbf         *terminate_cbf;
  void          *context_tcbf;

  /* PUT/POST support */
  char          *default_put_name;
  ThotBool       put_redirection;
  char          *put_content_type; /* Content-Type for PUT body          */
  FILE          *put_input;        /* body source file for PUT           */
  unsigned long  block_size;       /* body size for PUT progress         */
  int            put_counter;      /* bytes uploaded so far              */

  /* ── libcurl-specific fields (replace HTRequest/HTAnchor/etc.) ── */
  CURL          *easy;             /* easy handle for this request       */
  struct curl_slist *req_headers;  /* custom request headers             */

  /* write buffer for non-file responses (e.g. HEAD, error bodies) */
  char          *mem_buffer;
  size_t         mem_size;

  /* status line components filled by the header callback */
  long           http_status;      /* e.g. 200, 404 */
  char           status_urlName[MAX_LENGTH]; /* for status bar display   */

} AHTReqContext;

/* HTList compatibility stub -- guarded to avoid redefinition from libwww.h */
#ifndef HTLIST_STRUCT_DEFINED
#define HTLIST_STRUCT_DEFINED
typedef struct _HTList {
  void            *object;
  struct _HTList  *next;
} HTList;
#endif

#ifndef HTLIST_FUNCS_DECLARED
#define HTLIST_FUNCS_DECLARED
HTList *HTList_new(void);
void    HTList_delete(HTList *list);
void    HTList_addObject(HTList *list, void *object);
void   *HTList_nextObject(HTList *list);
int     HTList_count(HTList *list);
#endif

/* AHTDocId_Status -- unchanged */
#ifndef AHTDOCID_STATUS_DEFINED
#define AHTDOCID_STATUS_DEFINED
typedef struct {
  int  docid;
  int  counter;
} AHTDocId_Status;
#endif

#endif /* AHT_REQCONTEXT_CURL_H */
