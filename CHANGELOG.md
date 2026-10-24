# Changelog

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
