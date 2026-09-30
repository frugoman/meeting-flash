# MeetingFlash

A tiny macOS menu bar app that **flashes your screen red right before a meeting starts**, so you never miss one while heads-down.

It reads the calendars in the macOS Calendar app, so it works with Exchange / Microsoft 365, Google, iCloud, or any account added under **System Settings → Internet Accounts**.

## Install

```bash
brew install --cask frugoman/tap/meeting-flash
```

Then open **MeetingFlash** from Applications and allow calendar access.

Or download the latest `.zip` from [Releases](https://github.com/frugoman/homebrew-tap/releases?q=meeting-flash), unzip it, and move `MeetingFlash.app` to Applications. Because the app isn't notarized, the first launch needs a right-click → **Open** (or **System Settings → Privacy & Security → Open Anyway**).

Requires macOS 14 Sonoma or later.

## Features

- Full-screen flash on every display, showing the meeting title, that stays until you click anywhere or press a key
- Flash in red (the default), any colour and opacity you like, or a photo of your choice
- Multiple alerts per meeting (at start, or 1–30 minutes before), each with its own flash and sound (a system sound or your own MP3/M4A/WAV) — e.g. a soft *Tink* at 5 min, flash + *Sosumi* at 1 min
- Sounds only on the outputs you choose — pick your AirPods and alerts stay silent on the laptop speakers at the office. Paired Bluetooth speakers and headphones are listed even when disconnected
- Wi-Fi rules: never make sound on certain networks (e.g. the office), or allow an output only on some (e.g. MacBook speakers only at home). Reading the Wi-Fi name needs Location access — macOS requires it
- Pick which calendars to watch
- Skips all-day, cancelled, declined, and (optionally) "Free" events
- Countdown in the menu bar when the next meeting is less than an hour away
- Upcoming meetings list with one-click join for Teams, Zoom, Meet, and Webex links
- Launch at login

> Using only the Outlook app? MeetingFlash can't see Outlook's own calendar store. Add your work account to **System Settings → Internet Accounts** (turn on Calendars) and it'll show up.

## Build from source

```bash
./build.sh
open build/MeetingFlash.app
```

Needs Xcode or the Command Line Tools (Swift 5.9+).

## Releasing

```bash
./release.sh 1.1.0
```

Builds a universal binary, publishes the zip as a release on, and updates the cask in, [frugoman/homebrew-tap](https://github.com/frugoman/homebrew-tap).

## License

MIT
