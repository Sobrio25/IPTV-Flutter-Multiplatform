import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/app_localizations.dart';
import 'package:iptv_player/main.dart';

void main() {
  test('parseM3u reads channel metadata and stream urls', () {
    final channels = parseM3u('''
#EXTM3U
#EXTINF:-1 tvg-id="demo" tvg-logo="https://example.com/logo.png" group-title="News",Demo Channel
https://example.com/live.m3u8
''');

    expect(channels, hasLength(1));
    expect(channels.single.name, 'Demo Channel');
    expect(channels.single.group, 'News');
    expect(channels.single.logo, 'https://example.com/logo.png');
    expect(channels.single.url, 'https://example.com/live.m3u8');
  });

  test('parseM3u preserves catch-up and EPG attributes', () {
    final channels = parseM3u('''
#EXTM3U
#EXTINF:-1 tvg-id="demo.us" tvg-name="Demo EPG" tvg-shift="-6" catchup="append" catchup-days="7" catchup-source="?utc={utc}&lutc={lutc}" group-title="Replay",Demo Replay
https://example.com/live/demo.m3u8
''');

    expect(channels, hasLength(1));
    expect(channels.single.id, 'demo.us');
    expect(channels.single.tvgName, 'Demo EPG');
    expect(channels.single.tvgShift, -6);
    expect(channels.single.catchup, 'append');
    expect(channels.single.catchupDays, 7);
    expect(channels.single.catchupSource, '?utc={utc}&lutc={lutc}');
    expect(channels.single.hasCatchup, isTrue);
  });

  test('parseM3u accepts common non-http stream schemes', () {
    final channels = parseM3u('''
#EXTM3U
#EXTINF:-1 group-title='Cameras',Garage
rtsp://example.com/camera
#EXTINF:-1 group-title=Local,Multicast
udp://@239.10.10.1:1234
''');

    expect(channels, hasLength(2));
    expect(channels.first.group, 'Cameras');
    expect(channels.first.url, 'rtsp://example.com/camera');
    expect(channels.last.group, 'Local');
    expect(channels.last.url, 'udp://@239.10.10.1:1234');
  });

  test('parseM3uPlaylist discovers XMLTV urls from the playlist header', () {
    final playlist = parseM3uPlaylist('''
#EXTM3U x-tvg-url="https://example.com/guide.xml,https://example.com/extra.xml"
#EXTINF:-1 tvg-id="demo",Demo
https://example.com/live.m3u8
''');

    expect(playlist.channels, hasLength(1));
    expect(
      playlist.epgUrls,
      containsAll([
        'https://example.com/guide.xml',
        'https://example.com/extra.xml',
      ]),
    );
  });

  test('parseXmlTv reads timezone-aware programs and display-name aliases', () {
    final guide = parseXmlTv('''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="demo.mx"><display-name>Demo México</display-name></channel>
  <programme start="20260806120000 -0600" stop="20260806130000 -0600" channel="demo.mx">
    <title>Noticias</title>
    <desc>Resumen del día</desc>
  </programme>
</tv>
''');

    final programs = guide['demo mexico'];
    expect(programs, isNotNull);
    expect(programs, hasLength(1));
    expect(programs!.single.title, 'Noticias');
    expect(programs.single.start, DateTime.utc(2026, 8, 6, 18));
    expect(programs.single.stop, DateTime.utc(2026, 8, 6, 19));
  });

  test('buildCatchupUrl expands common replay placeholders', () {
    const channel = IptvChannel(
      name: 'Demo',
      url: 'https://example.com/live.m3u8',
      catchup: 'append',
      catchupSource: '?utc={utc}&lutc={lutc}&duration={duration}',
    );
    final program = EpgProgram(
      channelId: 'demo',
      start: DateTime.utc(2026, 8, 6, 18),
      stop: DateTime.utc(2026, 8, 6, 19),
      title: 'Noticias',
    );

    final url = buildCatchupUrl(channel, program);

    expect(url, startsWith('https://example.com/live.m3u8?utc='));
    expect(url, contains('&lutc='));
    expect(url, contains('&duration=3600'));
    expect(url, isNot(contains('{')));
  });

  test('source and playback errors do not expose credentials', () {
    const privateUrl =
        'https://user:secret@example.com/get.php?username=user&password=secret';
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(sourceDisplayUrl(l10n, privateUrl), isNot(contains('secret')));
    expect(sourceDisplayUrl(l10n, privateUrl), isNot(contains('username')));
    expect(
      friendlyPlaybackError(l10n, 'Failed to open $privateUrl',
          channelName: 'Demo'),
      isNot(contains(privateUrl)),
    );
  });
}
