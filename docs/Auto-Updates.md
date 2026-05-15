# Auto Updates

Ultimate Organizer uses Sparkle to check GitHub Pages for:

```text
https://ginnov.github.io/Ultimate-Chrome-Bookmarks/appcast.xml
```

The GitHub workflow builds a signed Sparkle appcast and publishes the DMG plus appcast whenever code is pushed to `main`.

## Required GitHub Secrets

- `SPARKLE_PUBLIC_ED_KEY`: the public EdDSA key embedded in the app bundle.
- `SPARKLE_PRIVATE_KEY`: the matching private EdDSA key used by `generate_appcast`.

Generate the key pair with Sparkle's `generate_keys` tool. Keep the private key out of git and store it only as the GitHub secret.

## Local Packaging

For release-like local DMGs, pass the public key when packaging:

```bash
SPARKLE_PUBLIC_ED_KEY="..." ./script/package_dmg.sh
```

The build script ad-hoc signs local bundles by default. Set `CODE_SIGN_IDENTITY` if you want a Developer ID signature.
