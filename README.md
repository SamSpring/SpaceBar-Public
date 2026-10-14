# SpaceBar

A little space in your menu bar. SpaceBar is a free, native Swift/AppKit app
that adds independent blank spacers, subtle dividers, and one flexible gap.
Hold **Command (⌘)** and drag an item to arrange it.

**[Download SpaceBar 2.4.0 for Mac](https://github.com/SamSpring/SpaceBar-Public/releases/download/v2.4.0/SpaceBar-2.4.0-arm64.zip)**
— Developer ID signed and Apple notarized. Visit the
[SpaceBar website](https://samspring.github.io/SpaceBar-Public/) or
[release page](https://github.com/SamSpring/SpaceBar-Public/releases/tag/v2.4.0).

## Requirements

- macOS **27.0 or later**.
- **Apple silicon (arm64)** for this download. Intel binaries
  and older macOS versions are not currently built or tested.
- Accessibility access is optional for ordinary spacers and dividers. It is
  needed for automatic flex geometry, safe growth, and layout snapshots and
  restoration. Screen Recording and administrator access are not requested.

## Everyday use

1. Download the ZIP, unzip it, and drag SpaceBar
   into Applications. Open it there. First launch creates one divider and
   opens Settings.
2. Add spacers or dividers. Use the width, shared divider height, and shared
   opacity controls. Show an item's number to identify it in the menu bar.
3. Hold **⌘** and drag an item into place. Click a spacer or divider to open
   its menu. Close Settings to hide the temporary numbers.
4. For an automatic gap, add the single flex spacer, use **Arrange**, drag it
   between icon groups, and choose **Center**. **Pause** lets you set its width
   manually. Center may wait when room or reliable measurements are missing.
5. Item settings save automatically. Optional **Layout Backup & Restore** is
   **Experimental**. Saving creates a separate named snapshot; restoring first
   saves a recovery snapshot. Only visible, identifiable icons can be restored;
   some need manual arranging. Missing or disabled icons cannot be restored.
6. Enable **Launch at Login** if desired. macOS may require approval in Login
   Items. Reopen the app from Applications to return to Settings.

There is no permanent controller icon. The running Dock icon appears while
Settings is open; macOS may retain a recent-app Dock entry after it closes.
Quit removes SpaceBar's menu bar items until the next launch.

## Placement limits

macOS controls global menu bar placement. Crowding, notches, display changes,
other apps, and menu bar managers can hide or move items. SpaceBar uses native
saved placement and public Accessibility APIs; it cannot guarantee an exact
cross-app arrangement or move locked system items. Flex centering targets the
main display. Experimental layout backup and restore also targets that display. Hidden or inaccessible icons
are not included in snapshots. Restore may be partial, and a stop control is
available while it runs.

Center observes while Settings is closed, pauses its observation during sleep,
and resumes after wake. Simulated wake cycles and a live multi-display recovery
were checked during development; real overnight idle/sleep behavior remains
under evaluation. This is a known release-validation item.

## Local data and permissions

Settings and snapshots stay in
`~/Library/Application Support/MenuBarSpacers/`. The compatibility bundle ID
is `local.samuelaviv.MenuBarSpacers`; keep it stable when distributing updates.
The internal name preserves older settings and item identities.

SpaceBar has no accounts or analytics. The updater checks the configured
HTTPS feed only when you choose **Check for Updates…**. You can review release
notes, download, and install through Sparkle’s signed-update UI. Automatic checks,
downloads, and installation are off. Development previews are compiled without Sparkle or public update access.
Checking explains that public updates are disabled to protect ongoing work;
setting a feed URL alone cannot enable them.
The signed, notarized download and manual updater passed installation and
relaunch checks in an isolated macOS VM. Existing settings, item identities,
and saved layouts were preserved. Experimental restoration may be partial;
full cross-app layout restoration has not been verified.
Accessibility reads menu bar geometry and icon identities and posts drag
events only during an explicit restore. **Open Accessibility Settings…**
opens System Settings when clicked; permission checks do not prompt or grant
access automatically. Exported settings and layouts can reveal app names or
item identities; review them before sharing. See [Privacy](docs/PRIVACY.md).

## Build and contribute

See [Building](docs/BUILDING.md), [release packaging](docs/RELEASING.md), and
[contribution notes](CONTRIBUTING.md). The source uses only Apple frameworks;
public builds use Sparkle 2.10.0 for signed in-app updates. Development builds
do not link Sparkle or contact public update feeds.

## License and support

Copyright © 2026 Samuel Aviv. Distributed under the [MIT License](LICENSE),
with attribution in [NOTICE](NOTICE). All features are free. Optional donations
through [Ko-fi](https://ko-fi.com/samspring) support development.
