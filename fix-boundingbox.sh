#!/usr/bin/env bash
# fix-boundingbox.sh
# Run from ~/amaya-modern.
# Robust version: finds each function by its signature line, then its
# matching closing brace via brace-counting, rather than matching the
# whole function body as exact text (which kept failing on whitespace
# differences). Replaces ComputeBoundingBox and ComputeFilledBox in
# thotlib/view/glbox.c -- both still called raw OpenGL functions
# (glRenderMode, glFeedbackBuffer, glGetIntegerv) with no GL context
# at all now that AmayaCanvas is wxPanel-based, which is undefined
# behaviour and the likely cause of both the "only first element ever
# renders" bug and the intermittent crashes. Replaces both with the
# safe, direct BxClip computation from the box's own known position --
# the same fix applied during Option A's fix/gl-blanking work, which
# this branch's history never included.

set -e
cd ~/amaya-modern

python3 - << 'PYEOF'
path = 'thotlib/view/glbox.c'
with open(path) as f:
    lines = f.readlines()

def find_fn_range(lines, sig_start_text):
    matches = [i for i, l in enumerate(lines) if l.startswith(sig_start_text)]
    assert len(matches) == 1, f"expected 1 match for {sig_start_text!r}, found {len(matches)}"
    sig_line = matches[0]
    brace_line = None
    for j in range(sig_line, sig_line + 6):
        if lines[j].strip() == '{':
            brace_line = j
            break
    assert brace_line is not None, f"could not find opening brace for {sig_start_text!r}"
    depth = 0
    end_line = None
    for k in range(brace_line, len(lines)):
        depth += lines[k].count('{') - lines[k].count('}')
        if depth == 0 and k > brace_line:
            end_line = k
            break
    assert end_line is not None, f"could not find matching closing brace for {sig_start_text!r}"
    return sig_line, end_line

# --- ComputeBoundingBox ---
sig1, end1 = find_fn_range(lines, 'void ComputeBoundingBox (PtrBox box, int frame, int xmin, int xmax,')
new1 = '''void ComputeBoundingBox (PtrBox box, int frame, int xmin, int xmax, 
                        int ymin, int ymax)
{
  /* Option B: AmayaCanvas no longer has a GL context at all (the
   * wxGLCanvas -> wxPanel switch), so the glRenderMode/glFeedbackBuffer
   * calls this function used to make are undefined behaviour now --
   * no current GL context to operate on. Confirmed as the cause of a
   * real bug, not just dead code: a short test document only ever
   * showed its very first element (direct diagnostic logging showed
   * every single redraw, across many separate repaints, drawing only
   * that element), which fits exactly -- every OTHER box's
   * BxClipX/Y/W/H either came from undefined GL behaviour or, in
   * ComputeFilledBox's case below, was never set at all. This always
   * takes the safe, direct fallback the original code already used
   * for the "box not displayed via feedback" case, unconditionally --
   * the same fix applied during Option A's fix/gl-blanking work,
   * which this branch's history never included. */
  ViewFrame *pFrame = &ViewFrameTable[frame - 1];
  (void) xmin; (void) xmax; (void) ymin; (void) ymax;
  box->BxClipX = box->BxXOrg - (pFrame->FrXOrg?pFrame->FrXOrg:pFrame->OldFrXOrg);
  box->BxClipY = box->BxYOrg - (pFrame->FrYOrg?pFrame->FrYOrg:pFrame->OldFrYOrg);
  box->BxClipW = box->BxW;
  box->BxClipH = box->BxH;
  box->BxBoundinBoxComputed = TRUE;
}
'''
lines[sig1:end1+1] = [new1]
print(f"  ComputeBoundingBox: replaced lines {sig1+1}-{end1+1}")

# Re-find ComputeFilledBox since line numbers shifted after the first replace
sig2, end2 = find_fn_range(lines, 'void ComputeFilledBox (PtrBox box, int frame, int xmin, int xmax,')
new2 = '''void ComputeFilledBox (PtrBox box, int frame, int xmin, int xmax,
                      int ymin, int ymax, ThotBool show_bgimage)
{
  /* Option B: same fix as ComputeBoundingBox above -- see its comment.
   * This one is worse unfixed: there was no fallback at all here, so
   * BxClipX/Y/W/H were simply never set once the GL feedback stopped
   * ever returning anything. */
  ViewFrame *pFrame = &ViewFrameTable[frame - 1];
  (void) xmin; (void) xmax; (void) ymin; (void) ymax; (void) show_bgimage;
  box->BxClipX = box->BxXOrg - (pFrame->FrXOrg?pFrame->FrXOrg:pFrame->OldFrXOrg);
  box->BxClipY = box->BxYOrg - (pFrame->FrYOrg?pFrame->FrYOrg:pFrame->OldFrYOrg);
  box->BxClipW = box->BxW;
  box->BxClipH = box->BxH;
  box->BxBoundinBoxComputed = TRUE;
}
'''
lines[sig2:end2+1] = [new2]
print(f"  ComputeFilledBox: replaced lines {sig2+1}-{end2+1}")

with open(path, 'w') as f:
    f.writelines(lines)
print("OK: both functions fixed")
PYEOF

echo ""
echo "=== Rebuild ==="
cd build
make -j1 2>&1 | tee /tmp/build-boundingbox-fix2.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..

if grep -qE "error:|undefined reference" /tmp/build-boundingbox-fix2.log; then
  echo ""
  echo "!!! BUILD FAILED -- see /tmp/build-boundingbox-fix2.log !!!"
  exit 1
fi

echo ""
echo "=== Build succeeded ==="
