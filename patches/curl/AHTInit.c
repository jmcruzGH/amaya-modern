/*
 * amaya/AHTInit.c  --  Phase 3 libcurl replacement
 *
 * The original AHTInit.c set up the libwww protocol stack, converters,
 * transports, and alert callbacks.  With libcurl that infrastructure is
 * built into the library; this file just provides the stub symbols that
 * the rest of amaya expects.
 */

#include "thot_sys.h"
#include "amaya.h"
#include "AHTReqContext_curl.h"

/* All the HTXxxInit / HTXxxInit functions that amaya/init.c calls via
 * AHTInit.h are no-ops in the libcurl build.  We provide them as empty
 * functions so the linker is satisfied. */

void HTConverterInit         (HTList *c)  { (void)c; }
void HTPresenterInit         (HTList *c)  { (void)c; }
void HTFormatInit            (HTList *c)  { (void)c; }
void HTTransferEncoderInit   (HTList *c)  { (void)c; }
void HTContentEncoderInit    (HTList *c)  { (void)c; }
void HTBeforeInit            (void)       {}
void HTAfterInit             (void)       {}
void HTAAInit                (void)       {}
void HTNetInit               (void)       {}
void HTAlertInit             (void)       {}
void HTTransportInit         (void)       {}
void HTProtocolInit          (void)       {}
void HTProtocolPreemptiveInit(void)       {}
void HTIconInit              (const char *url_prefix) { (void)url_prefix; }
void HTMIMEInit              (void)       {}

/* AHTSSLInit -- Phase 3 is HTTP-only; HTTPS added later */
void AHTSSLInit(void) {}
void AHTSSLClose(void) {}

/* HTRequest/HTResponse stubs -- the libcurl query.c doesn't use these types
 * but the prototype headers reference them.  Provide minimal structs. */
/* These structs are also defined in libwww.h -- guard to avoid redefinition */
#ifndef HTREQUEST_STRUCT_DEFINED
#define HTREQUEST_STRUCT_DEFINED
struct _HTRequest  { int dummy; };
#endif
#ifndef HTRESPONSE_STRUCT_DEFINED
#define HTRESPONSE_STRUCT_DEFINED
struct _HTResponse { int dummy; };
#endif
