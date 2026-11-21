# PassArc roadmap

Make it easier to create a password-protected archive from Finder, share it, and help the recipient open it.

## Implemented

- **Generate and copy passwords.** Generate Password fills both password fields with a random 24-character password. Copy Password copies a valid, matching password to the clipboard for sharing through a separate channel. Passwords stay out of saved settings, command-line arguments, and logs.
- **Show format compatibility before compression.** The format selector explains that password-protected 7z archives encrypt file names and that recipients may need a compatible app to open AES-256 archives.

## On hold

2. **Share from the completion screen.** Offer Share and Show in Finder actions after the archive has been verified and saved.

## Follow-up features

4. **Compress selected folders individually.** Let users create one archive per selected folder in a single operation, with each archive saved next to its source.
5. **Add a drag-and-drop launch window.** Let users open PassArc and drop files or folders onto it to start archiving, including when the Finder extension is disabled.

## Distribution

**Sign and notarize public builds.** Reduce Gatekeeper friction on first launch. Prioritize this alongside the next feature release if the focus shifts to helping new users get started.
