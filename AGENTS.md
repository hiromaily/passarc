# PassArc development guide

PassArc is a macOS app that creates archives next to the files or folders selected in Finder. It targets macOS 15 or later on Apple Silicon. Use Swift 6 and the Xcode Command Line Tools. The app and extension are built with `swiftc`.

## Project layout

- `App/` owns the AppKit and SwiftUI dialog, URL handling, job launch, and notifications. Keep user-facing text in English.
- `Extension/` contains the sandboxed Finder Sync extension. It adds the context-menu item and forwards selected paths to the app via `passarc://archive`. Check both the sender and receiver when changing the URL contract.
- `Core/Sources/PassArcCore/` contains URL encoding and decoding, settings, command construction, archive creation, and verification. The Finder extension also links this library, so use APIs available to app extensions. Tests live in `Core/Tests/PassArcCoreTests/`.

## Archive behavior

- Pass passwords to the 7-Zip prompt through `PTYRunner`. Keep passwords out of command-line arguments and logs during both creation and verification.
- Preserve AES-256 for password-protected 7z and ZIP archives and encrypt file names in protected 7z archives. Disable tar.zst while password protection is enabled.
- Write to a temporary `.partial` file and move it to its final name after verification succeeds. Remove partial files on failure or cancellation and avoid overwriting existing archives, including when jobs run concurrently.
- Preserve the exclusion of `.DS_Store` and `._*` files and store symbolic links as links.

## Lint and formatting

Use `mise run format` to format Swift and shell scripts and `mise run lint` before submitting changes. Keep formatter rules in `.swiftformat` and tool versions and task definitions in `mise.toml`. CI runs the same lint task. See [Lint and formatting](docs/development-notes.md#lint-and-formatting) for setup and scope.

## Build and verification

Create temporary working directories for development and testing under `/tmp` with `mktemp -d /tmp/passarc.XXXXXX`. Remove every temporary directory created for the task when the work ends, including after failed or cancelled tests. For scripts, register an `EXIT` trap immediately after creating the directory so early exits also clean it up.

Run these commands from the repository root.

Start with the files and focused tests for the behavior you're changing.

For archive features that use external tools, verify the create-and-extract workflow with the real tools early. When the feature accepts user input, also check that users can correct invalid input and retry.

| Change | Start with | Focused test |
| --- | --- | --- |
| Password validation or available archive formats | `PasswordRules.swift`, `DialogState.swift` | `swift test --package-path Core --filter DialogStateTests` |
| Compression options or command-line arguments | `ArchiveOptions.swift`, `CommandBuilder.swift` | `swift test --package-path Core --filter CommandBuilderTests` |
| Output names and collision handling | `OutputNaming.swift`, `ArchiveJob.swift` | `swift test --package-path Core --filter OutputNamingTests` |
| Archive verification, cancellation, or partial-file cleanup | `ArchiveJob.swift` | `swift test --package-path Core --filter ArchiveJobTests` |
| Password prompts or pseudo-terminal behavior | `PTYRunner.swift` | `swift test --package-path Core --filter PTYRunnerTests` |
| Selected paths passed from Finder to the app | `Extension/FinderSync.swift`, `ArchiveURL.swift`, `App/AppDelegate.swift` | `swift test --package-path Core --filter ArchiveURLTests` |

Bare Swift filenames in the table are in `Core/Sources/PassArcCore/`. Run the full core suite when a change affects shared behavior, and build the app and extension when a change affects either target.

- `swift test --package-path Core` runs the core tests. Integration tests use real `7zz` and `zstd` binaries, available through `brew install sevenzip zstd`.
- `scripts/build.sh` builds the app and Finder Sync extension and verifies their signatures. The app bundle is generated at `build/scripts/PassArc.app`.
- If the compiler fails to start or cannot write its module cache, use the diagnostics and fallback in [Building without Xcode](docs/development-notes.md#building-without-xcode).
- `scripts/snapshot.sh <output-directory>` renders the dialog to PNG files. For changes to Finder integration, dialog launch, or notifications, check the affected workflow on macOS.
- For launch-window changes, follow [Verify the drag-and-drop launch window](docs/development-notes.md#verify-the-drag-and-drop-launch-window) through archive creation and content verification.
- For completion notification changes, click the notification and verify that Finder reveals every expected output. Include outputs in different parent folders when checking batch compression.
- For individual folder compression, verify that stopping a batch or encountering a failed folder preserves archives already saved and removes any unfinished archive.
- For changes to the archive result window, verify **Share** and **Show in Finder** on success and after stopping or failing a batch. Check that the actions include only saved outputs, including outputs in different parent folders.
- `scripts/build.sh --install` replaces `~/Applications/PassArc.app` and registers the Finder Sync extension. Use it when an installed build is needed.

See [README.md](README.md) for setup and verification steps and [development notes](docs/development-notes.md) for macOS and 7-Zip implementation details.

## Skill validation

When adding or editing a repository skill, run the `skill-creator` validator with `uv`. The command isolates PyYAML from the system Python. Pass the skill directory as the last argument.

```sh
uv run --no-project --with PyYAML==6.0.3 python \
  "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" \
  .agents/skills/review-work
```

## Commit and pull request checks

When asked to commit changes or open a pull request, verify that every intended file reaches the commit and the pull request.

1. Run `git status --short --branch --untracked-files=all` before editing. Note existing changes so you can distinguish them from the files you add or edit for the request.
2. Before committing, run the same status command and review both `git diff` and `git diff --cached`. Explicitly stage every in-scope file, including new documentation, images, and other assets. When a file mixes in-scope and unrelated changes, stage only the relevant hunks. Check `git diff --cached --name-status` against the intended file list and run `git diff --cached --check`.
3. After committing, inspect `git show --name-status --oneline HEAD` and rerun `git status --short --branch --untracked-files=all`. Resolve any in-scope files or hunks still staged, modified, or untracked before pushing or reporting completion. Leave unrelated user changes in place and report them if they remain.
4. For a pull request, compare `git diff --name-status <base>...HEAD` with the intended changes before pushing. After creating or updating the PR, use `gh pr diff <number> --name-only` to check the published file list and `gh pr view <number> --json url,baseRefName,headRefOid` to confirm the base and that the remote head matches `git rev-parse HEAD`. Report the PR link and any verification you could not complete.
5. After follow-up work on a submitted change, check where the new files and hunks ended up. If the follow-up includes publication, check the existing PR state before pushing. Use a new PR based on the latest target branch if the earlier PR has already merged. Report any follow-up changes that are still local.
