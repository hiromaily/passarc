# Homebrew releases

PassArc uses the same [Homebrew tap](https://github.com/hiromaily/homebrew-tap) as yaml-lint-rs.
The tap's `Casks/passarc.rb` installs the signed app bundle, including the Finder Sync
extension, and declares the Homebrew dependencies.

## Package a release

Run `scripts/package-release.sh 0.1.0` on an Apple Silicon Mac with the Xcode Command Line Tools.
It builds the app and extension, verifies the signature after extracting the ZIP, and generates
`build/release/PassArc-arm64.zip` and `build/release/passarc.rb`. The generated cask contains the
ZIP's SHA-256 and points to the GitHub release for that version. The Release workflow can also
be run manually from Actions to check packaging without publishing.

Tag builds use ad hoc signatures when the repository Actions variable
`PASSARC_NOTARIZE` is unset or `false`. This mode requires no Apple credentials.
macOS may show a Gatekeeper warning on first launch. See the [troubleshooting guide](../README.md#macos-says-passarc-was-not-opened).

To enable notarization for tag builds, go to **Settings → Secrets and variables → Actions → Variables**
and set the repository variable `PASSARC_NOTARIZE` to `true`. Configure these repository
Actions secrets before pushing the release tag. The release fails if signing or notarization fails.

| Secret | Value |
| --- | --- |
| `PASSARC_DEVELOPER_ID_P12` | Base64-encoded PKCS#12 export of the Developer ID Application certificate and private key |
| `PASSARC_DEVELOPER_ID_PASSWORD` | PKCS#12 export password |
| `PASSARC_NOTARY_KEY_P8` | Contents of the App Store Connect team API key file |
| `PASSARC_NOTARY_KEY_ID` | App Store Connect API key ID |
| `PASSARC_NOTARY_ISSUER` | App Store Connect API issuer ID |

The tag build signs both bundles with Hardened Runtime and a secure timestamp, submits
the app to Apple, staples the ticket to the app, and checks Gatekeeper acceptance on
the extracted final ZIP before publication.

## Publish a release

Push a `vMAJOR.MINOR.PATCH` tag after the release workflow is on the branch you intend to release.

```sh
git tag v0.1.0
git push origin v0.1.0
```

The Release workflow uploads the ZIP and generated cask to the GitHub release. Add
`HOMEBREW_TAP_TOKEN` to the PassArc repository's Actions secrets to publish the cask
automatically. Use a token with Contents read and write access to `hiromaily/homebrew-tap`.

For a manual tap update, download `passarc.rb` from the release, commit it to
`Casks/passarc.rb` in `hiromaily/homebrew-tap`, and push that commit.

## Verify an installed release

On an Apple Silicon Mac, install with `brew install --cask hiromaily/tap/passarc`.
Open PassArc once, follow the prompt to enable PassArcFinder, then use **Archive with Password** in Finder
to archive a test file. Check that the archive opens with the password. Uninstall with
`brew uninstall --cask hiromaily/tap/passarc` and confirm the app and its Finder menu
are removed.
