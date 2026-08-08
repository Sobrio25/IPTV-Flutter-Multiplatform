# IPTV Flutter Multiplatform

Flutter IPTV player for Android, iOS, Windows, macOS, Linux, and web with:

- editable M3U playlist sources
- channel search, groups, and favorites
- recent channels and sortable channel lists
- queue-based channel surfing inside the player
- adaptive layouts for mobile, desktop, and TV-sized windows
- integrated Flutter video playback through `media_kit`
- player controls for play/pause, retry, previous/next, volume/mute, fullscreen, and audio/video/subtitle tracks
- automatic retry, keyboard shortcuts, and safe playback errors that redact source URLs
- XMLTV discovery through `x-tvg-url`, configurable EPG sources, now/next data, and a searchable TV guide
- catch-up playback for playlists that provide a compatible `catchup-source`
- configurable User-Agent and Referer headers per playlist
- cross-platform settings that preserve the legacy Android/Windows/Linux store

Run it with:

```sh
flutter run -d <device>
```

Web providers must allow CORS requests from the app origin. IPTV Player does not
include channels or subscriptions; users are responsible for adding legally
authorized sources.

Build Windows with:

```sh
flutter build windows
```

Build Linux with:

```sh
flutter build linux
```

Linux playback depends on `libmpv` at runtime. On Ubuntu or Debian, install:

```sh
sudo apt install libmpv2 mpv
```

Linux builds also need the native desktop toolchain:

```sh
sudo apt install clang cmake ninja-build libgtk-3-dev libmpv-dev pkg-config
```
