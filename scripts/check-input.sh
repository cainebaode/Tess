#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
# Compile the actual model identifier enum without loading the ASR dependencies.
python3 - <<'PY'
from pathlib import Path
source = Path("Tess/Sources/ASRService.swift").read_text()
model_enum = source[source.index("enum ASRModel:"):source.index("\nenum ASRModelState:")]
Path(".build/verification/checks/ASRModel.swift").write_text("import Foundation\n" + model_enum)
PY
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  .build/verification/checks/ASRModel.swift Tess/Sources/Localization.swift Tess/Sources/SpeechLearning.swift Tess/Sources/SpeechInputObservation.swift \
  Tess/Sources/HotkeyService.swift Tess/Sources/DeliveryService.swift \
  Tess/Sources/TextService.swift Tess/Sources/SpeechVocabulary.swift Tess/Sources/APIConfiguration.swift Tess/Sources/LocalStore.swift \
  Tess/Checks/InputCheck.swift -o .build/verification/checks/input-check
.build/verification/checks/input-check
