#!/bin/zsh

set -euo pipefail

log() {
  print -r -- "==> $*"
}

usage() {
  cat <<'EOF'
Usage: resolve-android-version.sh --package-name <package> --version-name <name> [--output-file <path>]

Required environment:
  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64
EOF
}

PACKAGE_NAME=""
VERSION_NAME=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-name)
      PACKAGE_NAME="${2:-}"
      shift 2
      ;;
    --version-name)
      VERSION_NAME="${2:-}"
      shift 2
      ;;
    --output-file)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 -- "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PACKAGE_NAME" || -z "$VERSION_NAME" ]]; then
  usage
  exit 1
fi

if [[ -z "${GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64:-}" ]]; then
  print -u2 -- "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 is required."
  exit 1
fi

SERVICE_ACCOUNT_JSON="$(mktemp)"
trap 'rm -f "$SERVICE_ACCOUNT_JSON"' EXIT

python3 <<'PY' > "$SERVICE_ACCOUNT_JSON"
import base64
import os
import sys

sys.stdout.buffer.write(base64.b64decode(os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64"]))
PY

PYTHON_OUTPUT="$(
  PACKAGE_NAME="$PACKAGE_NAME" \
  VERSION_NAME="$VERSION_NAME" \
  SERVICE_ACCOUNT_JSON="$SERVICE_ACCOUNT_JSON" \
  python3 <<'PY'
import base64
import json
import os
import pathlib
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request


def b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


service_account = json.loads(pathlib.Path(os.environ["SERVICE_ACCOUNT_JSON"]).read_text())
package_name = os.environ["PACKAGE_NAME"]
version_name = os.environ["VERSION_NAME"]

now = int(time.time())
header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
payload = b64url(
    json.dumps(
        {
            "iss": service_account["client_email"],
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": service_account["token_uri"],
            "iat": now,
            "exp": now + 3600,
        },
        separators=(",", ":"),
    ).encode()
)
message = header + b"." + payload

with tempfile.NamedTemporaryFile("w", delete=False) as key_file:
    key_file.write(service_account["private_key"])
    key_path = key_file.name

try:
    signature = subprocess.check_output(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=message,
    )
finally:
    os.unlink(key_path)

assertion = (message + b"." + b64url(signature)).decode()
body = urllib.parse.urlencode(
    {
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion,
    }
).encode()
token_request = urllib.request.Request(
    service_account["token_uri"],
    data=body,
    headers={"Content-Type": "application/x-www-form-urlencoded"},
)
with urllib.request.urlopen(token_request) as resp:
    token = json.loads(resp.read())["access_token"]

def api_json(method: str, url: str, data=None):
    if data is not None and isinstance(data, (dict, list)):
        data = json.dumps(data).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        return json.loads(body) if body else None


edit = api_json(
    "POST",
    f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits",
    data={},
)
try:
    tracks = api_json(
        "GET",
        f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits/{edit['id']}/tracks",
    )

    max_version_code = 0
    for track in tracks.get("tracks", []):
        for release in track.get("releases", []):
            for version_code in release.get("versionCodes", []):
                max_version_code = max(max_version_code, int(version_code))
finally:
    try:
        api_json(
            "DELETE",
            f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits/{edit['id']}",
        )
    except Exception:
        pass

print(f"current_max_version_code={max_version_code}")
print(f"next_version_code={max_version_code + 1}")
print(f"version_name={version_name}")
PY
)"

CURRENT_MAX_VERSION_CODE="$(print -r -- "$PYTHON_OUTPUT" | awk -F= '/^current_max_version_code=/{print $2}')"
NEXT_VERSION_CODE="$(print -r -- "$PYTHON_OUTPUT" | awk -F= '/^next_version_code=/{print $2}')"

log "Latest Play versionCode: ${CURRENT_MAX_VERSION_CODE}"
log "Next Android versionCode: ${NEXT_VERSION_CODE}"
log "Android versionName: ${VERSION_NAME}"

if [[ -n "$OUTPUT_FILE" ]]; then
  {
    print -r -- "current_max_version_code=${CURRENT_MAX_VERSION_CODE}"
    print -r -- "version_code=${NEXT_VERSION_CODE}"
    print -r -- "version_name=${VERSION_NAME}"
  } >> "$OUTPUT_FILE"
else
  print -r -- "current_max_version_code=${CURRENT_MAX_VERSION_CODE}"
  print -r -- "version_code=${NEXT_VERSION_CODE}"
  print -r -- "version_name=${VERSION_NAME}"
fi
