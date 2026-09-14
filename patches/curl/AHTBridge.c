/*
 * amaya/AHTBridge.c  --  Phase 3 libcurl replacement
 *
 * The original AHTBridge.c bridged libwww's event-driven socket I/O to
 * the wx event loop via wxAmayaSocketEvent.  With libcurl + multi the
 * bridge is just the periodic poll in query.c (AmayaCurlPoll).
 * This file is a stub that satisfies the linker.
 */

#include "thot_sys.h"
#include "amaya.h"
#include "AHTReqContext_curl.h"

/* AHTBridge_f.h prototypes */

void AHTEvent_handler(void)           {}  /* replaced by AmayaCurlPoll */
int  AHTEvent_register(int sock, int type, void *event)
{
  (void)sock; (void)type; (void)event;
  return 0;
}
int  AHTEvent_unregister(int sock, int type)
{
  (void)sock; (void)type;
  return 0;
}
