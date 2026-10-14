# Project guidance

Use plain, concise communication. Lead with the user-visible result and keep
material risks, limits, uncertainty, and decisions visible. Keep detailed logs
in linked records. Include this guidance in new handoffs and delegated work.

SpaceBar is a native Swift/AppKit app. Preserve permanent item identifiers,
configuration and snapshot compatibility, native menu bar placement preferences,
the bundle ID `local.samuelaviv.MenuBarSpacers`, the `MenuBarSpacers` support
folder/settings domain, and login-item registration during updates.

Keep the project self-contained. Builds and tests must use isolated output;
do not install, restart, or change a user's working app as part of preparation.
Do not expose keys, certificates, credentials, user settings, layouts, private
recovery records, or unrelated desktop content in source or release assets.

Manual updates must use Sparkle's signed archive verification and normal native
install/relaunch flow. Automatic checking/downloading/installation stays off.
Do not interrupt layout operations or discard in-progress changes for an update.
Publish only after the publisher approves the concrete source/site/binary/feed
and required signing, notarization, and installation checks have passed.
