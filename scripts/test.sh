#!/bin/zsh
# Runs every package's tests. Exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/../Packages"
for package in DeskpouchCore DeskpouchCapture ToolScreenRecorder ToolScreenshot ToolColor ToolVoice; do
  echo "== $package"
  swift test --package-path "$package"
done
