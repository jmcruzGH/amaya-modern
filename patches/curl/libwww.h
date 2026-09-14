/*
 * libwww.h -- Phase 3 replacement
 *
 * The original libwww.h pulled in all of W3C libwww headers (wwwsys.h,
 * WWWLib.h, HTReqMan.h etc.).  These are no longer available; libwww has
 * been replaced by libcurl.
 *
 * This stub provides the minimal type definitions that amaya/ source files
 * expect when they include "libwww.h".  The full AHTReqContext is defined
 * in AHTReqContext_curl.h (installed by patches/generate-curl-sources.sh).
 */
#ifndef AMAYA_LIBWWW_H
#define AMAYA_LIBWWW_H

/* Minimal socket/select constants used in a few non-network files */
#ifndef _WINSOCKAPI_
#define FD_READ    0x01
#define FD_WRITE   0x02
#define FD_OOB     0x04
#define FD_ACCEPT  0x08
#define FD_CONNECT 0x10
#define FD_CLOSE   0x20
#endif
typedef unsigned long ms_t;

/* Include libcurl-based request context (replaces libwww types) */
#ifdef AMAYA_WITH_CURL
#  include "AHTReqContext_curl.h"
#else
/* Forward declarations for files that only use pointers to these types */
typedef struct _HTRequest  HTRequest;
typedef struct _HTResponse HTResponse;
#ifndef HTLIST_STRUCT_DEFINED
#define HTLIST_STRUCT_DEFINED
typedef struct _HTList     HTList;
struct _HTList     { void *object; struct _HTList *next; };
#endif
#ifndef HTREQUEST_STRUCT_DEFINED
#define HTREQUEST_STRUCT_DEFINED
struct _HTRequest  { int dummy; };
#endif
#ifndef HTRESPONSE_STRUCT_DEFINED
#define HTRESPONSE_STRUCT_DEFINED
struct _HTResponse { int dummy; };
#endif
#ifndef HT_STATUS_DEFINED
#define HT_STATUS_DEFINED
typedef enum { HT_OK = 0, HT_ERROR = -1, HT_INTERRUPTED = -2 } HTStatusCode;
#endif

/* AHTReqContext forward -- defined fully in AHTReqContext_curl.h */
typedef struct _AHTReqContext AHTReqContext;

/* AHTDocId_Status -- tracks active request count per document */
#ifndef AHTDOCID_STATUS_DEFINED
#define AHTDOCID_STATUS_DEFINED
typedef struct {
  int  docid;
  int  counter;
} AHTDocId_Status;
#endif

/* HTAlertOpcode used in answer.c stubs */
typedef int HTAlertOpcode;
typedef void HTAlertPar;
#endif /* AMAYA_WITH_CURL */

/* Global variables formerly declared in libwww.h */
#ifndef MAX_LENGTH
#  define MAX_LENGTH 800
#endif
#ifdef __cplusplus
extern "C" {
#endif
extern char AmayaLastHTTPErrorMsg[2*MAX_LENGTH];
#ifdef __cplusplus
}
#endif

#endif /* AMAYA_LIBWWW_H */
