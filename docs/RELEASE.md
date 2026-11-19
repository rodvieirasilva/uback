# UBack Release Process

Follow this checklist whenever cutting a new version of UBack Mobile.

## 1. Bump the Version
Update `version:` in [mobile/pubspec.yaml](../mobile/pubspec.yaml) using Semantic Versioning + incrementing Android build number:
```yaml
version: 1.1.0+2
```
- The version label displayed in the app UI (`UBack vX.Y.Z+N`) reads directly from Android's `PackageInfo` (and compile-time `UBACK_APP_VERSION` parsed by [scripts/parse_config.py](../scripts/parse_config.py)).

## 2. Run Full Verification Suite
```bash
mise run analyze
mise run test
mise run test-e2e
```
All static checks, unit/widget tests, and Android Emulator E2E tests (including real SMB2 SHA-256 read-back verification and Crop Mode cleanup) must pass with zero errors.

## 3. Refresh App Screenshots ("Prints")
Regenerate the Dark and Light mode screenshots in `docs/screenshots/` using clean demo NAS settings (never your private `config.toml` credentials):
```bash
mise run screenshots
```
This updates:
- `docs/screenshots/home-dark.png`
- `docs/screenshots/home-light.png`
- `docs/screenshots/settings-dark.png`
- `docs/screenshots/settings-light.png`

Inspect the updated screenshots and verify the new version label appears cleanly in both Dark and Light themes.

## 4. Commit Release Changes
```bash
git status
# Double-check config.toml and dart_defines.json are NOT staged
git add mobile/pubspec.yaml docs/screenshots/
git commit -m "Release v1.1.0"
git push origin main
```

## 5. Build & Deploy to Physical Device (Wireless ADB)
Ensure your local gitignored `config.toml` has your NAS defaults, then build and install the release APK onto your Samsung phone:
```bash
mise run deploy-release
```

## 6. Tag & Publish GitHub Release (Automated via Release CI)
Pushing a matching `vX.Y.Z` tag automatically triggers [.github/workflows/release.yml](../.github/workflows/release.yml), which verifies the tag against `mobile/pubspec.yaml`, runs `analyze` + `test`, builds a clean release APK with zero baked secrets, generates a `.sha256` checksum, and publishes the GitHub Release:
```bash
git tag -a v1.1.0 -m "UBack v1.1.0"
git push origin v1.1.0
gh run watch
```
> **Security Reminder**: Never commit `config.toml` or `mobile/dart_defines.json`. Release CI explicitly fails if either file exists in the checkout so public release APKs never contain personal NAS credentials.
