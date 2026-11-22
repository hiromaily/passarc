# PassArc roadmap

Make it easier to create a password-protected archive from Finder, share it, and help the recipient open it.

## Implemented

- **Simplify archive protection and age recipient parsing.** Each creation request has one protection mode. Core validates format compatibility and shares recipient parsing with the dialog while preserving original line numbers for errors. This reduces the files and branches contributors and AI coding tools need to trace when changing archive protection.
- **Create and extract public-key-encrypted tar.zst.age archives.** Paste recipient age or SSH public keys or import a recipient file when creating an archive. Choose the matching private key file when extracting it. PassArc checks the compressed data and saves it after age successfully encrypts it to the specified recipients. [age format specification](https://age-encryption.org/v1)

- **Generate and copy passwords.** Generate Password fills both password fields with a random 24-character password. Copy Password copies a valid, matching password to the clipboard for sharing through a separate channel. Passwords stay out of saved settings, command-line arguments, and logs.
- **Show format compatibility before compression.** The format selector explains that password-protected 7z archives encrypt file names and that recipients may need a compatible app to open AES-256 archives.
- **Compress selected folders individually.** Select multiple folders and choose **Create a separate archive for each folder** to save one archive next to each source.
- **Compress immediate subfolders individually.** Select a parent folder to create one archive per immediate subfolder. Skip the parent folder itself and any files directly inside it. Include deeper descendants in their immediate subfolder’s archive.
- **Add a drag-and-drop launch window.** Open PassArc and drop files or folders onto it to start archiving, including when the Finder extension is disabled.
- **Share from the completion screen.** Use **Share** or **Show in Finder** after PassArc verifies and saves the archives. These actions also work for archives saved before a batch stops or fails.
- **Create and extract passphrase-encrypted tar.zst archives.** age encrypts the entire compressed archive, including its file names. Recipients need PassArc or compatible age and Zstandard tools. [age format specification](https://age-encryption.org/v1)
- **Show the installed PassArc version.** The launch window displays the version of the PassArc build you are running.
- **Play a sound when compression or extraction completes.** PassArc plays a completion sound after successful compression or extraction, once per completed batch.
- **Lock GitHub Actions dependencies.** Workflow action versions are locked to exact commits in `.github/workflows/actions.lock`. CI verifies the lockfile when workflow YAML or the lockfile changes. Run `gh actions-lock` after updating a workflow dependency. [gh-actions-lock](https://github.com/github/gh-actions-lock)
- **Reduce temporary disk usage during extraction.** PassArc streams Zstandard output into tar for `.tar.zst` and `.tar.zst.age` and publishes the extracted files after both commands succeed. A command-line comparison of the two extraction pipelines with a 128 MiB file measured peak staging usage of about 256 MiB before streaming and 128 MiB after streaming, for both formats.

## On hold

- **Sign and notarize public builds.** Resume when the signing and notarization prerequisites are ready.

## Archive processing improvements to evaluate

- **Review shared encryption code when adding another method.** Compare how the new method and age locate tools, accept passphrases or keys, and report errors during creation, verification, and extraction. Consolidate the parts that follow the same workflow.

## Planned refactoring

- **Share exclusive output finalization.** Reuse the rename and collision retry logic for archive creation and extraction. Preserve creation's name reservations and each job's cancellation and error handling.

Defer sharing the tar and Zstandard pipelines because creation reports byte progress and extraction must validate the remaining Zstandard stream after tar finishes.

## Encrypted archive formats to evaluate

Compare recipient tool support, password and public-key workflows, file name protection, and the dependencies needed to create, verify, and extract each format before adding another option.

Before implementing a format, define how users create an archive in PassArc, how recipients extract it, and what PassArc verifies before saving it.

- **RAR 5 (`.rar`).** Evaluate compatibility with WinRAR and other RAR tools. RAR 5 supports AES-256 and optional header encryption to hide file names. Check tooling and redistribution terms for both archive creation and extraction. [RAR 5 format specification](https://www.rarlab.com/technote.htm)
- **OpenPGP-encrypted tar.zst.** Evaluate sharing with recipients who already use OpenPGP keys. Check which tools interoperate with RFC 9580 authenticated encryption and Argon2id passphrase protection. [RFC 9580](https://www.rfc-editor.org/rfc/rfc9580.html)
- **ZIP with AES-256-GCM.** Evaluate WinZip's authenticated encryption option. Check whether `7zz` and recipient tools can read and write it before offering it alongside the existing AES-encrypted ZIP option. [WinZip release notes](https://www.winzip.com/en/support/updates/)
