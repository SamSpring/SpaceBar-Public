# Building SpaceBar

Use an Apple silicon Mac running macOS 27 and Xcode Command Line Tools with
the macOS 27 SDK. The package declares Swift tools version 6.0; the prepared
release is verified with Apple Swift 6.4 and SDK 27.0. Other toolchains and
Intel builds remain unverified.

From the source root:

```sh
swift test --scratch-path "$(mktemp -d /tmp/spacebar-core-tests.XXXXXX)"
bash scripts/release-build.sh local release-output/local-preview
```

The script builds an optimized arm64 development binary, assembles an isolated
`SpaceBar Preview.app`, signs it ad hoc, verifies its signature, and creates
a ZIP marked `LOCAL-ONLY`. It does not create credentials or use a private
signing helper. Local builds are not notarized and may be blocked by
Gatekeeper. They are not the ordinary public download.

The preview bundle identifier ends in `.UITests`, so an accidental preview
launch has a separate settings store and does not register a production
login item. The build does not launch the app or run native UI probes.
For development, open the preview deliberately and quit it when finished.

Every packaging run requires a new output directory inside `release-output/`.
Build staging and Swift scratch output use a temporary folder outside cloud
sync; that folder is removed after the run. The finished bundle, archive,
metadata, and build log are kept in the chosen output directory. Existing outputs are
never overwritten. The scripts do not install, relaunch, stop, or change an
app in Applications. They do not change permission or login registration.

Do not run a second production-identifier app beside an existing install.
For a distributor build, see [Releasing](RELEASING.md).

Default development builds do not resolve/link/embed Sparkle or reach a public
feed. Release compilation explicitly enables the public channel; a feed URL
alone cannot enable updates in a development binary. `bash scripts/build.sh`
in this public source snapshot is a safe shortcut to an isolated development
preview; it never creates local certificates or Keychain items. The lower-level
accepted app builder is `scripts/build-app.sh`. Swift test scratch
output should be outside cloud-sync folders to avoid metadata signing errors.

The icon can be regenerated with `swift scripts/generate-icon.swift "$PWD"`.
It resizes the approved Resources/AppIconSource.png master without redrawing
it, and changes only the generated icon resources and local iconset. Builds
include the master, so no external design folder is needed.
