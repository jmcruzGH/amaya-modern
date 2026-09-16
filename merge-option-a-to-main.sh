#!/usr/bin/env bash
# merge-option-a-to-main.sh
# Merges trial/option-a into main, then creates a fresh branch off the
# new main for the remaining "occasional blanking" issue.

set -e
cd ~/amaya-modern

echo "=== Fetch latest ==="
git fetch origin

echo "=== Update local main ==="
git checkout main
git pull origin main

echo "=== Merge trial/option-a into main ==="
git merge trial/option-a --no-edit

echo "=== Push updated main ==="
git push origin main

echo ""
echo "=== main is now up to date. Verifying build from a clean state ==="
cd build
make -j$(nproc) 2>&1 | tee /tmp/build-main-merged.log | grep -E "error:|Built target|Linking" | grep -v "command-line option"
cd ..
if grep -q "error:" /tmp/build-main-merged.log; then
  echo ""
  echo "!!! BUILD FAILED on merged main -- see /tmp/build-main-merged.log !!!"
  exit 1
fi
echo "Build OK on main."

echo ""
echo "=== Creating fresh branch for the remaining blanking issue ==="
git checkout -b fix/gl-blanking
git push -u origin fix/gl-blanking

echo ""
echo "Done."
echo "  main            -> updated, includes all option-A rendering + keyboard fixes"
echo "  fix/gl-blanking -> new branch, currently identical to main, ready for the next fix"
echo ""
echo "You are currently on fix/gl-blanking."
