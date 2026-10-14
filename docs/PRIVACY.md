# Privacy

SpaceBar does not include analytics, advertising, or accounts. Its manual
updater contacts the configured HTTPS update feed, release-note host, and
download host when you choose to check or install an update. These hosts can
see standard connection information such as IP address and an updater/app
version user agent. Automatic checks, downloads, and installation are off;
Sparkle system profiling is disabled. No private configuration or layouts
are uploaded by the app. Public updates use GitHub Pages and GitHub Releases.
Development previews are compiled without public update access. Settings are saved locally in
`~/Library/Application Support/MenuBarSpacers/configuration.json`; optional
Experimental layout backup and restore uses `layouts.json` in that folder.

Ordinary spacers and dividers do not need Accessibility permission. The
optional flex and layout features use it to read system-hosted menu bar
geometry and icon identities. A snapshot may contain app names, bundle
identifiers, icon labels, display dimensions, item IDs, and configuration.
Restore uses public Accessibility/Core Graphics APIs to perform an explicit
menu bar arrangement and can affect other apps' icons. It asks for confirmation
and saves a recovery snapshot first. No screen capture is requested.

Permission checks do not show an automatic system prompt. The app's button
opens System Settings, where you decide whether to enable access. Launch at
Login is a separate optional macOS setting. Local data remains after quitting
or removing the app; removing that data also removes saved items and layouts.

The download site has no analytics scripts, remote fonts, embeds, or cookies
added by this project. GitHub Pages logs visitor IP addresses for security
under [GitHub's privacy policy](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
Opening the optional Ko-fi link visits a separate service subject to its own
policies. Apple notarization checks the distributed executable; it does not
receive your local configuration or snapshots through SpaceBar.
