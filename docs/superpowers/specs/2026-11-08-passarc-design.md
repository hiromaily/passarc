# PassArc design: a macOS app that compresses with a password from the Finder context menu

Date: 2026-11-08
Status: approved by the user on 2026-11-08, then revised during implementation (see "Revision history" at the end).
This document describes the current behaviour.

## 1. Why

Right-click a folder in Finder, choose **"Archive with Password"** at the top level of the menu, and a dialog lets
you compress it with a password. Inspired by [Keka](https://github.com/aonez/keka).

The main use is **storing files on your own Mac**. Security comes before whether other machines can open the
archive. Extraction is out of scope: archives are opened by double-clicking them in a common tool such as
The Unarchiver.

The name "PassArc" and the location of the app are placeholders chosen by Claude.

## 2. Goals, non-goals, and what counts as failure

### Goals
- "Archive with Password" appears at the **top level** of the Finder context menu (not under Quick Actions).
- The dialog lets you choose the format, the compression level and whether to use a password.
- A password-protected 7z also encrypts the file names inside it.
- Compression runs at native speed (Swift; the compression itself is done by 7-Zip and zstd).

### Non-goals
- Extraction, or opening archives by double-click (left to The Unarchiver; may be added later).
- App Store distribution, distribution to other Macs, notarization.
- A settings window, a menu bar icon, Dock interaction.
- Split archives, listing archive contents.
- Switching languages. All UI text and the README are in English (changed from Japanese at the user's request on
  2026-11-08).

### Failure, even if it works
- Encrypting with the weak, old ZIP method (ZipCrypto).
- The password being left anywhere: the process list (`ps`), logs, settings files, crash reports.
- Deleting or modifying the original files or folders.
- A half-written archive left behind after stopping or failing, looking like a real file.
- Compressing with a password whose confirmation does not match.

## 3. Constraints

- This Mac: macOS 15.7, Apple Silicon, Swift 6.1, Homebrew and zstd installed. **Xcode cannot be installed on this
  macOS**, so the app is built with the Command Line Tools (`scripts/build.sh`).
- Location: `vehicle-location-map/poc/passarc/`. **The poc is not subject to the parent repository's skills, rules
  or checks** (Biome, cc-sdd, lefthook, ...), at the user's request. Files tracked by the parent repository
  (`.gitignore`, `.impeccable/config.json`, ...) must not be changed.
- To appear at the top level of the context menu, the app contains a **Finder Sync extension**. App extensions only
  run inside the sandbox.
- If the extension is not enabled after installing, turn it on once in System Settings > General > Login Items &
  Extensions (described in the README).

## 4. Decided by the user

### Menu
- "Archive with Password" at the top level of the Finder context menu.

### Dialog (agreed from mockups)

```
┌─ Archive ──────────────────────────────────┐
│ 📁 Compress "projects-2026"                 │
│                                            │
│      Format  ◉ 7z                           │
│              ○ ZIP                          │
│              ○ tar.zst                      │
│ Compression  ○ Fast  ◉ Normal  ○ Maximum    │
│              ☑ Protect with a password      │
│    Password  [••••••••          ]           │
│      Verify  [••••••••          ]           │
│                                            │
│ (?)                    [Cancel] [Compress]  │
└────────────────────────────────────────────┘
```

- **Format**: vertical radio buttons, one of 7z / ZIP / tar.zst. No descriptions such as "security first".
- **Compression**: horizontal radio buttons, one of Fast / Normal / Maximum.
- **Protect with a password**: the Password and Verify fields appear only while it is checked, and disappear when
  it is unchecked.
- While it is checked, tar.zst is greyed out (zstd has no password support).
- Password messages appear when you leave a field, not while typing (see §5, Dialog behaviour).
- The **?** button in the lower-left corner explains that macOS Archive Utility cannot open password-protected
  7z or ZIP archives, and that The Unarchiver can.

### Formats and encryption
- With a password: **7z (AES-256, file names encrypted too)** and **ZIP (AES-256)**. ZIP cannot hide file names.
- Without a password, the fast format: **tar.zst (Zstandard)**.
- No extraction.

### How it is built
- Swift. (Originally Xcode; changed to the Command Line Tools because Xcode could not be installed.)

## 5. Decided by Claude (not checked by the user)

### Structure
- Two parts: **the app (PassArc.app)** and **a Finder Sync extension** inside it.
  - The extension only shows the menu item. It hands the selected paths to the app with a custom URL scheme
    (`passarc://archive?path=...`).
  - The app shows the dialog and compresses. It is **not sandboxed** (it writes next to the original files).
  - The extension watches `/`, so the menu appears wherever you right-click. As of 2026-11-08 no other Finder Sync
    extension (Dropbox etc.) is installed on this Mac (`pluginkit -mAv -p com.apple.FinderSync` printed
    `no matches`), so overlapping watched folders are not a concern.
- The app has no Dock icon (`LSUIElement`). It comes to the front when it shows the dialog.
- The dialog is SwiftUI on an AppKit base. The password fields and the format radio buttons are native AppKit
  controls (see `docs/development-notes.md`).
- Target: macOS 15 or later.

### Compression tools
- 7z and ZIP (AES-256) are created with **7-Zip's `7zz`** (Homebrew `sevenzip`), looked up in
  `/opt/homebrew/bin/7zz`, then `/usr/local/bin/7zz`. If it is missing, the dialog says
  "Install it in Terminal with: brew install sevenzip".
- tar.zst is created by piping `/usr/bin/tar` into `zstd`, looked up the same way.
- Levels:

  | Level | 7z / ZIP (`-mx`) | zstd |
  | --- | --- | --- |
  | Fast | 1 | `-1` |
  | Normal | 5 | `-3` |
  | Maximum | 9 | `-19` |

- 7z uses `-mhe=on` (encrypt file names); ZIP uses `-tzip -mem=AES256`. Multithreading is on. `-spd` makes `*` and
  `?` in names literal.
- **The password is never a command-line argument** (`7zz -psecret` is visible in `ps`). It is given by answering
  7zz's "Enter password" prompt through a pseudo-terminal. (This was checked in the first task, and it works.)
- If that had not worked, 7-Zip's source would have been built into the app as a library (decided by the user on
  2026-11-08), to keep 7z's file name encryption. The alternatives (ZIP only, or the password in a temporary file)
  were rejected. libarchive cannot write encrypted 7z, so it is not an option.

### Input and output
- **One folder**: the output is `<folder>.7z` next to it (`.zip` / `.tar.zst` by format). The top level inside the
  archive is that folder.
- **One file** works too: `<file>.7z`, keeping the original extension (for example `report.pdf.7z`).
- **Several items**: one archive, `Archive.7z`, next to them. The dialog title says "Compress 3 items".
- **Items from different folders** (possible from Finder search results or Recents) are refused with
  "Select items that are in the same folder."
- If the name is taken, add a number as Finder does: `name 2.7z`, `name 3.7z`. Never overwrite.
- `.DS_Store` and `._*` (macOS metadata files) are left out. tar runs with `COPYFILE_DISABLE=1`.
- Symbolic links are stored as links, not followed.
- Finder tags, extended attributes, ACLs and resource forks are not preserved (7z and ZIP can hardly store them).
  File contents, names, folder structure and modification times come first.

### Dialog behaviour
- Defaults: 7z, Normal, password on.
- The format, the level and the checkbox are remembered for next time (`UserDefaults`). **The password is never
  remembered.**
- With a password, **Compress** stays disabled until Password is not empty, contains only ASCII characters, and
  matches Verify. Messages appear under the fields:
  - "The passwords don't match." after leaving Verify.
  - "Enter a password." after leaving Password empty.
  - "Use only ASCII letters, numbers, and symbols." after leaving Password.
  - Values are taken only when a field loses focus; there is no per-keystroke validation.
  - Leaving Verify with Tab or Return while it does not match puts the focus back in Verify with its text selected.
  - Return in Verify starts compressing if everything is valid.
  (Revised from user feedback on 2026-11-08.)
- No length rule for passwords (personal use), but **only printable ASCII characters** are allowed. Japanese and
  full-width characters are handled differently by different tools in ZIP (AES) and in 7zz's terminal input, which
  could produce an archive The Unarchiver cannot open.
- Enter is Compress, Esc is Cancel.

### While compressing and after
- The dialog switches to a progress bar and a **Stop** button. 7zz progress comes from its `-bsp1` output; tar.zst
  progress is bytes read divided by the total size (approximate).
- Stop terminates the process and deletes the partial file.
- On failure, the partial file is deleted and the dialog shows the end of the tool's output (never the password).
- The archive is written under a temporary `.partial` name and renamed only at the end, so a half-written file is
  never mistaken for a real one.
- Before the rename, **the archive is verified**: 7z and ZIP with `7zz t` and the same password, checking that the
  number of files matches the source; tar.zst with `zstd -t`. If verification fails, the job fails and the file is
  deleted. The progress area says "Verifying…".
- When done, a macOS notification appears. Clicking it reveals the file in Finder. The dialog closes.
- Starting another job from the context menu while one is running opens another dialog; they run in parallel.
  Their output and partial names never collide.

### git
- `poc/passarc/` is not committed to vehicle-location-map. It has its own git repository (`git init` inside
  `poc/passarc/`), and work is committed there.
- The brainstorming mockups (`poc/.superpowers/`) are not committed anywhere.

## 6. Left to the builder

- How the app is built and signed (now `scripts/build.sh`: `swiftc`, ad-hoc signing, `pluginkit`). Target and
  bundle identifiers.
- Details of how the extension hands paths to the app.
- How 7zz and zstd are started, how their output is read, and how progress is computed.
- Test scope. At least: the command arguments (per format, level and password setting, and that the password is
  never an argument) and the output naming (including numbering) are unit tested. The context menu and the
  notification are checked by hand.
- The README (installation, enabling the extension, `brew install sevenzip`, how to verify).

## 7. Acceptance checks

1. Right-clicking a folder in Finder shows "Archive with Password" at the top level.
2. A 7z made with a password opens in The Unarchiver, asks for the password, and gives back the same contents.
   Without the password, not even the file names are visible (also checked with `7zz l`).
3. A ZIP made with a password is AES-256 encrypted (`Method` in `7zz l -slt` is `AES-256`).
4. A tar.zst (no password) extracts to the same contents (`tar --zstd -xf` or similar).
5. While compressing, the password does not appear in the arguments shown by `ps`.
6. Stopping leaves no partial file.
7. Fast, Normal and Maximum produce different sizes and times.

Results are in the README ("Verification results").

## Revision history

All on 2026-11-08, after the user approved the first version.

- **Build**: Xcode could not be installed on this macOS. XcodeGen and `xcodebuild` were replaced by
  `scripts/build.sh` (the user chose this).
- **Language**: all UI text and the README are in English (user request). This document and the plan were also
  translated to English.
- **Help**: a **?** button explains that macOS Archive Utility cannot open AES-256 archives and points to
  The Unarchiver (user request; Keka was removed from the text at the user's request).
- **Password fields**: messages appear when a field loses focus, values are taken only then, focus returns to
  Verify on a mismatch, and Return in Verify compresses (user feedback).
- **Different folders**: items from different folders are refused (found in the final review).
- **Verification count**: counts `T <name>` lines from `7zz t -bb1`, because `7zz t` prints no `Files:` line for
  archives without folders (found in the final review).
