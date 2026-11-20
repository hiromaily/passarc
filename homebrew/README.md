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
Open PassArc once, enable PassArcFinder in System Settings, then use **Archive with Password** in Finder
to archive a test file. Check that the archive opens with the password. Uninstall with
`brew uninstall --cask hiromaily/tap/passarc` and confirm the app and its Finder menu
are removed.
