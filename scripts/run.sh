#!/bin/zsh
# Build the Debug app with xcodebuild and launch it. Regenerates the project if project.yml is newer.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d Deskpouch.xcodeproj || project.yml -nt Deskpouch.xcodeproj/project.pbxproj ]]; then
  xcodegen generate
fi
xcodebuild -scheme Deskpouch -configuration Debug -derivedDataPath build/DerivedData build | grep -E "error|warning: |BUILD" || true
APP=build/DerivedData/Build/Products/Debug/Deskpouch.app
pkill -x Deskpouch || true
open "$APP"
echo "launched $APP"
