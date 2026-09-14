/*
 * amaya/AHTFWrite.c  --  Phase 3 stub
 *
 * The original provided a libwww HTStream that wrote to a file.
 * In the libcurl build, write_to_file_cb() in query.c handles this.
 */
#include "thot_sys.h"
/* AHTFWrite_f.h exports AHTFWriter_new -- not called outside AHTInit.c */
void *AHTFWriter_new(void *request, void *target, ThotBool append)
{
  (void)request; (void)target; (void)append;
  return NULL;
}
