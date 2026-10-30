#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
task_output="${1:-$task_root/.build/verification/hud-layout}"
mkdir -p "$task_output" .build/verification/checks .build/cache/CheckModuleCache
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  Tess/Sources/HUDView.swift Tess/Sources/Design/SettingsTheme.swift Tess/Sources/Design/TessBrand.swift \
  Tess/Sources/Design/TessIconMotion.swift Tess/Checks/HUDLayoutCheck.swift -o .build/verification/checks/hud-layout-check
.build/verification/checks/hud-layout-check "$task_output"
