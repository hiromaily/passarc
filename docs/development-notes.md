# Development notes

Things we learned while building PassArc (2026-11-08) that are not obvious from the code. Each item says what
happened, why, and what the code does about it. Read this before changing the build, the dialog, or how 7-Zip is
called.

## Building without Xcode

`scripts/build.sh` uses the macOS SDK and `swiftc` through `xcrun`. The standalone Command Line Tools SDK includes
`FinderSync.framework`.

If the compiler fails before it reaches project code, check the selected developer directory, compiler, and SDK.

```sh
xcode-select -p
xcrun --sdk macosx --find swiftc
xcrun --sdk macosx --show-sdk-path
```

If the selected Xcode fails to start and standalone Command Line Tools are installed, use `DEVELOPER_DIR` for the
individual command. If the default Clang module cache is unwritable, give the command a writable temporary cache.
The following combination has built and signed both PassArc targets successfully.

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  CLANG_MODULE_CACHE_PATH="$(mktemp -d)" scripts/build.sh
```

Run `swift test --package-path Core` separately. If SwiftPM fails while compiling `Package.swift`, record the
manifest error and selected Swift and SDK versions. A successful app build does not exercise the package manifest.

- **The extension's entry point is `NSExtensionMain`.** Link the appex with `-Xlinker -e -Xlinker _NSExtensionMain`
  and compile it (and any library it links) with `-application-extension`.
- **The appex `Info.plist` needs `CFBundlePackageType = XPC!`** and `NSExtension` with
  `NSExtensionPointIdentifier = com.apple.FinderSync` and `NSExtensionPrincipalClass = <Module>.FinderSync`.
  Xcode normally fills in `$(...)` variables; here every value is written out literally.
- **Sign the inside first**: the appex with `Extension/Extension.entitlements` (App Sandbox is required for app
  extensions), then the app. Ad-hoc signing (`--sign -`) is enough for a Finder Sync extension on your own Mac.
  `amfid` logs "adhoc signed" but the extension still loads.
- **Register with `pluginkit -a <appex>` and enable with `pluginkit -e use -i <bundle id>`.** Check with
  `pluginkit -mAv -p com.apple.FinderSync`: a leading `+` means enabled.
- **Stale copies steal the URL scheme.** Every copy of the app that LaunchServices has seen registers `passarc://`.
  A throwaway build in another folder received the URL instead of the installed app. `build.sh --install` now
  unregisters the copy in `build/` (`lsregister -u`). To inspect: `lsregister -dump URLSchemeBinding | grep passarc`.

## macOS app behaviour

- **`NSApp.activate()` does not bring the window to the front** when launched from the extension: since macOS 14,
  activation is cooperative and Finder keeps the focus. `NSApp.activate(ignoringOtherApps: true)` works on 15.7.
  We confirmed it by checking `lsappinfo front` and the window order from `CGWindowListCopyWindowInfo`.
- **Swift 6 traps when an Objective-C completion handler runs on a background queue.** A closure written inside a
  `@MainActor` class is inferred to be main-actor isolated. `UNUserNotificationCenter.requestAuthorization`
  calls it on a background queue, and the runtime isolation check kills the app (`EXC_BREAKPOINT`, crash report in
  `~/Library/Logs/DiagnosticReports/`). Use the `async` version of such APIs instead.
- **`UNUserNotificationCenter.current()` throws outside an app bundle.** `Notifier` creates it lazily so the dialog
  can be rendered by `scripts/snapshot.sh`.
- **If notifications never appear, the app is probably set to "denied".** Requests then fail with
  `UNErrorDomain Code=1 "Notifications are not allowed for this application"` and no prompt is shown. The app logs
  `authorizationStatus` (subsystem `local.passarc.app`, category `notification`). Only the user can turn it on in
  System Settings > Notifications.

## SwiftUI pitfalls in the dialog

- **`SecureField` doubled characters typed through a Japanese input method.** SwiftUI writes the bound value back
  into the field on every redraw, which commits the IME's pending text a second time ("h" became "hh", vowels were
  fine). `App/SecureInputField.swift` wraps `NSSecureTextField`, never writes back while editing, and only passes
  the value on when the field loses focus (validation runs then, not per keystroke; the user asked for this).
- **`Picker(.radioGroup)` ignores `.disabled` on individual options**, so tar.zst could not be greyed out.
  `App/RadioButton.swift` wraps `NSButton`. Setting `isEnabled` on the `NSButton` is not enough: SwiftUI
  overwrites it, so the SwiftUI `.disabled()` modifier is applied too.
- **A fixed dialog width truncated "Normal" and "Maximum".** The horizontal radio group uses `.fixedSize()` and the
  dialog width is `minWidth: 380, maxWidth: 480`.
- **You cannot screenshot other apps without Screen Recording permission** (`screencapture` only shows the
  desktop). `scripts/snapshot.sh <dir>` renders the dialog states and the help popover to PNG inside the process
  (`cacheDisplay`), which needs no permission. Use it after any layout change.

## 7-Zip (`7zz` 26.06) behaviour

- **`-p` without a value prompts for the password on `a`, but means "empty password" on `t` and `l`.** So the
  verify command has no `-p`. 7zz then asks when it meets the encrypted header, and `PTYRunner` answers.
- **Do not use `-bso0` when creating.** It also hides the "Enter password:" prompt, so nothing would answer it.
- **`7zz t` prints no `Files: N` line when the archive has no folder entries** (a single file, or several files).
  The verify step uses `-bb1` and counts the `T <name>` lines that do not end in `/`.
- **Item names are wildcards unless you pass `-spd`.** Selecting `What?.txt` also archived `Whatx.txt`.
  `-spd` also turns off wildcards in `-xr!` excludes, so `._*` stopped matching. Excludes are now written to a
  list file, one literal name per line (`-scsUTF-8 -xr@<file>`). The names come from `FileInventory`.
- **macOS Archive Utility cannot open AES-256 7z or ZIP archives.** It only handles the old ZipCrypto, which is
  weak and never used here. The dialog's **?** help says so.

## Pseudo-terminal (`PTYRunner`)

- **Canonical mode drops passwords of 1024 characters or more** (`MAX_CANON`): the newline never arrives and 7zz
  waits forever. The pty is put in non-canonical mode with `ICANON`, `ISIG`, `IEXTEN`, `ICRNL` and `IXON` off,
  `VMIN = 1` and `ECHO` off. Test: `pty_longPasswordDoesNotHang`.
- **Check the password through a different path from the one that set it.** Creating and verifying through the
  same pty would pass even if the password were garbled on the way. The tests reopen archives with
  `7zz t -p<password>` on the command line (fine in tests, never in the app).
- **The password-in-arguments test needs process inspection.** If
  `pty_createsEncrypted7zWithoutPasswordInArguments` reports empty process arguments, try
  `/bin/ps -ww -o args= -p $$` in the same execution environment. If process inspection is denied,
  rerun the test in an environment that lets it read its child process arguments.

## tar, zstd and files

- **bsdtar reads `@name` as "add the entries of archive `name`"**, even after `--`. Names starting with `@` are
  passed as `./@name`.
- **SIGPIPE killed the app when zstd exited early** (for example, the output folder is not writable) while tar
  output was still being pumped into it. The pipe has `F_SETNOSIGPIPE`, and the app also ignores `SIGPIPE`.
  To reproduce in a test, reset `SIGPIPE` to `SIG_DFL` (the test runner ignores it) and feed more than the 64 KB
  pipe buffer. Test: `job_tarZstFailsCleanlyInReadOnlyDirectory`.
- **`FileManager.enumerator` silently skips `._*` files**, and calling `skipDescendants()` on a file skips the rest
  of its parent folder. `FileInventory` walks the tree with `readdir` and `lstat`.
- **Items in one archive must share a parent folder.** 7zz and tar run in the parent with bare names.
  Finder can hand over items from different folders, for example through search results. Individual
  folder compression submits one job per folder, so each job uses its own parent.
- **Parallel jobs reserve their names.** Output and `.partial` names are reserved in a process-wide set, and the
  final rename picks a free name again if one appeared meanwhile.

## Debugging tips

- In zsh, `log` is a builtin. Use `/usr/bin/log show --last 10m --style compact --predicate '...'`.
- Useful predicates: `process == "PassArcFinder"`, `subsystem == "local.passarc.app"`,
  `eventMessage CONTAINS[c] "passarc"`.
- Window order and frontmost app without Screen Recording permission: `lsappinfo info -only name $(lsappinfo front)`
  and `CGWindowListCopyWindowInfo` (owner name, layer, bounds).
- On this machine `rm` and `cp` are aliased to `-i`, which blocks non-interactive commands. Use `command rm` and
  `command cp -f`.
