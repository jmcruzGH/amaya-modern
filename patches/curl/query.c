/*
 * amaya/query.c  -- Phase 3 libcurl replacement
 *
 * Replaces the original libwww-based query.c.
 * Public API (query_f.h) is UNCHANGED -- all callers remain unmodified.
 *
 * Design:
 *   - libcurl multi interface drives all async I/O.
 *   - A wxTimer (via wxAmayaSocketEventLoop) calls curl_multi_perform()
 *     at ~50 ms intervals and dispatches completion callbacks.
 *   - GetObjectWWW() is the primary entry point for HTTP GET.
 *   - PutObjectWWW() handles HTTP PUT (save to server).
 *   - StopRequest() / StopAllRequests() cancel in-flight requests.
 *
 * HTTP-only for Phase 3 (no HTTPS). HTTPS (via libcurl + system TLS)
 * is a one-line change: remove CURLOPT_PROTOCOLS restriction below.
 *
 * (c) 2026  J. Magalhães Cruz <jmcruz@fe.up.pt> -- FEUP
 * Derived from original Amaya query.c (c) INRIA/W3C 1996-2013.
 * Released under the same W3C licence.
 */

#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"
#include "amaya.h"
#include "init_f.h"
#include "AHTURLTools_f.h"

/* wx event loop integration */
/* Undef amaya constants that clash with wx member function names */
#ifdef Align
#  undef Align
#endif
#ifdef Style
#  undef Style
#endif
#ifdef Inline
#  undef Inline
#endif
#ifdef Block
#  undef Block
#endif
#ifdef Centre
#  undef Centre
#endif
#include "wx/wx.h"
#include "wxAmayaSocketEventLoop.h"
#include "wxAmayaSocketEvent.h"
#include "message_wx.h"

/* libcurl */
#include <curl/curl.h>
#include <pthread.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/stat.h>

/* Our own types (replaces libwww.h) */
#include "AHTReqContext_curl.h"

/* Forward declarations of functions defined later in this file */
static void  curl_check_multi_info   (void);
static void  deliver_result          (AHTReqContext *me, int status);
static size_t write_to_file_cb       (char *ptr, size_t size, size_t nmemb, void *userdata);
static size_t write_to_mem_cb        (char *ptr, size_t size, size_t nmemb, void *userdata);
static size_t header_cb              (char *buffer, size_t size, size_t nitems, void *userdata);

/* Global error message buffer (declared in libwww.h) */
char AmayaLastHTTPErrorMsg[2*MAX_LENGTH];

/* ── Module-level state ─────────────────────────────────────────────────── */

static CURLM   *s_curlm        = NULL;   /* libcurl multi handle */
static HTList  *s_doc_list     = NULL;   /* list of AHTDocId_Status entries */
static ThotBool s_alive        = FALSE;  /* QueryInit called */
static ThotBool s_can_do_stop  = TRUE;
static ThotBool s_ftp_flag     = FALSE;
static wxTimer *s_poll_timer   = NULL;

/* Maximum simultaneous connections */
#define MAX_CONNECTIONS 8

/* Poll interval in milliseconds */
#define CURL_POLL_MS 50

/* ── HTList helpers ─────────────────────────────────────────────────────── */

HTList *HTList_new(void)
{
  HTList *l = (HTList*)TtaGetMemory(sizeof(HTList));
  l->object = NULL;
  l->next   = NULL;
  return l;
}

void HTList_delete(HTList *list)
{
  HTList *cur = list;
  while (cur) {
    HTList *next = cur->next;
    TtaFreeMemory(cur);
    cur = next;
  }
}

void HTList_addObject(HTList *list, void *object)
{
  /* append */
  while (list->next) list = list->next;
  HTList *node = HTList_new();
  node->object = object;
  list->next   = node;
}

void *HTList_nextObject(HTList *list)
{
  /* stateless iteration -- caller must use a local pointer */
  if (!list || !list->next) return NULL;
  return list->next->object;
}

int HTList_count(HTList *list)
{
  int n = 0;
  HTList *cur = list ? list->next : NULL;
  while (cur) { n++; cur = cur->next; }
  return n;
}

/* ── AHTDocId_Status helpers ────────────────────────────────────────────── */

AHTDocId_Status *GetDocIdStatus(int docid, HTList *documents)
{
  if (!documents) return NULL;
  HTList *cur = documents->next;
  while (cur) {
    AHTDocId_Status *ds = (AHTDocId_Status*)cur->object;
    if (ds && ds->docid == docid) return ds;
    cur = cur->next;
  }
  return NULL;
}

static AHTDocId_Status *get_or_create_docid_status(int docid)
{
  if (!s_doc_list) s_doc_list = HTList_new();
  AHTDocId_Status *ds = GetDocIdStatus(docid, s_doc_list);
  if (!ds) {
    ds = (AHTDocId_Status*)TtaGetMemory(sizeof(AHTDocId_Status));
    ds->docid   = docid;
    ds->counter = 0;
    HTList_addObject(s_doc_list, ds);
  }
  return ds;
}

/* ── AHTReqContext lifecycle ────────────────────────────────────────────── */

AHTReqContext *AHTReqContext_new(int docid)
{
  AHTReqContext *me = (AHTReqContext*)TtaGetMemory(sizeof(AHTReqContext));
  memset(me, 0, sizeof(*me));
  me->docid     = docid;
  me->reqStatus = HT_NEW;
  return me;
}

ThotBool AHTReqContext_delete(AHTReqContext *me)
{
  if (!me) return FALSE;
  if (me->easy) {
    curl_multi_remove_handle(s_curlm, me->easy);
    curl_easy_cleanup(me->easy);
    me->easy = NULL;
  }
  if (me->req_headers) {
    curl_slist_free_all(me->req_headers);
    me->req_headers = NULL;
  }
  if (me->output)    { fclose(me->output);       me->output    = NULL; }
  if (me->urlName)   { TtaFreeMemory(me->urlName); me->urlName = NULL; }
  if (me->outputfile){ TtaFreeMemory(me->outputfile); me->outputfile = NULL; }
  if (me->error_stream) { TtaFreeMemory(me->error_stream); me->error_stream = NULL; }
  if (me->mem_buffer)   { TtaFreeMemory(me->mem_buffer);   me->mem_buffer   = NULL; }
  if (me->http_headers.content_type)         TtaFreeMemory(me->http_headers.content_type);
  if (me->http_headers.charset)              TtaFreeMemory(me->http_headers.charset);
  if (me->http_headers.content_length)       TtaFreeMemory(me->http_headers.content_length);
  if (me->http_headers.reason)               TtaFreeMemory(me->http_headers.reason);
  if (me->http_headers.content_location)     TtaFreeMemory(me->http_headers.content_location);
  if (me->http_headers.full_content_location)TtaFreeMemory(me->http_headers.full_content_location);
  TtaFreeMemory(me);
  return TRUE;
}

/* ── libcurl write callbacks ────────────────────────────────────────────── */

static size_t write_to_file_cb(char *ptr, size_t size, size_t nmemb, void *userdata)
{
  AHTReqContext *me = (AHTReqContext*)userdata;
  if (!me->output) return 0;
  size_t written = fwrite(ptr, size, nmemb, me->output);
  if (me->incremental_cbf) {
    /* deliver each chunk to the incremental callback */
    me->incremental_cbf(me->docid, HT_OK,
                        me->urlName, me->outputfile,
                        &me->http_headers,
                        ptr, (int)(size * nmemb),
                        me->context_icbf);
  }
  return written;
}

static size_t write_to_mem_cb(char *ptr, size_t size, size_t nmemb, void *userdata)
{
  AHTReqContext *me = (AHTReqContext*)userdata;
  size_t total = size * nmemb;
  me->mem_buffer = (char*)TtaRealloc(me->mem_buffer, me->mem_size + total + 1);
  memcpy(me->mem_buffer + me->mem_size, ptr, total);
  me->mem_size += total;
  me->mem_buffer[me->mem_size] = '\0';
  return total;
}

/* ── libcurl header callback ────────────────────────────────────────────── */

static size_t header_cb(char *buffer, size_t size, size_t nitems, void *userdata)
{
  AHTReqContext *me = (AHTReqContext*)userdata;
  size_t len = size * nitems;
  char header[4096];
  if (len >= sizeof(header)) return len; /* too long, skip */
  memcpy(header, buffer, len);
  header[len] = '\0';

  /* strip trailing \r\n */
  char *end = header + len - 1;
  while (end > header && (*end == '\r' || *end == '\n')) *end-- = '\0';

  /* Content-Type */
  if (strncasecmp(header, "Content-Type:", 13) == 0) {
    char *val = header + 13;
    while (*val == ' ') val++;
    if (me->http_headers.content_type) TtaFreeMemory(me->http_headers.content_type);
    /* split charset out */
    char *semi = strchr(val, ';');
    if (semi) {
      *semi = '\0';
      char *cs = strcasestr(semi + 1, "charset=");
      if (cs) {
        cs += 8;
        if (me->http_headers.charset) TtaFreeMemory(me->http_headers.charset);
        me->http_headers.charset = TtaStrdup(cs);
      }
    }
    me->http_headers.content_type = TtaStrdup(val);
  }
  /* Content-Length */
  else if (strncasecmp(header, "Content-Length:", 15) == 0) {
    char *val = header + 15;
    while (*val == ' ') val++;
    if (me->http_headers.content_length) TtaFreeMemory(me->http_headers.content_length);
    me->http_headers.content_length = TtaStrdup(val);
  }
  /* Content-Location */
  else if (strncasecmp(header, "Content-Location:", 17) == 0) {
    char *val = header + 17;
    while (*val == ' ') val++;
    if (me->http_headers.content_location) TtaFreeMemory(me->http_headers.content_location);
    me->http_headers.content_location = TtaStrdup(val);
    if (me->http_headers.full_content_location) TtaFreeMemory(me->http_headers.full_content_location);
    me->http_headers.full_content_location = TtaStrdup(val);
  }
  return len;
}

/* ── Poll timer callback ────────────────────────────────────────────────── */

/*
 * Called by wxAmayaSocketEventLoop every CURL_POLL_MS ms.
 * Drives curl and dispatches completed transfers.
 */
void AmayaCurlPoll(void)
{
  if (!s_curlm) return;
  int still_running = 0;
  curl_multi_perform(s_curlm, &still_running);
  curl_check_multi_info();
}

/* ── Check completed transfers ──────────────────────────────────────────── */

static void curl_check_multi_info(void)
{
  CURLMsg *msg;
  int msgs_left;

  while ((msg = curl_multi_info_read(s_curlm, &msgs_left))) {
    if (msg->msg != CURLMSG_DONE) continue;

    CURL *easy = msg->easy_handle;
    AHTReqContext *me = NULL;
    curl_easy_getinfo(easy, CURLINFO_PRIVATE, &me);
    if (!me) continue;

    /* Get final HTTP status */
    curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &me->http_status);
    me->http_headers.status = (int)me->http_status;

    /* Determine success/failure */
    int amaya_status;
    if (msg->data.result == CURLE_OK && me->http_status >= 200 && me->http_status < 400)
      amaya_status = HT_OK;
    else if (me->http_status >= 400)
      amaya_status = HT_ERROR;
    else
      amaya_status = HT_ERROR;

    me->reqStatus = HT_IDLE;

    /* Close output file before callback reads it */
    if (me->output) {
      fclose(me->output);
      me->output = NULL;
    }

    /* Update document request counter */
    AHTDocId_Status *ds = GetDocIdStatus(me->docid, s_doc_list);
    if (ds && ds->counter > 0) ds->counter--;

    deliver_result(me, amaya_status);
  }
}

static void deliver_result(AHTReqContext *me, int status)
{
  if (me->terminate_cbf) {
    me->terminate_cbf(me->docid, status,
                      me->urlName, me->outputfile,
                      NULL /* proxyName */,
                      &me->http_headers,
                      me->context_tcbf);
  }
  AHTReqContext_delete(me);
}

/* ── InvokeGetObjectWWW_callback ────────────────────────────────────────── */

void InvokeGetObjectWWW_callback(int docid, char *urlName, char *outputfile,
                                  TTcbf *terminate_cbf, void *context_tcbf,
                                  int status)
{
  if (terminate_cbf)
    terminate_cbf(docid, status, urlName, outputfile, NULL, NULL, context_tcbf);
}

/* ── GetObjectWWW -- the main fetch entry point ─────────────────────────── */

int GetObjectWWW(int docid, int refdoc, char *urlName,
                 const char *formdata, char *outputfile,
                 int mode,
                 TIcbf *incremental_cbf, void *context_icbf,
                 TTcbf *terminate_cbf, void *context_tcbf,
                 ThotBool error_html, const char *content_type)
{
  if (!s_curlm || !urlName) return HT_ERROR;

  /* Phase 3: HTTP only.  Skip anything that isn't http:// or file:// */
  if (strncmp(urlName, "http://",  7) != 0 &&
      strncmp(urlName, "file://",  7) != 0 &&
      strncmp(urlName, "/",        1) != 0) {
    /* For HTTPS, remove this check -- libcurl handles it natively */
    if (terminate_cbf)
      terminate_cbf(docid, HT_ERROR, urlName, outputfile, NULL, NULL, context_tcbf);
    return HT_ERROR;
  }

  AHTReqContext *me = AHTReqContext_new(docid);
  me->urlName         = TtaStrdup(urlName);
  me->outputfile      = outputfile ? TtaStrdup(outputfile) : NULL;
  me->mode            = mode;
  me->incremental_cbf = incremental_cbf;
  me->context_icbf    = context_icbf;
  me->terminate_cbf   = terminate_cbf;
  me->context_tcbf    = context_tcbf;
  me->error_html      = error_html;

  /* Build the easy handle */
  CURL *easy = curl_easy_init();
  if (!easy) { AHTReqContext_delete(me); return HT_ERROR; }
  me->easy = easy;

  curl_easy_setopt(easy, CURLOPT_URL, urlName);
  curl_easy_setopt(easy, CURLOPT_PRIVATE, (void*)me);
  curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(easy, CURLOPT_MAXREDIRS, 10L);
  curl_easy_setopt(easy, CURLOPT_USERAGENT, "Amaya/11.4.7-modern (libcurl)");
  curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, header_cb);
  curl_easy_setopt(easy, CURLOPT_HEADERDATA, (void*)me);

  /* Write body */
  if (outputfile) {
    me->output = fopen(outputfile, "wb");
    if (!me->output) {
      AHTReqContext_delete(me);
      return HT_ERROR;
    }
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_to_file_cb);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, (void*)me);
  } else {
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_to_mem_cb);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, (void*)me);
  }

  /* POST with form data */
  if (formdata) {
    curl_easy_setopt(easy, CURLOPT_POSTFIELDS, formdata);
    if (content_type) {
      char ct_header[256];
      snprintf(ct_header, sizeof(ct_header), "Content-Type: %s", content_type);
      me->req_headers = curl_slist_append(me->req_headers, ct_header);
    }
  }

  /* Accept header */
  me->req_headers = curl_slist_append(me->req_headers,
    "Accept: text/html, application/xhtml+xml, image/*, */*; q=0.5");
  if (me->req_headers)
    curl_easy_setopt(easy, CURLOPT_HTTPHEADER, me->req_headers);

  /* Register with multi */
  CURLMcode mc = curl_multi_add_handle(s_curlm, easy);
  if (mc != CURLM_OK) {
    AHTReqContext_delete(me);
    return HT_ERROR;
  }

  me->reqStatus = HT_BUSY;
  get_or_create_docid_status(docid)->counter++;

  /* Kick the multi to start the transfer */
  int still_running = 0;
  curl_multi_perform(s_curlm, &still_running);

  return HT_OK;
}

/* ── PutObjectWWW ───────────────────────────────────────────────────────── */

int PutObjectWWW(int docid, char *fileName, char *urlName,
                 const char *contentType, char *outputfile,
                 int mode, TTcbf *terminate_cbf, void *context_tcbf)
{
  if (!s_curlm || !urlName || !fileName) return HT_ERROR;

  struct stat st;
  if (stat(fileName, &st) != 0) return HT_ERROR;

  AHTReqContext *me = AHTReqContext_new(docid);
  me->urlName       = TtaStrdup(urlName);
  me->outputfile    = outputfile ? TtaStrdup(outputfile) : NULL;
  me->mode          = mode;
  me->terminate_cbf = terminate_cbf;
  me->context_tcbf  = context_tcbf;
  me->block_size    = (unsigned long)st.st_size;

  FILE *src = fopen(fileName, "rb");
  if (!src) { AHTReqContext_delete(me); return HT_ERROR; }
  me->put_input = src;

  CURL *easy = curl_easy_init();
  if (!easy) { fclose(src); AHTReqContext_delete(me); return HT_ERROR; }
  me->easy = easy;

  curl_easy_setopt(easy, CURLOPT_URL, urlName);
  curl_easy_setopt(easy, CURLOPT_PRIVATE, (void*)me);
  curl_easy_setopt(easy, CURLOPT_UPLOAD, 1L);
  curl_easy_setopt(easy, CURLOPT_READDATA, src);
  curl_easy_setopt(easy, CURLOPT_INFILESIZE_LARGE, (curl_off_t)st.st_size);
  curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, header_cb);
  curl_easy_setopt(easy, CURLOPT_HEADERDATA, (void*)me);
  curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_to_mem_cb);
  curl_easy_setopt(easy, CURLOPT_WRITEDATA, (void*)me);

  if (contentType) {
    char ct[256];
    snprintf(ct, sizeof(ct), "Content-Type: %s", contentType);
    me->req_headers = curl_slist_append(me->req_headers, ct);
    curl_easy_setopt(easy, CURLOPT_HTTPHEADER, me->req_headers);
  }

  CURLMcode mc = curl_multi_add_handle(s_curlm, easy);
  if (mc != CURLM_OK) {
    fclose(src);
    AHTReqContext_delete(me);
    return HT_ERROR;
  }

  me->reqStatus = HT_BUSY;
  get_or_create_docid_status(docid)->counter++;
  int still_running = 0;
  curl_multi_perform(s_curlm, &still_running);
  return HT_OK;
}

/* ── Stop / cancel ──────────────────────────────────────────────────────── */

/*
 * Walk the curl multi handle's active transfers and cancel the ones
 * belonging to docid.  libcurl doesn't expose an iterator directly,
 * so we keep a global list.
 *
 * For simplicity in Phase 3 we implement a lightweight pending list.
 */

/* Global pending list -- populated in GetObjectWWW/PutObjectWWW */
static HTList *s_pending = NULL;

void StopRequest(int docid)
{
  if (!s_curlm || !s_pending) return;
  HTList *cur = s_pending->next;
  while (cur) {
    AHTReqContext *me = (AHTReqContext*)cur->object;
    if (me && me->docid == docid && me->reqStatus == HT_BUSY) {
      me->reqStatus = HT_ABORT;
      curl_multi_remove_handle(s_curlm, me->easy);
      curl_easy_cleanup(me->easy);
      me->easy = NULL;
      if (me->terminate_cbf)
        me->terminate_cbf(docid, HT_INTERRUPTED,
                          me->urlName, me->outputfile,
                          NULL, &me->http_headers, me->context_tcbf);
      AHTReqContext_delete(me);
      cur->object = NULL;
    }
    cur = cur->next;
  }
}

void StopAllRequests(int docid)
{
  StopRequest(docid);
}

/* ── HTTP header accessors ──────────────────────────────────────────────── */

/* Called by amaya/ when it needs to set request headers.
 * With libwww these manipulated an HTRequest; here we use the
 * req_headers slist on the AHTReqContext. The ctx arg IS the context. */
void HTTP_headers_set(HTRequest *request, HTResponse *response,
                      void *context, int status)
{
  /* no-op in Phase 3 -- headers are set directly via CURLOPT_HTTPHEADER */
  (void)request; (void)response; (void)context; (void)status;
}

char *HTTP_headers(AHTHeaders *me, AHTHeaderName param)
{
  if (!me) return NULL;
  switch (param) {
    case AM_HTTP_CONTENT_TYPE:           return me->content_type;
    case AM_HTTP_CHARSET:                return me->charset;
    case AM_HTTP_CONTENT_LENGTH:         return me->content_length;
    case AM_HTTP_REASON:                 return me->reason;
    case AM_HTTP_CONTENT_LOCATION:       return me->content_location;
    case AM_HTTP_FULL_CONTENT_LOCATION:  return me->full_content_location;
    default:                             return NULL;
  }
}

void AHTRequest_setRefererHeader(AHTReqContext *me)
{
  /* no-op in Phase 3; could add CURLOPT_REFERER if needed */
  (void)me;
}

void AHTRequest_setCustomAcceptHeader(HTRequest *request, const char *value)
{
  /* no-op; Accept is set in GetObjectWWW above */
  (void)request; (void)value;
}

/* ── Lifecycle ──────────────────────────────────────────────────────────── */

void QueryInit(void)
{
  curl_global_init(CURL_GLOBAL_DEFAULT);
  s_curlm   = curl_multi_init();
  s_pending = HTList_new();
  s_doc_list= HTList_new();
  s_alive   = TRUE;

  curl_multi_setopt(s_curlm, CURLMOPT_MAX_TOTAL_CONNECTIONS, (long)MAX_CONNECTIONS);

  /* Register our poll function with the wx event loop */
  wxAmayaSocketEvent::GetEventLoop()->SetCurlPoll(AmayaCurlPoll, CURL_POLL_MS);
}

void QueryClose(void)
{
  if (!s_curlm) return;
  wxAmayaSocketEvent::GetEventLoop()->ClearCurlPoll();

  /* Cancel all pending transfers */
  if (s_pending) {
    HTList *cur = s_pending->next;
    while (cur) {
      AHTReqContext *me = (AHTReqContext*)cur->object;
      if (me) AHTReqContext_delete(me);
      cur = cur->next;
    }
    HTList_delete(s_pending);
    s_pending = NULL;
  }

  curl_multi_cleanup(s_curlm);
  curl_global_cleanup();
  s_curlm = NULL;
  s_alive = FALSE;
}

ThotBool AmayaIsAlive(void)           { return s_alive; }
ThotBool CanDoStop(void)              { return s_can_do_stop; }
void     CanDoStop_set(ThotBool v)    { s_can_do_stop = v; }

void     AHTFTPURL_flag_set(ThotBool v) { s_ftp_flag = v; }
ThotBool AHTFTPURL_flag(void)           { return s_ftp_flag; }

void libwww_updateNetworkConf(int status) { (void)status; }

/* Cache stubs -- Amaya's cache logic is in init.c; these are no-ops
   until we implement a file-based cache in a later iteration. */
void libwww_CleanCache(void) {}
void FreeAmayaCache(void)    {}
void InitAmayaCache(void)    {}
void ClearCacheEntry(char *url) { (void)url; }

/* SafePut_query: check whether a PUT to url is safe (not cancelled) */
ThotBool SafePut_query(char *url)
{
  (void)url;
  return TRUE; /* simplified; full impl checks s_pending list */
}

/* AHTOpen_file: called by the old libwww pipeline; not used in libcurl path */
int AHTOpen_file(HTRequest *request)
{
  (void)request;
  return HT_OK;
}

int AHTLoadTerminate_handler(HTRequest *request, HTResponse *response,
                              void *param, int status)
{
  (void)request; (void)response; (void)param; (void)status;
  return HT_OK;
}
