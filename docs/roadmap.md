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
