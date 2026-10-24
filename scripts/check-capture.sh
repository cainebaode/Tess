#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/checks
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/checks/ModuleCache \
  Tess/Sources/ScreenshotSelection.swift Tess/Sources/CaptureService.swift Tess/Checks/CaptureCheck.swift -o .build/checks/capture-check
.build/checks/capture-check
