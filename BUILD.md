# Building SideQuest Client — Reproducible Verification Guide

This guide allows you to audit the SideQuest plugin and macOS app source code and verify that the binaries distributed in GitHub Releases were built faithfully from the published source.

## Prerequisites

**System Requirements:**
- macOS 14.0 or later
- Xcode 15.3 or later (Command Line Tools sufficient for plugin, full Xcode required for app)
- Git 2.36 or later
- Bash 5.0 or later

**Check your versions:**
```bash
sw_vers                          # macOS version
xcodebuild -version              # Xcode version (should show 15.3+)
git --version                    # Git version
bash --version                   # Bash version
```

**Optional Tools for Verification:**
- `shasum` (built-in on macOS)
- `codesign` (built-in with Xcode, for inspecting the app's ad-hoc signature)

---

## Building from Source

### Plugin Tarball

The SideQuest plugin is a portable Bash/Python package that installs into the Claude CLI. You can build and verify it locally.

**1. Clone the Repository at a Specific Release Tag**

To audit the exact code that was released, clone at the release tag:

```bash
# Example: clone at plugin release v0.2.0
git clone --depth 1 --branch plugin-v0.2.0 https://github.com/trySideQuest-ai/sidequest.git
cd sidequest
```

Verify you're at the correct tag:
```bash
git describe --tags HEAD
# Expected output: plugin-v0.2.0
```

**2. Build the Plugin Tarball**

The build script uses deterministic flags (`--sort=name --mtime`) to ensure reproducible archives:

```bash
# Build plugin with current tag version
./scripts/package-plugin.sh

# Output file: dist/sidequest-plugin-0.2.0.tar.gz (version from tag)
# Example output:
# ✓ Plugin packaged: dist/sidequest-plugin-0.2.0.tar.gz
#   Size: 128K
#   SHA256: abc123def456...
#   Version: 0.2.0
```

**3. Compute SHA256 of Local Build**

```bash
shasum -a 256 dist/sidequest-plugin-*.tar.gz
# Output: abc123def456... dist/sidequest-plugin-0.2.0.tar.gz
```

**4. Verify Against GitHub Release**

1. Navigate to https://github.com/trySideQuest-ai/sidequest/releases/tag/plugin-v0.2.0
2. In the **Release Notes** section, find the SHA256 hash for the plugin tarball
3. Compare with your local build:

```bash
# Expected: Your SHA256 matches the Release Notes exactly
echo "Expected: <paste-from-release-notes>"
echo "Got:      abc123def456..."
```

If they match, the plugin binary was built faithfully from the published source.

---

### macOS App DMG

The SideQuest app is a native macOS application built with Xcode. The CI workflow currently builds and ships the app with **ad-hoc signing** (no Apple Developer ID, no notarization). On first launch users must right-click → Open to bypass Gatekeeper.

**1. Clone at Release Tag**

```bash
git clone --depth 1 --branch app-v2.2.4 https://github.com/trySideQuest-ai/sidequest.git
cd sidequest
```

**2. Build the App**

The app requires Xcode (full IDE, not just Command Line Tools). The CI workflow uses Xcode 15.3 with ad-hoc signing:

```bash
cd macOS
xcodebuild -scheme SideQuestApp \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

# Package into DMG
APP_PATH="build/DerivedData/Build/Products/Release/SideQuestApp.app"
bash scripts/create-dmg.sh "$APP_PATH" "SideQuestApp-2.2.4.dmg"
```

Expected output:
```
SideQuestApp-2.2.4.dmg (size ~1.5-2 MB)
```

**3. Compute SHA256 of Local Build**

```bash
shasum -a 256 dist/SideQuestApp-*.dmg
# Output: abc123def456... dist/SideQuestApp-1.8.0.dmg
```

**4. Verify Against GitHub Release**

1. Navigate to the release page on GitHub for the tag you cloned (`app-v<version>`).
2. Find the DMG SHA256 in the Release Notes.
3. Compare:

```bash
echo "Expected: <paste-from-release-notes>"
echo "Got:      abc123def456..."
```

---

## Inspecting the App Signature

The CI workflow currently signs the app **ad-hoc** (no Apple Developer ID, no notarization). You can confirm this:

```bash
# Mount the DMG, then:
codesign -dvv /Volumes/SideQuestApp/SideQuestApp.app
# Expected: "Signature=adhoc"
```

Because the app is ad-hoc signed, macOS Gatekeeper will block it on first launch. To run it, right-click the app and choose **Open**, then confirm the prompt. This is the same flow other open-source macOS apps use when they ship without a paid Developer ID.

The repository contains `macOS/scripts/build-and-sign.sh` and `macOS/scripts/notarize.sh` for Developer-ID + notarization, but they are not invoked by the CI workflow today.

---

## Reproducibility Notes

### Deterministic Plugin Builds

The plugin build script uses reproducible archive flags:

- `--sort=name` — files ordered alphabetically (reproducible across systems)
- `--mtime=@{EPOCH}` — all files timestamped to commit date (from `git log`)
- `--owner=0 --group=0` — all files owned by root (portable across systems)
- `--numeric-owner` — UIDs/GIDs use numeric values (not user names, which vary)

Two builds of the same tagged version should produce identical SHA256 hashes.

### Xcode App Builds

The macOS app build uses:

- **Xcode version:** Pinned to 15.3 via `.xcode-version`
- **Build configuration:** Release
- **Code signing:** Ad-hoc only (`CODE_SIGN_IDENTITY="-"`)

Note: macOS app binaries are not byte-reproducible — Xcode embeds non-deterministic timestamps and the ad-hoc signature changes per build. Verify the DMG via SHA256 of the distribution artifact published in the Release Notes. The plugin tarball, by contrast, is reproducible.

---

## Troubleshooting

### Plugin Build Fails

**Error: `package-plugin.sh: No such file or directory`**
- Ensure you're in the repo root (`sidequest/`)
- Verify `scripts/package-plugin.sh` exists: `ls -la scripts/package-plugin.sh`

**Error: `tar: Unknown option --sort=name`**
- macOS ships with BSD tar; install GNU tar via Homebrew:
  ```bash
  brew install gnu-tar
  # Apple Silicon
  export PATH="/opt/homebrew/opt/gnu-tar/libexec/gnubin:$PATH"
  # Intel Macs
  # export PATH="/usr/local/opt/gnu-tar/libexec/gnubin:$PATH"
  ```

### App Build Fails

**Error: `xcodebuild: command not found`**
- Install Xcode: `xcode-select --install`
- Or launch Xcode from `/Applications/` at least once

**Error: `Xcode 15.3 not found` (if using a different version)**
- Pinned Xcode version may not be available on your system
- Edit `.xcode-version` to your installed version (e.g., `16.0`)
- Note: cross-version Xcode builds may produce different binaries

**Error: `Code signing failed`**
- The CI build uses ad-hoc signing — pass `CODE_SIGN_IDENTITY="-"` and the related flags shown in the build command above.

### SHA256 Mismatch

**If your local build SHA256 doesn't match the Release:**

1. **Verify your tag:** `git describe --tags HEAD` should match the release tag
2. **Check tool versions:** Xcode or tar version mismatch can affect output
3. **Report the issue:** File a GitHub issue with:
   - Your macOS version
   - Your Xcode version
   - Your local SHA256
   - Link to the Release notes SHA256

---

## Security Considerations

### What This Verification Proves

✓ The published plugin tarball SHA256 matches a deterministic build of the tagged source  
✓ The DMG SHA256 matches what was uploaded by CI for the tagged release  
✓ The app is ad-hoc signed (no third-party Developer ID involved)  

### What This Verification Does NOT Prove

✗ The source code is secure or bug-free (code review is separate)  
✗ The binary is free from all vulnerabilities  
✗ The macOS app has been notarized by Apple — it has not  
✗ Future builds will be byte-identical (toolchain updates may affect results)  

For security concerns, see [SECURITY.md](SECURITY.md).

---

## FAQ

**Q: Can I install the app I built locally?**
A: Yes. Mount the DMG and drag SideQuestApp.app to /Applications. Because the build is ad-hoc signed, on first launch right-click the app and choose **Open** to bypass Gatekeeper.

**Q: Will my locally-built plugin work with the Claude CLI?**
A: Yes. Extract the tarball and follow the installation instructions in the main README.md.

**Q: Why is the macOS app not byte-identical after rebuild?**
A: Xcode embeds non-deterministic timestamps in the binary, and the ad-hoc signature changes per build. The DMG SHA256 published in the Release Notes is the canonical artifact to compare against.

**Q: What if I don't trust GitHub Releases SHA256 links?**
A: Clone the repo, build from the tagged source yourself, and compare the resulting plugin tarball SHA256 to the value in the Release Notes. The plugin build is reproducible across machines.

---

## References

- [Reproducible Builds](https://reproducible-builds.org/) — Archive metadata standards
- [GNU tar Manual: Making Archives More Reproducible](https://www.gnu.org/software/tar/manual/html_section/Reproducibility.html)
