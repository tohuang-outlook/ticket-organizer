# Changelog

## 1.4.32

- Add firewall deletion in settings, protecting firewalls referenced by tickets.

## 1.4.31

- Allow removing the first traffic flow as well as additional flows.

## 1.4.30

- Add independent traffic flows to a ticket, each with its own firewall and zone selections.

## 1.4.29

- Allow removing a firewall from the selection menus while retaining existing ticket details and allowing reactivation in settings.

## 1.4.28

- Set firewall selection text to 16 pt and the traffic flow path to 22 pt bold.

## 1.4.27

- Extract the firewall hostname and zone column from PAN-OS `show interface all` output, with a warning that zone names may be truncated.

## 1.4.26

- Add Firewall Settings to manage firewall names, device groups, zones, and active status.
- Extract hostname and zone fields from supported PAN-OS CLI output for review before saving.

## 1.4.25

- Show three firewall and Zone selectors while preserving additional steps saved by earlier versions.

## 1.4.24

- Display each firewall's zone path in 20 pt bold text.

## 1.4.23

- Add ordered selections of up to two zones per firewall and display each zone path under its firewall.

## 1.4.22

- Display device group labels in 24 pt bold text.

## 1.4.21

- Display device group labels in 20 pt bold text.

## 1.4.20

- Show a numbered device group placeholder above each selected firewall in Traffic Flow.

## 1.4.19

- Align each traffic flow step beneath its corresponding firewall selector.

## 1.4.18

- Expand Traffic Flow to five firewall menus and show the route in 26 pt bold text.

## 1.4.17

- Display a 20 pt traffic flow line beneath the firewall selectors and save the selections with each ticket.

## 1.4.16

- Show three independently selectable firewall menus across the Traffic Flow row.

## 1.4.15

- Replace the Traffic Flow icon with a firewall menu containing FW01 through FW05 below Created.

## 1.4.14

- Add a Traffic Flow icon and an empty panel to the note editor.

## 1.4.13

- Rename the pending approval page title to "Pending Approval".

## 1.4.12

- Add a gray text color button to the plan editor.

## 1.4.11

- Add red and default text color buttons to the plan editor for selected text or new typing.

## 1.4.10

- Add an italic button and Command-I shortcut to the plan editor, including support for bold italic text.

## 1.4.9

- Set the RITM, CHG, and note title input text in the ticket editor to 18 pt.

## 1.4.8

- Fix selected text size controls so they change the actual text formatting and support undo and redo.
- Preserve different text sizes when reopening a saved note, and fix whole-note size shortcuts to apply font changes.

## 1.4.7

- Replace the small A−/A+ size icons with labeled, bordered Smaller and Larger buttons for clearer, easier clicking.
- Show “Select text first” when no selection is active.

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
