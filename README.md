# Mutiny

**Free music. No ads. No subscription.** A music player for iPhone, Android and Windows with
a dark-purple liquid-glass design.

Music comes from free and legal sources:

- **Audius**: millions of songs from independent artists, streamed for free
- **Live radio**: thousands of stations worldwide, including Malaysian ones (Sinar, 988, Hot FM…)
- **Your own songs**: MP3 / M4A / FLAC / WAV you add with your own name, cover and lyrics (they stay on your device)

## Features

- **Flow**: an endless mix with a morphing liquid-glass orb that moves faster when music plays. Tune it to a mood (Chill, Energy, Hip-Hop, Discover)
- **Daily mixes**: 6 genre mixes with liquid-gradient covers that change every day
- Trending songs, hot playlists, underground gems, radio in Malaysia
- Search songs, artists, playlists and radio, with recent searches and genre browsing
- **Profile**: your name and photo, minutes listened, top artists and top songs this month
- **Playlists**: your own cover photo or an automatic 4-picture mosaic, description, drag to
  reorder, search inside, **Add songs** with recommendations, pin, duplicate, delete
- **Library**: Liked Songs, playlists, saved Audius playlists, followed artists, saved
  stations and files, with filters, Recents / A–Z / Creator sorting and a grid view
- **Follow** artists and **Save** other people's playlists
- **Add your own song**: audio file + name, artist, cover picture and lyrics (timed `[mm:ss]`
  lyrics scroll with the song). Private to your device, never published, and you can put it
  in any playlist. Edit or delete it later from the song's ••• menu
- **Lyrics** that scroll with the song (tap a line to jump), from LRCLIB or your own
- **Share** songs, and **song radio** (similar songs from the same artist and genre)
- Full-screen player: blurred-cover background that takes the song's colour, shuffle, repeat / repeat-one, seek
- Queue: play next, add to queue, drag to reorder, swipe to remove
- Sleep timer (5 to 60 min, or end of song)
- Lock-screen and notification controls, plays in the background
- Mini player: tap to open, swipe up to expand, swipe sideways to skip

## Account & sync

Sign in (Library → cloud icon, or Profile) with email and password and Mutiny keeps
playlists, Liked Songs, followed artists, saved playlists, stations, profile and your
own songs (audio, covers, lyrics) the same on every phone, tablet and computer.
Changes show up on your other devices within seconds. Without an account everything
still works, on this device only.

The cloud is a Supabase project (`rtlycngyhzoqdvnqkbrl`, Singapore) with row-level
security: each account can only read and write its own rows and files.

## Background playback

Music keeps playing when you lock the phone or switch apps:

- **iPhone**: background audio mode plus a music audio session. Controls appear on the lock
  screen and in Control Center, it pauses for phone calls and resumes after.
- **Android**: a media-playback foreground service with notification and lock-screen
  controls. Some phones (Xiaomi, Oppo, Vivo, Samsung) kill background apps to save battery:
  set Mutiny's battery usage to **Unrestricted** if music stops.
- Pulling out headphones or disconnecting Bluetooth pauses the music, like Spotify.

## Branding

Everything is in `branding/`: SVG (vector) and PNG versions of the symbol, the
horizontal and stacked logos (dark, transparent, on-light), app icons (normal, rounded,
Android foreground, monochrome), the splash image and `mutiny-brand-sheet.png`.

The symbol is a **flag made of sound waves**: raise your own flag against paid music.
Its stripes wave like cloth and step down like an equalizer.

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
    ├── effects.dart           aurora background, liquid orb, liquid covers
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

Every push to `main` also publishes the three files as a **Release**
(`v1.0.<build>`) on the repo's Releases page.

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

## Updates

Mutiny checks GitHub Releases a few seconds after it opens (and from
**Settings → Check for updates**). When a newer build exists it shows **Update available**:

- **Android**: *Update now* downloads the new APK and opens the installer (allow
  "Install unknown apps" for Mutiny the first time). Your data stays.
- **Windows**: *Update now* downloads the new version, closes Mutiny, replaces the files
  and reopens it.
- **iPhone**: Apple doesn't let apps install themselves outside the App Store, so it
  tells you a new version exists. Install the new `.ipa` with Sideloadly; your data stays.

### Android signing key (one-time setup)

Android only accepts an update if it's signed with the same key. Add two repository secrets
(**Settings → Secrets and variables → Actions → New repository secret**):

| Name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the whole content of `keystore-base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | the content of `password.txt` |

Keep the key files private and backed up: if the key is lost, Android users must uninstall
once to switch to a new key.

## Windows

Unzip `Mutiny-Windows.zip` anywhere and run `mutiny.exe`. If Windows SmartScreen warns
you, click **More info → Run anyway** (the app isn't code-signed).

## Android

Copy `Mutiny-Android.apk` to the phone, open it and allow "Install unknown apps".

## Credits

- Music: [Audius](https://audius.co) API · Radio: [Radio Browser](https://www.radio-browser.info)
- Font: [Unbounded](https://fonts.google.com/specimen/Unbounded) (SIL Open Font License)
- Playback: just_audio, just_audio_background, media_kit
