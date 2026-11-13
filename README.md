# Sunshine Calendar

A personal macOS calendar app with a week view, group event dragging, and an unscheduled Event Bank.

## Build and open

Requires an Apple Silicon Mac with macOS 14+ and Xcode or its Swift command-line tools. No external packages.

```sh
./test.sh
./setup-signing.sh
./build.sh
open "build/Sunshine Calendar.app"
```

`setup-signing.sh` creates a local development certificate and imports its private key into your login Keychain. Review the script before running it; macOS may request approval. The certificate is trusted only for code signing at the user level. Reuse this identity for future builds to preserve app permissions. Alternatively, `./build.sh --temporary-signing` creates a one-off build without installing a certificate, but macOS may ask for Calendar access again after each rebuild.

## Use

Open `build/Sunshine Calendar.app`. It starts with sample calendars until full Calendar access is granted. After that, it reconnects automatically on launch and remembers calendar visibility choices. Sample edits last until the app closes.

- Command-click events to select or deselect them.
- Drag any selected event to shift the entire group. Vertical movement snaps to 15 minutes; horizontal movement shifts by days.
- Command-Z undoes the last group move; Shift-Command-Z redoes it.
- Escape cancels a drag and clears selection.
- Double-click an event to edit it; double-click an empty time or use Command-N to create one.
- Swipe horizontally over the calendar to move the seven-day view one day at a time. Each deliberate swipe moves one day; momentum does not skip ahead. Vertical scrolling still moves through the hours. Shift-scroll also moves by day.
- Use the sidebar to show and hide calendars, and the small calendar to jump to a date.
- Click the sidebar button beside the month heading, or press Option-Command-S, to hide or show the sidebar. This preference is remembered between launches.
- Command-T returns to today, Command-Left/Right changes weeks, and Command-R refreshes.
- Shift-Command-R restarts the app and restores the visible dates and scroll position. Save or close open editors first.
- Drag across empty week time to create an event with that duration. The draggable New Task button also creates a draft when dropped into the week or bank.
- Select calendar events and press Delete, or right-click to delete. Connected calendar deletions require confirmation; repeating events delete only selected occurrences.
- The sun menu controls subtle nighttime shading based on your Mac’s location. Location access is optional; calculations run locally using [NOAA solar equations](https://www.gml.noaa.gov/grad/solcalc/solareqns.PDF). The display uses the Mac’s current timezone.

## Connect real calendars

Click **Connect My Calendars**, then grant full calendar access in the macOS prompt. The app uses EventKit to access accounts already configured in macOS Calendar. Google, iCloud, shared, and subscribed calendars appear as exposed by macOS. Calendars whose names start with `- ` are treated as archived and excluded from the sidebar, event grid, and calendar choices. Calendar permissions determine which events can be edited. Account syncing is handled by macOS; this app does not connect to a separate server.

Moving or saving real events changes the underlying calendar and may notify guests. Moves involving repeating events or events with guests show a confirmation. Repeating events are edited one selected occurrence at a time. Read-only calendars cannot be edited or dragged; if any selected event is read-only, the whole group move is rejected.

## Event Bank

The right-hand panel holds unscheduled tasks with a title, estimated duration, calendar/color, and optional notes. Add tasks after connecting your calendars. Choose a preset duration or a custom number of minutes, up to seven days.

Task heights use the same time scale as the week calendar. Drag over the empty bank area to choose an estimated duration and open a new task editor. Drag cards onto one another to reorder them; dropping into empty bank space moves a card to the end. Ordering is saved with the synced bank records.

Drag editable timed calendar events into the bank to unschedule them while preserving title, duration, calendar, and notes. Selected groups are supported. Bank records are saved before the calendar events are removed; repeating occurrences and events with guests require confirmation.

Drag a card into a day/time on the calendar. A dashed preview shows where the event will land, snapping to 15-minute increments. Its duration and notes come from the bank task. The task leaves the bank only after the calendar event is saved. Dropping outside the grid or canceling a drag keeps the task in the bank. Double-click a card to edit; its context menu can remove it.

Drag the small handle along the bank’s left edge to resize it, or use its sidebar button to collapse/expand it. Panel size and collapse state are remembered.

Bank data uses the private `My Drive/Calendar Studio/Event Bank` folder in the connected Google Drive account. Each revision is a separate file under `records`, allowing independent tasks edited on different Macs to merge. Scheduled/removed records prevent stale offline edits from resurrecting tasks. Simultaneous edits to the same task are rejected when detected; conflicting revisions are resolved consistently. Sync arrival is handled by Google Drive; the app checks the folder every three seconds and when activated. The UI confirms local folder saves, not completion of an upload to Google.

Use the same bank folder and Google Drive account on another Mac running Sunshine Calendar. The bank menu can choose a folder or show it in Finder. Keep the folder available offline in Drive for desktop. Tasks whose calendars cannot be uniquely matched on another Mac require choosing a calendar before scheduling. A future iPhone app will need Google Drive API integration.

If calendar saving fails, the task stays in the bank. If calendar saving succeeds while the bank folder becomes unavailable, the task is hidden locally and its scheduled receipt is retried when the folder returns. A bank task should be scheduled on one Mac at a time; file sync does not provide a cross-device scheduling lock. Cross-device transport has not been validated on a second physical Mac.

## First version scope

Includes week navigation, calendar visibility controls, multi-selection, group dragging with previews, one group-move undo/redo, a synced Event Bank, and a basic event editor (title, calendar, dates, all-day, location, notes).

Not yet included: month/day/year views, search, drag resizing, attendee or recurrence-rule editing, persistent sample data, or multiple levels of undo. Multi-day all-day events render as continuous bars across the week. Two all-day rows are drawn, with a count for additional events. All-day events can be edited but cannot be group-dragged. Event editing clears move undo history. Move undo history is not retained between launches. Reopening the app reconnects automatically when Calendar access has already been granted.

## Build and check

Requires an Apple Silicon Mac with macOS 14+ and Xcode or its Swift command-line tools. No external packages.

Run `./build.sh` to build and sign the app with the persistent Calendar Studio Local Development identity in your login Keychain. Run `./test.sh` for calendar behavior checks and `./verify-signing.sh` to confirm different builds retain the same certificate-based identity. The app is locally signed for personal development, not notarized for distribution.

Live account access, remote sync, guest notifications, and recurring-event saves need validation after permission is granted. Automated checks use sample data and do not modify real calendars.

The signing setup script installs the identity only when you run it. Its private key stays in your Mac’s login Keychain, outside this project; temporary import files are removed after setup. The certificate is trusted at the user level only for code signing. Keep using this same identity and bundle identifier for future updates. The first certificate-signed build requires Calendar permission again because the previous builds used temporary identities. Future updates should retain that approval. Do not use `--temporary-signing` for ordinary updates, since that changes the identity again. App bundles are built and signed in a staging folder before replacing the installed build.
