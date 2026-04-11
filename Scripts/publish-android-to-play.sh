#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: publish-android-to-play.sh --package-name <package> --track <track> --bundle-file <path> --release-name <name> --version-code <code>

Required environment:
  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64
EOF
}

PACKAGE_NAME=""
TRACK=""
BUNDLE_FILE=""
RELEASE_NAME=""
VERSION_CODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-name)
      PACKAGE_NAME="${2:-}"
      shift 2
      ;;
    --track)
      TRACK="${2:-}"
      shift 2
      ;;
    --bundle-file)
      BUNDLE_FILE="${2:-}"
      shift 2
      ;;
    --release-name)
      RELEASE_NAME="${2:-}"
      shift 2
      ;;
    --version-code)
      VERSION_CODE="${2:-}"
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

if [[ -z "$PACKAGE_NAME" || -z "$TRACK" || -z "$BUNDLE_FILE" || -z "$RELEASE_NAME" || -z "$VERSION_CODE" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$BUNDLE_FILE" ]]; then
  print -u2 -- "Bundle file not found: $BUNDLE_FILE"
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

PACKAGE_NAME="$PACKAGE_NAME" \
TRACK="$TRACK" \
BUNDLE_FILE="$BUNDLE_FILE" \
RELEASE_NAME="$RELEASE_NAME" \
VERSION_CODE="$VERSION_CODE" \
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
import urllib.error


def b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def build_token(service_account: dict) -> str:
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
    request = urllib.request.Request(
        service_account["token_uri"],
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read())["access_token"]


class ApiHttpError(RuntimeError):
    def __init__(self, method: str, url: str, status_code: int, reason: str, body: str):
        message = f"{method} {url} failed: {status_code} {reason}"
        if body.strip():
            message = f"{message}\n{body}"
        super().__init__(message)
        self.method = method
        self.url = url
        self.status_code = status_code
        self.reason = reason
        self.body = body


def api_json(token: str, method: str, url: str, data=None, content_type: str = "application/json"):
    payload = data
    if data is not None and isinstance(data, (dict, list)):
        payload = json.dumps(data).encode()
    request = urllib.request.Request(
        url,
        data=payload,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": content_type,
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise ApiHttpError(method, url, exc.code, exc.reason, body) from exc


service_account = json.loads(pathlib.Path(os.environ["SERVICE_ACCOUNT_JSON"]).read_text())
package_name = os.environ["PACKAGE_NAME"]
track = os.environ["TRACK"]
bundle_path = pathlib.Path(os.environ["BUNDLE_FILE"])
release_name = os.environ["RELEASE_NAME"]
version_code = int(os.environ["VERSION_CODE"])

token = build_token(service_account)
edit = api_json(
    token,
    "POST",
    f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits",
    data={},
)

try:
    upload_request = urllib.request.Request(
        (
            "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/"
            f"applications/{package_name}/edits/{edit['id']}/bundles?uploadType=media"
        ),
        data=bundle_path.read_bytes(),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/octet-stream",
        },
    )
    with urllib.request.urlopen(upload_request) as response:
        bundle_response = json.loads(response.read())

    uploaded_version_code = int(bundle_response["versionCode"])
    if uploaded_version_code != version_code:
        raise RuntimeError(
            f"Play reported versionCode {uploaded_version_code}, expected {version_code}."
        )

    track_payload = {
        "releases": [
            {
                "name": release_name,
                "status": "completed",
                "versionCodes": [str(uploaded_version_code)],
            }
        ]
    }

    try:
        api_json(
            token,
            "PUT",
            f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits/{edit['id']}/tracks/{track}",
            data=track_payload,
        )
        release_status = "completed"
    except ApiHttpError as exc:
        if "Only releases with status draft may be created on draft app" not in exc.body:
            raise
        track_payload["releases"][0]["status"] = "draft"
        api_json(
            token,
            "PUT",
            f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits/{edit['id']}/tracks/{track}",
            data=track_payload,
        )
        release_status = "draft"

    commit_url = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits/{edit['id']}:commit"
    try:
        api_json(
            token,
            "POST",
            commit_url,
        )
    except ApiHttpError as exc:
        if exc.status_code != 400 or "changesNotSentForReview" not in exc.body:
            raise
        api_json(
            token,
            "POST",
            f"{commit_url}?changesNotSentForReview=true",
        )
finally:
    try:
        api_json(
            token,
            "DELETE",
            f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package_name}/edits/{edit['id']}",
        )
    except Exception:
        pass

print(f"Published {package_name} versionCode {version_code} to {track} with status {release_status}.")
PY
