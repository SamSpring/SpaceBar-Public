# SpaceBar 2.4.0 — first public release

Native menu bar spacers and dividers, free and open source.

- Independent blank spacers and adjustable dividers you can Command-drag.
- One flex spacer that can adjust a centered gap as icons change.
- Experimental layout backup and restore, with named snapshots and recovery
  before an explicit restore. Only visible, identifiable icons can be restored;
  some need manual arranging. Missing or disabled icons cannot be restored.
- Local settings, optional Launch at Login, and no permanent controller icon.
- Background centering recovery after display, session, and wake changes.
- Manual **Check for Updates…** using Sparkle’s signed-update UI.
  Automatic checks and downloads are off.

Download target: Apple silicon, macOS 27.0 or later. Ordinary items
work without Accessibility; flex geometry and layout features need access.
macOS owns placement, so crowded or changed bars may need manual adjustment.
Intel support is unverified. Real overnight sleep/wake testing is still pending.

Build 25 is Developer ID signed, Apple notarized, and includes a stapled
notarization ticket. Installation from a quarantined download and the manual
update flow passed in an isolated macOS VM, preserving settings and item IDs.
Full cross-app layout restoration has not been verified and remains Experimental.

Copyright © 2026 Samuel Aviv / SamSpring. Released under the MIT license.
All features are free; [Ko-fi support](https://ko-fi.com/samspring) is optional.
