#!/usr/bin/env bash

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/pterodactyl/wings}"
UPSTREAM_REF="${UPSTREAM_REF:-}"
DATE_OVERRIDE="${DATE_OVERRIDE:-}"
PATCH_DIR="${PATCH_DIR:-$GITHUB_WORKSPACE/patches}"
WORK_DIR="${WORK_DIR:-$RUNNER_TEMP/wings-src}"
DIST_DIR="${DIST_DIR:-$GITHUB_WORKSPACE/dist}"

rm -rf "$WORK_DIR"
git clone --filter=blob:none "$UPSTREAM_URL" "$WORK_DIR"

if [[ -n "$UPSTREAM_REF" ]]; then
  git -C "$WORK_DIR" fetch --force origin "$UPSTREAM_REF"
  git -C "$WORK_DIR" checkout --force FETCH_HEAD
fi

cd "$WORK_DIR"

BASE_VERSION="$(sed -nE 's/^## v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' CHANGELOG.md | head -n1)"
if [[ -z "$BASE_VERSION" ]]; then
  echo "Failed to parse base version from CHANGELOG.md" >&2
  exit 1
fi

if [[ -n "$DATE_OVERRIDE" ]]; then
  if [[ ! "$DATE_OVERRIDE" =~ ^[0-9]{8}$ ]]; then
    echo "DATE_OVERRIDE must be in YYYYMMDD format" >&2
    exit 1
  fi
  RELEASE_DATE="$DATE_OVERRIDE"
else
  RELEASE_DATE="$(date -u +%Y%m%d)"
fi

RELEASE_TAG="v${BASE_VERSION}-${RELEASE_DATE}"
EMBED_VERSION="${BASE_VERSION}-${RELEASE_DATE}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "base_version=${BASE_VERSION}"
    echo "release_date=${RELEASE_DATE}"
    echo "release_tag=${RELEASE_TAG}"
    echo "embed_version=${EMBED_VERSION}"
  } >> "$GITHUB_OUTPUT"
fi

if [[ -d "$PATCH_DIR" ]]; then
  shopt -s nullglob
  patch_files=("$PATCH_DIR"/*.patch)
  shopt -u nullglob

  if (( ${#patch_files[@]} == 0 )); then
    echo "No patch files found in $PATCH_DIR; continuing without patch application."
  fi

  for patch in "${patch_files[@]}"; do
    if [[ ! -s "$patch" ]]; then
      echo "Skipping empty patch file: $patch"
      continue
    fi

    echo "Applying patch: $(basename "$patch")"
    git apply --whitespace=nowarn "$patch"
  done
else
  echo "Patch directory $PATCH_DIR does not exist; continuing without patch application."
fi

mkdir -p "$DIST_DIR"

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
go build \
  -o "$DIST_DIR/wings_linux_amd64" \
  -trimpath \
  -ldflags="-s -w -X github.com/pterodactyl/wings/system.Version=${EMBED_VERSION}" \
  github.com/pterodactyl/wings

chmod 755 "$DIST_DIR/wings_linux_amd64"

(cd "$DIST_DIR" && sha256sum wings_linux_amd64 > SHA256SUMS)

echo "Built release artifact for tag: $RELEASE_TAG"
