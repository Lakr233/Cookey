# Android Release Signing

Cookey uses a Play App Signing friendly setup:

- Keep the real upload keystore out of git.
- Load signing values from either `Frontend/Android/keystore.properties` or CI environment variables.
- Use the generated upload key when creating Play releases.

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

For GitHub Actions, store these repository secrets:

- `ANDROID_UPLOAD_KEYSTORE_BASE64`
- `ANDROID_UPLOAD_STORE_PASSWORD`
- `ANDROID_UPLOAD_KEY_ALIAS`
- `ANDROID_UPLOAD_KEY_PASSWORD`

For GitHub Actions, the common pattern is:

- Store the `.jks` file as a Base64 secret.
- Decode it into a temporary file in the workflow.
- Export the four variables above before calling Gradle.

Example command to produce the Base64 payload locally:

```bash
base64 < Frontend/Android/.signing/cookey-upload.jks | tr -d '\n'
```
