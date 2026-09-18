import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const _storageChannel = MethodChannel('iptv_player/storage');

Future<String?> readAppString(String key) async {
  if (Platform.isAndroid) {
    try {
      return _storageChannel.invokeMethod<String>('getString', {'key': key});
    } on PlatformException {
      return null;
    }
  }
  return _enqueue(() async => (await _loadFileStore())[key]);
}

Future<void> writeAppString(String key, String value) async {
  if (Platform.isAndroid) {
    try {
      await _storageChannel.invokeMethod<void>('setString', {
        'key': key,
        'value': value,
      });
    } on PlatformException {
      // Playback must remain available when storage is unavailable.
    }
    return;
  }
  await _enqueue(() async {
    final values = await _loadFileStore();
    if (values[key] == value) return;
    values[key] = value;
    await _writeFileStore(values);
  });
}

Future<void> removeAppString(String key) async {
  if (Platform.isAndroid) {
    try {
      await _storageChannel.invokeMethod<void>('removeString', {'key': key});
    } on PlatformException {
      // Old caches should never prevent the app from opening.
    }
    return;
  }
  await _enqueue(() async {
    final values = await _loadFileStore();
    if (values.remove(key) == null) return;
    await _writeFileStore(values);
  });
}

// File operations are serialized: concurrent read-modify-write cycles would
// otherwise drop keys or interleave writes and corrupt settings.json.
Future<void> _queue = Future<void>.value();
Map<String, String>? _cache;

Future<T> _enqueue<T>(Future<T> Function() operation) {
  final result = _queue.then((_) => operation());
  _queue = result.then<void>((_) {}, onError: (_) {});
  return result;
}

Future<Map<String, String>> _loadFileStore() async =>
    _cache ??= await _readFileStore();

File get _storageFile {
  final baseDir = _platformConfigDirectory;
  return File(
    [baseDir, 'IPTV Player', 'settings.json'].join(Platform.pathSeparator),
  );
}

String get _platformConfigDirectory {
  if (Platform.isWindows) {
    return _firstEnvironmentValue(['APPDATA', 'LOCALAPPDATA']);
  }
  if (Platform.isLinux) {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.trim().isNotEmpty) return xdg;
    return [
      _firstEnvironmentValue(['HOME']),
      '.config',
    ].join(Platform.pathSeparator);
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return [
      _firstEnvironmentValue(['HOME']),
      'Library',
      'Application Support',
    ].join(Platform.pathSeparator);
  }
  return Directory.current.path;
}

String _firstEnvironmentValue(List<String> keys) {
  for (final key in keys) {
    final value = Platform.environment[key];
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return Directory.current.path;
}

Future<Map<String, String>> _readFileStore() async {
  try {
    if (!await _storageFile.exists()) return <String, String>{};
    final decoded = jsonDecode(await _storageFile.readAsString());
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

Future<void> _writeFileStore(Map<String, String> values) async {
  try {
    await _storageFile.parent.create(recursive: true);
    // Write to a temp file first so a crash mid-write cannot truncate the
    // real settings file.
    final temp = File('${_storageFile.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(values),
      flush: true,
    );
    await temp.rename(_storageFile.path);
  } on FileSystemException {
    // Persistence is useful but should not block playback.
  }
}
