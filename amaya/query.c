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
 * Schemes: http and https (TLS through libcurl, checked against the
 * system's authorities plus ~/.amaya/trusted-certs.pem).
 *
 * (c) 2026  JoseMCruz <jmcruz@fe.up.pt> -- FEUP
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
#include <fcntl.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pem.h>
#include <openssl/evp.h>
#include <unistd.h>
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

/* ── TLS certificates ───────────────────────────────────────────────────
   libcurl (OpenSSL) checks HTTPS servers against the system's trusted
   authorities (/etc/ssl/certs).  Here, for every new TLS connection:
   - certificates in <APP_HOME>/trusted-certs.pem are trusted as well
     (a site's own certificate is enough: partial chains are accepted);
   - the server certificate and the reason of a verification failure are
     recorded, so that the error page can show them. */
typedef struct _TlsInfo {
  char reason[200];        /* why the certificate was rejected */
  int  x509_error;         /* OpenSSL X509_V_ERR_..., 0 if none */
  char subject[400];
  char issuer[400];
  char not_before[64];
  char not_after[64];
  char sha256[3 * 32 + 1]; /* AB:CD:... */
  char *pem;               /* server certificate (depth 0), allocated */
} TlsInfo;

static char s_trusted_file[MAX_LENGTH] = "";
static int  s_tls_ex_index = -1;

static void asn1_time_text(const ASN1_TIME *t, char *buf, size_t len)
{
  BIO *b = BIO_new(BIO_s_mem());
  buf[0] = EOS;
  if (!b) return;
  if (ASN1_TIME_print(b, t)) {
    int n = BIO_read(b, buf, (int)len - 1);
    buf[n > 0 ? n : 0] = EOS;
  }
  BIO_free(b);
}

static void record_cert(TlsInfo *ti, X509 *cert)
{
  unsigned char md[EVP_MAX_MD_SIZE];
  unsigned int  mdlen = 0;
  X509_NAME_oneline(X509_get_subject_name(cert), ti->subject, sizeof(ti->subject));
  X509_NAME_oneline(X509_get_issuer_name(cert), ti->issuer, sizeof(ti->issuer));
  asn1_time_text(X509_get0_notBefore(cert), ti->not_before, sizeof(ti->not_before));
  asn1_time_text(X509_get0_notAfter(cert), ti->not_after, sizeof(ti->not_after));
  ti->sha256[0] = EOS;
  if (X509_digest(cert, EVP_sha256(), md, &mdlen))
    for (unsigned int i = 0; i < mdlen && 3 * i + 3 < sizeof(ti->sha256); i++)
      snprintf(ti->sha256 + 3 * i, sizeof(ti->sha256) - 3 * i,
               i + 1 < mdlen ? "%02X:" : "%02X", md[i]);
  BIO *b = BIO_new(BIO_s_mem());
  if (b && PEM_write_bio_X509(b, cert)) {
    char *data = NULL;
    long n = BIO_get_mem_data(b, &data);
    if (ti->pem) TtaFreeMemory(ti->pem);
    ti->pem = (char *)TtaGetMemory(n + 1);
    memcpy(ti->pem, data, n);
    ti->pem[n] = EOS;
  }
  if (b) BIO_free(b);
}

/* called by OpenSSL for every certificate of the chain */
static int tls_verify_cb(int preverify_ok, X509_STORE_CTX *xctx)
{
  SSL *ssl = (SSL *)X509_STORE_CTX_get_ex_data(xctx,
                              SSL_get_ex_data_X509_STORE_CTX_idx());
  TlsInfo *ti = (ssl && s_tls_ex_index >= 0) ?
    (TlsInfo *)SSL_CTX_get_ex_data(SSL_get_SSL_CTX(ssl), s_tls_ex_index) : NULL;
  if (ti) {
    /* the site's own certificate: verification goes from the top of the
       chain down and stops at the first failure, so depth 0 is not always
       reached (e.g. an untrusted intermediate): take it from the context */
    X509 *cert = X509_STORE_CTX_get0_cert(xctx);
    if (cert && ti->subject[0] == EOS)
      record_cert(ti, cert);
    if (!preverify_ok && ti->x509_error == 0) {
      ti->x509_error = X509_STORE_CTX_get_error(xctx);
      snprintf(ti->reason, sizeof(ti->reason), "%s",
               X509_verify_cert_error_string(ti->x509_error));
    }
  }
  return preverify_ok;
}

static CURLcode tls_ctx_cb(CURL *easy, void *sslctx, void *userptr)
{
  SSL_CTX *ctx = (SSL_CTX *)sslctx;
  (void)easy;
  if (s_tls_ex_index >= 0)
    SSL_CTX_set_ex_data(ctx, s_tls_ex_index, userptr);
  SSL_CTX_set_verify(ctx, SSL_CTX_get_verify_mode(ctx), tls_verify_cb);
  if (s_trusted_file[0] != EOS && TtaFileExist(s_trusted_file)) {
    X509_STORE *store = SSL_CTX_get_cert_store(ctx);
    if (store) {
      X509_STORE_load_file(store, s_trusted_file);
      /* a trusted site certificate is enough, even without its CA */
      X509_STORE_set_flags(store, X509_V_FLAG_PARTIAL_CHAIN);
    }
  }
  return CURLE_OK;
}

static void tls_setup(CURL *easy, AHTReqContext *me)
{
  if (strncmp(me->urlName ? me->urlName : "", "https:", 6))
    return;
  if (!me->tls)
    me->tls = (TlsInfo *)TtaGetMemory(sizeof(TlsInfo));
  memset(me->tls, 0, sizeof(TlsInfo));
  curl_easy_setopt(easy, CURLOPT_SSL_CTX_FUNCTION, tls_ctx_cb);
  curl_easy_setopt(easy, CURLOPT_SSL_CTX_DATA, me->tls);
  /* without CA cache, every new connection gets a fresh store */
  curl_easy_setopt(easy, CURLOPT_CA_CACHE_TIMEOUT, 0L);
}

static void tls_free(AHTReqContext *me)
{
  if (me->tls) {
    if (me->tls->pem) TtaFreeMemory(me->tls->pem);
    TtaFreeMemory(me->tls);
    me->tls = NULL;
  }
}

/* requests in progress (used by StopRequest) */
static HTList *s_pending = NULL;

/* register a request, reusing a free slot of the list if there is one */
static void pending_add(AHTReqContext *me)
{
  if (!s_pending) return;
  for (HTList *cur = s_pending->next; cur; cur = cur->next)
    if (cur->object == NULL) { cur->object = me; return; }
  HTList_addObject(s_pending, me);
}

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
  if (s_pending)
    for (HTList *cur = s_pending->next; cur; cur = cur->next)
      if (cur->object == me)
        cur->object = NULL;
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
  if (me->put_input) { fclose(me->put_input);    me->put_input = NULL; }
  tls_free(me);
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

  /* Status line (one per response; several with redirections):
     "HTTP/1.1 404 Not Found", "HTTP/2 200".  Start afresh for each
     response so that headers of a redirection do not linger. */
  if (strncmp(header, "HTTP/", 5) == 0) {
    char *p = strchr(header, ' ');
    if (p) p = strchr(p + 1, ' ');          /* skip the status code */
    if (me->http_headers.reason) TtaFreeMemory(me->http_headers.reason);
    me->http_headers.reason = (p && p[1]) ? TtaStrdup(p + 1) : NULL;
    if (me->http_headers.content_type)
      { TtaFreeMemory(me->http_headers.content_type); me->http_headers.content_type = NULL; }
    if (me->http_headers.charset)
      { TtaFreeMemory(me->http_headers.charset); me->http_headers.charset = NULL; }
    if (me->http_headers.content_length)
      { TtaFreeMemory(me->http_headers.content_length); me->http_headers.content_length = NULL; }
  }
  /* Content-Type */
  else if (strncasecmp(header, "Content-Type:", 13) == 0) {
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
        if (*cs == '"') {                       /* charset="utf-8" */
          cs++;
          char *q = strchr(cs, '"');
          if (q) *q = '\0';
        }
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

/* -- Errors -------------------------------------------------------------
   As the libwww version did: when the caller wants HTML errors (loading a
   document), an HTTP error page sent by the server is displayed like a
   normal page; the error is flagged (AMAYA_NET_ERROR, so "Finished!" is not
   shown) and reported in the status bar.  When there is no server answer at
   all (connection refused, unknown host, TLS failure...), a small page
   stating the reason is generated instead of a blank document. */
static void html_escape_to(FILE *f, const char *s)
{
  for (; s && *s; s++)
    switch (*s) {
    case '<': fputs("&lt;", f); break;
    case '>': fputs("&gt;", f); break;
    case '&': fputs("&amp;", f); break;
    default:  fputc(*s, f);
    }
}

/* certificate section of the error page */
static void write_cert_details(FILE *f, AHTReqContext *me, TlsInfo *ti)
{
  /* trusting the certificate only helps when its issuer is the problem */
  ThotBool trust_helps = (ti->x509_error == X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT ||
                          ti->x509_error == X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN ||
                          ti->x509_error == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY ||
                          ti->x509_error == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT ||
                          ti->x509_error == X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE);
  fputs("<h2>Server certificate</h2>\n<table border=\"1\">\n", f);
  const char *labels[] = {"Subject", "Issued by", "Valid from", "Valid until",
                          "SHA-256 fingerprint"};
  const char *values[] = {ti->subject, ti->issuer, ti->not_before, ti->not_after,
                          ti->sha256};
  for (int i = 0; i < 5; i++) {
    fputs("<tr><th align=\"left\">", f); fputs(labels[i], f);
    fputs("</th><td>", f);
    if (i == 4 && strlen(values[i]) > 48) {
      /* 32 bytes: two lines of 16, so that the page can wrap it */
      fwrite(values[i], 1, 48, f);
      fputs("<br />", f);
      html_escape_to(f, values[i] + 48);
    }
    else
      html_escape_to(f, values[i]);
    fputs("</td></tr>\n", f);
  }
  fputs("</table>\n", f);
  if (ti->x509_error == 0 && me->curl_error[0]) {
    fputs("<p>Details: ", f); html_escape_to(f, me->curl_error); fputs("</p>\n", f);
  }
  if (trust_helps && ti->pem && s_trusted_file[0]) {
    fputs("<h2>Trusting this certificate</h2>\n"
          "<p>Amaya trusts the certification authorities of the system "
          "(/etc/ssl/certs) and the certificates in</p>\n<pre>", f);
    html_escape_to(f, s_trusted_file);
    fputs("</pre>\n<p>If you are sure that this certificate belongs to this "
          "site (compare its SHA-256 fingerprint with one obtained from a "
          "source you trust), append the following text to that file and "
          "reload the page.  Only this certificate will be trusted; remove "
          "it from the file to undo.</p>\n<pre>", f);
    html_escape_to(f, ti->pem);
    fputs("</pre>\n", f);
  }
  else if (!trust_helps)
    fputs("<p>Trusting this certificate would not solve this problem "
          "(for example, it has expired or was issued for another site "
          "name).</p>\n", f);
}

static int report_error(AHTReqContext *me, CURLcode res)
{
  char message[300];
  TlsInfo *ti = me->tls;
  ThotBool cert_problem = (res == CURLE_PEER_FAILED_VERIFICATION &&
                           ti && (ti->x509_error || ti->subject[0]));
  if (cert_problem)
    snprintf(message, sizeof(message), "Certificate not accepted: %s",
             ti->x509_error ? ti->reason : me->curl_error);
  else if (res != CURLE_OK)
    snprintf(message, sizeof(message), "%s%s%s", curl_easy_strerror(res),
             me->curl_error[0] ? ": " : "", me->curl_error);
  else
    snprintf(message, sizeof(message), "HTTP %ld%s%s", me->http_status,
             me->http_headers.reason ? " " : "",
             me->http_headers.reason ? me->http_headers.reason : "");
  for (char *c = message; *c; c++)
    if (*c == '%' || *c == '\r' || *c == '\n')
      *c = ' ';
  if (me->docid > 0) {
    TtaSetStatus(me->docid, 1, message, NULL);
    /* keep the message: ResetStop shows "Finished!" only without errors */
    DocNetworkStatus[me->docid] |= AMAYA_NET_ERROR;
  }
  if (!me->error_html || !me->outputfile)
    return HT_ERROR;
  if (res == CURLE_OK && TtaGetFileSize(me->outputfile) > 0)
    /* display the error page sent by the server */
    return HT_OK;

  FILE *f = fopen(me->outputfile, "w");
  if (!f)
    return HT_ERROR;
  fputs("<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" "
        "\"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n"
        "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head>"
        "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />"
        "<title>Cannot load page</title></head><body>\n"
        "<h1>Cannot load page</h1>\n<p>", f);
  html_escape_to(f, me->urlName);
  fputs("</p>\n<p>", f);
  html_escape_to(f, message);
  fputs("</p>\n", f);
  if (cert_problem)
    write_cert_details(f, me, ti);
  fputs("</body></html>\n", f);
  fclose(f);
  if (me->http_headers.content_type)
    TtaFreeMemory(me->http_headers.content_type);
  me->http_headers.content_type = TtaStrdup("text/html");
  if (me->http_headers.charset)
    TtaFreeMemory(me->http_headers.charset);
  me->http_headers.charset = TtaStrdup("utf-8");
  return HT_OK;
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
    /* after redirections, report the final URL (as libwww did) */
    char *effective = NULL;
    curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &effective);
    if (effective && me->urlName && strcmp(effective, me->urlName)) {
      TtaFreeMemory(me->urlName);
      me->urlName = TtaStrdup(effective);
    }
    me->http_headers.status = (int)me->http_status;

    /* Close output file before the callback reads it */
    if (me->output) {
      fclose(me->output);
      me->output = NULL;
    }

    /* Determine success/failure */
    int amaya_status;
    CURLcode res = msg->data.result;
    if (res == CURLE_OK && me->http_status >= 200 && me->http_status < 400)
      amaya_status = HT_OK;
    else
      amaya_status = report_error(me, res);

    me->reqStatus = HT_IDLE;

    /* Update document request counter */
    AHTDocId_Status *ds = GetDocIdStatus(me->docid, s_doc_list);
    if (ds && ds->counter > 0) ds->counter--;

    deliver_result(me, amaya_status);
  }
}

static void deliver_result(AHTReqContext *me, int status)
{
  if (me->sync_done) {
    *me->sync_done = TRUE;
    if (me->sync_status)
      *me->sync_status = status;
  }
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

/* the network event loop, or NULL once it has been deleted at exit */
static wxAmayaSocketEventLoop *event_loop(void)
{
  return wxAmayaSocketEvent::GetEventLoop();
}

/* ── Cookies ────────────────────────────────────────────────────────────
   One cookie store, shared by every transfer, so that a session cookie
   received with one page (e.g. after a login form) is sent with the next
   requests.  Persistent cookies are kept in <APP_HOME>/cookies.txt (Netscape
   format, as curl/wget use), loaded at start-up and saved at exit; session
   cookies (no expiry date) are not saved, as in other browsers.
   Set ENABLE_COOKIES=no in thot.rc to disable cookies altogether. */
static CURLSH  *s_share = NULL;
static ThotBool s_cookies = TRUE;

/* computed at start-up: at exit, QueryClose runs after the registry
   (APP_HOME) has been freed */
static char s_cookie_file[MAX_LENGTH] = "";

static void cookie_file_name(char *buf, size_t len)
{
  snprintf(buf, len, "%s", s_cookie_file);
}

/* Feed the cookies of a Netscape-format file into the shared store.
   Returns the number of cookies read; when domains is not NULL, it gets a
   comma-separated list of the cookies' sites. */
static int cookies_read_file(const char *name, char *domains, size_t dlen)
{
  char line[8192];
  int  count = 0;
  FILE *f = fopen(name, "r");
  if (domains && dlen) domains[0] = EOS;
  if (!f) return -1;
  CURL *easy = curl_easy_init();
  if (easy) {
    curl_easy_setopt(easy, CURLOPT_SHARE, s_share);
    while (fgets(line, sizeof(line), f)) {
      size_t l = strlen(line);
      while (l && (line[l-1] == '\n' || line[l-1] == '\r')) line[--l] = EOS;
      /* comments, but "#HttpOnly_" lines are cookies */
      if (l == 0 || (line[0] == '#' && strncmp(line, "#HttpOnly_", 10)))
        continue;
      /* a cookie has 7 tab-separated fields */
      int tabs = 0;
      for (const char *t = line; *t; t++) if (*t == '\t') tabs++;
      if (tabs < 6) continue;
      if (curl_easy_setopt(easy, CURLOPT_COOKIELIST, line) != CURLE_OK)
        continue;
      count++;
      if (domains && dlen) {
        /* add the site to the list, once */
        char site[256];
        const char *d = line;
        if (!strncmp(d, "#HttpOnly_", 10)) d += 10;
        if (*d == '.') d++;
        size_t n = strcspn(d, "\t");
        if (n >= sizeof(site)) n = sizeof(site) - 1;
        memcpy(site, d, n);
        site[n] = EOS;
        size_t used = strlen(domains);
        char *found = strstr(domains, site);
        ThotBool known = FALSE;
        while (found) {
          size_t e = (found - domains) + n;
          if ((found == domains ||
               (found - domains >= 2 && found[-2] == ',' && found[-1] == ' ')) &&
              (domains[e] == EOS || domains[e] == ','))
            { known = TRUE; break; }
          found = strstr(found + 1, site);
        }
        if (!known) {
          if (used + n + 6 < dlen)
            snprintf(domains + used, dlen - used, "%s%s", used ? ", " : "", site);
          else if (used + 5 < dlen && strcmp(domains + used - 3, "...") != 0)
            snprintf(domains + used, dlen - used, ", ...");
        }
      }
    }
    curl_easy_cleanup(easy);
  }
  fclose(f);
  return count;
}

static void cookies_load(void)
{
  char name[MAX_LENGTH];
  const char *home = TtaGetEnvString("APP_HOME");
  if (home == NULL || home[0] == EOS) {
    s_cookie_file[0] = EOS;              /* nowhere safe to keep cookies */
    return;
  }
  snprintf(s_cookie_file, sizeof(s_cookie_file), "%s%ccookies.txt",
           home, DIR_SEP);
  cookie_file_name(name, sizeof(name));
  cookies_read_file(name, NULL, 0);
}

static void cookies_save(void)
{
  char name[MAX_LENGTH], tmp[MAX_LENGTH + 8];
  struct curl_slist *list = NULL;
  if (s_cookie_file[0] == EOS) return;
  CURL *easy = curl_easy_init();
  if (!easy) return;
  curl_easy_setopt(easy, CURLOPT_SHARE, s_share);
  curl_easy_getinfo(easy, CURLINFO_COOKIELIST, &list);
  cookie_file_name(name, sizeof(name));
  snprintf(tmp, sizeof(tmp), "%s.new", name);
  int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);   /* private */
  FILE *f = (fd >= 0) ? fdopen(fd, "w") : NULL;
  if (f) {
    fputs("# Netscape HTTP Cookie File\n"
          "# Written by Amaya; session cookies are not kept.\n\n", f);
    for (struct curl_slist *c = list; c; c = c->next) {
      /* fields: domain, subdomains, path, secure, expiry, name, value */
      const char *t = c->data;
      int tabs = 0;
      while (*t && tabs < 4) if (*t++ == '\t') tabs++;
      if (tabs == 4 && atol(t) > 0)
        fprintf(f, "%s\n", c->data);
    }
    if (fclose(f) == 0)
      rename(tmp, name);
    else
      unlink(tmp);
  }
  else if (fd >= 0)
    close(fd);
  curl_slist_free_all(list);
  curl_easy_cleanup(easy);
}

/* to be called on every new transfer */
static void cookies_setup(CURL *easy)
{
  if (!s_cookies || !s_share) return;
  curl_easy_setopt(easy, CURLOPT_SHARE, s_share);
  curl_easy_setopt(easy, CURLOPT_COOKIEFILE, "");  /* enable the engine */
}

/*----------------------------------------------------------------------
  LoadCookies (File > Load cookies...)
  Add the cookies of a Netscape-format cookie file (as written by curl,
  wget, or contrib/firefox-cookies.py) to Amaya's cookies, e.g. to use in
  Amaya a login made in another browser.  As any cookie received by Amaya,
  session cookies are kept in memory only; cookies with an expiry date
  are saved in cookies.txt at exit.  The file holds credentials, so Amaya
  offers to delete it once it has been read.
  ----------------------------------------------------------------------*/
void LoadCookies (Document doc, View view)
{
  char domains[400], msg[600];
  int  count;

  if (!s_cookies || !s_share)
    {
      TtaSetStatus (doc, view, "Cookies are disabled (ENABLE_COOKIES=no)%s", "");
      return;
    }
  const char *home = getenv ("HOME");
  wxFileDialog dlg (NULL, wxT("Load cookies (Netscape cookie file)"),
                    home ? wxString::FromUTF8 (home) : wxString (),
                    wxEmptyString,
                    wxT("Cookie files (*.txt)|*.txt|All files|*"),
                    wxFD_OPEN | wxFD_FILE_MUST_EXIST);
  if (dlg.ShowModal () != wxID_OK)
    return;
  wxString path = dlg.GetPath ();
  wxCharBuffer fname = path.mb_str (wxConvFile);
  count = cookies_read_file (fname, domains, sizeof (domains));
  if (count < 0)
    {
      TtaSetStatus (doc, view, "Cannot read %s", (const char *)fname);
      return;
    }
  if (count == 0)
    snprintf (msg, sizeof (msg), "No cookies found in that file");
  else
    snprintf (msg, sizeof (msg), "%d cookie%s loaded for: %s",
              count, count > 1 ? "s" : "", domains);
  TtaSetStatus (doc, view, "%s", msg);
  if (count > 0 &&
      wxMessageBox (wxString::FromUTF8 (msg) +
                    wxT("\n\nThe file contains login credentials. Delete it now?"),
                    wxT("Load cookies"), wxYES_NO | wxICON_QUESTION) == wxYES)
    {
      if (unlink (fname) != 0)
        TtaSetStatus (doc, view, "Cookies loaded, but the file could not be deleted%s", "");
    }
}


/* Synchronous requests: drive the transfer here until it has ended (the
   termination callback has then been called), still handling GUI events so
   that the interface stays responsive, as libwww's LoopForStop did. */
static int wait_for_request(AHTReqContext *me, int docid)
{
  ThotBool done = FALSE;
  int      status = HT_ERROR;
  me->sync_done = &done;
  me->sync_status = &status;
  /* was another transfer of this document already in progress (e.g. the
     page that needs this style sheet) or is the document idle (e.g. a save)? */
  int already_loading = (docid > 0) ? FilesLoading[docid] : 0;
  SetStopButton(docid);
  while (!done) {
    int still_running = 0, numfds = 0;
    curl_multi_perform(s_curlm, &still_running);
    curl_check_multi_info();
    if (done)
      break;
    curl_multi_poll(s_curlm, NULL, 0, 50, &numfds);
    TtaHandlePendingEvents();
  }
  /* as libwww's version did: when the document was already loading,
     compensate the decrement done by ResetStop, which would otherwise mark
     the document as no longer loading while its own load is still in
     progress (its images would then never be fetched); when it was idle,
     ResetStop brings it back to idle */
  if (already_loading > 0)
    FilesLoading[docid]++;   /* ResetStop must leave the count unchanged */
  ResetStop(docid);
  return status;
}

static int object_counter = 0;

/* Create a temporary file name, as the libwww version did: CSS files go to
   subdirectory 0, everything else to a subdirectory named after the docid.
   The name is written into the caller's buffer, which callers then read. */
static void GetOutputFileName(char *outputfile, int tempsubdir)
{
  char dir[MAX_LENGTH];
  /* the per-document directory may not exist yet (e.g. when the first
     document of a session is a remote one) */
  snprintf(dir, sizeof(dir), "%s%c%d", TempFileDirectory, DIR_SEP, tempsubdir);
  if (!TtaCheckDirectory(dir))
    TtaMakeDirectory(dir);
  sprintf(outputfile, "%s%c%d%c%04dAM", TempFileDirectory, DIR_SEP,
          tempsubdir, DIR_SEP, object_counter);
  object_counter++;
}

static int fail_request(int docid, char *urlName, char *outputfile,
                        ThotBool error_html, TTcbf *terminate_cbf,
                        void *context_tcbf)
{
  if (outputfile)
    outputfile[0] = EOS;
  if (error_html && docid > 0)
    DocNetworkStatus[docid] |= AMAYA_NET_ERROR;
  InvokeGetObjectWWW_callback(docid, urlName, outputfile, terminate_cbf,
                              context_tcbf, HT_ERROR);
  return HT_ERROR;
}

int GetObjectWWW(int docid, int refdoc, char *urlName,
                 const char *formdata, char *outputfile,
                 int mode,
                 TIcbf *incremental_cbf, void *context_icbf,
                 TTcbf *terminate_cbf, void *context_tcbf,
                 ThotBool error_html, const char *content_type)
{
  if (urlName == NULL || outputfile == NULL) {
    TtaSetStatus(docid, 1, TtaGetMessage(AMAYA, AM_BAD_URL), urlName);
    return fail_request(docid, urlName, outputfile, error_html,
                        terminate_cbf, context_tcbf);
  }
  /* a 'docImage' that was already downloaded */
  if (!strncmp("internal:", urlName, 9)) {
    strcpy(outputfile, urlName);
    InvokeGetObjectWWW_callback(docid, urlName, outputfile,
                                terminate_cbf, context_tcbf, HT_OK);
    return HT_OK;
  }
  if (!s_curlm ||
      (strncmp(urlName, "http://", 7) && strncmp(urlName, "https://", 8))) {
    TtaSetStatus(docid, 1, TtaGetMessage(AMAYA, AM_GET_UNSUPPORTED_PROTOCOL),
                 urlName);
    return fail_request(docid, urlName, outputfile, error_html,
                        terminate_cbf, context_tcbf);
  }

  /* temporary file that receives the body; its name goes back to the caller */
  GetOutputFileName(outputfile, (mode & AMAYA_LOAD_CSS) ? 0 : docid);
  if (TtaFileExist(outputfile))
    TtaFileUnlink(outputfile);

  /* normalize/escape the URL (spaces etc.) */
  char *esc_url = EscapeURL(urlName);
  char *ref = NULL;
  if (esc_url) {
    ref = AmayaParseUrl(esc_url, "", AMAYA_PARSE_ALL);
    TtaFreeMemory(esc_url);
  }
  if (ref == NULL || ref[0] == EOS) {
    TtaFreeMemory(ref);
    TtaSetStatus(docid, 1, TtaGetMessage(AMAYA, AM_BAD_URL), urlName);
    return fail_request(docid, urlName, outputfile, error_html,
                        terminate_cbf, context_tcbf);
  }

  AHTReqContext *me = AHTReqContext_new(docid);
  me->urlName         = TtaStrdup(urlName);
  me->outputfile      = TtaStrdup(outputfile);
  me->mode            = mode;
  me->incremental_cbf = incremental_cbf;
  me->context_icbf    = context_icbf;
  me->terminate_cbf   = terminate_cbf;
  me->context_tcbf    = context_tcbf;
  me->error_html      = error_html;

  /* Build the easy handle */
  CURL *easy = curl_easy_init();
  if (!easy) {
    AHTReqContext_delete(me);
    TtaFreeMemory(ref);
    return fail_request(docid, urlName, outputfile, error_html,
                        terminate_cbf, context_tcbf);
  }
  me->easy = easy;

  ThotBool is_post = (mode & AMAYA_FORM_POST) || (mode & AMAYA_FILE_POST);
  if (formdata && !is_post && formdata[0] != EOS) {
    /* GET form: send the data as the query part of the URL */
    char *q = strchr(ref, '?');
    if (q) *q = EOS;                      /* the form replaces any query */
    char *full = (char *)TtaGetMemory(strlen(ref) + strlen(formdata) + 2);
    sprintf(full, "%s?%s", ref, formdata);
    curl_easy_setopt(easy, CURLOPT_URL, full);   /* curl copies the URL */
    TtaFreeMemory(full);
  }
  else
    curl_easy_setopt(easy, CURLOPT_URL, ref);
  TtaFreeMemory(ref);
  curl_easy_setopt(easy, CURLOPT_PRIVATE, (void*)me);
  curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(easy, CURLOPT_MAXREDIRS, 10L);
  curl_easy_setopt(easy, CURLOPT_USERAGENT, "Amaya/11.4.7-modern (libcurl)");
  cookies_setup(easy);
  tls_setup(easy, me);
  me->curl_error[0] = EOS;
  curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, me->curl_error);
  curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, header_cb);
  curl_easy_setopt(easy, CURLOPT_HEADERDATA, (void*)me);

  /* Write body */
  if (outputfile) {
    me->output = fopen(outputfile, "wb");
    if (!me->output) {
      AHTReqContext_delete(me);
      return fail_request(docid, urlName, outputfile, error_html,
                          terminate_cbf, context_tcbf);
    }
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_to_file_cb);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, (void*)me);
  } else {
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_to_mem_cb);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, (void*)me);
  }

  /* Form data: POST only for AMAYA_FORM_POST/AMAYA_FILE_POST (as libwww);
     for a GET form the data was appended to the URL above.  The caller may
     free formdata as soon as we return, so curl must keep its own copy. */
  if (is_post) {
    /* a form with no named field still posts (an empty body), as libwww did */
    curl_easy_setopt(easy, CURLOPT_COPYPOSTFIELDS, formdata ? formdata : "");
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
  pending_add(me);

  /* make sure the polling timer runs (it used to start only when a libwww
     socket was registered, which libcurl never does) */
  if (event_loop()) event_loop()->Start();

  if ((mode & AMAYA_SYNC) || (mode & AMAYA_ISYNC))
    return wait_for_request(me, docid);

  /* Kick the multi to start the transfer */
  int still_running = 0;
  curl_multi_perform(s_curlm, &still_running);
  return HT_OK;
}

/* ── PutObjectWWW ───────────────────────────────────────────────────────── */

/* MIME type for an upload, from the URL's extension (libwww guessed it) */
static const char *guess_content_type(const char *url)
{
  static const struct { const char *ext, *type; } map[] = {
    {"html", "text/html"}, {"htm", "text/html"}, {"xhtml", "application/xhtml+xml"},
    {"css", "text/css"}, {"xml", "text/xml"}, {"svg", "image/svg+xml"},
    {"mml", "application/mathml+xml"}, {"txt", "text/plain"},
    {"js", "application/javascript"}, {"png", "image/png"},
    {"jpg", "image/jpeg"}, {"jpeg", "image/jpeg"}, {"gif", "image/gif"},
    {NULL, NULL}};
  const char *slash = strrchr(url, '/');
  const char *dot = strrchr(slash ? slash : url, '.');
  if (dot)
    for (int i = 0; map[i].ext; i++)
      if (!strcasecmp(dot + 1, map[i].ext))
        return map[i].type;
  return "application/octet-stream";
}

int PutObjectWWW(int docid, char *fileName, char *urlName,
                 const char *contentType, char *outputfile,
                 int mode, TTcbf *terminate_cbf, void *context_tcbf)
{
  if (!s_curlm || !urlName || !fileName) return HT_ERROR;
  if (strncmp(urlName, "http://", 7) && strncmp(urlName, "https://", 8))
    return HT_ERROR;

  struct stat st;
  if (stat(fileName, &st) != 0) return HT_ERROR;

  char *esc_url = EscapeURL(urlName);
  if (!esc_url) return HT_ERROR;

  AHTReqContext *me = AHTReqContext_new(docid);
  me->urlName       = TtaStrdup(urlName);
  me->outputfile    = outputfile ? TtaStrdup(outputfile) : NULL;
  me->mode          = mode;
  me->terminate_cbf = terminate_cbf;
  me->context_tcbf  = context_tcbf;
  me->block_size    = (unsigned long)st.st_size;

  FILE *src = fopen(fileName, "rb");
  if (!src) { TtaFreeMemory(esc_url); AHTReqContext_delete(me); return HT_ERROR; }
  me->put_input = src;               /* closed by AHTReqContext_delete */

  CURL *easy = curl_easy_init();
  if (!easy) { TtaFreeMemory(esc_url); AHTReqContext_delete(me); return HT_ERROR; }
  me->easy = easy;

  curl_easy_setopt(easy, CURLOPT_URL, esc_url);
  TtaFreeMemory(esc_url);
  curl_easy_setopt(easy, CURLOPT_PRIVATE, (void*)me);
  curl_easy_setopt(easy, CURLOPT_UPLOAD, 1L);
  curl_easy_setopt(easy, CURLOPT_READDATA, src);
  curl_easy_setopt(easy, CURLOPT_INFILESIZE_LARGE, (curl_off_t)st.st_size);
  curl_easy_setopt(easy, CURLOPT_USERAGENT, "Amaya/11.4.7-modern (libcurl)");
  cookies_setup(easy);
  tls_setup(easy, me);
  me->curl_error[0] = EOS;
  curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, me->curl_error);
  curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, header_cb);
  curl_easy_setopt(easy, CURLOPT_HEADERDATA, (void*)me);
  curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_to_mem_cb);
  curl_easy_setopt(easy, CURLOPT_WRITEDATA, (void*)me);

  /* Content-Type: given by the caller, else guessed from the URL as libwww
     did; text types get the document's charset */
  const char *type = contentType ? contentType : guess_content_type(urlName);
  char ct[300];
  const char *cs = NULL;
  if (docid > 0 && (!strncmp(type, "text/", 5) || strstr(type, "xml"))) {
    CHARSET charset = TtaGetDocumentCharset(docid);
    if (charset != UNDEFINED_CHARSET)
      cs = TtaGetCharsetName(charset);
  }
  if (cs && *cs && !strstr(type, "charset="))
    snprintf(ct, sizeof(ct), "Content-Type: %s; charset=%s", type, cs);
  else
    snprintf(ct, sizeof(ct), "Content-Type: %s", type);
  me->req_headers = curl_slist_append(me->req_headers, ct);
  /* no "Expect: 100-continue": some servers handle it badly */
  me->req_headers = curl_slist_append(me->req_headers, "Expect:");
  curl_easy_setopt(easy, CURLOPT_HTTPHEADER, me->req_headers);

  CURLMcode mc = curl_multi_add_handle(s_curlm, easy);
  if (mc != CURLM_OK) {
    AHTReqContext_delete(me);
    return HT_ERROR;
  }

  me->reqStatus = HT_BUSY;
  get_or_create_docid_status(docid)->counter++;
  pending_add(me);
  if (event_loop()) event_loop()->Start();

  /* the save code checks the result right after the call */
  if ((mode & AMAYA_SYNC) || (mode & AMAYA_ISYNC))
    return wait_for_request(me, docid);

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
      if (me->output) { fclose(me->output); me->output = NULL; }
      AHTDocId_Status *ds = GetDocIdStatus(me->docid, s_doc_list);
      if (ds && ds->counter > 0) ds->counter--;
      if (me->sync_done) {
        *me->sync_done = TRUE;
        if (me->sync_status) *me->sync_status = HT_INTERRUPTED;
      }
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

  /* TLS: user's trusted certificates; slot for per-connection data */
  {
    const char *home = TtaGetEnvString("APP_HOME");
    if (home && home[0] != EOS)
      snprintf(s_trusted_file, sizeof(s_trusted_file), "%s%ctrusted-certs.pem",
               home, DIR_SEP);
    if (s_tls_ex_index < 0)
      s_tls_ex_index = SSL_CTX_get_ex_new_index(0, NULL, NULL, NULL, NULL);
  }

  /* cookies: one store for all transfers (Amaya is single-threaded) */
  TtaSetEnvBoolean("ENABLE_COOKIES", TRUE, FALSE);
  TtaGetEnvBoolean("ENABLE_COOKIES", &s_cookies);
  if (s_cookies) {
    s_share = curl_share_init();
    if (s_share) {
      curl_share_setopt(s_share, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
      cookies_load();
    }
  }

  /* Register our poll function with the wx event loop */
  if (event_loop()) event_loop()->SetCurlPoll(AmayaCurlPoll, CURL_POLL_MS);
}

void QueryClose(void)
{
  if (!s_curlm) return;
  if (event_loop()) event_loop()->ClearCurlPoll();

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
  if (s_share) {
    cookies_save();
    curl_share_cleanup(s_share);
    s_share = NULL;
  }
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
