# Changelog

## 1.4.6

- Add bottom A−/A+ controls to resize only the selected text in the plan editor.
- Show the selected text size and disable the controls until text is selected.

## 1.4.5

- Preserve the note editor's current scroll position when changing body text size with keyboard shortcuts.

## 1.4.4

- Label the large ticket body editor as “Change, Backout, and Validation Plan” in new and edit windows.

## 1.4.3

- Warn when a new or edited ticket uses an RITM already present in the ticket list.
- Show matching CHG, workflow, and title while allowing intentional duplicate RITMs to be saved.

## 1.4.2

- Allow editing a ticket's Created date and time in the ticket editor.
- Validate the entered local date and time before saving; the updated timestamp is synced and affects list ordering.

## 1.4.1

- Widen the Ticket Number column so full RITM identifiers and important stars have more room.
- Align the Ticket Number and CHG Number headers with their data columns.

## 1.4.0

- Add an Important ticket toggle to the editor without changing the ticket's workflow status.
- Show marked tickets in the Important sidebar collection and allow dragging tickets there to mark them.
- Preserve existing Important tickets and automatically mark them during data decoding.

## 1.3.3

- Replace the Examples workflow with Important and a filled star icon.
- Preserve the existing saved workflow value so existing tickets stay in the renamed workflow.

## 1.3.2

- Increase CHG number contrast and weight while keeping RITM as the blue primary identifier.

## 1.3.1

- Show RITM identifiers in blue and CHG identifiers in neutral gray for clearer visual distinction.

## 1.3.0

- Rename All Notes to Open Notes and exclude Closed tickets from that list and count.
- Add File menu commands to export a complete JSON backup and restore from a backup.
- Save a separate, restorable safety backup before replacing tickets.
- Restore ticket revisions through the existing local persistence and iCloud sync safeguards.

## 1.2.9

- Show the All Notes sidebar count for all tickets except Closed tickets.

## 1.2.8

- Add a Completed workflow between Approved and Examples.
- Support moving tickets into Completed by dragging them to its sidebar row or selecting it in the editor.
- Include Completed in workflow counts, filters, and persisted ticket status.

## 1.2.0

- Add opt-in iCloud sync settings, status, automatic sync while running, and Sync Now.
- Use a private CloudKit database with one asset-backed record per ticket.
- Persist offline changes, upload acknowledgments, and deletion tombstones across restarts.
- Merge concurrent edits deterministically and keep losing versions recoverable as new drafts.
- Pause sync when a different iCloud account is detected.
- Preserve legacy notes and creation times; keep a pre-migration backup on the first save.
- Block stale open editors from overwriting newly synchronized content.
- Add provisioning-profile validation and iCloud entitlements to the signed build workflow.

CloudKit requires an Apple provisioning profile and a registered container. Default ad-hoc builds keep sync disabled and continue local saving. Live two-Mac sync has not been validated without those credentials.

## 1.1.4

- Open the Draft workflow by default.
- New notes default to Draft and Low priority; saving a new note displays the Draft list.

## 1.1.3

- Save new drafts with only RITM populated; CHG, title, and body are optional.
- Continue editing and saving incomplete drafts without requiring CHG or a title.

## 1.1.2

- Drag tickets onto Draft, Pending Approval, Approved, or Examples in the sidebar to move them.
- Highlight valid workflow drop targets and show the moved ticket in the destination list.
- Save moves atomically while preserving note text, formatting, and creation time.
- Preserve dragged workflow changes when saving an already-open editor whose Status field was not changed.

## 1.1.1

- Fix native Swift Package Manager builds by giving the SwiftUI @main entry-point file a non-reserved filename.

## 1.1.0

- English interface with Draft, Pending Approval, Approved, and Examples.
- Native selection, double-click editing, independent resizable editors, and confirmed deletion.
- Created date column with ascending/descending sorting and a date/time field for new notes.
- 16 pt rich-text notes with Command-B and persistent bold formatting.
- Stable creation times when editing and migration for older saved notes.
- Shared data across main windows, atomic saves, previous-save backups, and visible error handling.
- Protect damaged data files from being overwritten; keep editors open if saving fails.
- Confirm before closing an editor with unsaved changes.
- New installations start empty instead of displaying synthetic ticket examples.
- Automated persistence and formatting tests before CI packaging.
- Universal Apple Silicon/Intel packages, signature verification, relative checksums, and optional Developer ID notarization.

This release is not yet Developer ID signed or notarized. Complete Apple signing and notarization before general distribution.
