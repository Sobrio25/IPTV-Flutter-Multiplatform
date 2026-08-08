import 'package:web/web.dart' as web;

const _prefix = 'iptv_player.';

Future<String?> readAppString(String key) async {
  return web.window.localStorage.getItem('$_prefix$key');
}

Future<void> writeAppString(String key, String value) async {
  web.window.localStorage.setItem('$_prefix$key', value);
}

Future<void> removeAppString(String key) async {
  web.window.localStorage.removeItem('$_prefix$key');
}
