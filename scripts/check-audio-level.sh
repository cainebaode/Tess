#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/checks
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/checks/ModuleCache \
  Tess/Sources/AudioLevelMeter.swift Tess/Checks/AudioLevelCheck.swift -o .build/checks/audio-level-check
.build/checks/audio-level-check
