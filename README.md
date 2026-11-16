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

- Command-click events to select or deselect them. Selecting an editable event sets its calendar as the default for new events and bank tasks until you select an event in another calendar.
- Staggered overlapping events use layered cards with protected title labels; labels shift within the actual event bounds where space allows. Card heights follow duration, with compact text for short events.
- Calendar dropdowns show the same calendar colors as the sidebar.
- Drag any selected event to shift the entire group. Vertical movement snaps to 5 minutes (hold Shift for 1-minute precision); horizontal movement shifts by days.
- Command-minus / Command-plus (or Command-equals) adjust text size throughout the app in 10% steps, from 80% to 160%. Command-0 resets it. The View menu has the same controls, and your choice is remembered.
- Command-Z undoes calendar and Event Bank actions; Shift-Command-Z redoes them. The Edit menu names the next action. Text fields keep normal typing undo.
- Escape cancels a drag and clears selection.
- Double-click an event to edit it; double-click an empty time or use Command-N to create one.
- Swipe horizontally over the calendar to pan continuously through days, with faster trackpad tracking and a short snap to the nearest day on release. You can grab an unfinished snap and continue from its current position. Mouse-wheel bursts and Shift-scroll navigate by day; momentum does not skip ahead. Vertical scrolling still moves through the hours.
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

Task heights use the same time scale as the week calendar. Drag over the empty bank area to choose an estimated duration and open a new task editor. Drop calendar events or existing bank tasks anywhere in the bank, including the creation area. A placement marker follows the pointer: drop above or below a card’s midpoint to insert before or after it, or below the list to append. Group drops retain their order. Ordering is saved with the synced bank records, and calendar-to-bank transfers can be undone together with their insertion position.

The bank uses quiet, collapsible category sections. Create one from the bank’s ellipsis menu → **New Category…**. Click a section title to expand or collapse it; drag the section itself to reorder it, with no separate grabber. Task cards retain their own drag action for moving between categories or scheduling on the calendar. Right-click a task for **Move to Category**, or choose a category in its editor. Right-click a section to rename it, create a task in it, or remove it while keeping its tasks. Existing tasks and tasks from removed categories appear in **Uncategorized**. Names, category order, and membership sync in the bank folder; collapse choices are remembered separately on each Mac.

Drag editable timed calendar events into the bank to unschedule them while preserving title, duration, calendar, and notes. Selected groups are supported. Bank records are saved before the calendar events are removed; repeating occurrences and events with guests require confirmation.

Drag a card into a day/time on the calendar. A dashed preview shows where the event will land, snapping to 5-minute increments (hold Shift for 1 minute). Its duration and notes come from the bank task. The task leaves the bank only after the calendar event is saved. Dropping outside the grid or canceling a drag keeps the task in the bank. Double-click a card to edit; its context menu can remove it.

Drag the small handle along the bank’s left edge to resize it, or use its sidebar button to collapse/expand it. Panel size and collapse state are remembered.

Bank data uses the private `My Drive/Calendar Studio/Event Bank` folder in the connected Google Drive account. Each revision is a separate file under `records`, allowing independent tasks edited on different Macs to merge. Scheduled/removed records prevent stale offline edits from resurrecting tasks. Simultaneous edits to the same task are rejected when detected; conflicting revisions are resolved consistently. Sync arrival is handled by Google Drive; the app checks the folder every three seconds and when activated. The UI confirms local folder saves, not completion of an upload to Google.

Use the same bank folder and Google Drive account on another Mac running Sunshine Calendar. The bank menu can choose a folder or show it in Finder. Keep the folder available offline in Drive for desktop. Tasks whose calendars cannot be uniquely matched on another Mac require choosing a calendar before scheduling. A future iPhone app will need Google Drive API integration.

If calendar saving fails, the task stays in the bank. If calendar saving succeeds while the bank folder becomes unavailable, the task is hidden locally and its scheduled receipt is retried when the folder returns. A bank task should be scheduled on one Mac at a time; file sync does not provide a cross-device scheduling lock. Cross-device transport has not been validated on a second physical Mac.

## First version scope

Includes week navigation, calendar visibility controls, multi-selection, group dragging with previews, multi-step event and Event Bank undo/redo, a synced Event Bank, and a basic event editor (title, calendar, dates, all-day, location, notes).

Not yet included: search, attendee or recurrence-rule editing, persistent sample data, or persistent undo history. Multi-day all-day events render as continuous bars across the week. Two all-day rows are drawn, with a count for additional events. All-day events can be edited but cannot be group-dragged. Undo covers creation, edits, moves, resizing, deletion, bank task changes, scheduling, and transfers to the bank. New changes discard the redo branch; navigation and refresh preserve history. History is not retained between launches. Undo refuses to overwrite events or bank tasks that changed elsewhere. Deleted repeating occurrences are restored as standalone events. EventKit cannot recreate guest invitations after deletion or retract sent cancellation/update notices. Reopening the app reconnects automatically when Calendar access has already been granted.

## Build and check

Requires an Apple Silicon Mac with macOS 14+ and Xcode or its Swift command-line tools. No external packages.

Run `./build.sh` to build and sign the app with the persistent Calendar Studio Local Development identity in your login Keychain. Run `./test.sh` for calendar behavior checks and `./verify-signing.sh` to confirm different builds retain the same certificate-based identity. The app is locally signed for personal development, not notarized for distribution.

Live account access, remote sync, guest notifications, and recurring-event saves need validation after permission is granted. Automated checks use sample data and do not modify real calendars.

The signing setup script installs the identity only when you run it. Its private key stays in your Mac’s login Keychain, outside this project; temporary import files are removed after setup. The certificate is trusted at the user level only for code signing. Keep using this same identity and bundle identifier for future updates. The first certificate-signed build requires Calendar permission again because the previous builds used temporary identities. Future updates should retain that approval. Do not use `--temporary-signing` for ordinary updates, since that changes the identity again. App bundles are built and signed in a staging folder before replacing the installed build.

## Timezone map

The shared timezone chooser offers a Map with selectable city pins and a searchable List. It is available from the comparison/primary timezone slots and event editor. Map pins represent timezone reference cities, not geographic timezone boundaries. Map tiles are supplied by Apple Maps and require network access. The bundled `Resources/zone.tab` reference-city coordinates come from the public-domain IANA timezone database shipped with macOS; the Eastern shortcut uses Miami coordinates to match its label.

Daylight shading uses a continuous civil-twilight gradient driven by calculated solar elevation: no night tint above the apparent sunrise/sunset elevation (-0.833°), maximum night tint at -6°. This reflects solar geometry and varies with latitude, date, and location; it is not a measurement of weather-dependent sky brightness. Hovering the transition shows the calculated official sunrise or sunset separately from the end of twilight. Calendar days use their dates and the Mac location; comparison ribbons use today and their reference city.

## Weather overlay

Temperatures show Celsius first with Fahrenheit alongside, for example **13°C / 55°F**. Current conditions, feels-like temperatures, daily highs and lows, and hourly graph labels all include both units; Fahrenheit is visually secondary.

The cloud/sun toolbar menu toggles an hourly weather overlay and separate sky, precipitation, and wind layers. The primary timezone’s reference city determines the forecast location; no event titles, attendee details, or calendar data are sent. Subtle precipitation bands sit behind event cards, with weather/temperature markers and a wind-intensity strip beside each day. Hover the weather strip for hourly details. Data is fetched only with the overlay enabled and cached in memory for twenty minutes. Dates outside the returned forecast range show “No forecast.” Internet access is required.

Weather data: [Open-Meteo](https://open-meteo.com/), [forecast API documentation](https://open-meteo.com/en/docs). The public API is used without an embedded API key; review the provider’s terms before commercial distribution.

## Calendar views

The toolbar view selector offers Day, 2 Days, 3 Days, 4 Days, 5 Days, 6 Days, 7 Days (Week), Month Standard, Month Detailed, and Year. The selected view is remembered. Outside text fields and event editors, press 1–7 to select the corresponding number of days. Timeline views retain event dragging/resizing, all-day expansion, timezones, and overlays. Month Standard shows three event titles per day; Detailed shows up to six titles and times with taller rows. Overflow opens the day’s complete list. Double-click a month event to edit or empty day space to create; click a day number to open Day view. Year shows twelve month calendars with event dots; click a month heading for Month view or a date for Day view. Arrow navigation advances the selected number of days, one month, or one year.
