# SpaceBar 2.4.2 — flex fallback and optional support

- Collapse the flex spacer to a temporary 1 pt when right-hand icons reach or cross the display center, while keeping Center enabled and your normal minimum gap saved. macOS adds its own small item padding.
- Keep recovery from that temporary width compatible with normal settings and saved layouts.
- Add an illustrated **Buy me a coffee** button in Settings, linked to the existing optional Ko-fi page.
- Show a small, dismissible thank-you once after adopting this feature or successfully launching a newer update. **Not now** dismisses it; **Don’t show this after updates** turns it off. Fresh installations and ordinary relaunches stay quiet. The support page opens only when you click its button.

Your existing spacers, dividers, saved layouts and settings remain compatible. Updates are manual; automatic checks and downloads remain off.

macOS controls placement and capacity. The temporary collapse cannot move right-hand icons themselves away from the center. Natural expansion after pressure clears, overnight sleep/wake, extreme crowding and other hardware are not fully validated. Optional layout backup and restore remains Experimental.

Apple silicon · macOS 27.0 or later. Copyright © 2026 Samuel Aviv / SamSpring. MIT license.

---

# SpaceBar 2.4.1 — flex centering improvements

- Apply a permitted centering adjustment in one step instead of repeated small growth steps.
- Refresh remembered size limits when surrounding icons, their owners, the right anchor, or the display arrangement change.
- Recover more reliably from interrupted or inconsistent menu bar measurements.
- Add an optional **Keep centered when left icons overflow** setting for the flex spacer. When enabled, macOS may hide leftmost icons as the centered gap grows. Existing configurations keep this option off until you select it.

Your existing spacers, dividers, saved layouts and settings remain compatible.
Updates are still manual; automatic checks and downloads remain off.

macOS controls placement and capacity. Hidden icons' internal order cannot be verified. Extreme crowding, overnight sleep/wake and other hardware are not fully validated. Optional layout backup and restore remains Experimental.

Apple silicon · macOS 27.0 or later. Copyright © 2026 Samuel Aviv / SamSpring. MIT license.

---

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
