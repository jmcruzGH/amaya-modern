/*
 * Stubs for the translation-schema compiler (amaya_tra_compiler).
 * The shared thotlib sources it is built from refer to these display and
 * editing functions, which the compiler never calls.
 */
#include "thot_gui.h"
#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"
#include "style.h"
#include "content.h"
#include "content_f.h"
#include "boxrelations_f.h"
#include "style_f.h"
#include "createabsbox_f.h"

void CopyStringToBuffer (unsigned char *src, PtrTextBuffer pDestBuf, int *length)
{ *length = 0; }
void CopyTextToText (PtrTextBuffer pSrceBuf, PtrTextBuffer pCopyBuf, int *len)
{ *len = 0; }
void *TtaCopyAnim (void *src) { return NULL; }
void *TtaCopyTransform (void *void_pPa) { return NULL; }
void GetExtraMargins (PtrBox pBox, int frame, ThotBool blockMargin,
                      int *t, int *b, int *l, int *r)
{ *t = *b = *l = *r = 0; }
void PRuleToPresentationSetting (PtrPRule rule, PresentationSetting setting,
                                 PtrPSchema pPS) {}
void TtaPToCss (PresentationSetting settings, char *buffer, int len,
                Element el, void* pSchP)
{ if (len > 0) buffer[0] = EOS; }
void ApplyPresRules (PtrElement pEl, PtrDocument pDoc, DocViewNumber viewNb,
                     int viewSch, PtrSSchema pSchS, PtrPSchema pSchP,
                     PtrPRule *pRSpec, PtrPRule *pRDef,
                     PtrAbstractBox *pAbbReturn, ThotBool forward, int *lqueue,
                     void* rQueue, PtrAbstractBox pNewAbbox, void* CSScasc,
                     FILE *fileDescriptor, ThotBool pseudoElOnly) {}
