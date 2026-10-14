# Contributing

Keep changes small and include the user-visible problem, resulting behavior,
and relevant checks. Use plain, concise descriptions. Start with the build
instructions in docs/BUILDING.md. Run the core tests for behavior changes.

Preserve permanent item IDs, the compatibility bundle ID, existing settings
and layout formats, native placement preferences, and login registration.
macOS owns global placement; do not add undocumented preference writes or
promise exact restoration of every app's icons.

Do not commit local settings, layouts, certificates, private keys, signing
credentials, recovery records, or screenshots of unrelated personal data.
Use an isolated preview bundle for native tests and quit it afterward.

Do not publish security-sensitive details in an issue. Use the repository's
private vulnerability reporting feature when enabled. Before it is enabled,
request a private reporting route without including exploit details.

Contributions are made under the project's MIT License.
