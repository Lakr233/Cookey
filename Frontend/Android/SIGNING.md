# Android Release Signing

Cookey uses a Play App Signing friendly setup:

- Keep the real upload keystore out of git.
- Load signing values from either `Frontend/Android/keystore.properties` or CI environment variables.
- Use the generated upload key when creating Play releases.
- Resolve the next Android `versionCode` from Google Play before building a release bundle.

## Local setup

1. Copy `Frontend/Android/keystore.properties.example` to `Frontend/Android/keystore.properties`.
2. Fill in:
   - `storeFile`
   - `storePassword`
   - `keyAlias`
   - `keyPassword`
3. Place the keystore at the path referenced by `storeFile`.
4. Build with:

```bash
cd Frontend/Android
./gradlew bundleRelease
```

## CI setup

Provide these environment variables:

- `COOKEY_UPLOAD_STORE_FILE`
- `COOKEY_UPLOAD_STORE_PASSWORD`
- `COOKEY_UPLOAD_KEY_ALIAS`
- `COOKEY_UPLOAD_KEY_PASSWORD`
- `COOKEY_VERSION_CODE` (optional override)
- `COOKEY_VERSION_NAME` (optional override)

For GitHub Actions, store these repository secrets:

- `ANDROID_UPLOAD_KEYSTORE_BASE64`
- `ANDROID_UPLOAD_STORE_PASSWORD`
- `ANDROID_UPLOAD_KEY_ALIAS`
- `ANDROID_UPLOAD_KEY_PASSWORD`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64`

For GitHub Actions, the common pattern is:

- Store the `.jks` file as a Base64 secret.
- Decode it into a temporary file in the workflow.
- Export the four variables above before calling Gradle.
- Grant the Play service account access to the app and `Release apps to testing tracks` so CI can query the latest published `versionCode`.
- The release workflow strips the leading `v` from the Git tag for `versionName`, then sets `versionCode` to `max(existing Play versionCodes) + 1`.
- The release workflow uploads the signed `.aab` to the Google Play `internal` track after storing both the `.apk` and `.aab` in GitHub Actions artifacts.

Example command to produce the Base64 payload locally:

```bash
base64 < Frontend/Android/.signing/cookey-upload.jks | tr -d '\n'
```
