#!/usr/bin/env bash
# Reconstruct one or more trees from a TreeScanPL10k LAZ plot.
#
# Usage:
#   ./run_tree.sh <input.laz> <tree_id> [tree_id ...] [--out <output_dir>]
#
# Examples:
#   ./run_tree.sh plot.laz 1
#   ./run_tree.sh plot.laz 1 2 5 --out /my/results

set -euo pipefail

DOCKER_IMAGE="ghcr.io/csiro-robotics/raycloudtools:latest"
PREP="$(dirname "$0")/prep_laz.py"
BASE_OUT="$(dirname "$0")/results"

# ── parse arguments ───────────────────────────────────────────────────────────
if [ $# -lt 2 ]; then
  echo "Usage: $0 <input.laz> <tree_id> [tree_id ...] [--out <dir>]"
  exit 1
fi

INPUT_LAZ="$1"; shift
TREE_IDS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) BASE_OUT="$2"; shift 2 ;;
    *)     TREE_IDS+=("$1"); shift ;;
  esac
done

PLOT_NAME=$(basename "$INPUT_LAZ" .laz)

# ── process each tree ─────────────────────────────────────────────────────────
for TREE_ID in "${TREE_IDS[@]}"; do
  OUT_DIR="$BASE_OUT/$PLOT_NAME/tree_$TREE_ID"
  mkdir -p "$OUT_DIR"

  echo "=== [$TREE_ID] Plot: $PLOT_NAME  →  $OUT_DIR"

  echo "  [1/5] Converting LAZ..."
  python3 "$PREP" "$INPUT_LAZ" "$OUT_DIR/tree.laz" --tree_id "$TREE_ID"

  echo "  [2/5] Importing to ray cloud..."
  docker run --rm --network host \
    -v "$OUT_DIR":/workspace -w /workspace "$DOCKER_IMAGE" \
    rayimport tree.laz 0,0,0

  echo "  [3/5] Extracting terrain..."
  docker run --rm --network host \
    -v "$OUT_DIR":/workspace -w /workspace "$DOCKER_IMAGE" \
    rayextract terrain tree.ply

  echo "  [4/5] Reconstructing tree structure..."
  docker run --rm --network host \
    -v "$OUT_DIR":/workspace -w /workspace "$DOCKER_IMAGE" \
    rayextract trees tree.ply tree_mesh.ply

  echo "  [5/5] Computing stats..."
  docker run --rm --network host \
    -v "$OUT_DIR":/workspace -w /workspace "$DOCKER_IMAGE" \
    treeinfo tree_trees.txt --crop_length 1

  sudo chown -R "$USER:$USER" "$OUT_DIR"
  echo "  Done → $OUT_DIR"
  echo
done
