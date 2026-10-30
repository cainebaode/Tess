#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  Tess/Sources/LocalStore.swift Tess/Sources/TextService.swift Tess/Sources/APIConfiguration.swift Tess/Sources/SpeechVocabulary.swift \
  Tess/Checks/SpeechCorrectionCheck.swift -o .build/verification/checks/speech-correction-check
task_endpoint=$(mktemp -t tess-check-endpoint)
python3 Tess/Checks/text_service_fixture.py "$task_endpoint" &
task_server=$!
trap 'kill "$task_server" 2>/dev/null || true; rm -f "$task_endpoint"' EXIT
for task_attempt in {1..50}; do
  [[ -s "$task_endpoint" ]] && break
  sleep 0.1
done
[[ -s "$task_endpoint" ]]
TESS_TEST_TEXT_URL="$(cat "$task_endpoint")" .build/verification/checks/speech-correction-check
