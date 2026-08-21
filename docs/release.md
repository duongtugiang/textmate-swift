# Cutting a release

The CD pipeline (`2.T4` / issue #22, `2.S5` / issue #18) lives in
[`.github/workflows/release.yml`](../.github/workflows/release.yml).

## One tag → release

```bash
git tag v0.1.0
git push origin v0.1.0
```

Pushing a `v*` tag triggers the `Release` workflow on the macos-14 runner:

1. `xcodegen generate` + `xcodebuild -configuration Release` (universal binary)
2. **Codesign** — Developer ID Application cert, hardened runtime; the embedded
   `TextCore.framework` is signed before the app bundle, then `codesign
   --verify --deep` + `spctl -a` check the result
3. **Notarize & staple** — `notarytool submit --wait`, then `stapler staple`
   + `stapler validate`
4. **Package** — `.dmg` built once from the final (signed/notarized) bundle;
   Gatekeeper check on the mounted dmg when notarized
5. **Publish** — GitHub Release with auto changelog; `.dmg` + `BUILD_INFO.txt`
   attached

## Required secrets

Set these under **Settings → Secrets and variables → Actions** (see
[`scripts/setup-gh.sh`](../scripts/setup-gh.sh)):

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE` | Developer ID Application cert, base64 of the `.p12` |
| `MACOS_CERTIFICATE_PWD` | `.p12` password |
| `MACOS_CERTIFICATE_NAME` | Codesign identity, e.g. `Developer ID Application: Van (TEAMID)` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarytool |

## Without secrets

The signing and notarization steps are guarded on the secrets being present.
Without them the pipeline still builds, packages, and publishes an **unsigned**
`.dmg` — `BUILD_INFO.txt` states this explicitly so the release notes stay
honest. Add the secrets at any point and the next tagged release is signed
and notarized automatically.

## Verification checklist

- [ ] CI green on `main`
- [ ] Tag name is the version you want users to see (release notes are
      generated from merged PRs)
- [ ] `BUILD_INFO.txt` in the release says what was produced
- [ ] On a signed release: Gatekeeper shows no warning on first launch
