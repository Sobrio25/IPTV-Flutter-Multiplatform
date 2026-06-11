import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const IptvApp());
}

const _storageChannel = MethodChannel('iptv_player/storage');
const _playerChannel = MethodChannel('iptv_player/player');

class PlaylistSource {
  const PlaylistSource({
    required this.name,
    required this.description,
    required this.url,
  });

  final String name;
  final String description;
  final String url;
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
  final _searchController = TextEditingController();
  final _urlController = TextEditingController(text: defaultSources.first.url);
  final _pasteController = TextEditingController();

  var _channels = <IptvChannel>[];
  var _favorites = <String>{};
  var _selectedGroup = 'Todos';
  var _searchText = '';
  var _loading = false;
  var _status =
      'Elige una fuente actualizada de IPTV.org o pega una lista M3U.';
  IptvChannel? _selectedChannel;

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _restoreState() async {
    final values = await Future.wait([
      _readString('playlistUrl'),
      _readString('channels'),
      _readString('favorites'),
    ]);
    final savedUrl = values[0];
    final savedChannels = values[1];
    final savedFavorites = values[2];

    if (!mounted) return;
    setState(() {
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _urlController.text = savedUrl;
      }
      if (savedChannels != null && savedChannels.isNotEmpty) {
        final decoded = jsonDecode(savedChannels) as List<dynamic>;
        _channels = decoded
            .whereType<Map<String, Object?>>()
            .map(IptvChannel.fromJson)
            .where((channel) => channel.url.isNotEmpty)
            .toList();
        _status = 'Lista restaurada: ${_channels.length} canales.';
      }
      if (savedFavorites != null && savedFavorites.isNotEmpty) {
        _favorites = (jsonDecode(savedFavorites) as List<dynamic>)
            .whereType<String>()
            .toSet();
      }
    });
  }

  Future<String?> _readString(String key) async {
    if (!Platform.isAndroid) return null;
    try {
      return _storageChannel.invokeMethod<String>('getString', {'key': key});
    } on PlatformException {
      return null;
    }
  }

  Future<void> _writeString(String key, String value) async {
    if (!Platform.isAndroid) return;
    try {
      await _storageChannel.invokeMethod<void>('setString', {
        'key': key,
        'value': value,
      });
    } on PlatformException {
      // Persistence is helpful, but playback should not depend on it.
    }
  }

  Future<void> _loadFromSource(PlaylistSource source) async {
    _urlController.text = source.url;
    await _loadFromUrl(source.url);
  }

  Future<void> _loadFromUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _status = 'Descargando lista...';
    });

    try {
      final uri = Uri.parse(url);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'IPTV Player Flutter');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      await _setChannels(parseM3u(body), url);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'No se pudo cargar la lista: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFromPaste() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) return;
    await _setChannels(parseM3u(text), 'pegada');
  }

  Future<void> _setChannels(List<IptvChannel> channels, String source) async {
    final unique = <String, IptvChannel>{};
    for (final channel in channels) {
      unique[channel.url] = channel;
    }

    if (!mounted) return;
    setState(() {
      _channels = unique.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectedGroup = 'Todos';
      _selectedChannel = _channels.isEmpty ? null : _channels.first;
      _status = _channels.isEmpty
          ? 'La lista no tenia canales reproducibles.'
          : 'Cargados ${_channels.length} canales desde $source.';
    });

    await _writeString('playlistUrl', _urlController.text.trim());
    await _writeString(
      'channels',
      jsonEncode(_channels.map((channel) => channel.toJson()).toList()),
    );
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
    if (!Platform.isAndroid) {
      setState(
        () => _status = 'La reproduccion nativa esta disponible en Android.',
      );
      return;
    }

    try {
      await _playerChannel.invokeMethod<void>('play', {
        'name': channel.name,
        'url': channel.url,
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _status = 'No se pudo abrir el reproductor: ${error.message}',
      );
    }
  }

  List<String> get _groups {
    final groups =
        _channels
            .map((channel) => channel.group.trim())
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['Todos', 'Favoritos', ...groups];
  }

  List<IptvChannel> get _visibleChannels {
    final query = _searchText.trim().toLowerCase();
    return _channels.where((channel) {
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

  @override
  Widget build(BuildContext context) {
    final visibleChannels = _visibleChannels;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final player = _PlayerPanel(
              channel: _selectedChannel,
              favorite:
                  _selectedChannel != null &&
                  _favorites.contains(_selectedChannel!.url),
              onFavorite: _selectedChannel == null
                  ? null
                  : () => _toggleFavorite(_selectedChannel!),
              onPlay: _selectedChannel == null
                  ? null
                  : () => _playChannel(_selectedChannel!),
            );
            final library = _LibraryPanel(
              loading: _loading,
              status: _status,
              sources: defaultSources,
              channels: visibleChannels,
              groups: _groups,
              selectedGroup: _selectedGroup,
              selectedChannel: _selectedChannel,
              favorites: _favorites,
              urlController: _urlController,
              searchController: _searchController,
              pasteController: _pasteController,
              onSourceSelected: _loadFromSource,
              onLoadUrl: () => _loadFromUrl(_urlController.text),
              onLoadPaste: _loadFromPaste,
              onGroupChanged: (group) => setState(() => _selectedGroup = group),
              onSearchChanged: (value) => setState(() => _searchText = value),
              onChannelSelected: (channel) =>
                  setState(() => _selectedChannel = channel),
              onChannelPlay: _playChannel,
              onFavorite: _toggleFavorite,
            );

            return Padding(
              padding: const EdgeInsets.all(12),
              child: wide
                  ? Row(
                      children: [
                        Expanded(flex: 5, child: player),
                        const SizedBox(width: 12),
                        Expanded(flex: 4, child: library),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(height: 220, child: player),
                        const SizedBox(height: 12),
                        Expanded(child: library),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.channel,
    required this.favorite,
    required this.onFavorite,
    required this.onPlay,
  });

  final IptvChannel? channel;
  final bool favorite;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff080b0e),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              child: _PreviewPlayer(channel: channel, onPlay: onPlay),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel?.name ?? 'Sin canal seleccionado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        channel?.group ?? 'Carga una lista para comenzar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: favorite ? 'Quitar favorito' : 'Agregar favorito',
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.star : Icons.star_border),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPlayer extends StatelessWidget {
  const _PreviewPlayer({required this.channel, required this.onPlay});

  final IptvChannel? channel;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff14212b), Color(0xff101418), Color(0xff081110)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChannelLogo(channel: channel, size: 86),
              const SizedBox(height: 14),
              Text(
                channel?.name ?? 'Selecciona un canal',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                channel?.group ??
                    'Carga una fuente IPTV.org o pega una lista M3U.',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Reproducir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryPanel extends StatelessWidget {
  const _LibraryPanel({
    required this.loading,
    required this.status,
    required this.sources,
    required this.channels,
    required this.groups,
    required this.selectedGroup,
    required this.selectedChannel,
    required this.favorites,
    required this.urlController,
    required this.searchController,
    required this.pasteController,
    required this.onSourceSelected,
    required this.onLoadUrl,
    required this.onLoadPaste,
    required this.onGroupChanged,
    required this.onSearchChanged,
    required this.onChannelSelected,
    required this.onChannelPlay,
    required this.onFavorite,
  });

  final bool loading;
  final String status;
  final List<PlaylistSource> sources;
  final List<IptvChannel> channels;
  final List<String> groups;
  final String selectedGroup;
  final IptvChannel? selectedChannel;
  final Set<String> favorites;
  final TextEditingController urlController;
  final TextEditingController searchController;
  final TextEditingController pasteController;
  final ValueChanged<PlaylistSource> onSourceSelected;
  final VoidCallback onLoadUrl;
  final VoidCallback onLoadPaste;
  final ValueChanged<String> onGroupChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<IptvChannel> onChannelSelected;
  final ValueChanged<IptvChannel> onChannelPlay;
  final ValueChanged<IptvChannel> onFavorite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalChannels = channels.length;
    PlaylistSource? sourceValue;
    for (final source in sources) {
      if (source.url == urlController.text.trim()) {
        sourceValue = source;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'IPTV Player',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            if (loading)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          status,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<PlaylistSource>(
                  initialValue: sourceValue,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.live_tv),
                    labelText: 'Fuente IPTV.org',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final source in sources)
                      DropdownMenuItem(value: source, child: Text(source.name)),
                  ],
                  onChanged: loading || sources.isEmpty
                      ? null
                      : (source) {
                          if (source != null) onSourceSelected(source);
                        },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: urlController,
                        minLines: 1,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.link),
                          labelText: 'URL M3U',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Cargar URL',
                      onPressed: loading ? null : onLoadUrl,
                      icon: const Icon(Icons.download),
                    ),
                    const SizedBox(width: 4),
                    IconButton.outlined(
                      tooltip: 'Pegar M3U',
                      onPressed: loading
                          ? null
                          : () => _showPasteSheet(context),
                      icon: const Icon(Icons.content_paste),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _MetricChip(icon: Icons.tv, label: '$totalChannels canales'),
            const SizedBox(width: 8),
            _MetricChip(
              icon: Icons.star,
              label: '${favorites.length} favoritos',
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
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
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final group = groups[index];
              return ChoiceChip(
                label: Text(group),
                selected: selectedGroup == group,
                onSelected: (_) => onGroupChanged(group),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: channels.isEmpty
              ? const Center(child: Text('Sin canales para mostrar'))
              : ListView.separated(
                  itemCount: channels.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    final selected = selectedChannel?.url == channel.url;
                    final favorite = favorites.contains(channel.url);
                    return Material(
                      color: selected
                          ? colorScheme.primaryContainer.withValues(alpha: 0.36)
                          : colorScheme.surfaceContainerLow,
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
                              onPressed: () => onChannelPlay(channel),
                              icon: const Icon(Icons.play_circle),
                            ),
                            IconButton(
                              tooltip: favorite
                                  ? 'Quitar favorito'
                                  : 'Agregar favorito',
                              onPressed: () => onFavorite(channel),
                              icon: Icon(
                                favorite ? Icons.star : Icons.star_border,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => onChannelSelected(channel),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showPasteSheet(BuildContext context) {
    showModalBottomSheet<void>(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pegar lista M3U',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pasteController,
                minLines: 8,
                maxLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '#EXTM3U...',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onLoadPaste();
                },
                icon: const Icon(Icons.content_paste_go),
                label: const Text('Importar'),
              ),
            ],
          ),
        );
      },
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel, this.size = 42});

  final IptvChannel? channel;
  final double size;

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
