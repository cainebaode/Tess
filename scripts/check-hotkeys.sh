#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/hotkeys .build/cache/HotkeyModuleCache
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/HotkeyModuleCache \
  Tess/Sources/HotkeyService.swift Tess/Checks/HotkeyCheck.swift -o .build/verification/hotkeys/hotkey-check
.build/verification/hotkeys/hotkey-check
