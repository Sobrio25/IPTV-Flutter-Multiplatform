## IPTV Player

Flutter IPTV player for Android, Windows, and Linux with:

- editable M3U playlist sources
- channel search, groups, and favorites
- integrated Flutter video playback on Android, Windows, and Linux through `media_kit`

Run it with:

```sh
flutter run -d <device>
```

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
