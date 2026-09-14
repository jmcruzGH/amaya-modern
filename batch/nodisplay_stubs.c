/*
 * batch/nodisplay_stubs.c
 *
 * Stub implementations of display-dependent symbols required to link
 * the batch 'app' schema compiler without the full thotlib display stack.
 *
 * These are never called during schema compilation -- they exist only to
 * satisfy the linker when structlist.c, tree.c, etc. reference presentation
 * and view functions that are not compiled in NODISPLAY mode.
 *
 * Generated for amaya-modern Phase 1.
 * (c) 2026 J. Magalhães Cruz <jmcruz@fe.up.pt> -- FEUP
 */

#include "thot_sys.h"
#include "constmedia.h"
#include "typemedia.h"

/* ── Text buffer operations (content.c) ─────────────────────────────── */

PtrTextBuffer NewTextBuffer(PtrTextBuffer pBuf)
{ (void)pBuf; return NULL; }

void CreateTextBuffer(PtrElement pEl)
{ (void)pEl; }

void DeleteTextBuffer(PtrTextBuffer *pBuf)
{ (void)pBuf; }

PtrTextBuffer CopyText(PtrTextBuffer pBuf, PtrElement pEl)
{ (void)pBuf; (void)pEl; return NULL; }

void CopyTextToText(PtrTextBuffer pSrceBuf, PtrTextBuffer pDstBuf)
{ (void)pSrceBuf; (void)pDstBuf; }

void ClearText(PtrTextBuffer pBuf)
{ (void)pBuf; }

int CopyBuffer2MBs(PtrTextBuffer pBuf, int pos, unsigned char *des, int max)
{ (void)pBuf; (void)pos; (void)des; (void)max; return 0; }

void CopyStringToBuffer(unsigned char *src, PtrTextBuffer *pBuf, int *index)
{ (void)src; (void)pBuf; (void)index; }

ThotBool StringAndTextEqual(const char *text, PtrTextBuffer pBuf)
{ (void)text; (void)pBuf; return FALSE; }

/* ── Path operations (content.c) ────────────────────────────────────── */

PtrPathSeg CopyPath(PtrPathSeg firstPathEl)
{ (void)firstPathEl; return NULL; }

/* ── Schema loading (schemas.c / document.c) ────────────────────────── */







/* ── Document identity (document.c) ─────────────────────────────────── */

int IdentDocument(PtrDocument pDoc)
{ (void)pDoc; return 0; }

/* ── Presentation schema (presentation/) ───────────────────────────── */


void SearchPresSchema(PtrElement pEl, PtrPSchema *pSPR,
                      int *viewNb, PtrSSchema *pSSR,
                      PtrDocument pDoc)
{ (void)pEl; (void)pSPR; (void)viewNb; (void)pSSR; (void)pDoc; }

int AppliedView(PtrElement pEl, PtrAttribute pAttr,
                PtrDocument pDoc, int view)
{ (void)pEl; (void)pAttr; (void)pDoc; (void)view; return 0; }

void ApplyPresRules(PtrElement pEl, PtrDocument pDoc,
                    int viewNb, ThotBool specif,
                    PtrPSchema pSPR, PtrSSchema pSSR)
{ (void)pEl; (void)pDoc; (void)viewNb; (void)specif; (void)pSPR; (void)pSSR; }

PtrHandlePSchema FirstPSchemaExtension(PtrSSchema pSS, PtrDocument pDoc,
                                        PtrElement pEl)
{ (void)pSS; (void)pDoc; (void)pEl; return NULL; }

void PRuleToPresentationSetting(PtrPRule rule, PtrElement pEl,
                                 PtrDocument pDoc, void *setting)
{ (void)rule; (void)pEl; (void)pDoc; (void)setting; }

void TtaPToCss(void *settings, char *buffer, int len,
               Element el, void *pSchP)
{ (void)settings; (void)buffer; (void)len; (void)el; (void)pSchP; }

/* ── View / box layout (view/) ──────────────────────────────────────── */

char *AbsBoxType(PtrAbstractBox pAb, ThotBool withClass)
{ (void)pAb; (void)withClass; return (char*)""; }

void GetExtraMargins(PtrBox pBox, PtrDocument pDoc,
                     ThotBool inLine, int *top, int *bottom,
                     int *left, int *right)
{ (void)pBox; (void)pDoc; (void)inLine;
  *top = *bottom = *left = *right = 0; }

/* ── Selection (editing/) ───────────────────────────────────────────── */

void TtaGiveFirstSelectedElement(Document document,
                                  Element *selectedElement,
                                  int *firstCharacter,
                                  int *lastCharacter)
{ (void)document;
  if (selectedElement) *selectedElement = NULL;
  if (firstCharacter)  *firstCharacter  = 0;
  if (lastCharacter)   *lastCharacter   = 0; }

/* ── Application event system (appstruct.h) ────────────────────────── */

void TteConnectAction(int id, Proc procedure)
{ (void)id; (void)procedure; }

/* ── Namespace handling (tree/) ─────────────────────────────────────── */




/* ── System exit (registry.c) ───────────────────────────────────────── */

void ThotExit(int result)
{
  exit(result);
}
