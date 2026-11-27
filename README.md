# Mutiny

**Free music. No ads. No subscription.** A music player for iPhone, Android and Windows with
a dark-purple liquid-glass design.

Music comes from free and legal sources:

- **Audius**: millions of songs from independent artists, streamed for free
- **Live radio**: thousands of stations worldwide, including Malaysian ones (Sinar, 988, Hot FM…)
- **Your own files**: MP3 / M4A / FLAC / WAV you import (they stay on your device)

## Features

- **My Wave**: an endless mix with an animated dot-matrix orb. Tune it to a mood (Chill, Energy, Hip-Hop, Discover)
- **Daily Mixes**: 6 genre mixes with halftone covers that change every day
- Trending songs, hot playlists, underground gems, radio in Malaysia
- Search songs, artists, playlists and radio, with recent searches and genre browsing
- Liked Songs, your own playlists (create, rename, delete, add/remove songs), saved stations
- Full-screen player: blurred-cover background that takes the song's colour, shuffle, repeat / repeat-one, seek
- Queue: play next, add to queue, drag to reorder, swipe to remove
- Sleep timer (5 to 60 min, or end of song)
- Lock-screen and notification controls, plays in the background
- Mini player: tap to open, swipe up to expand, swipe sideways to skip

## Project layout

```
lib/
├── main.dart                  start-up: audio engine, providers
├── models/models.dart         Track, Playlist, Artist…
├── services/
│   ├── audius_api.dart        Audius music API (no key needed)
│   ├── radio_api.dart         Radio Browser API (no key needed)
│   ├── library_store.dart     likes, playlists, history, imported files
│   └── player_controller.dart queue, shuffle, repeat, sleep timer
└── ui/
    ├── theme.dart             purple palette + Unbounded font
    ├── glass.dart             liquid-glass panels, buttons, sheets
    ├── effects.dart           aurora background, wave orb, halftone covers
    ├── widgets.dart           song rows, cards, song menu
    ├── shell.dart             tab bar + mini player
    └── screens/               home, search, radio, library, player…
```

## Build it yourself

You need [Flutter](https://docs.flutter.dev/get-started/install) **3.50** or newer.

```bash
flutter pub get
flutter run                   # run on a connected phone / emulator / Windows
flutter build apk --release   # Android → build/app/outputs/flutter-apk/app-release.apk
flutter build windows         # Windows → build/windows/x64/runner/Release/
flutter test                  # unit tests
```

## Getting it on your iPhone (no Mac needed)

Apple only builds iPhone apps on a Mac, so GitHub builds it for you on one of its Macs
(free), and you install it from Windows with **Sideloadly**.

### 1. Let GitHub build the .ipa

1. Create a free account on <https://github.com> and make a new repository called `mutiny`.
2. Upload this whole folder to it (on the repository page: **Add file → Upload files**, drag
   everything in, including the hidden `.github` folder, then **Commit changes**).
   Or with Git: `git remote add origin https://github.com/YOUR_NAME/mutiny.git && git push -u origin main`
3. Open the **Actions** tab. The **Build Mutiny** workflow starts by itself (about 10–15 min).
4. When it shows a green tick, open the run, scroll to **Artifacts**, and download
   **Mutiny-iOS** (it unzips to `Mutiny-iOS.ipa`). The same run also gives you
   **Mutiny-Android** and **Mutiny-Windows**.

Tip: push a tag (`git tag v1.0.0 && git push --tags`) to get all three files on a
**Releases** page instead.

### 2. Install with Sideloadly (Windows)

1. Install **iTunes** (the Apple website version, not the Microsoft Store one) and
   **Sideloadly** from <https://sideloadly.io>.
2. Plug your iPhone into the laptop with a cable and tap **Trust** on the phone.
3. Open Sideloadly, drag `Mutiny-iOS.ipa` in, type your Apple ID email, click **Start**,
   then enter your Apple ID password when asked. (Use an Apple ID you're comfortable
   with; a spare one works too.)
4. On the iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID →
   **Trust**.
5. Turn on **Developer Mode** if iOS asks: **Settings → Privacy & Security → Developer
   Mode → On**, then restart.
6. Open Mutiny 🎧

**Every 7 days** a free Apple ID's apps expire. Plug in and press **Start** in Sideloadly again
(about a minute). Your likes and playlists are kept.

With a paid Apple Developer account ($99/year) the app lasts a year, or you can use TestFlight.

## Windows

Unzip `Mutiny-Windows.zip` anywhere and run `mutiny.exe`. If Windows SmartScreen warns
you, click **More info → Run anyway** (the app isn't code-signed).

## Android

Copy `Mutiny-Android.apk` to the phone, open it and allow "Install unknown apps".

## Credits

- Music: [Audius](https://audius.co) API · Radio: [Radio Browser](https://www.radio-browser.info)
- Font: [Unbounded](https://fonts.google.com/specimen/Unbounded) (SIL Open Font License)
- Playback: just_audio, just_audio_background, media_kit
