# 11 Calendar

Requested 2026-09-25, researched and grilled the same day. Package `ToolCalendar`, tool id `calendar`, row
"Calendar", hotkey ⌃⌘J (join). Imports Core only. Off by default.

## Goal
Replace Notion Calendar's menu bar job natively: the next meeting in the menubar with a countdown, a pill with a
sound before it starts, and the Google Meet call one click or one key away. Today's agenda lives in the panel.

Out of scope (from a read of Notion Calendar's help pages and the Cron changelog): week and month views, other
days, creating or editing events, RSVP, emailing participants, availability and booking links, time zone columns,
Notion doc links, native notifications, snooze.

Premise check: no credible measurement of Notion Calendar's memory or CPU was found (the heavy-memory reports are
for the main Notion app). The reason to build this is control over the menubar and the alert.

## Source: EventKit (decided 2026-09-25)
One account for now: the personal Gmail, already in System Settings › Internet Accounts (confirmed 2026-09-25;
there is no Workspace account). EventKit merges any accounts added later, so nothing here assumes one. Calendar.app's own event alerts are turned off there so Deskpouch is the only alert;
the alarm data stays readable through EventKit.

Why EventKit over the Google Calendar API:
- No Google Cloud project, OAuth, tokens or polling code. `requestFullAccessToEvents` plus
  `NSCalendarsFullAccessUsageDescription`; `EKEventStoreChanged` on every change.
- More accounts merge for free if they come. The API path needs one sign-in, token and poll loop per account.
- A Workspace admin can block unverified OAuth apps asking for Calendar read (a sensitive scope). Internet Accounts
  signs in through Apple's own verified client, which admins rarely block. Matters for a public release.

Costs, checked in step 0:
- `EKEvent` has no conference field (`EKVirtualConferenceProvider` is provider-side only), so the Meet link is
  found by regex in `url`, `location` and `notes`. Google's CalDAV sync most likely writes it into the description
  (`notes`): unverified.
- Freshness is macOS's sync of the Google accounts. Calendar.app's refresh set to every 5 minutes, plus
  `EKEventStore.refreshSourcesIfNecessary()` when the panel opens and every 2 minutes (whether Google-backed
  sources honour it is unverified).

Fallback, only if step 0 fails: `GoogleCalendarSource` behind the same `CalendarSource` protocol. Desktop OAuth
client, loopback redirect `http://127.0.0.1:<port>` with PKCE S256 (Google no longer supports custom schemes for
new flows), consent screen External and "In production" without verification (personal use under 100 users is
allowed with a click-through; Testing status expires refresh tokens after 7 days), refresh token in the Keychain,
`events.list?singleEvents=true&orderBy=startTime&timeMin&timeMax&eventTypes=default` per calendar every 60 s,
link from `conferenceData.entryPoints[type == video].uri`. Push (`events.watch`) needs a public HTTPS server:
not an option. MeetingBar (Apache-2.0) implements both paths and is the code reference.

## Decisions
- **Which events count** (revised after step 0, 2026-09-25: Google adds a Meet link to every event the user
  creates, and solo events like "Bin day!" are reminders the user wants):
  - Menubar countdown and agenda: every timed event I have not declined, solo or not.
  - Pills: only events with alarms (see Pill alert).
  - Join, the Join button and ⌃⌘J: only a Meet link on an event with another person on it, as organizer or
    attendee (the organizer is not in `attendees` when someone else invited me). A solo event's auto-added Meet
    link is ignored.
  - Declined events are hidden everywhere; cancelled ones never show. All-day events never reach the menubar or
    a pill; they are one line on top of the agenda.
- **Menubar item**: its own `NSStatusItem` left of the pouch; the pouch's states are untouched. Hidden unless a
  timed event starts within the preview window (default 1 h; options 15 min, 30 min, 1 h, 3 h) or is running. When the
  running meeting ends and the next is inside the window, it hands straight over.
  - Text: "Design sync · in 12 min", "· in 4 min", "· 23 min left" during the meeting. Title cut at about 20
    characters with "…". "Show title" switch (on by default); off leaves the countdown only.
  - Look: plain template text over 5 min out, amber capsule in the last 5 minutes, mint capsule while running.
    Drawn by `MenubarIcon.calendar(...)` like the recording pill. Text re-renders every 30 s from cached events.
  - Click opens the Deskpouch panel dropped from this item, straight on the Calendar view.
- **Panel**: a "Calendar" row in the Tools list, status line "Next: Design sync · 14:30" or "Nothing else today",
  switchable in General like every tool. The Calendar view: today only, the whole day with past events
  dimmed, all-day events as one line on top, rows with time, title, calendar colour dot, a Meet glyph and a Join
  button when Join applies, the next event highlighted, "Nothing else today" when empty. Settings under the agenda: calendars (per-calendar toggles, all on), preview window, show title, sound,
  join shortcut. No other days, no day navigation.
- **Pill alert**: only events with alarms; an event without alarms never gets a pill. Alarms at the same offset
  are merged (step 0 found four "10 min before" on one event). Two kinds:
  - **Sticky**, for an event today: a pill at each alarm and again at the start. Stays until ×, Join, or the
    event's end. A later alarm replaces the earlier pill for the same event; joining (any route) clears it and
    skips its later ones. An alarm missed while the Mac slept still fires within 5 minutes of its time.
  - **Heads-up**, for an event on a later day (alarms of 1, 3, 6 days are common on this calendar): shows for
    8 s and slides away; hovering holds it, like the screenshot pill. Text "tomorrow 13:30", "Sat 10:00" or
    "in 3 days"; × only, no Join. One missed while the Mac slept or was off shows once on wake, while the event
    is still ahead.
  - Content: tile (Meet glyph when Join applies, else a bell), line 1 the title, line 2 "in 5 min" / "starting
    now" / the day, plus "· Meet" or the location. Buttons: Join (only when Join applies) and ×. Clicking the body
    of a sticky pill opens the Calendar view. No attendees, notes or snooze.
  - Sound when either kind appears, its own switch in the Calendar view, on by default, independent of General's
    Sounds. No native notification.
  - Pills for different events stack from the anchor, newest nearest, 3 at most.
  - Position: draggable by the body, remembered per display, default top-right under the menubar; double-click
    resets. Only the calendar pill moves; the other pills keep General's Top / Bottom setting, so a calendar pill
    and a dictation pill can be on screen at once. Slides in, then sits still.
- **Join**: ⌃⌘J (Notion Calendar's default), rebindable with the existing shortcut recorder. Target: an event
  Join applies to that started up to 10 minutes ago, else the next one starting within 15 minutes,
  else a small pill "No call in the next 15 min". Opens with `NSWorkspace.open` in the default browser. Meet links
  get `authuser=<account email>` (both accounts are signed into one browser profile); the email comes from the
  account's name in Internet Accounts (checked in step 0).
- **Providers**: Meet only. Any other link is still picked up and opened as a plain URL. **Before a public
  release**: a detector for Zoom, Teams, Webex and others, app deep links (`zoommtg://`, `msteams:`), and the
  empty state pointing to Internet Accounts.
- **Link detection** (`MeetingLink`, pure): step 0 found Google's link only in `notes`, on a
  "Join with Google Meet:" line. Prefer that line's link, then the first Meet link in notes (HTML stripped), then
  url and location; a Meet link beats any other link; Google `/url?q=` redirects unwrapped.
- **Permission**: tool off by default. Switching it on (General or its row) asks for Calendars access once. Denied:
  the view says "Calendar access is off" with a button to that System Settings pane. General's permissions summary
  shows a Calendars line while the tool is on.
- **Tool shape**: a `Tool` with `pressKey`, a switch, a row and a view; `activate` starts the source and the clock,
  `deactivate` stops them and clears the item and pills. Emits no `ToolResult`, writes nothing to history.
- **Refresh**: refetch on `EKEventStoreChanged` and every 2 minutes (with the sync nudge above). Window: start of
  today to end of today plus the 3 h preview reach past midnight.
- **Settings** `calendar.*`: `calendarsOff` (ids), `previewMinutes`, `showTitle`, `sound`, `hotkey`,
  `pillOrigin` (per display).

## Structure
```
Packages/ToolCalendar/
  CalendarTool.swift          Tool: activate/deactivate, keyPressed joins, publishes state to the shell
  CalendarSource.swift        protocol: authorize(), calendars(), events(in:), changes (AsyncStream), nudge()
  EventKitSource.swift        EKEventStore, full access, EKEventStoreChanged, refreshSourcesIfNecessary. Not unit tested.
  Model/
    CalendarEvent.swift       value: id, calendar (id, title, colour, account email), title, start, end, allDay,
                              myStatus, hasOtherPerson (attendee or organizer), alarms (offsets), location,
                              link candidates
    MeetingLink.swift         pure detector + authuser. Tested.
    Agenda.swift              pure: events + now + settings -> menubar text and tint, next, current, today's rows,
                              join target. Tested.
    Reminders.swift           pure: due pills at now (sticky today, heads-up later), merged offsets,
                              replacement per event, clear on end or join, missed-on-wake, no repeat after a
                              refetch. Tested.
  CalendarSettings.swift      calendar.*
Core:
  MenubarIcon.calendar(text:tint:)
  PillState / OverlayController: a calendar pill kind with its own anchor, stacking up to 3, drag and reset
App:
  CalendarStatusItem          second status item, panel anchor
  MenuPanel/CalendarToolView  row, agenda, settings; PanelTools entry
Info.plist: NSCalendarsFullAccessUsageDescription
KeyCombo.controlCommandJ
```

## Steps
0. **Spike** (half a day; decides EventKit vs the fallback). **Done 2026-09-25** (findings above): EventKit holds. The spike (`App/CalendarSpike.swift`) was removed once the
   real source existed. It was `DESKPOUCH_DEMO=calendar-dump`, which asked for full access
   and logs the next 10 events of both accounts: `url`, `location`, `notes`, alarms, attendees, the source and
   calendar titles. Pass when: a real Meet event carries its link in one of the three fields; Google default
   reminders show up as alarms; the account email is readable; moving a meeting on the
   web reaches Deskpouch within about 5 minutes (time it with and without the nudge).
1. **Mocks** (**done 2026-09-25**, three variants each, picked A / A / A: glyph and text menubar item, agenda list
   view, pill with the dictation pill's anatomy; canvas page "Calendar (plan 11)") in `design/mocks/Calendar*.dc.html`: the menubar item in plain, amber and mint; the Calendar view
   (day with past, now, all-day line, empty, access off); the pill, alone and stacked, with and without Join.
2. **Model and tests** (done): `CalendarEvent`, `MeetingLink`, `Agenda`, `Reminders`, settings, with fixture events and
   an injected clock.
3. **Source and tool** (done): `EventKitSource`, permission flow, refresh, state on `ShellState`, General switch and
   permissions line.
4. **Menubar item, panel view, ⌃⌘J** (done).
5. **Pill** (done): calendar kind, sound, stacking, drag with a per-display origin, reset.
6. **Demo** (done; hands-on pass left) `DESKPOUCH_DEMO=calendar` with a fixture source (a meeting 3 minutes out with a Meet link, one running,
   one in-person): snapshots of the item, the view and stacked pills. Then the hands-on pass below.

## Step 0 findings (2026-09-25)
Run through the since-removed `DESKPOUCH_DEMO=calendar-dump` on 13 events (18 Sep to 9 Oct) of the personal Gmail, the only account.
- **Meet link: in `notes`, always.** 8 of 13 events, never in `url` or `location`. Google writes a line
  `Join with Google Meet: https://meet.google.com/xxx-xxxx-xxx`. A description can hold other Meet links too (one
  event had a pasted `<a href="https://meet.google.com/…?hs=224">` plus Google's own line): the detector prefers
  the link on the "Join with Google Meet:" line, then the first Meet link.
- **Correction (2026-09-25, while building):** the summary above filtered the dump to lines about me and missed
  that some of these events have a second attendee (the user's partner on the shared "Bin day!"). Those count as
  "another person", so Google's auto-added Meet link gives them a Join button. The code is right by the rule;
  turning off Google Calendar › Settings › Event settings › "Add video conferencing" stops new ones.
- **Google auto-adds Meet to events the user creates.** "Bin day!", "Clean coffee machine" and an all-day show
  visit carry a Meet link with the user as organizer and only attendee. A link is therefore not a meeting signal
  on this account; "Which events count" was revised for it.
- **Alarms: present on every event**, including Google's defaults, as relative offsets. Duplicates happen (one
  event had four "10 min before") and offsets reach days (1440, 4320, 8640 min). Merged, and later-day alarms
  became the heads-up pill.
- **Account email: readable.** The source title and the primary calendar title are the address, and the attendee
  flagged `isCurrentUser` carries `mailto:<address>`. `authuser` can use the source title.
- **Organizer is not in `attendees`** when someone else invited me (only I appear); "another person" has to count
  the organizer too.
- Extra sources with no event calendars show up (sub-sources of the Google account): ignore sources without
  calendars.
- Sync lag: not measured; skipped by choice, judged in daily use. If moved events arrive late, the Google source is
  the fix.

## Status (2026-09-25)
Steps 0 to 6 are built. `scripts/test.sh` passes (ToolCalendar 37 tests; Core gained one for off-by-default
switches). Checked through `DESKPOUCH_DEMO=calendar` PNGs: the menubar item in its three tints, the panel's
Calendar view against mock A, the stacked pills and the message pill. The panel was also seen on the real calendar
(today's events, past rows dimmed, the now line). Not driven by hand yet (the hands-on pass below): a real alarm
firing a pill with its sound, dragging and double-click reset, hover holding a heads-up, ⌃⌘J from another app,
Join opening Meet in the browser as the right account, switching the tool off and on, the access-denied card.

Decisions made while building:
- Package `ToolCalendar` (imports Core only): pure `Model/` (event, link, text, agenda, reminders and pill stack),
  `EventKitSource`, `CalendarTool`, `CalendarModel` (observable, read by the App's views), `CalendarPillController`
  and its SwiftUI view, `CalendarMenubarImage`. App: `CalendarStatusItem`, `MenuPanel/CalendarToolView.swift`.
- Off by default through `ToolSwitches(offByDefault:)` (stored under `tools.enabled`). Switching it on asks for
  Calendars access; General's permission line lists Calendars only while the tool is on.
- Menubar rule when events overlap: a running event wins, except when the next one is inside its last 5 minutes
  (a long solo block must not hide a call). The Tools row follows the same focus.
- Links: Google's "Join with Google Meet:" line, then any Meet link in notes, url or location; a non-Meet link is
  only taken from the url or location fields (notes are full of docs and help links).
- Fetch window: start of today to 8 days ahead (6 day alarms are common here), refetched on
  `EKEventStoreChanged`, every 120 s with a `refreshSourcesIfNecessary` nudge, on wake and at midnight. A 5 s
  tick rebuilds the agenda and checks alarms; heads-up expiry gets its own timer. Fired alarms and the last check
  persist (`calendar.firedAlarms`, `calendar.lastCheck`), so a relaunch neither repeats nor loses a pill.
- The pill window is its own non-activating panel (not the shared overlay), sized to the stack, anchored by its
  top-right corner. The offset from the display's visible top-right is stored per display
  (`calendar.pillOffset`). The sound is the system "Glass".
- The calendar list in the Calendar view folds into one "Calendars · N of M shown" row: an account brings several
  calendars (holidays, a phone, shared ones) that pushed the options off the panel.
- Sound (added 2026-09-25 on request): a picker instead of the on/off switch. None plus every alert sound in
  ~/Library/Sounds and /System/Library/Sounds (what `NSSound(named:)` finds), default Glass, played once when
  picked. Stored as `calendar.soundName` ("" is None); an old `calendar.sound = false` loads as None.
- Review fixes (2026-09-25, /review): a Google `/url?q=` redirect is only unwrapped to an http(s) target, and
  Join refuses anything else (an invite could otherwise make Join open `file:`, `smb:` or an app's scheme). The
  tool remembers whether it is switched on and rechecks after the access prompt, so switching it off while the
  prompt is up keeps it off. EventKit change bursts are coalesced (300 ms). Each event's link is found once at
  init; the detector and HTML regexes are built once; times use `Date.FormatStyle`; the heads-up hairline is one
  scoped animation instead of a 10 Hz redraw. The tool takes its source, pill window, defaults, clock, URL opener
  and sound player as parameters, and `CalendarToolTests` cover persisted alarms across a relaunch, the prompt
  race, Join, and the "No call" message (45 tests in the package).
- The demo freezes its fixture events; otherwise opening the panel refetched and replaced them with the real
  calendar.

## Tests
- `MeetingLink`: the "Join with Google Meet:" line beats a pasted `<a href>` Meet link earlier in notes; Meet in
  HTML notes; a YouTube link before a Meet link loses; redirect unwrapped; no link; `authuser` added once, kept
  when already there.
- `Agenda`: solo timed events included; Join only with a link and another person (organizer counts; solo event
  with Google's auto link has no Join); declined and all-day excluded; hidden
  outside the window, visible inside and while running; hand-over at the end; "in N min" vs "N min left"; tint at
  5 min and while running; title trimming; join target (10 min back, 15 min ahead, none).
- `Reminders`: no alarms, no pill; sticky at each alarm and at start for today; heads-up for later days with 8 s
  life; duplicate offsets merged; later replaces earlier for the same event; cleared at the end and after join;
  stacking cap; missed sticky within 5 min fires, older does not; missed heads-up fires once on wake; a refetch
  moving the event by a minute does not re-fire a shown alarm; cancelled or declined clears its pills.

## Hands-on pass
Create a Meet event 20 minutes ahead with 15 and 5 minute reminders and one other guest. The item appears
at the 1 h window, turns amber at 5 minutes, mint at the start. Pills with the sound at 15, 5 and 0, each
replacing the last. ⌃⌘J joins in the browser as the right account. A solo event with an alarm gets a pill with no
Join; one with a 1 day alarm gets an 8 s heads-up; two overlapping events stack; drag the pill, restart the app, it comes back there; double-click resets.

## Risks
- The Meet link is not in any EventKit field for Google-synced events. Step 0; fallback is the Google source.
- Sync lag for moved or late invites. Step 0 measures it; the nudge may or may not help.
- A menubar crowded with other items can hide the second status item (macOS drops items that do not fit); the
  Tools row and the pill still work.
- Calendars is a new TCC grant; the self-signed dev certificate keeps it across rebuilds like the others.
