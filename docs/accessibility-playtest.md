# Screen-reader playtest

Task T-705. The probes in `docs/accessibility.md` prove that Hectopolis can be
reached and is announced: every control is focusable, the map speaks the cell
under the cursor, a tile pick and a placement are announced. They cannot say
whether playing it with a screen reader is **understandable and pleasant**.
That takes people who use one every day. This page is the script for one
session with one such person, about an hour, so that their time produces
findings rather than first impressions of a setup problem.

## Who and with what

Two to four participants are enough to find most problems; each brings their
own device and screen reader, set up the way they use it. Do not lend a device:
an unfamiliar configuration produces findings about the configuration.

| Setup | Build | Notes |
|---|---|---|
| NVDA with Firefox or Chrome, Windows | web build | the most common screen reader in Germany's working population |
| VoiceOver with Safari, macOS | web build | |
| VoiceOver, iPhone | App Store or TestFlight build | relays are not in this build |
| TalkBack, Android | release APK | |

The web build is the first priority: it is where the 2026-10-26 fixes landed,
and it needs nothing installed.

Recruiting, in Germany: the Deutscher Blinden- und Sehbehindertenverband
(DBSV) and its regional associations, the BIK für Alle project, the
accessibility services of universities, and accessibility meetups. Offer to pay
for the hour; testing is work.

## Before the session

- Ask for consent to take notes, and separately for any recording. Record
  nothing without it. Notes name no one; a participant is "P1".
- Agree on the language (DE or EN). The game follows the device language; the
  language button switches it.
- Have the build open on the start screen. Do not demonstrate anything: the
  first minutes are the most informative ones.

## Tasks

Read each task aloud as written. Do not explain how the game works unless the
participant asks twice. Note what the screen reader said when something went
wrong, word for word where possible.

1. **Start.** "Please start a new game in the village." (Level select, a
   scenario button, the mission briefing.)
2. **The briefing.** "What is your mission? What does the game ask you to
   predict?" (Dialog content, the prediction radio group.) Answer the
   prediction and continue.
3. **Find your way.** "What is on this screen?" (Reading order: app bar,
   palette, map, goals, gauges, inspector.)
4. **The goals.** "Which goals have you already met?" (Goal rows say "met" or
   "not met yet".)
5. **The map.** "Move to a cell next to the road and tell me what is there."
   (Tab to the map, arrow keys, the cell description.)
6. **Build.** "Build detached housing on that cell." (A digit key or the
   palette, Enter; the announcement of the pick and of the placement.)
7. **Consequences.** "What did that change?" (Gauges, the inspector.)
8. **Undo.** "Undo the last building."
9. **Time.** "Let a year pass. How is the village doing?"
10. **An overlay.** "Show where it is loud." (The overlay menu, then reading
    the map with the overlay on.)
11. **Finish.** Play until the level ends, or for ten minutes. "What was the
    result?"
12. **Optional, co-op.** "Host a game for a friend. What would you tell them
    so they can join?" (The room code in the lobby is now spoken.)

## What to note, per task

| | |
|---|---|
| Done? | yes / with help / no |
| What was said that helped | |
| What was said that confused | (exact words) |
| What was missing | (information a sighted player has and they did not) |
| Too much | (repetition, noise, announcements over each other) |
| Severity | 1 blocks the task · 2 slows it a lot · 3 annoyance |

Close with three questions: what was hardest, what was better than expected,
and whether they would play it again.

## After

File each severity-1 and severity-2 finding as an issue that quotes the screen
reader's words and names the setup. Add the session (date, setup, P-number,
build) to the log below, and tick T-705 once two setups have been tested and
their severity-1 findings fixed.

| Date | Setup | Participant | Build | Findings |
|---|---|---|---|---|
| | | | | |
