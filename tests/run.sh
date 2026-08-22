#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/tests/test-backend.sh"
"$ROOT/tests/test-hotplug.sh"
"$ROOT/tests/test-lifecycle.sh"
python3 "$ROOT/tests/test-package.py"
