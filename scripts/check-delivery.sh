#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  Tess/Sources/DeliveryService.swift Tess/Sources/SpeechInputObservation.swift Tess/Checks/DeliveryCheck.swift -o .build/verification/checks/delivery-check
.build/verification/checks/delivery-check
