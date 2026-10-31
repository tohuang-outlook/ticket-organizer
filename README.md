# Ticket Organizer

A native, offline macOS app for organizing RITM and CHG ticket notes. Requires macOS 14 or later. Universal builds support Apple Silicon and Intel Macs.

## Daily use

- Click once to select a ticket; double-click to open a movable, resizable editor.
- The ticket editor uses 18 pt text for the RITM, CHG, and note title inputs.
- The list has separate Ticket Number and CHG Number columns, followed by Created, Status, Priority, and Notes. All list text and headers use 18 pt; RITM numbers are blue and bold, while CHG numbers use high-contrast primary text with medium weight. Notes shows only the note title; the full body remains available in the editor and search.
- Sidebar labels and workflow counts use 18 pt.
- Organize notes into Draft, Working, Pending Approval, Approved, Completed, Important, and Closed. Open Notes lists and counts all tickets except Closed. Mark an open ticket as Important in its editor without changing its workflow status; marked tickets also appear in the Important sidebar collection.
- Drag a ticket onto a workflow in the sidebar to move it. The target highlights on hover; successful drops save immediately and open the destination list.
- Type the Created date and time directly when adding a note (`yyyy-MM-dd HH:mm:ss`, local time), or click Now. Invalid dates cannot be saved.
- Drafts require only an RITM number; CHG, title, and body can be filled in later.
- Warn when an entered RITM already exists, with the matching CHG, status, and title. The warning does not block intentional duplicates.
- Label the large note editor “Change, Backout, and Validation Plan” in new and edit windows.
- Firewall selection text uses 16 pt; the firewall path uses 22 pt bold text.
- Configure firewall names, device groups, available zones, and active status in Ticket Organizer > Settings > Firewalls. FW01–FW05 and their numbered device groups and zones are initial placeholders. Active firewalls appear in the three Traffic Flow menus below Created; each step and its device group appear below its menu. Choices are saved with the ticket; use Clear to remove a selection. Additional steps saved by older versions remain visible as read-only text and are preserved.
- Use Remove Firewall in a firewall menu to remove a firewall from future selections. Existing ticket details remain available; reactivate the firewall in Settings > Firewalls when needed.
- Use Import CLI Output in Firewall Settings to extract a hostname and zones from PAN-OS `show interface all`, or explicit `hostname:`, `set deviceconfig system hostname`, and `set zone` lines from one firewall. Interface tables may truncate long zone names, so verify and complete them before saving; device group is entered manually. Pasted CLI text is processed locally and is not saved.
  Supported line examples follow the Palo Alto Networks documentation for [system information](https://docs.paloaltonetworks.com/ngfw/pan-os-cli-quick-start/use-the-cli/view-settings-and-statistics) and the [PAN-OS CLI command hierarchy](https://docs.paloaltonetworks.com/ngfw/pan-os-cli-quick-start/cli-command-hierarchy/pan-os-11-2-configure-cli-command-hierarchy).
- After selecting a firewall, use its Zones menu to choose up to two zones in order. The selected path appears in 20 pt bold text below that firewall and is saved with the ticket. Deselect a zone to change the order; changing or clearing the firewall clears its zones.
- Use Add Traffic Flow to add another independent path, or Remove Flow to remove an additional path. Save the ticket to keep changes.
- Keep the current text and scroll position visible when changing body font size with Command-period or Command-minus.
- Use the bottom Smaller/Larger controls to change only highlighted plan text by 2 pt; the controls show the selected text size and prompt you to select text first when nothing is selected.
- Working tickets can also be edited and saved with only RITM while their details are still incomplete.
- The app opens Draft by default. New notes default to Draft with Low priority.
- Tickets are ordered oldest-first on launch. Click Created to toggle between oldest-first and newest-first.
- Click the Created column heading to switch between newest-first and oldest-first order.
- Search RITM, CHG, titles, or note text; filter by priority.
- Select text and press Command-B to toggle bold. The body starts at 16 pt. Press Command-period (or Command-plus) to increase the whole note by 2 pt or Command-minus to decrease it; font size is saved with the note and ranges from 10 to 48 pt.
- Select plan text and press Command-I or click the italic I above the editor to toggle italic. Bold and italic can be combined.
- Select plan text and click Red, Gray, or Default above the editor to change its text color; with no selection, the color applies to subsequent typing.
- Press Command-S in the editor to save. Changes close the editor only after saving succeeds.
- Quitting with unsaved ticket editors asks before discarding their changes.
- Delete the selected ticket with Delete Selected Ticket or its context menu, then confirm.
- Use File > Back Up Tickets to save a portable JSON snapshot. File > Restore Tickets from Backup replaces the current ticket list after confirmation; the current list is saved to a separate restorable safety backup first.

New installations start with an empty list. Existing notes are preserved. Local-only use needs no account and sends no data. Optional iCloud sync uses your Apple Account's private CloudKit database. There is no telemetry.

## Install

Download and unzip the release archive, then move Ticket Organizer.app to Applications. Quit the old version before replacing it. App updates do not delete saved notes.

Current locally generated archives are ad-hoc signed for testing, not Apple Developer ID signed or notarized. macOS may require approval in System Settings > Privacy & Security. Do not disable Gatekeeper globally.

## Data and backups

The app always keeps local data on this Mac:

```text
~/Library/Application Support/TicketOrganizer/tickets.json
~/Library/Application Support/TicketOrganizer/tickets.json.backup
```

The backup contains the previous successful save; it is replaced on the next successful change. The first save in 1.2 also keeps the original array in tickets.json.pre-icloud-backup. Include this folder in your normal Mac backups. For a manual backup, quit the app and copy the folder to another location. Version 1.2 uses a versioned archive containing notes, deletion tombstones, upload revisions, account binding, and recovered conflict versions; do not use an older app to edit this archive.

File > Back Up Tickets creates a portable JSON snapshot containing ticket text, formatting, workflow, priorities, creation times, and sync metadata. These files contain sensitive ticket information; store them securely. Restore replaces the current ticket list, first saving a separate `TicketOrganizer-before-restore-*.json` safety snapshot in the Ticket Organizer Application Support folder. Close all ticket editors before restoring. On a Mac with iCloud sync enabled, restored changes reconcile with the same bound iCloud account; backups bound to a different account are rejected.

To recover, quit the app, make a copy of both files, inspect the backup, and restore the desired copy as tickets.json. If the current file cannot be read, the app reports an error and blocks writes rather than replacing it. Save errors leave edited text open for retrying.

Writes are locked across app instances. If another instance or external tool changes the data file, a stale instance blocks saving instead of overwriting it. Copy any unsaved text, quit all copies, and reopen the app. The adjacent .lock file contains no ticket data and does not need to be deleted.

Update every Mac to 1.2.8 or newer before using Completed with iCloud. Older app versions cannot read the Completed workflow value and may pause rather than load the notes. Update every Mac to 1.2.1 or newer before using Closed with iCloud, and to 1.2.2 or newer before using Working.

Update every Mac to 1.4.30 or newer before editing tickets or firewall settings. Older versions may not preserve additional traffic flows or firewall settings when they save data. Firewall settings are stored locally and included in ticket backups; they are not synced by the current iCloud implementation.

Working requires 1.2.2 or newer on every Mac. Its addition preserves existing workflow values and does not move existing tickets or change the default Draft/Low settings.

Older versions did not record creation time. Their last-modified timestamp is used as the initial creation time and preserved on subsequent edits. The original creation time cannot be reconstructed.

The Created date and time can be changed in either the new-ticket form or the ticket editor. Enter local time as `yyyy-MM-dd HH:mm:ss`; use Now to reset it to the current time. Changing this value also changes where the ticket appears in creation-time order.

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
MARKETING_VERSION=1.4.30 BUILD_NUMBER=66 ./scripts/build-app.sh
(cd dist && shasum -c SHA256SUMS)
```

The script builds both CPU architectures, validates the bundle and signature, verifies the ZIP, and generates relative SHA256 checksums. Artifacts are written to dist/ and are not committed to Git.

## Developer ID distribution

Install your Apple Developer ID Application certificate and store notarization credentials in a local notarytool keychain profile. These credentials are not part of this repository.

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="ticket-organizer-notary" \
REQUIRE_NOTARIZATION=1 \
./scripts/build-app.sh
```

This signs with the hardened runtime, submits to Apple, staples the accepted ticket, and checks Gatekeeper assessment. REQUIRE_NOTARIZATION=1 rejects builds without the signing identity and notarization profile.

## iCloud sync

In an iCloud-enabled signed build, open Ticket Organizer > Settings and enable Sync with iCloud on each Mac using the same Apple Account. Local notes are merged with existing cloud notes on first sync. Sync runs on activation, shortly after edits, and approximately every 60 seconds while the app is open. Sync Now is available in Settings. Offline changes remain queued on disk. Disabling sync keeps both local and cloud data.

Concurrent edits use the latest revision timestamp, with a deterministic tie-breaker. Losing unsent versions remain in Settings > Recovered Versions and can be restored as new drafts. Deletions win over edits to the same identifier; recovery creates a new identifier. Account changes pause sync rather than uploading local notes to another account. Sync is not a replacement for backups.

Ad-hoc builds **cannot enable CloudKit**. The build checks the actual signature and embedded provisioning profile before allowing sync. The sync logic is tested with a simulated transport; live iCloud and two-Mac testing still require an Apple Developer account and valid signing setup.

To configure an enabled build:

1. Register the explicit macOS App ID com.tohuang.ticket-organizer in your Apple Developer team and enable CloudKit.
2. Register and associate iCloud.com.tohuang.ticket-organizer with that App ID.
3. Create the TicketChange record type with a payload field of type Asset in the CloudKit development schema. Add a Queryable index for recordName. Keep the database private; the app uses the TicketOrganizer custom zone.
4. Deploy the schema to Production in CloudKit Console. Install the matching Apple signing certificate and generate a macOS provisioning profile that includes the same App ID, CloudKit container, and environment.
5. Build with the profile, then notarize for distribution:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ICLOUD_PROVISIONING_PROFILE="/absolute/path/TicketOrganizer.provisionprofile" \
ICLOUD_ENVIRONMENT=Production \
REQUIRE_ICLOUD=1 \
NOTARY_PROFILE="ticket-organizer-notary" \
REQUIRE_NOTARIZATION=1 \
./scripts/build-app.sh
```

The build validates profile expiration, App ID, CloudKit service, container, and environment before generating entitlements. It embeds the profile and signs the complete app. REQUIRE_ICLOUD=1 rejects builds without a profile or with a non-Production environment. Do not commit certificates, profiles, credentials, or ticket data. Use a development profile and ICLOUD_ENVIRONMENT=Development for development-only testing; do not mix the two environments across Macs.

## Release acceptance gates (1.4.30)

Local automated tests and an ad-hoc package are not sufficient for a public production release. Before publishing:

- Run all tests and build a universal archive; verify SHA256SUMS and the bundle signature.
- On a disposable test account, verify selecting, double-click editing, bold/undo, manual Created input on creation and editing (including invalid dates), editing Created time then confirming the ticket re-sorts, duplicate RITM warnings on create and edit (including Closed matches), and intentional duplicate saves. Verify deletion confirmation, marking/unmarking Important without changing workflow status, and moving between workflows. Confirm Working appears between Draft and Pending Approval, Completed between Approved and Important, and Open Notes excludes Closed tickets. Verify backup export, restore confirmation, recovery of deleted/edited tickets, and pre-restore safety backup creation.
- Confirm list and sidebar text are 18 pt. In the body editor, verify Command-period/Command-minus adjust all text by 2 pt, preserve bold, remain within 10–48 pt, and persist after saving and reopening.
- Select a portion of plan text and verify bottom Smaller/Larger changes only that selection by 2 pt, preserves bold, updates the displayed size, and persists after saving and reopening. Verify the controls are disabled without a selection and explain that text must first be selected.
- While the text cursor or selection is in the middle and near the end of a long note, verify Command-period/Command-minus preserve the current viewport instead of scrolling to the bottom.
- Confirm full RITM identifiers fit beside the Important star and the table headers align with their columns. Confirm RITM is blue and bold, and CHG is high-contrast primary text with medium weight.
- Verify unsaved edits trigger a warning on both editor close and Command-Q; Keep Editing must preserve the text.
- Verify the packaged app on macOS 14 and on an Intel Mac; building both architectures is not the same as running on both.
- Configure the real Apple Developer team, Production CloudKit schema, matching profile/certificate, and notarization credentials. Build with both REQUIRE_NOTARIZATION=1 and REQUIRE_ICLOUD=1. Require successful stapler validation and Gatekeeper assessment.
- Test the signed build on two Macs using a separate test iCloud account: initial merge, offline edit/reconnect, Working and Closed, deletion without resurrection, conflict recovery, and account-switch protection. Simulated sync tests do not verify Apple's live service.
- Back up the local data folder before upgrading. Upgrade all participating Macs before syncing the new Working status. Avoid downgrading the data archive.
- Upload only the validated, notarized ZIP and its matching checksum to the draft release, then publish after all checks pass. Never publish private ticket data, profiles, certificates, or credentials.

The local 1.2.2 UI smoke check confirmed workflow order and filtering, single-click selection, double-click editing, Low priority by default, invalid Created-date rejection, enabled saving for RITM-only Working notes, and unsaved-edit warnings on close and Command-Q. Test edits were cancelled without saving. This does not replace the full acceptance checks above.

Current local artifacts are ad-hoc signed. Live CloudKit, notarization, macOS 14/Intel runtime checks, and remaining full acceptance scenarios still require validation before public release.

## GitHub builds

Pushes to main, pull requests, and manual runs execute tests and package the app. A vX.Y.Z tag must match VERSION and creates a **draft** GitHub Release with the ZIP and checksums. The CI build is ad-hoc signed; use the Developer ID process above and replace the draft assets before publishing for general distribution.

For the next release, update VERSION, commit, and push the matching tag. Existing published tags must not be moved.
