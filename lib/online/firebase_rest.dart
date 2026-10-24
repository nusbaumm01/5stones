/// A small Firebase client that talks to Firebase over plain HTTPS.
///
/// Using the REST API instead of the FlutterFire plugins keeps online play
/// working the same way on Mac, Windows, iPhone and iPad, with no native
/// setup files per platform.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Where the Firebase project lives. Built into the app at build time.
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.databaseUrl,
    this.authEmulator,
    this.databaseNamespace,
  });

  /// Reads `--dart-define=FIREBASE_API_KEY=...` and
  /// `--dart-define=FIREBASE_DATABASE_URL=...` given at build time.
  /// For local testing, `--dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1`
  /// uses the Firebase emulator instead.
  static FirebaseConfig? fromEnvironment() {
    const emulator = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
    if (emulator.isNotEmpty) return FirebaseConfig.emulator(host: emulator);
    const key = String.fromEnvironment('FIREBASE_API_KEY');
    const url = String.fromEnvironment('FIREBASE_DATABASE_URL');
    if (key.isEmpty || url.isEmpty) return null;
    return const FirebaseConfig(apiKey: key, databaseUrl: url);
  }

  /// Settings for the local Firebase emulator, used by tests.
  factory FirebaseConfig.emulator({
    String host = '127.0.0.1',
    String project = 'demo-5stones',
  }) => FirebaseConfig(
    apiKey: 'fake-api-key',
    databaseUrl: 'http://$host:9000',
    authEmulator: 'http://$host:9099',
    databaseNamespace: '$project-default-rtdb',
  );

  final String apiKey;

  /// For example https://my-project-default-rtdb.firebaseio.com
  final String databaseUrl;

  /// Base URL of the auth emulator, or null for real Firebase.
  final String? authEmulator;

  /// The `ns` query parameter the database emulator needs.
  final String? databaseNamespace;
}

class FirebaseException implements Exception {
  FirebaseException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  bool get permissionDenied => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'Firebase error $statusCode: $message';
}

/// Signs in anonymously and keeps the ID token fresh.
class FirebaseAuthRest {
  FirebaseAuthRest(this.config, {http.Client? client, this.storage})
    : _http = client ?? http.Client();

  final FirebaseConfig config;
  final http.Client _http;

  /// Saves the sign-in between launches so a player keeps the same identity
  /// (and can rejoin their games).
  final AuthStorage? storage;

  String? _uid;
  String? _idToken;
  String? _refreshToken;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _pending;

  String? get uid => _uid;

  Uri _endpoint(String host, String path) {
    final base = config.authEmulator == null
        ? 'https://$host'
        : '${config.authEmulator}/$host';
    return Uri.parse('$base$path?key=${config.apiKey}');
  }

  /// Signs in if needed and returns this device's player id.
  Future<String> signIn() async {
    await token();
    return _uid!;
  }

  /// A valid ID token, refreshed when it is about to expire.
  Future<String> token({bool forceRefresh = false}) async {
    if (forceRefresh) _expires = DateTime.fromMillisecondsSinceEpoch(0);
    while (_idToken == null ||
        DateTime.now().isAfter(_expires.subtract(const Duration(minutes: 5)))) {
      _pending ??= _renew().whenComplete(() => _pending = null);
      await _pending;
    }
    return _idToken!;
  }

  Future<void> _renew() async {
    if (_refreshToken == null && storage != null) {
      final saved = await storage!.load();
      if (saved != null) _refreshToken = saved;
    }
    if (_refreshToken != null) {
      try {
        await _refresh();
        return;
      } on FirebaseException catch (e) {
        // A revoked or unknown refresh token: start over with a new player.
        if (e.statusCode != 400) rethrow;
        _refreshToken = null;
      }
    }
    await _signUp();
  }

  Future<void> _signUp() async {
    final res = await _http.post(
      _endpoint('identitytoolkit.googleapis.com', '/v1/accounts:signUp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'returnSecureToken': true}),
    );
    final body = _decode(res);
    _set(
      body['localId'] as String,
      body['idToken'] as String,
      body['refreshToken'] as String,
      body['expiresIn'],
    );
  }

  Future<void> _refresh() async {
    final res = await _http.post(
      _endpoint('securetoken.googleapis.com', '/v1/token'),
      body: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken!},
    );
    final body = _decode(res);
    _set(
      body['user_id'] as String,
      body['id_token'] as String,
      body['refresh_token'] as String,
      body['expires_in'],
    );
  }

  void _set(String uid, String idToken, String refresh, Object? expiresIn) {
    _uid = uid;
    _idToken = idToken;
    _refreshToken = refresh;
    final seconds = int.tryParse('$expiresIn') ?? 3600;
    _expires = DateTime.now().add(Duration(seconds: seconds));
    storage?.save(refresh);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode != 200) {
      throw FirebaseException(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void close() => _http.close();
}

/// Keeps the refresh token between app launches.
abstract class AuthStorage {
  Future<String?> load();
  Future<void> save(String refreshToken);
}

/// Reads and writes the Realtime Database, and listens for changes.
class FirebaseDatabaseRest {
  FirebaseDatabaseRest(this.config, this.auth, {http.Client? client})
    : _http = client ?? http.Client();

  final FirebaseConfig config;
  final FirebaseAuthRest auth;
  final http.Client _http;

  Future<Uri> _uri(String path) async {
    final token = await auth.token();
    final base = config.databaseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/$path.json').replace(
      queryParameters: {
        'auth': token,
        if (config.databaseNamespace != null) 'ns': config.databaseNamespace!,
      },
    );
  }

  Future<Object?> get(String path) async {
    final res = await _http.get(await _uri(path));
    return _decode(res);
  }

  /// Replaces the data at [path].
  Future<void> put(String path, Object? value) async {
    final res = await _http.put(await _uri(path), body: jsonEncode(value));
    _decode(res);
  }

  /// Writes several children of [path] at once. Either all of them are
  /// saved or none are.
  Future<void> patch(String path, Map<String, Object?> values) async {
    final res = await _http.patch(await _uri(path), body: jsonEncode(values));
    _decode(res);
  }

  Object? _decode(http.Response res) {
    if (res.statusCode != 200) {
      throw FirebaseException(res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  /// The data at [path], again each time it changes. Reconnects on its own
  /// after network trouble.
  Stream<Object?> watch(String path) {
    late StreamController<Object?> out;
    var cancelled = false;
    http.Client? client;

    Future<void> run() async {
      var delay = const Duration(seconds: 1);
      while (!cancelled) {
        try {
          if (kIsWeb) {
            // Browsers can't stream these responses: check every so often.
            if (!out.isClosed) out.add(await get(path));
            await Future<void>.delayed(const Duration(milliseconds: 1500));
            continue;
          }
          client = http.Client();
          final req = http.Request('GET', await _uri(path))
            ..headers['Accept'] = 'text/event-stream';
          final res = await client!.send(req);
          if (res.statusCode != 200) {
            final body = await res.stream.bytesToString();
            throw FirebaseException(res.statusCode, body);
          }
          final tree = JsonTree();
          await for (final event in parseServerSentEvents(res.stream)) {
            if (cancelled) break;
            delay = const Duration(seconds: 1);
            switch (event.name) {
              case 'put' || 'patch':
                final data = jsonDecode(event.data) as Map<String, dynamic>;
                tree.apply(
                  data['path'] as String,
                  data['data'],
                  merge: event.name == 'patch',
                );
                if (!out.isClosed) out.add(tree.value);
              case 'auth_revoked':
                await auth.token(forceRefresh: true);
              case 'cancel':
                throw FirebaseException(403, event.data);
            }
            if (event.name == 'auth_revoked') break;
          }
        } catch (e) {
          if (cancelled) break;
          if (e is FirebaseException && e.permissionDenied) {
            if (!out.isClosed) out.addError(e);
          }
          debugPrint('Game connection dropped: $e');
          await Future<void>.delayed(delay);
          if (delay < const Duration(seconds: 15)) delay *= 2;
        } finally {
          client?.close();
          client = null;
        }
      }
    }

    out = StreamController<Object?>(
      onListen: run,
      onCancel: () {
        cancelled = true;
        client?.close();
      },
    );
    return out.stream;
  }

  void close() => _http.close();
}

class ServerSentEvent {
  const ServerSentEvent(this.name, this.data);
  final String name;
  final String data;
}

/// Splits a text/event-stream body into events.
Stream<ServerSentEvent> parseServerSentEvents(Stream<List<int>> bytes) async* {
  var name = '';
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (name.isNotEmpty || data.isNotEmpty) {
        yield ServerSentEvent(name, data.join('\n'));
      }
      name = '';
      data.clear();
    } else if (line.startsWith('event:')) {
      name = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }
}

/// A local copy of a JSON value that put and patch events update.
class JsonTree {
  Object? value;

  void apply(String path, Object? data, {bool merge = false}) {
    final keys = path.split('/').where((k) => k.isNotEmpty).toList();
    if (merge) {
      for (final entry in (data as Map<String, dynamic>).entries) {
        apply('$path/${entry.key}', entry.value);
      }
      return;
    }
    value = _setAt(value, keys, data);
  }

  static Object? _setAt(Object? node, List<String> keys, Object? data) {
    if (keys.isEmpty) return data;
    final map = _asMap(node);
    final child = _setAt(map[keys.first], keys.sublist(1), data);
    if (child == null) {
      map.remove(keys.first);
    } else {
      map[keys.first] = child;
    }
    return map.isEmpty ? null : map;
  }

  /// Firebase sends objects with keys 0, 1, 2… as lists. Treat both alike.
  static Map<String, Object?> _asMap(Object? node) {
    if (node is Map) return {for (final e in node.entries) '${e.key}': e.value};
    if (node is List) {
      return {
        for (var i = 0; i < node.length; i++)
          if (node[i] != null) '$i': node[i],
      };
    }
    return {};
  }
}
