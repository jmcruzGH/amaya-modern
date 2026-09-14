/*
 * amaya/answer.c  --  Phase 3 libcurl replacement
 *
 * The original answer.c provided libwww alert/progress/error callbacks.
 * In the libcurl build these are handled inline in query.c.
 * This file provides stub symbols for the prototypes in answer_f.h.
 */

#include "thot_sys.h"
#include "amaya.h"
#include "AHTReqContext_curl.h"

/* answer_f.h prototypes -- all stubs */

/* HTRequest* / HTResponse* are opaque in Phase 3 */
typedef struct _HTRequest  HTRequest;
typedef struct _HTResponse HTResponse;

/* Progress -- called by libwww during transfer; not needed with libcurl */
int AHTProgress(HTRequest *request, HTAlertOpcode op, int msgnum,
                const char *dfault, void *input, HTAlertPar *reply)
{
  (void)request; (void)op; (void)msgnum;
  (void)dfault; (void)input; (void)reply;
  return TRUE;
}

int AHTConfirm(HTRequest *request, HTAlertOpcode op, int msgnum,
               const char *dfault, void *input, HTAlertPar *reply)
{
  (void)request; (void)op; (void)msgnum;
  (void)dfault; (void)input; (void)reply;
  return TRUE;
}

int AHTPrompt(HTRequest *request, HTAlertOpcode op, int msgnum,
              const char *dfault, void *input, HTAlertPar *reply)
{
  (void)request; (void)op; (void)msgnum;
  (void)dfault; (void)input; (void)reply;
  return TRUE;
}

int AHTPromptUsernameAndPassword(HTRequest *request, HTAlertOpcode op,
                                  int msgnum, const char *dfault,
                                  void *input, HTAlertPar *reply)
{
  /* TODO Phase 4: show wx authentication dialog */
  (void)request; (void)op; (void)msgnum;
  (void)dfault; (void)input; (void)reply;
  return FALSE;  /* cancel auth for now */
}

int AHTError_print(HTRequest *request, HTAlertOpcode op, int msgnum,
                   const char *dfault, void *input, HTAlertPar *reply)
{
  (void)request; (void)op; (void)msgnum;
  (void)dfault; (void)input; (void)reply;
  return TRUE;
}

void AHTError_MemPrint(HTRequest *request)
{
  (void)request;
}

ThotBool IsHTTP09Error(HTRequest *request)
{
  (void)request;
  return FALSE;
}

void AHTPrintPendingRequestStatus(Document docid, ThotBool cancel)
{
  (void)docid; (void)cancel;
}

void PrintTerminateStatus(AHTReqContext *me, int status)
{
  (void)me; (void)status;
}
