# Ticket Organizer

A native, offline macOS app for organizing RITM and CHG ticket notes. Requires macOS 14 or later. Universal builds support Apple Silicon and Intel Macs.

## Daily use

- Click once to select a ticket; double-click to open a movable, resizable editor.
- Organize notes into Draft, Pending Approval, Approved, and Examples.
- Drag a ticket onto a workflow in the sidebar to move it. The target highlights on hover; successful drops save immediately and open the destination list.
- Choose a creation date and time when adding a note.
- Drafts require only an RITM number; CHG, title, and body can be filled in later.
- The app opens Draft by default. New notes default to Draft with Low priority.
- Click the Created column heading to switch between newest-first and oldest-first order.
- Search RITM, CHG, titles, or note text; filter by priority.
- Select text and press Command-B to toggle bold. Body text defaults to 16 pt.
- Press Command-S in the editor to save. Changes close the editor only after saving succeeds.
- Delete the selected ticket with Delete Selected Ticket or its context menu, then confirm.

New installations start with an empty list. Existing notes are preserved. There is no account, web service, or telemetry.

## Install

Download and unzip the release archive, then move Ticket Organizer.app to Applications. Quit the old version before replacing it. App updates do not delete saved notes.

Current locally generated archives are ad-hoc signed for testing, not Apple Developer ID signed or notarized. macOS may require approval in System Settings > Privacy & Security. Do not disable Gatekeeper globally.

## Data and backups

Notes are stored only on this Mac:

```text
~/Library/Application Support/TicketOrganizer/tickets.json
~/Library/Application Support/TicketOrganizer/tickets.json.backup
```

The backup contains the previous successful save; it is replaced on the next successful change. Include this folder in your normal Mac backups. For a manual backup, quit the app and copy the folder to another location.

To recover, quit the app, make a copy of both files, inspect the backup, and restore the desired copy as tickets.json. If the current file cannot be read, the app reports an error and blocks writes rather than replacing it. Save errors leave edited text open for retrying.

Older versions did not record creation time. Their last-modified timestamp is used as the initial creation time and preserved on subsequent edits. The original creation time cannot be reconstructed.

## Develop and test

Use Xcode 15 or later, or its command-line tools:

```bash
swift run
swift test
```

Open Package.swift in Xcode to build and debug. Tests cover legacy date migration, persistence, deletion, backup behavior, write failures, damaged files, and selected-text bold formatting.

## Package

```bash
./scripts/build-app.sh
open "dist/Ticket Organizer.app"
```

VERSION controls the default release version. Override version and build number when needed:

```bash
MARKETING_VERSION=1.1.4 BUILD_NUMBER=18 ./scripts/build-app.sh
(cd dist && shasum -c SHA256SUMS)
```

The script builds both CPU architectures, validates the bundle and signature, verifies the ZIP, and generates relative SHA256 checksums. Artifacts are written to dist/ and are not committed to Git.

## Developer ID distribution

Install your Apple Developer ID Application certificate and store notarization credentials in a local notarytool keychain profile. These credentials are not part of this repository.

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \\
NOTARY_PROFILE="ticket-organizer-notary" \\
REQUIRE_NOTARIZATION=1 \\
./scripts/build-app.sh
```

This signs with the hardened runtime, submits to Apple, staples the accepted ticket, and checks Gatekeeper assessment. REQUIRE_NOTARIZATION=1 rejects builds without the signing identity and notarization profile.

## GitHub builds

Pushes to main, pull requests, and manual runs execute tests and package the app. A vX.Y.Z tag must match VERSION and creates a **draft** GitHub Release with the ZIP and checksums. The CI build is ad-hoc signed; use the Developer ID process above and replace the draft assets before publishing for general distribution.

For the next release, update VERSION, commit, and push the matching tag. Existing published tags must not be moved.
