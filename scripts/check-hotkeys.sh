#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/hotkey-check
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/hotkey-check/ModuleCache \
  Tess/Sources/HotkeyService.swift Tess/Checks/HotkeyCheck.swift -o .build/hotkey-check/hotkey-check
.build/hotkey-check/hotkey-check
