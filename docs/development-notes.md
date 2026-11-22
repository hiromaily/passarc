# Development notes

Things we learned while building PassArc (2026-11-08) that are not obvious from the code. Each item says what
happened, why, and what the code does about it. Read this before changing the build, the dialog, or how 7-Zip is
called.

## Lint and formatting

Install [mise](https://mise.jdx.dev/getting-started.html) with `brew install mise`, then run these commands from the repository root.

```sh
mise trust
mise install
mise run format
mise run lint
```

`mise.toml` pins the tool versions and defines the commands used locally and in CI. The lint task checks Swift formatting with SwiftFormat, Bash formatting with shfmt, shell scripts with ShellCheck, and GitHub Actions workflows with actionlint. actionlint also uses ShellCheck for inline shell steps.

Swift formatting uses two spaces and LF line endings. The rules in `.swiftformat` cover indentation, whitespace, and spacing. Shell scripts use two spaces. Edit workflow YAML directly and use `mise run lint` to validate it. When adding or upgrading a workflow action, regenerate `.github/workflows/actions.lock` with `gh actions-lock`.

## CI triggers

GitHub Actions filters pull requests and pushes to `main` by changed paths before starting a runner.

| Workflow | Changes that trigger it |
| --- | --- |
| Core tests | `Core/` or the Core test workflow |
| Lint | `App/`, `Core/`, `Extension/`, `scripts/`, formatter or mise configuration, or workflow YAML |
| Verify Actions lockfile | Workflow YAML or `.github/workflows/actions.lock` |

CI cancels older runs of the same workflow for the same ref. Lint and lockfile verification run on Linux.
Core unit and integration tests run together on macOS and install only the archive tools missing from the runner.

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
(
  work_dir="$(mktemp -d /tmp/passarc.XXXXXX)" || exit 1
  trap 'rm -rf -- "$work_dir"' EXIT
  DEVELOPER_DIR=/Library/Developer/CommandLineTools \
    CLANG_MODULE_CACHE_PATH="$work_dir/module-cache" scripts/build.sh
)
```

Run `swift test --package-path Core` separately. If SwiftPM fails while compiling `Package.swift`, record the
manifest error and selected Swift and SDK versions. A successful app build does not exercise the package manifest.

If `xcodebuild` fails to start and standalone Command Line Tools fail to resolve `.macOS(.v15)` in
`Package.swift`, run Xcode's Swift executable directly with its matching SDK and Testing framework. Keep
`DEVELOPER_DIR` on Command Line Tools for subprocesses that use `xcrun`. All Core tests use Swift Testing, so
`--disable-xctest` skips the XCTest platform lookup. This ran all 75 tests with Xcode's Swift 6.0.2 and macOS
15.1 SDK on a host where Command Line Tools reported Swift 6.3.3 and macOS 26.5 SDK.

```sh
(
  work_dir="$(mktemp -d /tmp/passarc.XXXXXX)" || exit 1
  trap 'rm -rf -- "$work_dir"' EXIT
  xcode_dir=/Applications/Xcode.app/Contents/Developer
  platform_dir="$xcode_dir/Platforms/MacOSX.platform/Developer"
  framework_dir="$platform_dir/Library/Frameworks"
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  export SDKROOT="$platform_dir/SDKs/MacOSX.sdk"
  export CLANG_MODULE_CACHE_PATH="$work_dir/module-cache"
  "$xcode_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" test \
    --package-path Core --scratch-path "$work_dir/build" --disable-xctest \
    -Xswiftc -F -Xswiftc "$framework_dir" -Xlinker -rpath -Xlinker "$framework_dir"
)
```

If the SwiftPM manifest fails with `sandbox_apply: Operation not permitted` inside an existing sandbox, add
`--disable-sandbox` to the command above. If the build cannot find `TestingMacros`, add `--build-system native`
to use the Xcode toolchain's SwiftPM build backend. If only the PTY argument check fails with an empty
`psArgs`, try `/bin/ps -o args= -p $$`. When the environment denies `ps`, rerun the suite in an authorized
environment where process arguments are visible.

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

## Verify the drag-and-drop launch window

Build the app and use a macOS session where PassArcFinder is disabled. Open the built PassArc directly and check that it shows **Drop files or folders here** and **Enable Finder Extension…**.

Before creating the test files, confirm that Finder and the PassArc launch window can be shown side by side on the same display and that you can drag between them. If your automation tool cannot drag across windows, use Finder directly in that macOS session.

Run this block from the repository root. Leave it waiting in Terminal while you test in Finder.

```sh
(
  work_dir="$(mktemp -d /tmp/passarc.XXXXXX)" || exit 1
  trap 'rm -rf -- "$work_dir"' EXIT
  mkdir "$work_dir/sample-folder" || exit 1
  printf 'file contents\n' > "$work_dir/sample.txt"
  printf 'folder contents\n' > "$work_dir/sample-folder/nested.txt"
  open "$work_dir" || exit 1
  printf 'Press Return after compression completes: '
  read -r reply || exit 1
  7zz t "$work_dir/Archive.7z" &&
    7zz l "$work_dir/Archive.7z"
)
```

1. Arrange Finder and the PassArc launch window side by side so both are visible. Select `sample.txt` and `sample-folder` in Finder and drag them together onto PassArc. The drop area should highlight and one **Archive** dialog should open.
2. Choose **7z**, clear **Protect with a password**, and click **Compress**. Check that `Archive.7z` appears next to the source items, then press Return in Terminal. The integrity check should pass and the listing should contain `sample.txt` and `sample-folder/nested.txt`. The temporary directory is removed when the block exits.

A successful drag, archive integrity check, and listing verify the full workflow.

### Open the archive dialog with a test selection

To exercise the result window, pass test paths directly to the built app using its Finder URL contract.
For example, use a small folder followed by a larger folder to check stopping a batch after the first save.

```sh
(
  work_dir="$(mktemp -d /tmp/passarc.XXXXXX)" || exit 1
  trap 'rm -rf -- "$work_dir"' EXIT
  mkdir "$work_dir/small" "$work_dir/large"
  printf 'PassArc stop test\n' > "$work_dir/small/first.txt"
  mkfile -n 8g "$work_dir/large/large.dat"
  open -a "$PWD/build/scripts/PassArc.app" \
    "passarc://archive?path=$work_dir/small&path=$work_dir/large" || exit 1
  printf 'Press Return after checking the saved archive and cleanup in %s\n' "$work_dir"
  read -r finish
)
```

Enable **Create a separate archive for each folder**, start compression, then click **Stop** during the
second folder. Confirm that **Share** and **Show in Finder** target only the first archive and that no
`.partial` files remain. If a restricted shell reports `kLSNoExecutableErr` for a signed
bundle that launches normally from Finder, run the command in an authorized macOS session.

## Verify the completion sound

Build and launch PassArc in a macOS session with audible audio output. Enable PassArcFinder for the
extraction check. Use disposable files and folders in a temporary directory as shown above.

1. Compress one file. Confirm that its archive is saved and the completion sound plays once.
2. Select two folders and enable **Create a separate archive for each folder**. Confirm that both archives
   are saved and the sound plays once, after the second archive is saved.
3. In Finder, choose **Extract with PassArc** for one of the new archives. Confirm that Finder reveals the
   extracted output and the sound plays once.
4. Run a batch with a small folder followed by a large one. Click **Stop** after the first archive is saved.
   For the failure case, select a folder in the temporary directory and a second folder one level deeper
   under a separate parent. PassArc processes the shallower selection first. Remove write permission
   from the second folder's parent before starting, then restore it after the failure for cleanup.
   Confirm that the first archive is still available in each case and that neither run plays the
   completion sound.

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

## Adding an archive format

Define the extension, compression backend, and encryption together in `ArchiveFormat` in
`Core/Sources/PassArcCore/ArchiveOptions.swift`. The extension also drives Finder extraction recognition.
Keep password controls tied to the format's password policy. Compression and extraction select their
backend separately from an outer encryption step such as age. Keep the compatibility note in
`App/ArchiveDialogView.swift` and document any new executable in the Homebrew cask template and README.

For a new format, exercise creation, verification, and extraction with the real tools. Check an incorrect
passphrase, cancellation cleanup, and preservation of symbolic links where applicable. To test with a
standalone age executable, run `PASSARC_TEST_AGE=/path/to/age swift test --package-path Core --filter ExtractionJobTests`.
The [Core tests workflow](../.github/workflows/core-tests.yml) sets `PASSARC_TEST_AGE` so the
encrypted tar.zst round-trip runs in CI alongside the other Core tests.
Run the full Core suite and build both the app and Finder extension before checking the Finder menu.

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
