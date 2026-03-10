#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${1:-$ROOT_DIR/.venv-no-torch}"
MODE="${2:-runtime}"

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip setuptools wheel

# Install mlx-whisper without upstream's torch dependency, then install the
# runtime stack we actually exercise in Muesli.
python -m pip install --no-deps "mlx-whisper==0.4.3"
python -m pip install -r "$ROOT_DIR/requirements-no-torch.txt"

if [[ "$MODE" == "dev" ]]; then
  python -m pip install -r "$ROOT_DIR/requirements-no-torch-dev.txt"
fi

python - <<'PY'
import importlib.util

has_torch = importlib.util.find_spec("torch") is not None
print(f"[setup_no_torch_env] torch installed: {has_torch}")
if has_torch:
    raise SystemExit("torch is present in the no-torch environment")
PY

echo "[setup_no_torch_env] ready: $VENV_DIR"
