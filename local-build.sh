#!/bin/bash
# Local replica of .github/workflows/build-bpi-r4-deploy.yml using Docker.
#
#   ./local-build.sh [standard|wired|pro|pro-wired]     (default: standard)
#
# Runs the same builder script the workflow runs, with the same pinned
# versions (build-versions.env; override with OPENWRT_COMMIT / MTK_COMMIT in
# the environment, like the workflow_dispatch inputs). The build happens in
# local-build/<variant>/ — a staged copy of the repo — so the checkout itself
# stays clean. Needs ~50 GB free disk and takes a few hours.
#
# Images land in:   local-build/<variant>/openwrt/bin/targets/mediatek/filogic/
# Release layout:   ./local-release.sh <variant>   (same packaging as the
#                                                   workflow's release step)
set -euo pipefail

VARIANT="${1:-standard}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${REPO_DIR}/local-build/${VARIANT}"
IMAGE_TAG="bpi-r4-deploy-builder"

# Same variant -> builder mapping as the workflow's "Set build variables".
case "$VARIANT" in
  standard)  BUILDER=builder-wifimgr-universal.sh ;;
  wired)     BUILDER=builder-wired-universal.sh ;;
  pro)       BUILDER=builder-pro-8x.sh ;;
  pro-wired) BUILDER=builder-pro-8x-wired.sh ;;
  *) echo "usage: $0 [standard|wired|pro|pro-wired]" >&2; exit 1 ;;
esac

# 1. Builder image (same deps as the workflow's ubuntu-22.04 step).
docker build -t "$IMAGE_TAG" \
  --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
  "$REPO_DIR/docker"

# 2. Pinned versions, exactly like the workflow's "Load build versions" step;
#    host environment overrides win (the workflow_dispatch inputs analogue).
ENV_ARGS=()
while IFS= read -r line; do
  ENV_ARGS+=( -e "$line" )
done < <(grep -v '^\s*#' "$REPO_DIR/build-versions.env" | grep -v '^\s*$')
[ -n "${OPENWRT_COMMIT:-}" ] && ENV_ARGS+=( -e "OPENWRT_COMMIT=$OPENWRT_COMMIT" )
[ -n "${MTK_COMMIT:-}" ]     && ENV_ARGS+=( -e "MTK_COMMIT=$MTK_COMMIT" )

# 3. Stage a fresh repo copy (the workflow starts from a clean checkout; the
#    builder recreates openwrt/ and mtk-openwrt-feeds/ itself).
mkdir -p "$WORK_DIR"
rsync -a --delete \
  --exclude /.git --exclude /local-build \
  --exclude /openwrt --exclude /mtk-openwrt-feeds \
  "$REPO_DIR/" "$WORK_DIR/"

# 4. Run the builder — the same two lines the workflow's "Run builder script"
#    step executes.
docker run --rm --init \
  -v "$WORK_DIR":/work \
  "${ENV_ARGS[@]}" \
  "$IMAGE_TAG" \
  bash -c "chmod +x ./$BUILDER && ./$BUILDER"

echo
echo "Build finished."
echo "Images: $WORK_DIR/openwrt/bin/targets/mediatek/filogic/"
echo "Release layout: ./local-release.sh $VARIANT"
