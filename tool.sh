#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_URL="https://github.com/pterodactyl/wings"
BASE_COMMIT="ac814095055e999aa60c2cd1aac7f6ac45ee1742"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_OVERRIDE=""

REPO_ROOT=""
SOURCE_DIR=""
PATCH_DIR=""

log() {
    printf '[tool] %s\n' "$*"
}

die() {
    printf '[tool] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage:
  ./tool.sh [--repo-root /path/to/repo] <command> [args...]

Commands:
  info
      Show repo paths, upstream URL, pinned base commit, and source git status.

  list
      List patches/*.patch in filename order.

  init
      Clone source repo if missing and configure upstream remote.

  fetch [ref]
      Fetch upstream (or a specific ref) into source.

  sync [ref] [--force]
      Fetch and checkout source to ref (default: BASE_COMMIT).
      --force will hard reset and clean untracked files in source.

  apply <patch-file-or-name>
      Apply one patch to source using git apply --3way.

  apply-all
      Apply all patches/*.patch in filename order.

  check [patch-file-or-name]
      Run git apply --check for one patch or all patches.

  gen [name]
      Generate a patch from current source working tree changes (git diff HEAD).
      Output defaults to patches/NNNN-local-changes.patch

  gen-from-base [name] [base-ref]
      Generate patch from base-ref..HEAD (default base-ref is BASE_COMMIT).

  gen-commit <commit> [name]
      Generate patch from a specific commit using git format-patch -1 --stdout.

  refresh [ref] [--force]
      Equivalent to: sync [ref] [--force] + apply-all

Examples:
  ./tool.sh info
  ./tool.sh sync
  ./tool.sh sync develop --force
  ./tool.sh apply 0001-some-change.patch
  ./tool.sh apply-all
  ./tool.sh gen my-change
  ./tool.sh gen-from-base my-feature
  ./tool.sh gen-commit HEAD
USAGE
}

resolve_context() {
    if [[ -n "$REPO_ROOT_OVERRIDE" ]]; then
        [[ -d "$REPO_ROOT_OVERRIDE" ]] || die "repo root does not exist: $REPO_ROOT_OVERRIDE"
        REPO_ROOT="$(cd "$REPO_ROOT_OVERRIDE" && pwd)"
    else
        REPO_ROOT="$SCRIPT_DIR"
    fi

    SOURCE_DIR="$REPO_ROOT/source"
    PATCH_DIR="$REPO_ROOT/patches"
}

ensure_dirs() {
    mkdir -p "$PATCH_DIR"
}

ensure_source_exists() {
    if [[ -d "$SOURCE_DIR/.git" ]]; then
        return 0
    fi

    log "source repo missing, cloning $UPSTREAM_URL -> $SOURCE_DIR"
    git clone --filter=blob:none "$UPSTREAM_URL" "$SOURCE_DIR"
}

configure_upstream_remote() {
    if git -C "$SOURCE_DIR" remote get-url upstream >/dev/null 2>&1; then
        git -C "$SOURCE_DIR" remote set-url upstream "$UPSTREAM_URL"
    else
        git -C "$SOURCE_DIR" remote add upstream "$UPSTREAM_URL"
    fi

    if ! git -C "$SOURCE_DIR" remote get-url origin >/dev/null 2>&1; then
        git -C "$SOURCE_DIR" remote add origin "$UPSTREAM_URL"
    fi
}

require_clean_source_tree() {
    if ! git -C "$SOURCE_DIR" diff --quiet || ! git -C "$SOURCE_DIR" diff --cached --quiet; then
        die "source has tracked changes; commit/stash/reset first, or use --force for sync."
    fi

    if [[ -n "$(git -C "$SOURCE_DIR" ls-files --others --exclude-standard)" ]]; then
        die "source has untracked files; clean them first, or use --force for sync."
    fi
}

fetch_upstream() {
    local ref="${1:-}"
    if [[ -n "$ref" ]]; then
        log "fetch upstream ref: $ref"
        git -C "$SOURCE_DIR" fetch --prune upstream "$ref"
    else
        log "fetch upstream"
        git -C "$SOURCE_DIR" fetch --prune upstream
    fi
}

resolve_source_ref() {
    local ref="${1:-}"
    [[ -n "$ref" ]] || die "missing ref"

    if git -C "$SOURCE_DIR" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null; then
        echo "$ref"
        return 0
    fi

    if git -C "$SOURCE_DIR" rev-parse --verify --quiet "upstream/${ref}^{commit}" >/dev/null; then
        echo "upstream/$ref"
        return 0
    fi

    die "could not resolve ref: $ref"
}

resolve_patch_path() {
    local patch_arg="${1:-}"
    local path

    [[ -n "$patch_arg" ]] || die "missing patch name/path"

    if [[ -f "$patch_arg" ]]; then
        path="$patch_arg"
    elif [[ -f "$PATCH_DIR/$patch_arg" ]]; then
        path="$PATCH_DIR/$patch_arg"
    else
        die "patch not found: $patch_arg"
    fi

    echo "$path"
}

slugify() {
    local input="${1:-local-changes}"
    echo "$input" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

next_patch_path() {
    local slug="${1:-local-changes}"
    local last_num next_num

    last_num="$({
        find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' -printf '%f\n' \
            | sed -nE 's/^([0-9]{4})-.+\.patch$/\1/p' \
            | sort -n \
            | tail -n1
    } || true)"

    if [[ -z "$last_num" ]]; then
        next_num="0001"
    else
        next_num="$(printf '%04d' "$((10#$last_num + 1))")"
    fi

    echo "$PATCH_DIR/${next_num}-$(slugify "$slug").patch"
}

cmd_info() {
    local repo_name
    repo_name="$(basename "$REPO_ROOT")"

    log "repo:           $repo_name"
    log "repo root:      $REPO_ROOT"
    log "source dir:     $SOURCE_DIR"
    log "patch dir:      $PATCH_DIR"
    log "upstream url:   $UPSTREAM_URL"
    log "base commit:    $BASE_COMMIT"

    if [[ -d "$SOURCE_DIR/.git" ]]; then
        log "source HEAD:    $(git -C "$SOURCE_DIR" rev-parse --short HEAD)"
        log "source branch:  $(git -C "$SOURCE_DIR" rev-parse --abbrev-ref HEAD)"
        log "source status:"
        git -C "$SOURCE_DIR" status --short || true
    else
        log "source repo:    missing (run: ./tool.sh init)"
    fi
}

cmd_list() {
    ensure_dirs

    local found=0 patch_path
    while IFS= read -r patch_path; do
        found=1
        echo "$(basename "$patch_path")"
    done < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | sort)

    if [[ "$found" -eq 0 ]]; then
        log "no patch files found in $PATCH_DIR"
    fi
}

cmd_init() {
    ensure_source_exists
    configure_upstream_remote
    log "initialized"
}

cmd_fetch() {
    ensure_source_exists
    configure_upstream_remote
    fetch_upstream "${1:-}"
}

cmd_sync() {
    local ref="" resolved_ref="" force=0 arg

    for arg in "$@"; do
        if [[ "$arg" == "--force" ]]; then
            force=1
        elif [[ -z "$ref" ]]; then
            ref="$arg"
        else
            die "unexpected argument: $arg"
        fi
    done

    [[ -n "$ref" ]] || ref="$BASE_COMMIT"

    ensure_source_exists
    configure_upstream_remote
    fetch_upstream
    resolved_ref="$(resolve_source_ref "$ref")"

    if [[ "$force" -eq 1 ]]; then
        log "force-clean source tree"
        git -C "$SOURCE_DIR" reset --hard
        git -C "$SOURCE_DIR" clean -fd
    else
        require_clean_source_tree
    fi

    log "checkout source to: $resolved_ref"
    git -C "$SOURCE_DIR" checkout -B patch-base "$resolved_ref"
    git -C "$SOURCE_DIR" reset --hard "$resolved_ref"
}

cmd_apply() {
    ensure_source_exists

    local patch_path
    patch_path="$(resolve_patch_path "${1:-}")"

    log "applying patch: $(basename "$patch_path")"
    git -C "$SOURCE_DIR" apply --3way --whitespace=nowarn "$patch_path"
}

cmd_apply_all() {
    ensure_source_exists

    local patches=() patch_path
    while IFS= read -r patch_path; do
        patches+=("$patch_path")
    done < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | sort)

    if [[ "${#patches[@]}" -eq 0 ]]; then
        log "no patch files found in $PATCH_DIR"
        return 0
    fi

    for patch_path in "${patches[@]}"; do
        log "applying patch: $(basename "$patch_path")"
        git -C "$SOURCE_DIR" apply --3way --whitespace=nowarn "$patch_path"
    done
}

cmd_check() {
    ensure_source_exists

    if [[ $# -gt 0 ]]; then
        local patch_path
        patch_path="$(resolve_patch_path "$1")"
        log "checking patch: $(basename "$patch_path")"
        git -C "$SOURCE_DIR" apply --check "$patch_path"
        return 0
    fi

    local patch_path
    while IFS= read -r patch_path; do
        log "checking patch: $(basename "$patch_path")"
        git -C "$SOURCE_DIR" apply --check "$patch_path"
    done < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | sort)
}

cmd_gen() {
    ensure_source_exists
    ensure_dirs

    local out_path
    if [[ $# -gt 0 ]]; then
        if [[ "$1" == *.patch ]]; then
            out_path="$PATCH_DIR/$1"
        else
            out_path="$(next_patch_path "$1")"
        fi
    else
        out_path="$(next_patch_path "local-changes")"
    fi

    if git -C "$SOURCE_DIR" diff --quiet HEAD --; then
        die "no changes in source (vs HEAD) to generate a patch"
    fi

    log "generating patch from source working tree -> $out_path"
    git -C "$SOURCE_DIR" diff --binary HEAD -- > "$out_path"
}

cmd_gen_from_base() {
    ensure_source_exists
    ensure_dirs

    local name="${1:-local-changes-from-base}"
    local base_ref="${2:-$BASE_COMMIT}"
    local resolved_base_ref out_path

    if [[ "$name" == *.patch ]]; then
        out_path="$PATCH_DIR/$name"
    else
        out_path="$(next_patch_path "$name")"
    fi

    resolved_base_ref="$(resolve_source_ref "$base_ref")"

    log "generating patch from range ${resolved_base_ref}..HEAD -> $out_path"
    git -C "$SOURCE_DIR" diff --binary "${resolved_base_ref}..HEAD" -- > "$out_path"
}

cmd_gen_commit() {
    ensure_source_exists
    ensure_dirs

    local commit="${1:-}"
    local name="${2:-}"
    local out_path

    [[ -n "$commit" ]] || die "missing commit for gen-commit"

    if [[ -z "$name" ]]; then
        local subject
        subject="$(git -C "$SOURCE_DIR" show -s --format=%s "$commit")"
        out_path="$(next_patch_path "$subject")"
    elif [[ "$name" == *.patch ]]; then
        out_path="$PATCH_DIR/$name"
    else
        out_path="$(next_patch_path "$name")"
    fi

    log "generating patch from commit ${commit} -> $out_path"
    git -C "$SOURCE_DIR" format-patch -1 "$commit" --stdout > "$out_path"
}

cmd_refresh() {
    cmd_sync "$@"
    cmd_apply_all
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo-root)
                shift
                [[ $# -gt 0 ]] || die "missing value for --repo-root"
                REPO_ROOT_OVERRIDE="$1"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
        shift
    done

    local cmd="${1:-help}"
    if [[ $# -gt 0 ]]; then
        shift
    fi

    if [[ "$cmd" == "help" ]]; then
        usage
        exit 0
    fi

    resolve_context

    case "$cmd" in
        info) cmd_info "$@" ;;
        list) cmd_list "$@" ;;
        init) cmd_init "$@" ;;
        fetch) cmd_fetch "$@" ;;
        sync) cmd_sync "$@" ;;
        apply) cmd_apply "$@" ;;
        apply-all) cmd_apply_all "$@" ;;
        check) cmd_check "$@" ;;
        gen) cmd_gen "$@" ;;
        gen-from-base) cmd_gen_from_base "$@" ;;
        gen-commit) cmd_gen_commit "$@" ;;
        refresh) cmd_refresh "$@" ;;
        *)
            die "unknown command: $cmd"
            ;;
    esac
}

main "$@"
