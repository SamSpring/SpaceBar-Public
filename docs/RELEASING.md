# Releasing SpaceBar

This workflow produced SpaceBar 2.4.0 build 25, the first public release.
Developer ID signing, Apple notarization, quarantined-download installation,
and manual updater installation passed in an isolated macOS VM. Each later
release needs its own approval and distribution checks.

## What can be done before Apple membership

Review the clean source snapshot, license, publisher identity, site, docs, and
notes. Build local previews and test the signed-update flow with isolated test
apps/keys. Prepare GitHub Pages and Releases configuration privately. Source
publication does not require Apple membership.

The first public binary targets Apple silicon / macOS 27. Keep the internal
bundle identifier `local.samuelaviv.MenuBarSpacers`. Do not bundle user settings,
layouts, local credentials, recovery records, or developer screenshots.

## Production signing prerequisites

After authorized Apple Developer Program enrollment, obtain a **Developer ID
Application** certificate for the publisher's team. Apple currently lists
membership at US$99 per year, or local currency where available. Keep the
certificate and private key in private non-cloud release storage/Keychain.
Use Xcode's existing notarization tools and an approved, stored `notarytool`
Keychain profile. The scripts never create/import credentials or enroll/pay.

Provision a separate production Sparkle Ed25519 signing key after authorization,
using the official `generate_keys` tool with a dedicated account. Retain an
encrypted recovery copy in private non-cloud storage. Only its **public** key
belongs in source and the app. The Apple certificate and update-signing key
serve different purposes; losing or exposing either requires careful recovery.

## Build, notarize, and package

Set the approved HTTPS feed and Sparkle public key in
`release/update-config.json`. Use the app owner's accepted version/build contract
and ensure `CFBundleVersion` increases for every distributed update. Configure
the approved public repository URL in `site/release.json`.

```sh
SIGNING_IDENTITY='Developer ID Application: Approved Publisher (TEAMID)' \
  bash scripts/release-build.sh developer-id release-output/signed-candidate
NOTARY_PROFILE='approved-existing-profile' \
  bash scripts/release-notarize.sh \
  release-output/signed-candidate/SpaceBar-2.4.0-arm64-SIGNED-UNNOTARIZED.zip \
  release-output/notarized-candidate
```

The wrapper uses the accepted app builder with `SPACEBAR_UPDATE_CHANNEL=public`,
embeds Sparkle, signs its nested helpers from the inside out, and
signs the outer app with hardened runtime and a secure timestamp. It adds
LICENSE/NOTICE and re-signs before notarization. Default local previews are
compiled as development copies with no public feed or embedded Sparkle. Public builds
must not use the local preview's library-validation exception. Verify all
helpers use the same Apple team and retain their required upstream entitlements.

The signed build is retained as a `SIGNED-UNNOTARIZED.zip` and verified after
extraction before handoff. Use its versioned filename from `build-metadata.json`.
Keep the ZIP intact; an unpacked app in cloud storage can lose framework links
or content after an initial successful check. Notarization extracts the ZIP
into temporary local storage and repeats the signature check before upload.

Notarization submits a ZIP to Apple's automated security check. An **Accepted**
result is required. Staple the ticket to the app, validate it, run macOS
distribution/Gatekeeper assessment, then make the final ZIP from that stapled
app. Signing/notarization staging and later checks run outside cloud sync;
the feed pipeline extracts and validates the exact final ZIP in a fresh
temporary folder. This avoids later Finder/OneDrive metadata invalidating an
app-directory check. ZIP files themselves cannot carry a stapled ticket. The script emits
SHA256SUMS.txt. Do not change the app or ZIP after approval, notarization, or
update signing. A changed build must repeat those steps.

Notarization is separate from App Store review. This is a direct-download app;
the proposed release does not require listing it in the Mac App Store.

## Generate the signed update feed

Use official tools from the pinned Sparkle 2.10.0 distribution:

```sh
SPARKLE_TOOLS='/private/path/to/Sparkle/bin' \
SPARKLE_KEY_ACCOUNT='approved-existing-spacebar-key-account' \
  bash scripts/release-appcast.sh release-output/notarized-candidate \
  release-output/feed-candidate
```

The feed points to the **same immutable ZIP** used for website downloads. It
uses increasing build numbers, embedded release notes, minimum macOS 27, and
an explicit arm64 hardware requirement checked against the executable. The
prepared generator supplies version/OS/notes/signature data; a final schema
step adds arm64 when Sparkle omits that label. Archive signatures are
created by Sparkle's `generate_appcast`, never custom download/execute code.
The pipeline verifies the existing signing account's public key matches the
embedded key, then verifies the final archive signature with Sparkle's tool.
The feed itself is not configured for optional signed-feed enforcement;
HTTPS and signed-archive validation are required. Delta updates are disabled
for the first simple release.

Preserve earlier feed items when producing later updates. Retain previous
public archives, feed, and notes in private release staging. Set
`PREVIOUS_FEED_STAGE` to that reviewed staging directory on later runs; the
script copies only its feed and versioned ZIP/notes into a fresh output and
refuses to overwrite a released archive name. It reuses the previous feed so
older items keep their existing URLs. It does not modify the live feed.
For the first release, the supplied script generates one item. Validate the
feed and archive lengths, version, OS/hardware requirements, release notes,
and signature; test them with an older isolated app. The public feed and public
key are recorded in release/update-config.json. Keep all private signing
material outside the source repository.

## Installation and updater acceptance

On a clean supported test Mac, VM, or separate test account, download the exact
ZIP using a normal browser so quarantine metadata is present. Verify its hash;
unzip, move to Applications, and open without removing quarantine or bypassing
Gatekeeper. Record successful first launch, permissions guidance, and quit.
Do not use Samuel's live SpaceBar installation for this test.

Check manual update UI for current version, offline/failure, incompatible OS or
architecture, valid newer release notes, user-approved download/install, and
relaunch. Tampered archives/signatures must fail. Automatic checking/downloading
must remain off. Verify installation waits for a restore and in-progress edits,
and preserves configuration/layout bytes, item UUIDs, placement preferences,
permissions, login registration, and Settings/Dock behavior. Local ad-hoc tests
do not prove Developer ID, Gatekeeper, or first-transition permission behavior.
Repeat acceptance using the actual Developer ID-signed builds before release.
The first transition from a self-issued development signature to an Apple
Developer ID signature may require Accessibility reapproval. Do not infer
permission continuity from local tests or ship a public update to the protected
development channel; any migration of an existing local install is separate.

## Publish after approval

Use a fresh public repository from the reviewed source export, retaining the
existing personal-history repository privately. GitHub Releases can host the
ZIP, SHA256SUMS.txt, and notes. GitHub Pages can host only `site/`, including
the approved `appcast.xml`. The Pages workflow uses manual dispatch and the
`github-pages` environment. Keep deployment restricted to the release branch;
use required reviewer protection when available for the repository.

Create a draft release, upload the exact verified files, check their hashes
and links, then publish after the publisher's approval. Set `repositoryUrl`,
`downloadUrl`, checksum, notarized/installation flags in `site/release.json`
only after their evidence exists. Run `python3 scripts/validate-site.py --release`
before the manual site deployment. Never upload the entire workspace, signing
tools, test fixtures, or release-output directory.

Keep the feed stable and available. Do not overwrite a released version's
archive. Withhold a bad newer update before installation; for a correction,
ship a new higher build number. Keep a backup of the previous feed/site and
draft state so publication can be withdrawn without touching users' data.

## Official references (checked 10 October 2026)

- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [Apple membership](https://developer.apple.com/programs/whats-included/)
- [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple signing requirements](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- [Sparkle setup and security](https://sparkle-project.org/documentation/)
- [Sparkle publishing](https://sparkle-project.org/documentation/publishing/)
- [Sparkle manual defaults](https://sparkle-project.org/documentation/customization/)
- [GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [GitHub funding](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository)
