#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
# Keep value types/gesture logic current, without linking native permission or device services.
python3 - <<'PY'
from pathlib import Path
source = Path("Tess/Sources")
def section(file, start, end):
    text = (source / file).read_text()
    return text[text.index(start):text.index(end)]
types = [
    "import AppKit\nimport Carbon\nimport Foundation\n",
    section("ASRService.swift", "enum ASRModel:", "\nenum ASRModelState:"),
    section("AudioRecorder.swift", "struct RecordedAudio:", "\nstruct AudioInputDevice:"),
    section("HotkeyService.swift", "enum ShortcutAction:", "\n@MainActor @Observable final class HotkeyService"),
    (source / "HotkeyService.swift").read_text().split("struct RecordKeyGesture {", 1)[1],
    section("HUDView.swift", "enum HUDPhase:", "\n/// One presentation"),
    section("SettingsView.swift", "enum SettingsSection:", "\nprivate struct ShortcutRecorder:"),
]
types[4] = "struct RecordKeyGesture {" + types[4]
Path(".build/verification/checks/InteractionTypes.swift").write_text("\n".join(types))
PY
xcrun swiftc -D TESS_INTERNAL_CHECKS -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  .build/verification/checks/InteractionTypes.swift Tess/Sources/Localization.swift \
  Tess/Sources/AppModel.swift Tess/Sources/LocalStore.swift Tess/Sources/APIConfiguration.swift Tess/Sources/TextService.swift \
  Tess/Checks/InteractionCheck.swift -o .build/verification/checks/interaction-check
.build/verification/checks/interaction-check
