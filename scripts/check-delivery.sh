#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/checks
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/checks/ModuleCache \
  Tess/Sources/DeliveryService.swift Tess/Checks/DeliveryCheck.swift -o .build/checks/delivery-check
.build/checks/delivery-check
