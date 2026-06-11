import 'package:flutter_test/flutter_test.dart';
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
}
