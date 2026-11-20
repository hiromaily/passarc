# PassArc

A small macOS app (proof of concept, for use on your own Mac) that adds **Archive with Password** to the top level
of the Finder context menu. Right-click a folder or file, choose a format, a compression level and an optional
password, and PassArc creates the archive next to the original.

- Design: [docs/superpowers/specs/2026-11-08-passarc-design.md](docs/superpowers/specs/2026-11-08-passarc-design.md)
- Implementation plan (as written before implementation): [docs/superpowers/plans/2026-11-08-passarc.md](docs/superpowers/plans/2026-11-08-passarc.md)
- Development notes (pitfalls and how the code handles them): [docs/development-notes.md](docs/development-notes.md)
- PassArc only creates archives. It does not extract them.

## Formats

| Format | Password | Notes |
| --- | --- | --- |
| 7z | AES-256 | File names are encrypted too (`-mhe=on`). Default. |
| ZIP | AES-256 | File names are visible. The weak ZipCrypto method is never used. |
| tar.zst | none | Zstandard. Fastest. Not available while "Protect with a password" is on. |

Compression levels: Fast / Normal / Maximum (`-mx=1/5/9` for 7z and ZIP, `-1/-3/-19` for zstd).

### Opening the archives

**macOS Archive Utility cannot open password-protected 7z or ZIP archives (AES-256).** Use
[The Unarchiver](https://apps.apple.com/app/the-unarchiver/id425424353) (free).
To open archives by double-clicking, select an archive in Finder, press ⌘I, choose The Unarchiver
under "Open with", and click "Change All…".

The dialog explains this too: click the **?** button in its lower-left corner.

## Install with Homebrew

On macOS 15 or later with Apple Silicon, use the following command once the first release
has been published to the tap.

```sh
brew install --cask hiromaily/tap/passarc
```

Homebrew installs `PassArc.app` in `/Applications` by default, registers its Finder Sync
extension, and installs `sevenzip` and `zstd`.

The release is ad hoc signed. If macOS blocks first launch and you trust the release,
open PassArc once and follow [Apple's Open Anyway instructions](https://support.apple.com/en-us/102445).

Enable **PassArcFinder** under **System Settings > General > Login Items & Extensions >
Finder**. Then right-click a test file in Finder and choose **Archive with Password**.
The archive should appear next to the original file.

If you previously installed from source, remove the old copy in `~/Applications`
to avoid having two copies registered for the Finder extension and the `passarc://` URL.

```sh
brew upgrade --cask hiromaily/tap/passarc
brew uninstall --cask hiromaily/tap/passarc
```

For release packaging and tap updates, see the [Homebrew release guide](homebrew/README.md).

## Build and install from source

- macOS 15 or later (Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`). **Xcode itself is not needed.** It could not be installed
  on this Mac's macOS, so the app is built with `swiftc` instead (since 2026-11-08).
- Homebrew: `brew install sevenzip zstd`

7-Zip (`7zz`) is not bundled. PassArc looks for it in `/opt/homebrew/bin`, then `/usr/local/bin`. 7-Zip is licensed
under the GNU LGPL and other licenses; because it is not bundled, this repository does not redistribute it.

```sh
<this directory>/scripts/build.sh --install
```

The script compiles the app and the Finder Sync extension with `swiftc`, signs both ad hoc, copies the app to
`~/Applications/PassArc.app`, and registers the extension with `pluginkit`. The last line it prints should be a
`local.passarc.app.finder` entry starting with `+`, which means the extension is enabled.
Without `--install`, it only builds into `build/scripts/`.

If the menu item does not appear, close all Finder windows and open them again. If it still does not appear, open
System Settings > General > Login Items & Extensions, and make sure PassArcFinder is turned on.

### Notifications

PassArc posts a notification when an archive is ready. Click it to reveal the file in Finder. If no notification
appears, open System Settings > Notifications > PassArc and turn on "Allow notifications".

## How it works

- The Finder Sync extension (sandboxed) only shows the menu item. It sends the selected paths to the app with a
  `passarc://archive?path=...` URL.
- The app (not sandboxed, no Dock icon) shows the dialog and runs `7zz`, or `tar` piped into `zstd`.
- The password is never passed as a command-line argument (it would be visible in `ps`). PassArc answers 7-Zip's
  "Enter password" prompt through a pseudo-terminal.
- The archive is written under a temporary `.partial` name, verified with the same password (`7zz t`, or
  `zstd -t`), and only then renamed. If you stop it, or it fails, the partial file is deleted.
- `.DS_Store` and `._*` files are left out. Symbolic links are stored as links.

## Tests

```sh
swift test --package-path <this directory>/Core
```

The tests run the real `7zz` and `zstd`, so install them with Homebrew first.

## Verification results (2026-11-08, macOS 15.7, 7-Zip 26.06)

End-to-end checks from section 7 of the design.

| # | Check | Result | How |
| --- | --- | --- | --- |
| 1 | "Archive with Password" appears at the top level of the Finder context menu | OK | Checked by hand in Finder |
| 2 | A password-protected 7z opens with the password, and file names are hidden without it | OK (7-Zip). **Not checked with The Unarchiver** (not installed) | `7zz t -phello` on an archive made from the dialog: "Everything is Ok". `7zz l` without the password: "Cannot open encrypted archive" |
| 3 | ZIP uses AES-256 | OK | Test `job_zipUsesAES256` (`Method = AES-256`). Same code path as the app, not checked from the dialog |
| 4 | tar.zst extracts to the same content | OK | Test `job_createsTarZst` |
| 5 | The password does not appear in `ps` | OK | Test `pty_createsEncrypted7zWithoutPasswordInArguments` |
| 6 | Stopping leaves no partial file | OK | Test `job_cancelRemovesPartial` (7z and tar.zst). Not checked from the dialog |
| 7 | Levels change size and time | OK | `/usr/share/man` (20 MB), same arguments as the app, table below |

| Level | 7z | tar.zst |
| --- | --- | --- |
| Fast | 7.7 MB, 0.4 s | 9.8 MB, 0.2 s |
| Normal | 5.8 MB, 5.9 s | 8.4 MB, 0.2 s |
| Maximum | 5.7 MB, 6.6 s | 6.1 MB, 7.1 s |

Also checked by hand: the dialog comes to the front, all text is in English with nothing cut off, tar.zst is greyed
out while a password is on, password messages appear when you leave a field, the **?** help, and the notification.

macOS Archive Utility could not extract a password-protected 7z made by PassArc (reported by the user), which is
why the dialog and this README point to The Unarchiver.
