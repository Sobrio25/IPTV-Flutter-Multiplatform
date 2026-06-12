import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const IptvApp());
}

const _storageChannel = MethodChannel('iptv_player/storage');

class PlaylistSource {
  const PlaylistSource({
    required this.name,
    required this.description,
    required this.url,
  });

  final String name;
  final String description;
  final String url;

  PlaylistSource copyWith({String? name, String? description, String? url}) {
    return PlaylistSource(
      name: name ?? this.name,
      description: description ?? this.description,
      url: url ?? this.url,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'url': url,
  };

  static PlaylistSource fromJson(Map<String, Object?> json) {
    final name = (json['name'] as String? ?? '').trim();
    final description = (json['description'] as String? ?? '').trim();
    final url = (json['url'] as String? ?? '').trim();
    return PlaylistSource(
      name: name.isEmpty ? 'Lista M3U' : name,
      description: description.isEmpty ? 'Lista personalizada' : description,
      url: url,
    );
  }
}

const defaultSources = <PlaylistSource>[
  PlaylistSource(
    name: 'Todo IPTV.org',
    description: 'Lista global publica',
    url: 'https://iptv-org.github.io/iptv/index.m3u',
  ),
  PlaylistSource(
    name: 'Mexico',
    description: 'Canales por pais',
    url: 'https://iptv-org.github.io/iptv/countries/mx.m3u',
  ),
  PlaylistSource(
    name: 'Estados Unidos',
    description: 'Canales por pais',
    url: 'https://iptv-org.github.io/iptv/countries/us.m3u',
  ),
  PlaylistSource(
    name: 'Espanol',
    description: 'Canales por idioma',
    url: 'https://iptv-org.github.io/iptv/languages/spa.m3u',
  ),
  PlaylistSource(
    name: 'Ingles',
    description: 'Canales por idioma',
    url: 'https://iptv-org.github.io/iptv/languages/eng.m3u',
  ),
  PlaylistSource(
    name: 'Noticias',
    description: 'Categoria',
    url: 'https://iptv-org.github.io/iptv/categories/news.m3u',
  ),
  PlaylistSource(
    name: 'Deportes',
    description: 'Categoria',
    url: 'https://iptv-org.github.io/iptv/categories/sports.m3u',
  ),
  PlaylistSource(
    name: 'Peliculas',
    description: 'Categoria',
    url: 'https://iptv-org.github.io/iptv/categories/movies.m3u',
  ),
  PlaylistSource(
    name: 'Ninos',
    description: 'Categoria',
    url: 'https://iptv-org.github.io/iptv/categories/kids.m3u',
  ),
];

class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.group = 'Sin grupo',
    this.logo = '',
    this.id = '',
  });

  final String name;
  final String url;
  final String group;
  final String logo;
  final String id;

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'group': group,
    'logo': logo,
    'id': id,
  };

  static IptvChannel fromJson(Map<String, Object?> json) => IptvChannel(
    name: json['name'] as String? ?? 'Canal sin nombre',
    url: json['url'] as String? ?? '',
    group: json['group'] as String? ?? 'Sin grupo',
    logo: json['logo'] as String? ?? '',
    id: json['id'] as String? ?? '',
  );
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff0d8b7f);
    return MaterialApp(
      title: 'IPTV Player',
      debugShowCheckedModeBanner: false,
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
  var _sources = List<PlaylistSource>.of(defaultSources);
  var _favorites = <String>{};
  var _status = 'Selecciona una lista M3U para ver sus canales.';
  String? _loadingSourceUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreState());
  }

  Future<void> _restoreState() async {
    final values = await Future.wait([
      _readString('playlistSources'),
      _readString('playlistUrl'),
      _readString('favorites'),
    ]);

    final savedSources = _decodeSources(values[0]);
    final savedUrl = values[1]?.trim();
    final savedFavorites = values[2];

    if (!mounted) return;
    setState(() {
      _sources = savedSources ?? List<PlaylistSource>.of(defaultSources);
      if (savedUrl != null &&
          savedUrl.isNotEmpty &&
          !_sources.any((source) => source.url == savedUrl)) {
        _sources = [
          PlaylistSource(
            name: 'Lista guardada',
            description: 'Fuente guardada anteriormente',
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
        name: source.name.trim().isEmpty ? 'Lista M3U' : source.name.trim(),
        description: source.description.trim().isEmpty
            ? 'Lista personalizada'
            : source.description.trim(),
        url: url,
      );
    }
    return unique.isEmpty
        ? List<PlaylistSource>.of(defaultSources)
        : unique.values.toList();
  }

  Future<String?> _readString(String key) async {
    if (Platform.isAndroid) {
      try {
        return _storageChannel.invokeMethod<String>('getString', {'key': key});
      } on PlatformException {
        return null;
      }
    }
    if (_supportsDesktopStorage) {
      final values = await _readDesktopStore();
      return values[key];
    }
    return null;
  }

  Future<void> _writeString(String key, String value) async {
    if (Platform.isAndroid) {
      try {
        await _storageChannel.invokeMethod<void>('setString', {
          'key': key,
          'value': value,
        });
      } on PlatformException {
        // Persistence is helpful, but playback should not depend on it.
      }
      return;
    }
    if (_supportsDesktopStorage) {
      final values = await _readDesktopStore();
      values[key] = value;
      await _writeDesktopStore(values);
    }
  }

  Future<void> _removeString(String key) async {
    if (Platform.isAndroid) {
      try {
        await _storageChannel.invokeMethod<void>('removeString', {'key': key});
      } on PlatformException {
        // Old saved playlist caches should never block the app from opening.
      }
      return;
    }
    if (_supportsDesktopStorage) {
      final values = await _readDesktopStore();
      values.remove(key);
      await _writeDesktopStore(values);
    }
  }

  bool get _supportsDesktopStorage => Platform.isWindows || Platform.isLinux;

  File get _desktopStorageFile {
    final baseDir = Platform.isLinux ? _linuxConfigDir : _windowsConfigDir;
    return File(
      [baseDir, 'IPTV Player', 'settings.json'].join(Platform.pathSeparator),
    );
  }

  String get _windowsConfigDir {
    final appData = Platform.environment['APPDATA'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (appData != null && appData.trim().isNotEmpty) return appData;
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      return localAppData;
    }
    return Directory.current.path;
  }

  String get _linuxConfigDir {
    final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
    if (xdgConfigHome != null && xdgConfigHome.trim().isNotEmpty) {
      return xdgConfigHome;
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return [home, '.config'].join(Platform.pathSeparator);
    }
    return Directory.current.path;
  }

  Future<Map<String, String>> _readDesktopStore() async {
    final file = _desktopStorageFile;
    try {
      if (!await file.exists()) return <String, String>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<dynamic, dynamic>) return <String, String>{};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeDesktopStore(Map<String, String> values) async {
    final file = _desktopStorageFile;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(values),
      );
    } on FileSystemException {
      // Desktop persistence should not prevent the app from playing channels.
    }
  }

  Future<void> _saveSources(List<PlaylistSource> sources) async {
    await _writeString(
      'playlistSources',
      jsonEncode(sources.map((source) => source.toJson()).toList()),
    );
  }

  Future<List<IptvChannel>> _downloadChannels(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return <IptvChannel>[];

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'IPTV Player Flutter');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final unique = <String, IptvChannel>{};
      for (final channel in parseM3u(body)) {
        unique[channel.url] = channel;
      }
      return unique.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openSource(PlaylistSource source) async {
    if (_loadingSourceUrl != null) return;
    setState(() {
      _loadingSourceUrl = source.url;
      _status = 'Descargando ${source.name}...';
    });

    try {
      final channels = await _downloadChannels(source.url);
      await _writeString('playlistUrl', source.url);
      await _removeString('channels');

      if (!mounted) return;
      setState(() {
        _loadingSourceUrl = null;
        _status = channels.isEmpty
            ? 'La lista no tenia canales reproducibles.'
            : '${channels.length} canales cargados desde ${source.name}.';
      });

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _ChannelListPage(
            source: source,
            channels: channels,
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
        _status = 'No se pudo cargar la lista: $error';
      });
      _showSnackBar('No se pudo cargar la lista.');
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

  Future<void> _playChannel(IptvChannel channel) async {
    if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => _PlayerPage(channel: channel)),
      );
      return;
    }

    _showSnackBar(
      'El reproductor integrado esta disponible en Android, Windows y Linux.',
    );
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _AppLogo(size: 46),
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
                          'Listas M3U',
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
                    tooltip: 'Configuracion',
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (_loadingSourceUrl != null) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: ListView.separated(
                  itemCount: _sources.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final source = _sources[index];
                    final loading = _loadingSourceUrl == source.url;
                    return Material(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        leading: _SourceIcon(loading: loading),
                        title: Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${source.description}\n${source.url}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _loadingSourceUrl == null
                            ? () => _openSource(source)
                            : null,
                      ),
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

class _ChannelListPage extends StatefulWidget {
  const _ChannelListPage({
    required this.source,
    required this.channels,
    required this.favorites,
    required this.onFavorite,
    required this.onPlayChannel,
  });

  final PlaylistSource source;
  final List<IptvChannel> channels;
  final Set<String> favorites;
  final ValueChanged<IptvChannel> onFavorite;
  final ValueChanged<IptvChannel> onPlayChannel;

  @override
  State<_ChannelListPage> createState() => _ChannelListPageState();
}

class _ChannelListPageState extends State<_ChannelListPage> {
  final _searchController = TextEditingController();
  late var _favorites = Set<String>.of(widget.favorites);
  var _selectedGroup = 'Todos';
  var _searchText = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _groups {
    final groups =
        widget.channels
            .map((channel) => channel.group.trim())
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['Todos', 'Favoritos', ...groups];
  }

  List<IptvChannel> get _visibleChannels {
    final query = _searchText.trim().toLowerCase();
    return widget.channels.where((channel) {
      final matchesGroup =
          _selectedGroup == 'Todos' ||
          (_selectedGroup == 'Favoritos' && _favorites.contains(channel.url)) ||
          channel.group == _selectedGroup;
      final matchesSearch =
          query.isEmpty ||
          channel.name.toLowerCase().contains(query) ||
          channel.group.toLowerCase().contains(query);
      return matchesGroup && matchesSearch;
    }).toList();
  }

  void _toggleFavorite(IptvChannel channel) {
    setState(() {
      if (!_favorites.add(channel.url)) {
        _favorites.remove(channel.url);
      }
    });
    widget.onFavorite(channel);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleChannels = _visibleChannels;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        actions: [
          _MetricChip(icon: Icons.tv, label: '${widget.channels.length}'),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
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
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchText = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Buscar canal o grupo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _groups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    return ChoiceChip(
                      label: Text(group),
                      selected: _selectedGroup == group,
                      onSelected: (_) => setState(() => _selectedGroup = group),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visibleChannels.isEmpty
                    ? const _EmptyState(
                        icon: Icons.tv_off,
                        title: 'Sin canales',
                        subtitle: 'No hay canales para mostrar.',
                      )
                    : ListView.separated(
                        itemCount: visibleChannels.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final channel = visibleChannels[index];
                          final favorite = _favorites.contains(channel.url);
                          return Material(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                channel.group,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Reproducir',
                                    onPressed: () =>
                                        widget.onPlayChannel(channel),
                                    icon: const Icon(Icons.play_circle),
                                  ),
                                  IconButton(
                                    tooltip: favorite
                                        ? 'Quitar favorito'
                                        : 'Agregar favorito',
                                    onPressed: () => _toggleFavorite(channel),
                                    icon: Icon(
                                      favorite ? Icons.star : Icons.star_border,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => widget.onPlayChannel(channel),
                            ),
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

class _PlayerPage extends StatefulWidget {
  const _PlayerPage({required this.channel});

  final IptvChannel channel;

  @override
  State<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<_PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  var _opening = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _errorSubscription = _player.stream.error.listen((error) {
      if (!mounted) return;
      setState(() => _error = error);
    });
    unawaited(_openChannel());
  }

  Future<void> _openChannel() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await _player.open(Media(widget.channel.url));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo reproducir este canal: $error');
    } finally {
      if (!mounted) return;
      setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    unawaited(_errorSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Video(controller: _controller),
                      ),
                    ),
                    if (_opening)
                      const Center(child: CircularProgressIndicator()),
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
                    if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
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
                              FilledButton.icon(
                                onPressed: _openChannel,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Material(
              color: colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  children: [
                    _ChannelLogo(channel: widget.channel),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            widget.channel.group,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reiniciar',
                      onPressed: _openChannel,
                      icon: const Icon(Icons.replay),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    final unique = <String, PlaylistSource>{};
    for (final source in sources) {
      final url = source.url.trim();
      if (url.isEmpty) continue;
      unique[url] = source.copyWith(
        name: source.name.trim().isEmpty ? 'Lista M3U' : source.name.trim(),
        description: source.description.trim().isEmpty
            ? 'Lista personalizada'
            : source.description.trim(),
        url: url,
      );
    }
    return unique.isEmpty
        ? List<PlaylistSource>.of(defaultSources)
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
    final updated = List<PlaylistSource>.of(_sources)..removeAt(index);
    await _commitSources(updated);
  }

  Future<void> _restoreDefaults() async {
    await _commitSources(List<PlaylistSource>.of(defaultSources));
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
                    source == null ? 'Nueva lista' : 'Editar lista',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.drive_file_rename_outline),
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Escribe un nombre'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.notes),
                      labelText: 'Descripcion',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.link),
                      labelText: 'URL M3U',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      final rawUrl = value?.trim() ?? '';
                      final uri = Uri.tryParse(rawUrl);
                      final valid =
                          uri != null &&
                          (uri.scheme == 'http' || uri.scheme == 'https') &&
                          uri.host.isNotEmpty;
                      return valid ? null : 'Escribe una URL http o https';
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
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
                                    ? 'Lista personalizada'
                                    : descriptionController.text.trim(),
                                url: urlController.text.trim(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Guardar'),
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
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuracion'),
        actions: [
          IconButton(
            tooltip: 'Restaurar listas',
            onPressed: _restoreDefaults,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar lista',
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
                  '${source.description}\n${source.url}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () => _editSource(index),
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
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

List<IptvChannel> parseM3u(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final channels = <IptvChannel>[];
  Map<String, String>? pending;

  for (final line in lines) {
    if (line.startsWith('#EXTINF')) {
      pending = _parseExtInf(line);
      continue;
    }
    if (line.startsWith('#')) continue;
    if (pending == null) continue;

    final url = line;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      pending = null;
      continue;
    }

    channels.add(
      IptvChannel(
        name: pending['name']?.trim().isNotEmpty == true
            ? pending['name']!.trim()
            : url,
        url: url,
        group: pending['group-title']?.trim().isNotEmpty == true
            ? pending['group-title']!.trim()
            : 'Sin grupo',
        logo: pending['tvg-logo'] ?? '',
        id: pending['tvg-id'] ?? '',
      ),
    );
    pending = null;
  }

  return channels;
}

Map<String, String> _parseExtInf(String line) {
  final result = <String, String>{};
  final comma = line.indexOf(',');
  result['name'] = comma == -1
      ? 'Canal sin nombre'
      : line.substring(comma + 1).trim();

  final attributes = comma == -1 ? line : line.substring(0, comma);
  final attributePattern = RegExp(r'([a-zA-Z0-9_-]+)="([^"]*)"');
  for (final match in attributePattern.allMatches(attributes)) {
    result[match.group(1)!] = match.group(2)!;
  }
  return result;
}
