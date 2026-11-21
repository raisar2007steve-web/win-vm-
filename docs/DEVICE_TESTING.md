# Physical device test plan

The automated suite runs on simulators. Everything below requires real hardware and
must be executed manually before shipping.

## Before you start

1. Connect the iPhone, trust the computer, and enable Developer Mode
   (Settings → Privacy & Security → Developer Mode).
2. In Xcode, select the `NotesApp` target → Signing & Capabilities, choose your team,
   and confirm the CloudKit container exists in your developer account.
3. Confirm the deployment target is ≤ the device iOS version.

## Test matrix

| # | Feature | Steps | Expected |
|---| --- | --- | --- |
| 1 | Camera | New note → Attach → Take Photo → capture | Permission prompt appears once; photo is downsampled, attached, and visible |
| 2 | Document scan | New note → Attach → Scan Document → 2 pages | Both pages saved as `.scan` attachments |
| 3 | Photo library | Attach → Photo Library → select 3 photos | All three attach without blocking the UI |
| 4 | Files | Attach → Import File → choose a PDF | Attachment row shows name and size; opens in the viewer |
| 5 | Export | Note menu → Export → PDF | Share sheet opens with a valid multi-page PDF |
| 6 | Face ID | Settings → enable app lock → background and return after the grace period | Lock screen appears, Face ID unlocks, cancel falls back to passcode |
| 7 | Protected note | Note menu → Protect Note → close and reopen | Note requires authentication even when the app is unlocked |
| 8 | Voice note | Attach → Voice Note → record 5 s → Attach | Audio attaches; transcript paragraph appears when speech is authorized |
| 9 | Permissions denied | Settings → deny Microphone / Speech / Photos → retry each feature | Clear message, no crash, no repeated prompting |
| 10 | Haptics | Pin a note, toggle a checklist | Tactile feedback (respects the Settings toggle) |
| 11 | Notifications | Note menu → Add Reminder → 1 minute ahead | Local notification fires with the note title |
| 12 | Share sheet | Export → Markdown | AirDrop/Mail destinations work |
| 13 | Spotlight | Lock the device, search a note title from the Home Screen | Note appears and opens via deep link |
| 14 | Background/foreground | Type a long note, send the app to background mid-sentence, force relaunch | No content loss; autosave flushed on background |
| 15 | iCloud sync | Two devices, same Apple ID, edit on each | Changes propagate; conflicts resolve without losing text |
| 16 | Offline | Airplane mode, create and edit notes, disable airplane mode | Everything works offline and syncs afterwards |
| 17 | Apple Pencil | Attach → Handwriting, draw with the Pencil | Strokes captured and saved as an attachment |
| 18 | Siri/Shortcuts | "Create a note in Notes" | Note is created and the dialog confirms |

## What has not been verified

No iPhone was available to the CI environment, so none of the items above have been
executed on hardware. They are implemented against the public APIs and permission
gated at the point of use.
