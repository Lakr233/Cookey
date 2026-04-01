#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_ROOT="$PWD"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"
ARCHIVE_ROOT=""
RAW_TAG=""
RELEASE_VERSION=""
STAGE="all"
SKIP_NOTARIZE=false
PRESERVE_KEYCHAIN_STATE="${PRESERVE_KEYCHAIN_STATE:-}"
ORIGINAL_DEFAULT_KEYCHAIN=""
ORIGINAL_KEYCHAINS=()

usage() {
    cat <<'EOF'
Usage: bash Scripts/build-release.sh --tag <tag> [options]

Options:
  --tag <tag>               Git tag or ref name, for example 2.2.0 or v2.2.0.
  --archive-root <path>     Output directory. Default: build/releases/<tag>
  --stage <name>            all, build-cli, package-cli, sign-cli, notarize-cli
  --keychain-profile <name> Override the auto-detected notarytool keychain profile.
  --skip-notarize           Skip notarization.
  --help, -h                Show this help.
EOF
}

log() {
    echo "==> $*"
}

run_and_log_status() {
    local label="$1"
    shift

    "$@"
    local status=$?
    echo "==> ${label} exit status: ${status}"
    return "$status"
}

log_kv() {
    echo "    $1: $2"
}

fail() {
    echo "Error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

capture_original_keychain_state() {
    local line

    ORIGINAL_DEFAULT_KEYCHAIN="$(security default-keychain -d user 2>/dev/null | sed 's/^ *"//; s/"$//')"
    while IFS= read -r line; do
        line="$(sed 's/^ *"//; s/"$//' <<<"$line")"
        [[ -n "$line" ]] && ORIGINAL_KEYCHAINS+=("$line")
    done < <(security list-keychains -d user 2>/dev/null || true)
}

restore_original_keychain_state() {
    [[ "$PRESERVE_KEYCHAIN_STATE" == "1" ]] && return

    if [[ -n "$ORIGINAL_DEFAULT_KEYCHAIN" ]]; then
        security default-keychain -d user -s "$ORIGINAL_DEFAULT_KEYCHAIN" >/dev/null 2>&1 || true
    fi

    if [[ "${#ORIGINAL_KEYCHAINS[@]}" -gt 0 ]]; then
        security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
    fi
}

load_keychain_secret_from_zshrc_if_needed() {
    if [[ -n "${KEYCHAIN_SECRET:-}" ]]; then
        return
    fi

    command -v zsh >/dev/null 2>&1 || return

    local tmp_file
    tmp_file="$(mktemp "${TMPDIR:-/tmp}/cookey-ci-keychain-secret.XXXXXX")"
    chmod 600 "$tmp_file"

    zsh -lc '
        source ~/.zshrc >/dev/null 2>&1 || true
        umask 077
        [[ -n "${KEYCHAIN_SECRET:-}" ]] && printf "%s" "$KEYCHAIN_SECRET" > "$1"
    ' zsh "$tmp_file"

    if [[ -s "$tmp_file" ]]; then
        KEYCHAIN_SECRET="$(<"$tmp_file")"
    fi

    rm -f "$tmp_file"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tag)
                RAW_TAG="${2:-}"
                shift 2
                ;;
            --archive-root)
                ARCHIVE_ROOT="${2:-}"
                shift 2
                ;;
            --stage)
                STAGE="${2:-}"
                shift 2
                ;;
            --keychain-profile)
                KEYCHAIN_PROFILE="${2:-}"
                shift 2
                ;;
            --skip-notarize)
                SKIP_NOTARIZE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
}

normalize_tag_version() {
    local raw="$1"
    raw="${raw#refs/tags/}"
    raw="${raw#v}"
    [[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid tag '$1'. Expected x.y.z or vX.Y.Z."
    echo "$raw"
}

ensure_signing_context() {
    if [[ -n "${SIGNING_IDENTITY:-}" && -n "${DEVELOPMENT_TEAM:-}" && -n "${KEYCHAIN_PATH:-}" && -n "${KEYCHAIN_PROFILE:-}" ]]; then
        log "Using signing context from environment"
        return
    fi

    local env_file
    env_file="$(mktemp "${TMPDIR:-/tmp}/cookey-release-env.XXXXXX")"
    trap 'rm -f "$env_file"' RETURN

    bash Scripts/setup-ci-keychain.sh --env-file "$env_file" --keychain-profile "$KEYCHAIN_PROFILE"
    # shellcheck disable=SC1090
    source "$env_file"

    [[ -n "${SIGNING_IDENTITY:-}" ]] || fail "SIGNING_IDENTITY was not detected."
    [[ -n "${DEVELOPMENT_TEAM:-}" ]] || fail "DEVELOPMENT_TEAM was not detected."
    [[ -n "${KEYCHAIN_PATH:-}" ]] || fail "KEYCHAIN_PATH was not detected."
    [[ -n "${KEYCHAIN_PROFILE:-}" ]] || fail "KEYCHAIN_PROFILE was not detected."
}

ensure_keychain_unlocked() {
    [[ -n "${KEYCHAIN_PATH:-}" ]] || fail "KEYCHAIN_PATH is not set."

    load_keychain_secret_from_zshrc_if_needed
    [[ -n "${KEYCHAIN_SECRET:-}" ]] || fail "KEYCHAIN_SECRET is required to unlock the signing keychain before signing."

    log "Setting signing keychain as default for build step"
    run_and_log_status "security default-keychain" security default-keychain -d user -s "$KEYCHAIN_PATH"

    log "Unlocking signing keychain for build step"
    run_and_log_status "security unlock-keychain" security unlock-keychain -p "$KEYCHAIN_SECRET" "$KEYCHAIN_PATH"
    run_and_log_status "security set-keychain-settings" security set-keychain-settings -t 3600 -u "$KEYCHAIN_PATH"
    run_and_log_status "security set-key-partition-list" security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_SECRET" "$KEYCHAIN_PATH"
}

print_signing_context() {
    log "Signing context"
    log_kv "signing_identity" "${SIGNING_IDENTITY:-<unset>}"
    log_kv "development_team" "${DEVELOPMENT_TEAM:-<unset>}"
    log_kv "keychain_path" "${KEYCHAIN_PATH:-<unset>}"
    log_kv "keychain_profile" "${KEYCHAIN_PROFILE:-<unset>}"
    security find-identity -v -p codesigning "${KEYCHAIN_PATH:-}" 2>/dev/null || true
}

build_universal_cli() {
    log "Building arm64 CLI"
    swift build -c release --product cookey --package-path CLI --arch arm64
    local arm64_bin
    arm64_bin="$(swift build -c release --product cookey --package-path CLI --arch arm64 --show-bin-path)/cookey"
    [[ -f "$arm64_bin" ]] || fail "arm64 binary not found at $arm64_bin"

    log "Building x86_64 CLI"
    swift build -c release --product cookey --package-path CLI --arch x86_64
    local x86_bin
    x86_bin="$(swift build -c release --product cookey --package-path CLI --arch x86_64 --show-bin-path)/cookey"
    [[ -f "$x86_bin" ]] || fail "x86_64 binary not found at $x86_bin"

    mkdir -p "$(dirname "$CLI_BINARY")"
    lipo -create "$arm64_bin" "$x86_bin" -output "$CLI_BINARY"
    chmod 755 "$CLI_BINARY"
    lipo -info "$CLI_BINARY"
}

sign_cli() {
    local cli_binary="$1"

    chmod 755 "$cli_binary"
    [[ -x "$cli_binary" ]] || fail "CLI binary is not executable: $cli_binary"

    log "Signing CLI binary"
    print_signing_context
    codesign \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp \
        --verbose=4 \
        --force \
        "$cli_binary"

    log "Verifying CLI signature"
    codesign --verify --verbose=2 "$cli_binary"
}

package_cli_zip() {
    local cli_binary="$1"
    local cli_zip="$2"

    rm -f "$cli_zip"
    ditto -c -k --keepParent "$cli_binary" "$cli_zip"
}

notarize_file() {
    local artifact="$1"
    local description="$2"

    if [[ "$SKIP_NOTARIZE" == "true" ]]; then
        log "Skipping notarization for $description"
        return
    fi

    log "Submitting $description for notarization"
    xcrun notarytool submit "$artifact" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait
}

init_release_paths() {
    CLI_BUILD_DIR="$ARCHIVE_ROOT/build-cli"
    CLI_BINARY="$CLI_BUILD_DIR/cookey"
    CLI_UNSIGNED_DIR="$ARCHIVE_ROOT/unsigned-cli"
    CLI_UNSIGNED_BINARY="$CLI_UNSIGNED_DIR/cookey"
    CLI_ZIP="$ARCHIVE_ROOT/cookey-${RELEASE_VERSION}-macOS-cli.zip"
}

run_stage() {
    case "$STAGE" in
        build-cli)
            build_universal_cli
            ;;
        package-cli)
            [[ -f "$CLI_BINARY" ]] || fail "CLI binary not found at $CLI_BINARY"
            mkdir -p "$CLI_UNSIGNED_DIR"
            cp "$CLI_BINARY" "$CLI_UNSIGNED_BINARY"
            chmod 755 "$CLI_UNSIGNED_BINARY"
            log "Prepared unsigned CLI binary at $CLI_UNSIGNED_BINARY"
            ;;
        sign-cli)
            ensure_signing_context
            ensure_keychain_unlocked
            [[ -f "$CLI_UNSIGNED_BINARY" ]] || fail "Unsigned CLI binary not found at $CLI_UNSIGNED_BINARY"
            sign_cli "$CLI_UNSIGNED_BINARY"
            package_cli_zip "$CLI_UNSIGNED_BINARY" "$CLI_ZIP"
            ;;
        notarize-cli)
            ensure_signing_context
            [[ -f "$CLI_ZIP" ]] || fail "CLI archive not found at $CLI_ZIP"
            notarize_file "$CLI_ZIP" "CLI archive"
            ;;
        all)
            STAGE="build-cli"
            run_stage
            STAGE="package-cli"
            run_stage
            STAGE="sign-cli"
            run_stage
            STAGE="notarize-cli"
            run_stage
            ;;
        *)
            fail "Unknown stage '$STAGE'"
            ;;
    esac
}

parse_args "$@"

[[ -n "$RAW_TAG" ]] || fail "--tag is required."
RELEASE_VERSION="$(normalize_tag_version "$RAW_TAG")"
RAW_TAG="${RAW_TAG#refs/tags/}"

if [[ -z "$ARCHIVE_ROOT" ]]; then
    ARCHIVE_ROOT="$PROJECT_ROOT/build/releases/$RAW_TAG"
fi

require_command bash
require_command swift
require_command ditto
require_command lipo
require_command codesign
require_command xcrun
require_command security

mkdir -p "$ARCHIVE_ROOT"
capture_original_keychain_state
trap restore_original_keychain_state EXIT

init_release_paths
run_stage
