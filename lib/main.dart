import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xml/xml.dart';

import 'app_storage.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IptvApp());
}

const _maxRecentChannels = 24;
const _streamHeaders = <String, String>{'User-Agent': 'IPTV Player Flutter'};
const _supportedStreamSchemes = {'http', 'https', 'rtmp', 'rtsp', 'udp', 'mms'};

bool get _supportsIntegratedPlayback =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

Map<String, String> _headersForSource(PlaylistSource source) {
  final headers = <String, String>{};
  if (!kIsWeb) {
    headers.addAll(_streamHeaders);
    if (source.userAgent.trim().isNotEmpty) {
      headers['User-Agent'] = source.userAgent.trim();
    }
  }
  if (source.referer.trim().isNotEmpty) {
    headers['Referer'] = source.referer.trim();
  }
  return headers;
}

Map<String, String> _headersForChannel(IptvChannel channel) {
  final headers = <String, String>{
    if (!kIsWeb) ..._streamHeaders,
    ...channel.httpHeaders,
  };
  if (kIsWeb) headers.remove('User-Agent');
  return headers;
}

class PlaylistSource {
  const PlaylistSource({
    required this.name,
    required this.description,
    required this.url,
    this.epgUrl = '',
    this.userAgent = '',
    this.referer = '',
  });

  final String name;
  final String description;
  final String url;
  final String epgUrl;
  final String userAgent;
  final String referer;

  PlaylistSource copyWith({
    String? name,
    String? description,
    String? url,
    String? epgUrl,
    String? userAgent,
    String? referer,
  }) {
    return PlaylistSource(
      name: name ?? this.name,
      description: description ?? this.description,
      url: url ?? this.url,
      epgUrl: epgUrl ?? this.epgUrl,
      userAgent: userAgent ?? this.userAgent,
      referer: referer ?? this.referer,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'url': url,
    'epgUrl': epgUrl,
    'userAgent': userAgent,
    'referer': referer,
  };

  static PlaylistSource fromJson(Map<String, Object?> json) {
    final name = (json['name'] as String? ?? '').trim();
    final description = (json['description'] as String? ?? '').trim();
    final url = (json['url'] as String? ?? '').trim();
    return PlaylistSource(
      name: name,
      description: description,
      url: url,
      epgUrl: (json['epgUrl'] as String? ?? '').trim(),
      userAgent: (json['userAgent'] as String? ?? '').trim(),
      referer: (json['referer'] as String? ?? '').trim(),
    );
  }
}

List<PlaylistSource> defaultSources(AppLocalizations l10n) => <PlaylistSource>[
  PlaylistSource(
    name: l10n.sourceGlobalName,
    description: l10n.sourceGlobalDescription,
    url: 'https://iptv-org.github.io/iptv/index.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceMexico,
    description: l10n.sourceByCountry,
    url: 'https://iptv-org.github.io/iptv/countries/mx.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceUsa,
    description: l10n.sourceByCountry,
    url: 'https://iptv-org.github.io/iptv/countries/us.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceSpanish,
    description: l10n.sourceByLanguage,
    url: 'https://iptv-org.github.io/iptv/languages/spa.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceEnglish,
    description: l10n.sourceByLanguage,
    url: 'https://iptv-org.github.io/iptv/languages/eng.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceNews,
    description: l10n.sourceCategory,
    url: 'https://iptv-org.github.io/iptv/categories/news.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceSports,
    description: l10n.sourceCategory,
    url: 'https://iptv-org.github.io/iptv/categories/sports.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceMovies,
    description: l10n.sourceCategory,
    url: 'https://iptv-org.github.io/iptv/categories/movies.m3u',
  ),
  PlaylistSource(
    name: l10n.sourceKids,
    description: l10n.sourceCategory,
    url: 'https://iptv-org.github.io/iptv/categories/kids.m3u',
  ),
];

class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.group = '',
    this.logo = '',
    this.id = '',
    this.tvgName = '',
    this.catchup = '',
    this.catchupSource = '',
    this.catchupDays,
    this.tvgShift,
    this.httpHeaders = const {},
  });

  final String name;
  final String url;
  final String group;
  final String logo;
  final String id;
  final String tvgName;
  final String catchup;
  final String catchupSource;
  final int? catchupDays;
  final int? tvgShift;
  final Map<String, String> httpHeaders;

  bool get hasCatchup =>
      catchup.trim().isNotEmpty ||
      catchupSource.trim().isNotEmpty ||
      catchupDays != null;

  IptvChannel copyWith({
    String? name,
    String? url,
    String? group,
    String? logo,
    String? id,
    String? tvgName,
    String? catchup,
    String? catchupSource,
    int? catchupDays,
    int? tvgShift,
    Map<String, String>? httpHeaders,
  }) {
    return IptvChannel(
      name: name ?? this.name,
      url: url ?? this.url,
      group: group ?? this.group,
      logo: logo ?? this.logo,
      id: id ?? this.id,
      tvgName: tvgName ?? this.tvgName,
      catchup: catchup ?? this.catchup,
      catchupSource: catchupSource ?? this.catchupSource,
      catchupDays: catchupDays ?? this.catchupDays,
      tvgShift: tvgShift ?? this.tvgShift,
      httpHeaders: httpHeaders ?? this.httpHeaders,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'group': group,
    'logo': logo,
    'id': id,
    'tvgName': tvgName,
    'catchup': catchup,
    'catchupSource': catchupSource,
    'catchupDays': catchupDays,
    'tvgShift': tvgShift,
    'httpHeaders': httpHeaders,
  };

  static IptvChannel fromJson(Map<String, Object?> json) => IptvChannel(
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
    group: json['group'] as String? ?? '',
    logo: json['logo'] as String? ?? '',
    id: json['id'] as String? ?? '',
    tvgName: json['tvgName'] as String? ?? '',
    catchup: json['catchup'] as String? ?? '',
    catchupSource: json['catchupSource'] as String? ?? '',
    catchupDays: _parseOptionalInt(json['catchupDays']),
    tvgShift: _parseOptionalInt(json['tvgShift']),
    httpHeaders: _parseStringMap(json['httpHeaders']),
  );
}

class EpgProgram {
  const EpgProgram({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subtitle = '',
    this.description = '',
    this.category = '',
    this.icon = '',
  });

  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String subtitle;
  final String description;
  final String category;
  final String icon;

  bool isLiveAt(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(stop);

  bool get hasEnded => stop.isBefore(DateTime.now());
}

class ParsedPlaylist {
  const ParsedPlaylist({required this.channels, required this.epgUrls});

  final List<IptvChannel> channels;
  final List<String> epgUrls;
}

class _PlaylistLoadResult {
  const _PlaylistLoadResult({required this.channels, required this.epgUrls});

  final List<IptvChannel> channels;
  final List<String> epgUrls;
}

int? _parseOptionalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

Map<String, String> _parseStringMap(Object? value) {
  if (value is! Map<dynamic, dynamic>) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

List<IptvChannel> _dedupeChannelsByUrl(Iterable<IptvChannel> channels) {
  final unique = <String, IptvChannel>{};
  for (final channel in channels) {
    final url = channel.url.trim();
    if (url.isEmpty) continue;
    unique[url] = channel;
  }
  return unique.values.toList();
}

typedef ChannelPlayRequest =
    Future<void> Function(IptvChannel channel, List<IptvChannel> queue);

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff0d8b7f);
    return MaterialApp(
      title: 'IPTV Player',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)!.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xff101418),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xff0b0f12),
        visualDensity: VisualDensity.compact,
      ),
      home: const IptvHomePage(),
    );
  }
}

class IptvHomePage extends StatefulWidget {
  const IptvHomePage({super.key});

  @override
  State<IptvHomePage> createState() => _IptvHomePageState();
}

class _IptvHomePageState extends State<IptvHomePage> {
  var _sources = <PlaylistSource>[];
  var _favorites = <String>{};
  var _recentChannels = <IptvChannel>[];
  var _status = '';
  String? _loadingSourceUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreState());
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  Future<void> _restoreState() async {
    final values = await Future.wait([
      _readString('playlistSources'),
      _readString('playlistUrl'),
      _readString('favorites'),
      _readString('recentChannels'),
    ]);

    final savedSources = _decodeSources(values[0]);
    final savedUrl = values[1]?.trim();
    final savedFavorites = values[2];
    final savedRecentChannels = _decodeChannels(values[3]);

    if (!mounted) return;
    setState(() {
      _sources = savedSources ?? defaultSources(_l10n);
      if (savedUrl != null &&
          savedUrl.isNotEmpty &&
          !_sources.any((source) => source.url == savedUrl)) {
        _sources = [
          PlaylistSource(
            name: _l10n.savedPlaylist,
            description: _l10n.savedPlaylistDescription,
            url: savedUrl,
          ),
          ..._sources,
        ];
      }
      if (savedFavorites != null && savedFavorites.isNotEmpty) {
        try {
          _favorites = (jsonDecode(savedFavorites) as List<dynamic>)
              .whereType<String>()
              .toSet();
        } on FormatException {
          _favorites = <String>{};
        }
      }
      _recentChannels = savedRecentChannels;
    });
    unawaited(_removeString('channels'));
  }

  List<PlaylistSource>? _decodeSources(String? rawSources) {
    if (rawSources == null || rawSources.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawSources);
      if (decoded is! List<dynamic>) return null;
      return _normalizeSources([
        for (final item in decoded)
          if (item is Map<dynamic, dynamic>)
            PlaylistSource.fromJson(Map<String, Object?>.from(item)),
      ]);
    } catch (_) {
      return null;
    }
  }

  List<PlaylistSource> _normalizeSources(List<PlaylistSource> sources) {
    final unique = <String, PlaylistSource>{};
    for (final source in sources) {
      final url = source.url.trim();
      if (url.isEmpty) continue;
      unique[url] = source.copyWith(
        name: source.name.trim().isEmpty ? _l10n.m3uListName : source.name.trim(),
        description: source.description.trim().isEmpty
            ? _l10n.customListDescription
            : source.description.trim(),
        url: url,
      );
    }
    return unique.isEmpty
        ? defaultSources(_l10n)
        : unique.values.toList();
  }

  List<IptvChannel> _decodeChannels(String? rawChannels) {
    if (rawChannels == null || rawChannels.trim().isEmpty) {
      return <IptvChannel>[];
    }
    try {
      final decoded = jsonDecode(rawChannels);
      if (decoded is! List<dynamic>) return <IptvChannel>[];
      return _dedupeChannelsByUrl([
        for (final item in decoded)
          if (item is Map<dynamic, dynamic>)
            IptvChannel.fromJson(Map<String, Object?>.from(item)),
      ]).take(_maxRecentChannels).toList();
    } catch (_) {
      return <IptvChannel>[];
    }
  }

  Future<String?> _readString(String key) async {
    return readAppString(key);
  }

  Future<void> _writeString(String key, String value) async {
    await writeAppString(key, value);
  }

  Future<void> _removeString(String key) async {
    await removeAppString(key);
  }

  Future<void> _saveSources(List<PlaylistSource> sources) async {
    await _writeString(
      'playlistSources',
      jsonEncode(sources.map((source) => source.toJson()).toList()),
    );
  }

  Future<_PlaylistLoadResult> _downloadChannels(PlaylistSource source) async {
    final url = source.url.trim();
    if (url.isEmpty) {
      return const _PlaylistLoadResult(channels: [], epgUrls: []);
    }

    final response = await http
        .get(Uri.parse(url), headers: _headersForSource(source))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final parsed = parseM3uPlaylist(body);
    final sourceHeaders = _headersForSource(source);
    final channels = _dedupeChannelsByUrl(
      parsed.channels.map(
        (channel) => channel.copyWith(httpHeaders: sourceHeaders),
      ),
    )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final epgUrls = <String>{
      if (source.epgUrl.trim().isNotEmpty) source.epgUrl.trim(),
      ...parsed.epgUrls,
    }.toList();
    return _PlaylistLoadResult(channels: channels, epgUrls: epgUrls);
  }

  Future<void> _openSource(PlaylistSource source) async {
    if (_loadingSourceUrl != null) return;
    setState(() {
      _loadingSourceUrl = source.url;
      _status = _l10n.statusDownloading(source.name);
    });

    try {
      final result = await _downloadChannels(source);
      final channels = result.channels;
      await _writeString('playlistUrl', source.url);
      await _removeString('channels');

      if (!mounted) return;
      setState(() {
        _loadingSourceUrl = null;
        _status = channels.isEmpty
            ? _l10n.statusNoChannels
            : _l10n.statusChannelsLoaded(channels.length, source.name);
      });

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _ChannelListPage(
            source: source,
            channels: channels,
            epgUrls: result.epgUrls,
            favorites: _favorites,
            onFavorite: _toggleFavorite,
            onPlayChannel: _playChannel,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSourceUrl = null;
        _status = friendlyNetworkError(_l10n, error, resource: _l10n.resourceList);
      });
      _showSnackBar(_l10n.snackbarLoadFailed);
    }
  }

  Future<void> _toggleFavorite(IptvChannel channel) async {
    setState(() {
      if (!_favorites.add(channel.url)) {
        _favorites.remove(channel.url);
      }
    });
    await _writeString('favorites', jsonEncode(_favorites.toList()));
  }

  Future<void> _rememberChannel(IptvChannel channel) async {
    final recents = [
      channel,
      ..._recentChannels.where((recent) => recent.url != channel.url),
    ].take(_maxRecentChannels).toList();
    if (mounted) {
      setState(() => _recentChannels = recents);
    } else {
      _recentChannels = recents;
    }
    await _writeString(
      'recentChannels',
      jsonEncode(recents.map((recent) => recent.toJson()).toList()),
    );
  }

  Future<void> _playChannel(
    IptvChannel channel,
    List<IptvChannel> queue,
  ) async {
    if (_supportsIntegratedPlayback) {
      final channels = _dedupeChannelsByUrl(
        queue.isEmpty ? <IptvChannel>[channel] : queue,
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _PlayerPage(
            initialChannel: channel,
            channels: channels,
            onChannelStarted: _rememberChannel,
          ),
        ),
      );
      return;
    }

    _showSnackBar(_l10n.playbackUnavailable);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PlaylistSettingsPage(
          sources: _sources,
          onSourcesChanged: (sources) async {
            final normalized = _normalizeSources(sources);
            if (mounted) {
              setState(() => _sources = normalized);
            }
            await _saveSources(normalized);
          },
        ),
      ),
    );
  }

  Widget _buildSourceCard(PlaylistSource source) {
    final loading = _loadingSourceUrl == source.url;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: _SourceIcon(loading: loading),
        title: Text(
          source.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${source.description}\n${sourceDisplayUrl(_l10n, source.url)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _loadingSourceUrl == null ? () => _openSource(source) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = _l10n;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _AppLogo(size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IPTV Player',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.playlistsLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: l10n.settingsTooltip,
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _status.isEmpty ? l10n.statusSelectPlaylist : _status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (_loadingSourceUrl != null) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              if (_recentChannels.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      l10n.recentChannels,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _MetricChip(
                      icon: Icons.history,
                      label: '${_recentChannels.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentChannels.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final channel = _recentChannels[index];
                      return _RecentChannelTile(
                        channel: channel,
                        onTap: () => _playChannel(channel, _recentChannels),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1180
                        ? 3
                        : constraints.maxWidth >= 720
                        ? 2
                        : 1;
                    if (columns == 1) {
                      return ListView.separated(
                        itemCount: _sources.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildSourceCard(_sources[index]),
                      );
                    }
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 96,
                      ),
                      itemCount: _sources.length,
                      itemBuilder: (context, index) =>
                          _buildSourceCard(_sources[index]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo({this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _AppLogoPainter()),
    );
  }
}

class _AppLogoPainter extends CustomPainter {
  const _AppLogoPainter();

  static const Color _bodyColor = Color(0xff103843);
  static const Color _screenColor = Color(0xff165764);
  static const Color _borderColor = Color(0xffebfbff);
  static const Color _accentColor = Color(0xffffa24a);
  static const Color _playColor = Color(0xffffffff);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final outerRect = Rect.fromLTWH(
      side * 0.10,
      side * 0.18,
      side * 0.80,
      side * 0.54,
    );
    final outer = RRect.fromRectAndRadius(
      outerRect,
      Radius.circular(side * 0.13),
    );
    final bodyPaint = Paint()..color = _bodyColor;
    final screenPaint = Paint()..color = _screenColor;
    final borderPaint = Paint()
      ..color = _borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.05
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final antennaPaint = Paint()
      ..color = _borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.045
      ..strokeCap = StrokeCap.round;
    final basePaint = Paint()..color = _accentColor;
    final playPaint = Paint()..color = _playColor;

    canvas.drawRRect(outer, bodyPaint);
    canvas.drawRRect(outer.deflate(side * 0.055), screenPaint);
    canvas.drawRRect(outer.deflate(side * 0.055), borderPaint);

    final antennaTop = Offset(side * 0.50, side * 0.15);
    canvas.drawLine(antennaTop, Offset(side * 0.38, side * 0.06), antennaPaint);
    canvas.drawLine(antennaTop, Offset(side * 0.62, side * 0.06), antennaPaint);

    final playPath = Path()
      ..moveTo(side * 0.44, side * 0.36)
      ..lineTo(side * 0.44, side * 0.57)
      ..lineTo(side * 0.60, side * 0.465)
      ..close();
    canvas.drawPath(playPath, playPaint);

    final baseRect = Rect.fromLTWH(
      side * 0.40,
      side * 0.75,
      side * 0.20,
      side * 0.05,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, Radius.circular(side * 0.025)),
      basePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) => false;
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox.square(
        dimension: 42,
        child: Padding(
          padding: EdgeInsets.all(9),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      child: const Icon(Icons.playlist_play),
    );
  }
}

String displayGroup(AppLocalizations l10n, String group) =>
    group.trim().isEmpty ? l10n.noGroup : group;

class _RecentChannelTile extends StatelessWidget {
  const _RecentChannelTile({required this.channel, required this.onTap});

  final IptvChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: 230,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _ChannelLogo(channel: channel),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displayGroup(l10n, channel.group),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ChannelSort { nameAsc, nameDesc, group, favoritesFirst }

extension _ChannelSortLabel on _ChannelSort {
  String label(AppLocalizations l10n) {
    switch (this) {
      case _ChannelSort.nameAsc:
        return l10n.sortNameAsc;
      case _ChannelSort.nameDesc:
        return l10n.sortNameDesc;
      case _ChannelSort.group:
        return l10n.sortGroup;
      case _ChannelSort.favoritesFirst:
        return l10n.sortFavorites;
    }
  }
}

class _ChannelListPage extends StatefulWidget {
  const _ChannelListPage({
    required this.source,
    required this.channels,
    required this.epgUrls,
    required this.favorites,
    required this.onFavorite,
    required this.onPlayChannel,
  });

  final PlaylistSource source;
  final List<IptvChannel> channels;
  final List<String> epgUrls;
  final Set<String> favorites;
  final ValueChanged<IptvChannel> onFavorite;
  final ChannelPlayRequest onPlayChannel;

  @override
  State<_ChannelListPage> createState() => _ChannelListPageState();
}

class _ChannelListPageState extends State<_ChannelListPage> {
  final _searchController = TextEditingController();
  late var _favorites = Set<String>.of(widget.favorites);
  var _selectedGroup = '';
  var _searchText = '';
  var _sortMode = _ChannelSort.nameAsc;
  var _epgByChannel = <String, List<EpgProgram>>{};
  var _epgLoading = false;
  String? _epgError;

  @override
  void initState() {
    super.initState();
    if (widget.epgUrls.isNotEmpty) {
      unawaited(_loadEpg());
    }
  }

  Future<void> _loadEpg() async {
    setState(() {
      _epgLoading = true;
      _epgError = null;
    });
    try {
      final results = await Future.wait(
        widget.epgUrls
            .take(4)
            .map(
              (url) =>
                  downloadXmlTv(url, headers: _headersForSource(widget.source)),
            ),
      );
      final merged = <String, List<EpgProgram>>{};
      for (final result in results) {
        for (final entry in result.entries) {
          merged
              .putIfAbsent(entry.key, () => <EpgProgram>[])
              .addAll(entry.value);
        }
      }
      for (final programs in merged.values) {
        programs.sort((a, b) => a.start.compareTo(b.start));
      }
      if (!mounted) return;
      setState(() => _epgByChannel = merged);
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _epgError = friendlyNetworkError(
              AppLocalizations.of(context)!,
              error,
              resource: AppLocalizations.of(context)!.resourceGuide,
            ),
      );
    } finally {
      if (mounted) setState(() => _epgLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _groups {
    final l10n = AppLocalizations.of(context)!;
    final groups =
        widget.channels
            .map((channel) => channel.group.trim())
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [l10n.groupAll, l10n.groupFavorites, ...groups];
  }

  List<IptvChannel> get _visibleChannels {
    final l10n = AppLocalizations.of(context)!;
    final query = _searchText.trim().toLowerCase();
    final visible = widget.channels.where((channel) {
      final isAll =
          _selectedGroup.isEmpty || _selectedGroup == l10n.groupAll;
      final matchesGroup =
          isAll ||
          (_selectedGroup == l10n.groupFavorites &&
              _favorites.contains(channel.url)) ||
          channel.group == _selectedGroup;
      final matchesSearch =
          query.isEmpty ||
          channel.name.toLowerCase().contains(query) ||
          channel.group.toLowerCase().contains(query) ||
          _programsFor(
            channel,
          ).any((program) => program.title.toLowerCase().contains(query));
      return matchesGroup && matchesSearch;
    }).toList();
    visible.sort((a, b) => _compareChannels(a, b, _sortMode));
    return visible;
  }

  int _compareChannels(IptvChannel a, IptvChannel b, _ChannelSort sortMode) {
    final favoriteA = _favorites.contains(a.url);
    final favoriteB = _favorites.contains(b.url);
    switch (sortMode) {
      case _ChannelSort.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case _ChannelSort.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      case _ChannelSort.group:
        final group = a.group.toLowerCase().compareTo(b.group.toLowerCase());
        return group == 0
            ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
            : group;
      case _ChannelSort.favoritesFirst:
        if (favoriteA != favoriteB) return favoriteA ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
  }

  void _toggleFavorite(IptvChannel channel) {
    setState(() {
      if (!_favorites.add(channel.url)) {
        _favorites.remove(channel.url);
      }
    });
    widget.onFavorite(channel);
  }

  List<EpgProgram> _programsFor(IptvChannel channel) {
    for (final key in [channel.id, channel.tvgName, channel.name]) {
      final programs = _epgByChannel[normalizeEpgKey(key)];
      if (programs != null && programs.isNotEmpty) return programs;
    }
    return const [];
  }

  EpgProgram? _nowFor(IptvChannel channel) {
    final now = DateTime.now();
    for (final program in _programsFor(channel)) {
      if (program.isLiveAt(now)) return program;
    }
    return null;
  }

  EpgProgram? _nextFor(IptvChannel channel) {
    final now = DateTime.now();
    for (final program in _programsFor(channel)) {
      if (program.start.isAfter(now)) return program;
    }
    return null;
  }

  Future<void> _openGuide() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _EpgGuidePage(
          channels: widget.channels,
          programsFor: _programsFor,
          onPlayLive: widget.onPlayChannel,
          onPlayCatchup: (channel, program) async {
            final catchupUrl = buildCatchupUrl(channel, program);
            if (catchupUrl == null) return;
            final catchupChannel = channel.copyWith(
              name: '${program.title} · ${channel.name}',
              url: catchupUrl,
            );
            await widget.onPlayChannel(catchupChannel, [catchupChannel]);
          },
        ),
      ),
    );
  }

  Widget _buildFilters(int visibleCount, {required bool wide}) {
    final l10n = AppLocalizations.of(context)!;
    final search = TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchText = value),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        labelText: l10n.searchChannelsHint,
        border: const OutlineInputBorder(),
      ),
    );
    final sort = DropdownButtonFormField<_ChannelSort>(
      initialValue: _sortMode,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.sort),
        labelText: l10n.sortLabel,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final mode in _ChannelSort.values)
          DropdownMenuItem(value: mode, child: Text(mode.label(l10n))),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _sortMode = value);
      },
    );
    if (wide) {
      return Row(
        children: [
          Expanded(flex: 2, child: search),
          const SizedBox(width: 10),
          Expanded(child: sort),
          const SizedBox(width: 10),
          _MetricChip(icon: Icons.filter_list, label: '$visibleCount'),
        ],
      );
    }
    return Column(
      children: [
        search,
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: sort),
            const SizedBox(width: 10),
            _MetricChip(icon: Icons.filter_list, label: '$visibleCount'),
          ],
        ),
      ],
    );
  }

  Widget _buildGroupSelector({required bool wide}) {
    final l10n = AppLocalizations.of(context)!;
    if (wide) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: _groups.length,
          itemBuilder: (context, index) {
            final group = _groups[index];
            final selected = _selectedGroup == group;
            return ListTile(
              selected: selected,
              selectedTileColor: Theme.of(
                context,
              ).colorScheme.secondaryContainer,
              leading: Icon(
                group == l10n.groupFavorites
                    ? Icons.star_outline
                    : Icons.folder_outlined,
              ),
              title: Text(group, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => setState(() => _selectedGroup = group),
            );
          },
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedGroup,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.folder_outlined),
        labelText: l10n.groupLabel,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final group in _groups)
          DropdownMenuItem(
            value: group,
            child: Text(group, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (group) {
        if (group != null) setState(() => _selectedGroup = group);
      },
    );
  }

  Widget _buildChannelList(List<IptvChannel> visibleChannels) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    if (visibleChannels.isEmpty) {
      return _EmptyState(
        icon: Icons.tv_off,
        title: l10n.emptyNoChannels,
        subtitle: l10n.emptyNoChannelsSubtitle,
      );
    }
    return ListView.separated(
      itemCount: visibleChannels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final channel = visibleChannels[index];
        final favorite = _favorites.contains(channel.url);
        final nowProgram = _nowFor(channel);
        final nextProgram = _nextFor(channel);
        final schedule = [
          displayGroup(l10n, channel.group),
          if (nowProgram != null) l10n.nowLabel(nowProgram.title),
          if (nowProgram == null && nextProgram != null)
            l10n.nextLabel(nextProgram.title),
        ].join(' · ');
        return Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            leading: _ChannelLogo(channel: channel),
            title: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              schedule,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.playTooltip,
                  onPressed: () =>
                      widget.onPlayChannel(channel, visibleChannels),
                  icon: const Icon(Icons.play_circle),
                ),
                IconButton(
                  tooltip: favorite
                      ? l10n.removeFavorite
                      : l10n.addFavorite,
                  onPressed: () => _toggleFavorite(channel),
                  icon: Icon(favorite ? Icons.star : Icons.star_border),
                ),
              ],
            ),
            onTap: () => widget.onPlayChannel(channel, visibleChannels),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final visibleChannels = _visibleChannels;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        actions: [
          if (_epgLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (widget.epgUrls.isNotEmpty)
            IconButton(
              tooltip: _epgByChannel.isEmpty
                  ? l10n.reloadGuide
                  : l10n.tvGuide,
              onPressed: _epgByChannel.isEmpty ? _loadEpg : _openGuide,
              icon: Icon(
                _epgByChannel.isEmpty
                    ? Icons.sync_problem
                    : Icons.calendar_view_week,
              ),
            ),
          _MetricChip(icon: Icons.tv, label: '${widget.channels.length}'),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1500),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.source.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      if (_epgError != null) ...[
                        const SizedBox(height: 8),
                        MaterialBanner(
                          content: Text(_epgError!),
                          actions: [
                            TextButton(
                              onPressed: _loadEpg,
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildFilters(visibleChannels.length, wide: wide),
                      const SizedBox(height: 12),
                      Expanded(
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: 250,
                                    child: _buildGroupSelector(wide: true),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildChannelList(visibleChannels),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildGroupSelector(wide: false),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: _buildChannelList(visibleChannels),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EpgGuidePage extends StatefulWidget {
  const _EpgGuidePage({
    required this.channels,
    required this.programsFor,
    required this.onPlayLive,
    required this.onPlayCatchup,
  });

  final List<IptvChannel> channels;
  final List<EpgProgram> Function(IptvChannel channel) programsFor;
  final ChannelPlayRequest onPlayLive;
  final Future<void> Function(IptvChannel channel, EpgProgram program)
  onPlayCatchup;

  @override
  State<_EpgGuidePage> createState() => _EpgGuidePageState();
}

class _EpgGuidePageState extends State<_EpgGuidePage> {
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<IptvChannel> get _visibleChannels {
    final query = _query.trim().toLowerCase();
    return widget.channels.where((channel) {
      final programs = widget.programsFor(channel);
      if (programs.isEmpty) return false;
      if (query.isEmpty) return true;
      return channel.name.toLowerCase().contains(query) ||
          programs.any(
            (program) => program.title.toLowerCase().contains(query),
          );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final channels = _visibleChannels;
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tvGuide),
        actions: [
          _MetricChip(
            icon: Icons.calendar_view_week,
            label: '${channels.length}',
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: l10n.guideSearchHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: channels.isEmpty
                        ? _EmptyState(
                            icon: Icons.event_busy,
                            title: l10n.guideEmptyTitle,
                            subtitle: l10n.guideEmptySubtitle,
                          )
                        : ListView.separated(
                            itemCount: channels.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final channel = channels[index];
                              final programs = widget
                                  .programsFor(channel)
                                  .where((program) {
                                    return program.stop.isAfter(
                                          now.subtract(const Duration(days: 7)),
                                        ) &&
                                        program.start.isBefore(
                                          now.add(const Duration(days: 3)),
                                        );
                                  })
                                  .toList();
                              EpgProgram? live;
                              for (final program in programs) {
                                if (program.isLiveAt(now)) {
                                  live = program;
                                  break;
                                }
                              }
                              return Material(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: ExpansionTile(
                                  leading: _ChannelLogo(channel: channel),
                                  title: Text(
                                    channel.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    live == null
                                        ? displayGroup(l10n, channel.group)
                                        : l10n.nowLabel(live.title),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    tooltip: l10n.watchLive,
                                    onPressed: () => widget.onPlayLive(
                                      channel,
                                      widget.channels,
                                    ),
                                    icon: const Icon(Icons.play_circle),
                                  ),
                                  children: [
                                    for (final program in programs)
                                      ListTile(
                                        dense: true,
                                        leading: SizedBox(
                                          width: 92,
                                          child: Text(
                                            '${_formatGuideTime(program.start)}\n${_formatGuideTime(program.stop)}',
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        title: Text(program.title),
                                        subtitle: program.description.isEmpty
                                            ? null
                                            : Text(
                                                program.description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                        trailing: program.isLiveAt(now)
                                            ? IconButton(
                                                tooltip: l10n.watchLive,
                                                onPressed: () =>
                                                    widget.onPlayLive(
                                                      channel,
                                                      widget.channels,
                                                    ),
                                                icon: const Icon(Icons.live_tv),
                                              )
                                            : program.hasEnded &&
                                                  buildCatchupUrl(
                                                        channel,
                                                        program,
                                                      ) !=
                                                      null
                                            ? IconButton(
                                                tooltip: l10n.watchFromStart,
                                                onPressed: () =>
                                                    widget.onPlayCatchup(
                                                      channel,
                                                      program,
                                                    ),
                                                icon: const Icon(Icons.history),
                                              )
                                            : null,
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatGuideTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _PlayerPage extends StatefulWidget {
  const _PlayerPage({
    required this.initialChannel,
    required this.channels,
    required this.onChannelStarted,
  });

  final IptvChannel initialChannel;
  final List<IptvChannel> channels;
  final Future<void> Function(IptvChannel channel) onChannelStarted;

  @override
  State<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<_PlayerPage> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  late final List<IptvChannel> _channels;
  late int _currentIndex;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _retryTimer;
  Timer? _rememberTimer;
  var _opening = true;
  var _fullscreen = false;
  var _openGeneration = 0;
  var _volume = 100.0;
  var _lastAudibleVolume = 100.0;
  var _autoRetries = 0;
  String? _lastRememberedUrl;
  String? _error;

  IptvChannel get _channel => _channels[_currentIndex];

  bool get _canBrowse => _channels.length > 1;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    _channels = _dedupeChannelsByUrl(
      widget.channels.isEmpty
          ? <IptvChannel>[widget.initialChannel]
          : widget.channels,
    );
    _currentIndex = _channels.indexWhere(
      (channel) => channel.url == widget.initialChannel.url,
    );
    if (_currentIndex == -1) {
      _channels.insert(0, widget.initialChannel);
      _currentIndex = 0;
    }
    _player = Player();
    _controller = VideoController(_player);
    _errorSubscription = _player.stream.error.listen(_handlePlayerError);
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!playing || !mounted) return;
      final channel = _channel;
      setState(() {
        _opening = false;
        _error = null;
        _autoRetries = 0;
      });
      if (_lastRememberedUrl != channel.url) {
        _rememberTimer?.cancel();
        final expectedUrl = channel.url;
        _rememberTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted ||
              _error != null ||
              !_player.state.playing ||
              _channel.url != expectedUrl) {
            return;
          }
          _lastRememberedUrl = expectedUrl;
          unawaited(widget.onChannelStarted(_channel));
        });
      }
    });
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (!completed || !mounted || _opening) return;
      if (!mounted) return;
      _rememberTimer?.cancel();
      setState(() {
        _error = AppLocalizations.of(context)!.streamEnded;
      });
    });
    unawaited(_setWakelock(true));
    unawaited(_openChannel());
  }

  Future<void> _openChannel({bool automaticRetry = false}) async {
    final generation = ++_openGeneration;
    final channel = _channel;
    if (!automaticRetry) {
      _retryTimer?.cancel();
      _rememberTimer?.cancel();
      _autoRetries = 0;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    var retryScheduled = false;
    try {
      await _player
          .open(
            Media(channel.url, httpHeaders: _headersForChannel(channel)),
            play: true,
          )
          .timeout(const Duration(seconds: 25));
      await _player.setVolume(_volume);
    } on TimeoutException catch (error) {
      if (!mounted || generation != _openGeneration) return;
      retryScheduled = _scheduleAutomaticRetry();
      if (!retryScheduled) {
        setState(
          () => _error = friendlyPlaybackError(
            AppLocalizations.of(context)!,
            error,
            channelName: channel.name,
          ),
        );
      }
    } catch (error) {
      if (!mounted || generation != _openGeneration) return;
      retryScheduled = _scheduleAutomaticRetry();
      if (!retryScheduled) {
        setState(
          () => _error = friendlyPlaybackError(
            AppLocalizations.of(context)!,
            error,
            channelName: channel.name,
          ),
        );
      }
    } finally {
      if (!mounted || generation != _openGeneration) return;
      if (!retryScheduled) setState(() => _opening = false);
    }
  }

  void _handlePlayerError(String error) {
    if (!mounted) return;
    _rememberTimer?.cancel();
    if (_scheduleAutomaticRetry()) return;
    setState(() {
      _opening = false;
      _error = friendlyPlaybackError(
        AppLocalizations.of(context)!,
        error,
        channelName: _channel.name,
      );
    });
  }

  bool _scheduleAutomaticRetry() {
    if (_autoRetries >= 1 || !mounted) return false;
    _autoRetries += 1;
    _retryTimer?.cancel();
    _rememberTimer?.cancel();
    setState(() {
      _opening = true;
      _error = null;
    });
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) unawaited(_openChannel(automaticRetry: true));
    });
    return true;
  }

  Future<void> _selectChannel(int index) async {
    if (index < 0 || index >= _channels.length) return;
    setState(() => _currentIndex = index);
    await _openChannel();
  }

  Future<void> _nextChannel() async {
    if (!_canBrowse) return;
    await _selectChannel((_currentIndex + 1) % _channels.length);
  }

  Future<void> _previousChannel() async {
    if (!_canBrowse) return;
    await _selectChannel(
      (_currentIndex - 1 + _channels.length) % _channels.length,
    );
  }

  Future<void> _setVolume(double value) async {
    final volume = value.clamp(0, 100).toDouble();
    setState(() {
      _volume = volume;
      if (volume > 0) _lastAudibleVolume = volume;
    });
    await _player.setVolume(volume);
  }

  Future<void> _toggleMute() async {
    await _setVolume(_volume == 0 ? _lastAudibleVolume : 0);
  }

  Future<void> _setFullscreen(bool value) async {
    if (_fullscreen == value) return;
    setState(() => _fullscreen = value);
    try {
      if (value) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          await SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      } else {
        await _restoreSystemUi();
      }
    } on PlatformException {
      // Fullscreen is a nice-to-have on desktop and older platform shells.
    }
  }

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await SystemChrome.setPreferredOrientations(
          const <DeviceOrientation>[],
        );
      }
    } on PlatformException {
      // Restoring the app chrome should not block leaving the player.
    }
  }

  Future<void> _setWakelock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Some desktop shells do not expose wake-lock support.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_player.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_restoreSystemUi());
    unawaited(_setWakelock(false));
    unawaited(_errorSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    _retryTimer?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _showChannelQueue() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            itemCount: _channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final channel = _channels[index];
              final selected = index == _currentIndex;
              return Material(
                color: selected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  leading: _ChannelLogo(channel: channel),
                  title: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    displayGroup(
                      AppLocalizations.of(context)!,
                      channel.group,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: selected
                      ? const Icon(Icons.play_circle)
                      : const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_selectChannel(index));
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showTrackOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: StreamBuilder<Tracks>(
            initialData: _player.state.tracks,
            stream: _player.stream.tracks,
            builder: (context, tracksSnapshot) {
              final tracks = tracksSnapshot.data ?? const Tracks();
              return StreamBuilder<Track>(
                initialData: _player.state.track,
                stream: _player.stream.track,
                builder: (context, selectedSnapshot) {
                  final selected = selectedSnapshot.data ?? const Track();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                    children: [
                      _trackSectionHeader(
                        AppLocalizations.of(context)!.audioTracks,
                      ),
                      ...tracks.audio.map(
                        (track) => _trackOptionTile(
                          label: _trackLabel(track),
                          selected: track == selected.audio,
                          onTap: () => unawaited(_player.setAudioTrack(track)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _trackSectionHeader(
                        AppLocalizations.of(context)!.subtitlesTracks,
                      ),
                      ...tracks.subtitle.map(
                        (track) => _trackOptionTile(
                          label: _trackLabel(track),
                          selected: track == selected.subtitle,
                          onTap: () =>
                              unawaited(_player.setSubtitleTrack(track)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _trackSectionHeader(
                        AppLocalizations.of(context)!.videoTracks,
                      ),
                      ...tracks.video.map(
                        (track) => _trackOptionTile(
                          label: _trackLabel(track),
                          selected: track == selected.video,
                          onTap: () => unawaited(_player.setVideoTrack(track)),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _trackSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _trackOptionTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(label),
      selected: selected,
      onTap: onTap,
    );
  }

  String _trackLabel(dynamic track) {
    final l10n = AppLocalizations.of(context)!;
    final id = track.id as String;
    if (id == 'auto') return l10n.trackAuto;
    if (id == 'no') return l10n.trackDisabled;
    final parts = <String>[
      if ((track.title as String?)?.trim().isNotEmpty == true)
        (track.title as String).trim(),
      if ((track.language as String?)?.trim().isNotEmpty == true)
        (track.language as String).trim(),
      if ((track.codec as String?)?.trim().isNotEmpty == true)
        (track.codec as String).trim(),
    ];
    return parts.isEmpty ? l10n.trackLabel(id) : parts.join(' - ');
  }

  Widget _buildVideoPane() {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(controller: _controller, fit: BoxFit.contain),
          if (_fullscreen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: AppLocalizations.of(context)!.exitFullscreen,
                        onPressed: () => _setFullscreen(false),
                        icon: const Icon(Icons.fullscreen_exit),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_opening) const Center(child: CircularProgressIndicator()),
          StreamBuilder<bool>(
            stream: _player.stream.buffering,
            builder: (context, snapshot) {
              final buffering = snapshot.data ?? false;
              if (!buffering || _opening || _error != null) {
                return const SizedBox.shrink();
              }
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
          ),
          if (_error != null) _buildErrorOverlay(),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _openChannel,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.retry),
                      ),
                      if (_canBrowse)
                        OutlinedButton.icon(
                          onPressed: _nextChannel,
                          icon: const Icon(Icons.skip_next),
                          label: Text(l10n.next),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _ChannelLogo(channel: _channel),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              displayGroup(l10n, _channel.group),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (_channel.hasCatchup)
                              Icon(
                                Icons.history_toggle_off,
                                size: 16,
                                color: colorScheme.secondary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.tracks,
                    onPressed: _showTrackOptions,
                    icon: const Icon(Icons.tune),
                  ),
                  IconButton(
                    tooltip: _fullscreen
                        ? l10n.exitFullscreen
                        : l10n.fullscreen,
                    onPressed: () => _setFullscreen(!_fullscreen),
                    icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: l10n.previous,
                    onPressed: _canBrowse ? _previousChannel : null,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    initialData: false,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return IconButton.filled(
                        tooltip: playing ? l10n.pause : l10n.play,
                        onPressed: _error == null
                            ? _player.playOrPause
                            : _openChannel,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: l10n.next,
                    onPressed: _canBrowse ? _nextChannel : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                  IconButton(
                    tooltip: l10n.restart,
                    onPressed: _openChannel,
                    icon: const Icon(Icons.replay),
                  ),
                  IconButton(
                    tooltip: l10n.channels,
                    onPressed: _showChannelQueue,
                    icon: const Icon(Icons.playlist_play),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: _volume == 0 ? l10n.unmute : l10n.mute,
                    onPressed: _toggleMute,
                    icon: Icon(
                      _volume == 0 ? Icons.volume_off : Icons.volume_up,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: _volume,
                      onChanged: (value) => unawaited(_setVolume(value)),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${_volume.round()}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Expanded(child: _buildVideoPane()),
        _buildControls(),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
        const SingleActivator(LogicalKeyboardKey.keyF): () =>
            _setFullscreen(!_fullscreen),
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _nextChannel,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _previousChannel,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _setVolume(_volume + 5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _setVolume(_volume - 5),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_fullscreen) unawaited(_setFullscreen(false));
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !_fullscreen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _fullscreen) {
              unawaited(_setFullscreen(false));
            }
          },
          child: Scaffold(
            appBar: _fullscreen ? null : AppBar(title: Text(_channel.name)),
            body: _fullscreen ? content : SafeArea(child: content),
          ),
        ),
      ),
    );
  }
}

class _PlaylistSettingsPage extends StatefulWidget {
  const _PlaylistSettingsPage({
    required this.sources,
    required this.onSourcesChanged,
  });

  final List<PlaylistSource> sources;
  final Future<void> Function(List<PlaylistSource> sources) onSourcesChanged;

  @override
  State<_PlaylistSettingsPage> createState() => _PlaylistSettingsPageState();
}

class _PlaylistSettingsPageState extends State<_PlaylistSettingsPage> {
  late var _sources = List<PlaylistSource>.of(widget.sources);

  Future<void> _commitSources(List<PlaylistSource> sources) async {
    final normalized = _normalizeSources(sources);
    setState(() => _sources = normalized);
    await widget.onSourcesChanged(normalized);
  }

  List<PlaylistSource> _normalizeSources(List<PlaylistSource> sources) {
    final l10n = AppLocalizations.of(context)!;
    final unique = <String, PlaylistSource>{};
    for (final source in sources) {
      final url = source.url.trim();
      if (url.isEmpty) continue;
      unique[url] = source.copyWith(
        name: source.name.trim().isEmpty ? l10n.m3uListName : source.name.trim(),
        description: source.description.trim().isEmpty
            ? l10n.customListDescription
            : source.description.trim(),
        url: url,
      );
    }
    return unique.isEmpty
        ? defaultSources(l10n)
        : unique.values.toList();
  }

  Future<void> _addSource() async {
    final source = await _showPlaylistEditor(context);
    if (source == null) return;
    await _commitSources([..._sources, source]);
  }

  Future<void> _editSource(int index) async {
    final source = await _showPlaylistEditor(context, source: _sources[index]);
    if (source == null) return;
    final updated = List<PlaylistSource>.of(_sources);
    updated[index] = source;
    await _commitSources(updated);
  }

  Future<void> _deleteSource(int index) async {
    if (_sources.length <= 1) return;
    final source = _sources[index];
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteTitle),
        content: Text(l10n.deleteConfirm(source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = List<PlaylistSource>.of(_sources)..removeAt(index);
    await _commitSources(updated);
  }

  Future<void> _restoreDefaults() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreTitle),
        content: Text(l10n.restoreMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _commitSources(defaultSources(l10n));
  }

  Future<PlaylistSource?> _showPlaylistEditor(
    BuildContext context, {
    PlaylistSource? source,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: source?.name ?? '');
    final descriptionController = TextEditingController(
      text: source?.description ?? '',
    );
    final urlController = TextEditingController(text: source?.url ?? '');
    final epgUrlController = TextEditingController(text: source?.epgUrl ?? '');
    final userAgentController = TextEditingController(
      text: source?.userAgent ?? '',
    );
    final refererController = TextEditingController(
      text: source?.referer ?? '',
    );

    final result = await showModalBottomSheet<PlaylistSource>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    source == null
                        ? AppLocalizations.of(context)!.newListTitle
                        : AppLocalizations.of(context)!.editListTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.drive_file_rename_outline),
                      labelText: AppLocalizations.of(context)!.nameLabel,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                        ? AppLocalizations.of(context)!.nameRequired
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.notes),
                      labelText: AppLocalizations.of(context)!.descriptionLabel,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: urlController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.link),
                      labelText: AppLocalizations.of(context)!.m3uUrlLabel,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      final rawUrl = value?.trim() ?? '';
                      final uri = Uri.tryParse(rawUrl);
                      final valid =
                          uri != null &&
                          (uri.scheme == 'http' || uri.scheme == 'https') &&
                          uri.host.isNotEmpty;
                      return valid
                          ? null
                          : AppLocalizations.of(context)!.urlInvalid;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: epgUrlController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.calendar_view_week),
                      labelText: AppLocalizations.of(context)!.epgUrlLabel,
                      helperText: AppLocalizations.of(context)!.epgUrlHelper,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      final rawUrl = value?.trim() ?? '';
                      if (rawUrl.isEmpty) return null;
                      final uri = Uri.tryParse(rawUrl);
                      final valid =
                          uri != null &&
                          (uri.scheme == 'http' || uri.scheme == 'https') &&
                          uri.host.isNotEmpty;
                      return valid
                          ? null
                          : AppLocalizations.of(context)!.epgUrlInvalid;
                    },
                  ),
                  const SizedBox(height: 4),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      AppLocalizations.of(context)!.advancedHeaders,
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context)!.advancedHeadersSubtitle,
                    ),
                    children: [
                      TextFormField(
                        controller: userAgentController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.badge_outlined),
                          labelText: AppLocalizations.of(context)!.userAgentLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: refererController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.reply),
                          labelText: AppLocalizations.of(context)!.refererLabel,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(AppLocalizations.of(context)!.cancel),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            if (formKey.currentState?.validate() != true) {
                              return;
                            }
                            Navigator.of(context).pop(
                              PlaylistSource(
                                name: nameController.text.trim(),
                                description:
                                    descriptionController.text.trim().isEmpty
                                    ? AppLocalizations.of(
                                        context,
                                      )!.customListDescription
                                    : descriptionController.text.trim(),
                                url: urlController.text.trim(),
                                epgUrl: epgUrlController.text.trim(),
                                userAgent: userAgentController.text.trim(),
                                referer: refererController.text.trim(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.check),
                          label: Text(AppLocalizations.of(context)!.save),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
    urlController.dispose();
    epgUrlController.dispose();
    userAgentController.dispose();
    refererController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        actions: [
          IconButton(
            tooltip: l10n.restoreListsTooltip,
            onPressed: _restoreDefaults,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.addListTooltip,
        onPressed: _addSource,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 92),
          itemCount: _sources.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final source = _sources[index];
            return Material(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                leading: const CircleAvatar(child: Icon(Icons.live_tv)),
                title: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${source.description}\n${sourceDisplayUrl(l10n, source.url)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.editTooltip,
                      onPressed: () => _editSource(index),
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: l10n.deleteTooltip,
                      onPressed: _sources.length > 1
                          ? () => _deleteSource(index)
                          : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel});

  final IptvChannel? channel;
  static const double size = 42;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: size / 2,
      child: Icon(Icons.tv, size: size * 0.52),
    );
    final logo = channel?.logo.trim() ?? '';
    if (logo.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size >= 70 ? 18 : 6),
      child: Image.network(
        logo,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

List<IptvChannel> parseM3u(String content) =>
    parseM3uPlaylist(content).channels;

ParsedPlaylist parseM3uPlaylist(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final channels = <IptvChannel>[];
  final epgUrls = <String>{};
  Map<String, String>? pending;

  for (final line in lines) {
    final upperLine = line.toUpperCase();
    if (upperLine.startsWith('#EXTM3U')) {
      final attributes = _parseAttributes(line);
      for (final key in ['x-tvg-url', 'url-tvg', 'tvg-url']) {
        final value = attributes[key];
        if (value == null) continue;
        epgUrls.addAll(
          value
              .split(',')
              .map((url) => url.trim())
              .where((url) => Uri.tryParse(url)?.hasScheme == true),
        );
      }
      continue;
    }
    if (upperLine.startsWith('#EXTINF')) {
      pending = _parseExtInf(line);
      continue;
    }
    if (line.startsWith('#')) continue;
    if (pending == null) continue;

    final url = line;
    if (!_isPlayableStreamUrl(url)) {
      pending = null;
      continue;
    }

    channels.add(
      IptvChannel(
        name: _firstNonEmpty([pending['name'], pending['tvg-name']]).isNotEmpty
            ? _firstNonEmpty([pending['name'], pending['tvg-name']])
            : url,
        url: url,
        group: pending['group-title']?.trim().isNotEmpty == true
            ? pending['group-title']!.trim()
            : '',
        logo: pending['tvg-logo'] ?? '',
        id: pending['tvg-id'] ?? '',
        tvgName: pending['tvg-name'] ?? '',
        catchup: pending['catchup'] ?? '',
        catchupSource: pending['catchup-source'] ?? '',
        catchupDays: _parseOptionalInt(pending['catchup-days']),
        tvgShift: _parseOptionalInt(pending['tvg-shift']),
      ),
    );
    pending = null;
  }

  return ParsedPlaylist(channels: channels, epgUrls: epgUrls.toList());
}

bool _isPlayableStreamUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (!_supportedStreamSchemes.contains(scheme)) return false;
  if (scheme == 'http' || scheme == 'https') return uri.host.isNotEmpty;
  return true;
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

Map<String, String> _parseExtInf(String line) {
  final comma = line.indexOf(',');
  final result = _parseAttributes(
    comma == -1 ? line : line.substring(0, comma),
  );
  result['name'] = comma == -1 ? '' : line.substring(comma + 1).trim();
  return result;
}

Map<String, String> _parseAttributes(String text) {
  final result = <String, String>{};
  final attributePattern = RegExp(
    r'''([a-zA-Z0-9_-]+)=("[^"]*"|'[^']*'|[^\s,]+)''',
  );
  for (final match in attributePattern.allMatches(text)) {
    final rawValue = match.group(2)!;
    final quoted =
        (rawValue.startsWith('"') && rawValue.endsWith('"')) ||
        (rawValue.startsWith("'") && rawValue.endsWith("'"));
    result[match.group(1)!.toLowerCase()] = quoted
        ? rawValue.substring(1, rawValue.length - 1)
        : rawValue;
  }
  return result;
}

Future<Map<String, List<EpgProgram>>> downloadXmlTv(
  String rawUrl, {
  Map<String, String> headers = const {},
}) async {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || !uri.hasScheme) {
    throw const FormatException('URL XMLTV inválida');
  }
  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 40));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('HTTP ${response.statusCode}');
  }
  return parseXmlTv(utf8.decode(response.bodyBytes, allowMalformed: true));
}

Map<String, List<EpgProgram>> parseXmlTv(String content) {
  final document = XmlDocument.parse(content);
  final result = <String, List<EpgProgram>>{};
  final aliases = <String, String>{};

  for (final channel in document.findAllElements('channel')) {
    final id = normalizeEpgKey(channel.getAttribute('id') ?? '');
    if (id.isEmpty) continue;
    aliases[id] = id;
    for (final displayName in channel.findElements('display-name')) {
      final alias = normalizeEpgKey(displayName.innerText);
      if (alias.isNotEmpty) aliases[alias] = id;
    }
  }

  for (final node in document.findAllElements('programme')) {
    final rawChannel = normalizeEpgKey(node.getAttribute('channel') ?? '');
    final channelId = aliases[rawChannel] ?? rawChannel;
    final start = _parseXmlTvDate(node.getAttribute('start'));
    final stop = _parseXmlTvDate(node.getAttribute('stop'));
    if (channelId.isEmpty ||
        start == null ||
        stop == null ||
        !stop.isAfter(start)) {
      continue;
    }
    final title = _xmlText(node, 'title');
    if (title.isEmpty) continue;
    final iconElements = node.findElements('icon');
    result
        .putIfAbsent(channelId, () => <EpgProgram>[])
        .add(
          EpgProgram(
            channelId: channelId,
            start: start,
            stop: stop,
            title: title,
            subtitle: _xmlText(node, 'sub-title'),
            description: _xmlText(node, 'desc'),
            category: _xmlText(node, 'category'),
            icon: iconElements.isEmpty
                ? ''
                : iconElements.first.getAttribute('src') ?? '',
          ),
        );
  }

  for (final programs in result.values) {
    programs.sort((a, b) => a.start.compareTo(b.start));
  }
  for (final entry in aliases.entries) {
    final programs = result[entry.value];
    if (programs != null) result[entry.key] = programs;
  }
  return result;
}

String _xmlText(XmlElement parent, String name) {
  final elements = parent.findElements(name);
  if (elements.isEmpty) return '';
  return elements.first.innerText.trim();
}

DateTime? _parseXmlTvDate(String? rawValue) {
  final value = rawValue?.trim() ?? '';
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4}|Z)?',
  ).firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '') ?? 0;
  var utc = DateTime.utc(year, month, day, hour, minute, second);
  final zone = match.group(7);
  if (zone != null && zone != 'Z') {
    final sign = zone.startsWith('-') ? -1 : 1;
    final zoneHours = int.parse(zone.substring(1, 3));
    final zoneMinutes = int.parse(zone.substring(3, 5));
    utc = utc.subtract(
      Duration(minutes: sign * (zoneHours * 60 + zoneMinutes)),
    );
  }
  return utc;
}

String normalizeEpgKey(String value) {
  var normalized = value.trim().toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

String? buildCatchupUrl(IptvChannel channel, EpgProgram program) {
  var template = channel.catchupSource.trim();
  if (template.isEmpty) return null;

  final start = program.start.toUtc();
  final stop = program.stop.toUtc();
  final startSeconds = start.millisecondsSinceEpoch ~/ 1000;
  final stopSeconds = stop.millisecondsSinceEpoch ~/ 1000;
  final durationSeconds = stopSeconds - startSeconds;
  final values = <String, String>{
    '{utc}': '$startSeconds',
    '{lutc}': '$stopSeconds',
    '{timestamp}': '$startSeconds',
    '{duration}': '$durationSeconds',
    '{duration:60}': '${(durationSeconds / 60).ceil()}',
    '{start}': _formatCatchupDate(start),
    '{end}': _formatCatchupDate(stop),
  };
  for (final entry in values.entries) {
    template = template.replaceAll(entry.key, entry.value);
  }

  final absolute = Uri.tryParse(template);
  if (absolute != null && absolute.hasScheme) return absolute.toString();
  final base = Uri.tryParse(channel.url);
  if (base == null) return null;
  if (template.startsWith('?') || template.startsWith('&')) {
    final separator = channel.url.contains('?') ? '&' : '?';
    return '${channel.url}$separator${template.replaceFirst(RegExp(r'^[?&]'), '')}';
  }
  return base.resolve(template).toString();
}

String _formatCatchupDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}:${two(value.hour)}-${two(value.minute)}';
}

String friendlyNetworkError(
  AppLocalizations l10n,
  Object error, {
  required String resource,
}) {
  if (error is TimeoutException) {
    return l10n.errorTimeout(resource);
  }
  final message = error.toString();
  final status = RegExp(r'HTTP\s+(\d{3})').firstMatch(message)?.group(1);
  if (status != null) {
    return l10n.errorHttp(resource, status);
  }
  if (error is FormatException || error is XmlParserException) {
    return l10n.errorFormat(resource);
  }
  return l10n.errorNetworkGeneric(resource);
}

String friendlyPlaybackError(
  AppLocalizations l10n,
  Object error, {
  String channelName = '',
}) {
  final raw = error.toString();
  final safeName = channelName.trim().isEmpty
      ? l10n.fallbackChannel
      : channelName.trim();
  if (raw.contains('401') || raw.contains('403')) {
    return l10n.errorAuth(safeName);
  }
  if (raw.contains('404')) {
    return l10n.errorGone(safeName);
  }
  if (raw.toLowerCase().contains('timeout') ||
      raw.toLowerCase().contains('timed out')) {
    return l10n.errorPlaybackTimeout(safeName);
  }
  return l10n.errorPlaybackGeneric(safeName);
}

String sourceDisplayUrl(AppLocalizations l10n, String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || uri.host.isEmpty) return l10n.privateSource;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.isEmpty ? '' : uri.path;
  final hiddenQuery = uri.hasQuery ? '?…' : '';
  return '${uri.scheme}://${uri.host}$port$path$hiddenQuery';
}
