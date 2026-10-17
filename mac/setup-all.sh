#!/bin/bash
# One-step setup: status line + menu-bar app.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/install.sh"
bash "$DIR/build-menubar.sh"
