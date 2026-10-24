#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  Tess/Sources/LocalStore.swift Tess/Sources/TextService.swift Tess/Sources/APIConfiguration.swift \
  Tess/Checks/StorageCheck.swift -o .build/verification/checks/storage-check
.build/verification/checks/storage-check
