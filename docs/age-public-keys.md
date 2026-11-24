# Use public keys with PassArc

## When to use public keys

For recurring file sharing, each recipient can give you their public key once and use their own private key to open the archives you send. You can encrypt a single archive for several recipients without exchanging a shared passphrase. If you also want to open the archive later, include your own public key.

For a one-off transfer to someone without a key pair, **Passphrase** lets you start immediately. Use a strong, unique passphrase and share it through a separate channel. Both modes encrypt the contents and the file names inside the archive.

## Prepare a key pair

The recipient creates the key pair and sends the sender the public key. Confirm that the public key belongs to the intended recipient through a channel you trust before using it.

### Create an age key

In the PassArc compression dialog, choose **tar.zst.age**, enable **Encrypt archive**, and select **Public keys**. If neither key file exists in the default folder, click **Create Key Pair…** and confirm. PassArc saves the keys in `~/.config/passarc/keys` and adds the public key to the recipient list.

### Create an age key from the terminal

On macOS, install age with `brew install age` if needed. From the PassArc repository root, run:

```sh
scripts/create-age-keypair.sh
```

The script creates both files in `~/.config/passarc/keys` and prints their paths. It stops if either key file already exists. To create a pair in a different directory, pass the directory as an argument.

```sh
scripts/create-age-keypair.sh "$HOME/.config/passarc/another-key"
```

To create the pair without the repository, run these commands in the directory where you want to keep the keys.

```sh
age-keygen -o passarc-identity.txt
age-keygen -y -o passarc-recipient.txt passarc-identity.txt
```

Share `passarc-recipient.txt`. Keep `passarc-identity.txt` private and retain a secure backup. You'll need the identity file to open archives encrypted to this key. If you lose it, you'll need another listed recipient to decrypt those archives for you.

Classic age keys work with older age versions. To choose hybrid post-quantum protection, use `age-keygen -pq -o passarc-identity.txt` in the key-generation step. Install age 1.3.0 or later on both sides and use a post-quantum key for every recipient of that archive. [age documentation](https://github.com/FiloSottile/age#post-quantum-keys)

### Use an SSH key

If you already have an SSH Ed25519 or RSA key pair, share the `.pub` file and keep the corresponding private key file for extraction. RSA keys must be at least 2048 bits. If you're creating a key specifically for PassArc, choose an age key so its lifetime is independent of your SSH credentials. [age manual](https://github.com/FiloSottile/age/blob/main/doc/age.1.ronn#ssh-keys)

## Encrypt and extract in PassArc

1. Select **tar.zst.age**, enable **Encrypt archive**, and choose **Public keys**.
2. When you first select **Public keys** in the dialog, PassArc fills the empty list from `~/.config/passarc/keys/passarc-recipient.txt` if available. Review the list and remove any keys you do not want to include. Paste one recipient public key per line or use **Import Recipient File…** to add keys from another file. The **?** button beside it explains how to navigate to a hidden folder. Click **Compress** and send the resulting `.tar.zst.age` file.
3. The recipient right-clicks the archive in Finder and chooses **Extract with PassArc**. Under **Identity file**, PassArc selects `~/.config/passarc/keys/passarc-identity.txt` if it is readable. Use **Choose…** or **Change…** to select a different key, then click **Extract**. The **?** button explains how to open a hidden folder in the file picker. If PassArc prompts for the SSH private key passphrase, enter it and click **Extract** again.

PassArc uses `age` and `zstd` for this format. See [Build from source](../README.md#build-from-source) for setup.
