# PassArc roadmap

Make it easier to create a password-protected archive from Finder, share it, and help the recipient open it.

## Implemented

- **Generate and copy passwords.** Generate Password fills both password fields with a random 24-character password. Copy Password copies a valid, matching password to the clipboard for sharing through a separate channel. Passwords stay out of saved settings, command-line arguments, and logs.
- **Show format compatibility before compression.** The format selector explains that password-protected 7z archives encrypt file names and that recipients may need a compatible app to open AES-256 archives.
- **Compress selected folders individually.** Select multiple folders and choose **Create a separate archive for each folder** to save one archive next to each source.
- **Add a drag-and-drop launch window.** Open PassArc and drop files or folders onto it to start archiving, including when the Finder extension is disabled.
- **Share from the completion screen.** Use **Share** or **Show in Finder** after PassArc verifies and saves the archives. These actions also work for archives saved before a batch stops or fails.

## On hold

- **Sign and notarize public builds.** Resume when the signing and notarization prerequisites are ready.

## Encrypted archive formats to evaluate

Expand the formats PassArc can create and extract. Compare recipient tool support, password and public-key workflows, file name protection, and the dependencies needed to create, verify, and extract each format before choosing what to build first.

- **Age-encrypted tar.zst (`.tar.zst.age`).** Encrypt the entire compressed archive, including its file names. Evaluate passphrase encryption with scrypt and public-key encryption as separate workflows. Recipients need an age-compatible tool. [age format specification](https://age-encryption.org/v1)
- **RAR 5 (`.rar`).** Evaluate compatibility with WinRAR and other RAR tools. RAR 5 supports AES-256 and optional header encryption to hide file names. Check tooling and redistribution terms for both archive creation and extraction. [RAR 5 format specification](https://www.rarlab.com/technote.htm)
- **OpenPGP-encrypted tar.zst.** Evaluate sharing with recipients who already use OpenPGP keys. Check which tools interoperate with RFC 9580 authenticated encryption and Argon2id passphrase protection. [RFC 9580](https://www.rfc-editor.org/rfc/rfc9580.html)
- **ZIP with AES-256-GCM.** Evaluate WinZip's authenticated encryption option. Check whether `7zz` and recipient tools can read and write it before offering it alongside the existing AES-encrypted ZIP option. [WinZip release notes](https://www.winzip.com/en/support/updates/)
