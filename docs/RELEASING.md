# Releasing Stage One

Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed.
Pull request CI (`ci.yml`) only builds, tests, bundles an ad-hoc signed DMG and smoke-tests it.

## What a release does

1. `swift test`.
2. Imports the Developer ID certificate into a temporary keychain (if the secrets exist).
3. `scripts/build-app.sh` builds a universal `Stage One.app`:
   - generates `Resources/AppIcon.icns` with `swift scripts/make-icon.swift` (never committed),
   - bundles the `stage` CLI at `Contents/Helpers/stage`,
   - copies `Sparkle.framework` into `Contents/Frameworks` and adds the
     `@executable_path/../Frameworks` rpath,
   - signs inside out. With a Developer ID identity it adds the hardened runtime and a secure
     timestamp; otherwise it signs ad-hoc.
4. `scripts/smoke-test.sh` launches the bundle to check dyld, the CLI and the icon.
5. `scripts/notarize.sh` notarises the app with `xcrun notarytool submit --wait` and staples it.
6. `scripts/make-dmg.sh` builds `StageOne-<version>.dmg`; it is signed, notarised and stapled too.
   A zip of the app (`StageOne-<version>.zip`) is made for Sparkle.
7. If `SPARKLE_ED_PRIVATE_KEY` exists, Sparkle's `generate_appcast` writes `appcast.xml`
   for the zip (earlier entries are kept from the previous release's appcast).
8. Prints the version and DMG sha256, writes a bumped `stage-one.rb` cask, and publishes a
   GitHub release with the DMG, zip, `SHA256SUMS`, `appcast.xml` and the cask.

Without any secrets the same pipeline runs and publishes ad-hoc signed builds. Users then
have to right-click > Open the first time, and Sparkle stays off (the app's update check
opens the releases page instead).

## Secrets and variables

Set these under Settings > Secrets and variables > Actions.

| Name | Kind | What it is |
| --- | --- | --- |
| `MACOS_CERT_P12` | secret | Developer ID Application certificate and key, exported as .p12, base64: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | secret | The .p12 export password |
| `APPLE_ID` | secret | Apple ID email used for notarisation |
| `APPLE_TEAM_ID` | secret | 10-character team id |
| `APPLE_APP_PASSWORD` | secret | App-specific password from appleid.apple.com |
| `SPARKLE_ED_PRIVATE_KEY` | secret | Sparkle EdDSA private key (see below) |
| `SPARKLE_ED_PUBLIC_KEY` | variable | The matching public key, written to `SUPublicEDKey` |

Notarisation runs only when the certificate and all three Apple secrets are present.

### Sparkle keys

Download a Sparkle release (`Sparkle-2.x.tar.xz`) and run `./bin/generate_keys` once. It
stores the private key in your login keychain and prints the public key. Export the private
key with `./bin/generate_keys -x sparkle_private_key` and paste the file's contents into
`SPARKLE_ED_PRIVATE_KEY`; put the public key in the `SPARKLE_ED_PUBLIC_KEY` variable.
Keep a backup: losing the private key means existing installs can no longer verify updates.

The feed URL is fixed in `Resources/Info.plist`:
`https://github.com/VenusOne-Lee/stage-one/releases/latest/download/appcast.xml`.
GitHub's `latest` skips prereleases, so only full releases reach Sparkle users.

## Tagging

```sh
git checkout main && git pull
git tag v0.1.0            # a full release
git tag v0.2.0-beta.1     # anything with a "-" becomes a prerelease
git push origin v0.1.0
```

No terminal? Open **Actions › Release › Run workflow**, keep the branch on `main`, type the tag
(`v0.1.0`) and run it. The workflow builds `main` and creates the tag with the release.

`CFBundleShortVersionString` comes from the tag; `CFBundleVersion` is the commit count on
the tagged commit, which is what Sparkle compares, so always tag a commit on `main`.

## Bumping the Homebrew cask

`Casks/stage-one.rb` lives in this repo, so the repo is its own tap:

```sh
brew tap VenusOne-Lee/stage-one https://github.com/VenusOne-Lee/stage-one
brew install --cask stage-one
```

After a full release, the job summary and the release assets contain a bumped
`stage-one.rb` with the new `version` and `sha256`. Replace `Casks/stage-one.rb` with it in a
small PR (`SO-133: bump cask to 0.1.0`), then check it with:

```sh
brew audit --cask --online stage-one
brew install --cask stage-one && brew uninstall --cask stage-one
```

## Local builds

```sh
scripts/build-app.sh                                    # ad-hoc, universal
ARCHS=arm64 scripts/build-app.sh                        # faster, Apple silicon only
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-app.sh
```
