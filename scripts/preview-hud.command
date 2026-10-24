#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
exec "$task_root/dist/Tess.app/Contents/MacOS/Tess" --hud-preview
