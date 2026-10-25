import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/pente.dart';
import 'firebase_rest.dart';

/// Letters and digits that are hard to mix up when read aloud or typed.
const String codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int codeLength = 6;

String newGameCode([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
    codeLength,
    (_) => codeAlphabet[r.nextInt(codeAlphabet.length)],
  ).join();
}

/// Cleans up what someone typed: "k7p 3qx" -> "K7P3QX".
String normalizeCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

bool isValidCode(String code) =>
    RegExp('^[$codeAlphabet]{$codeLength}\$').hasMatch(code);

/// Why joining a game failed.
enum JoinError { notFound, full }

class JoinException implements Exception {
  JoinException(this.error);
  final JoinError error;

  String get message => switch (error) {
    JoinError.notFound => 'No game has that code. Check it and try again.',
    JoinError.full => 'That game already has two players.',
  };

  @override
  String toString() => message;
}

/// One game as stored online, decoded.
class OnlineGameState {
  OnlineGameState._(this.raw);

  /// Returns null if [value] isn't a game.
  static OnlineGameState? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    if (map['host'] is! String) return null;
    return OnlineGameState._(map);
  }

  final Map<String, Object?> raw;

  String get host => raw['host'] as String;
  String? get guest => raw['guest'] as String?;

  /// The color the host plays this round.
  Player get hostColor => raw['hostColor'] == 'two' ? Player.two : Player.one;
  bool get tournament => raw['tournament'] == true;
  int get round => (raw['round'] as num?)?.toInt() ?? 0;
  int get moveCount => (raw['moveCount'] as num?)?.toInt() ?? 0;

  Map<String, Object?> _mapOf(String key) {
    final v = raw[key];
    if (v is Map) return {for (final e in v.entries) '${e.key}': e.value};
    if (v is List) {
      return {
        for (var i = 0; i < v.length; i++)
          if (v[i] != null) '$i': v[i],
      };
    }
    return {};
  }

  /// The moves in order, stopping at the first gap.
  List<Point> get moves {
    final m = _mapOf('moves');
    final out = <Point>[];
    for (var i = 0; m.containsKey('$i'); i++) {
      final mv = m['$i'];
      if (mv is! Map) break;
      out.add(Point((mv['r'] as num).toInt(), (mv['c'] as num).toInt()));
    }
    return out;
  }

  /// Round numbers each player asked a rematch for, by player id.
  Map<String, int> get rematch => {
    for (final e in _mapOf('rematch').entries)
      if (e.value is num) e.key: (e.value as num).toInt(),
  };

  Set<String> get left => {
    for (final e in _mapOf('left').entries)
      if (e.value == true) e.key,
  };

  Player colorOf(String uid) => uid == host ? hostColor : hostColor.opponent;

  /// The game data for a new game.
  static Map<String, Object?> create({
    required String host,
    required bool hostPlaysFirst,
    required bool tournament,
  }) => {
    'host': host,
    'hostColor': hostPlaysFirst ? 'one' : 'two',
    'tournament': tournament,
    'round': 0,
    'moveCount': 0,
    'createdAt': {'.sv': 'timestamp'},
  };
}

enum OnlineStatus {
  connecting,
  waitingForOpponent,
  playing,
  opponentLeft,
  error,
}

/// Talks to Firebase for the app: signs in, creates and joins games.
class OnlineService {
  OnlineService(this.config, {AuthStorage? storage})
    : auth = FirebaseAuthRest(config, storage: storage) {
    db = FirebaseDatabaseRest(config, auth);
  }

  /// The service for this build, or null if online play isn't set up.
  static OnlineService? get instance {
    if (_instance != null) return _instance;
    final config = FirebaseConfig.fromEnvironment();
    if (config == null) return null;
    return _instance = OnlineService(config, storage: _PrefsStorage());
  }

  static OnlineService? _instance;

  final FirebaseConfig config;
  final FirebaseAuthRest auth;
  late final FirebaseDatabaseRest db;

  /// Starts a new game and returns its code.
  Future<String> createGame({
    required bool hostPlaysFirst,
    required bool tournament,
  }) async {
    final uid = await auth.signIn();
    for (var attempt = 0; ; attempt++) {
      final code = newGameCode();
      try {
        await db.put(
          'games/$code',
          OnlineGameState.create(
            host: uid,
            hostPlaysFirst: hostPlaysFirst,
            tournament: tournament,
          ),
        );
        return code;
      } on FirebaseException catch (e) {
        // Someone else already has this code: pick another.
        if (!e.permissionDenied || attempt >= 4) rethrow;
      }
    }
  }

  /// Joins the game with [code], or rejoins one this player is already in.
  Future<void> joinGame(String code) async {
    final uid = await auth.signIn();
    final state = OnlineGameState.tryParse(await db.get('games/$code'));
    if (state == null) throw JoinException(JoinError.notFound);
    if (state.host == uid || state.guest == uid) return;
    if (state.guest != null) throw JoinException(JoinError.full);
    try {
      await db.put('games/$code/guest', uid);
    } on FirebaseException catch (e) {
      // Someone else joined first.
      if (e.permissionDenied) throw JoinException(JoinError.full);
      rethrow;
    }
  }

  OnlineGameController open(String code, {OnMove? onMove}) =>
      OnlineGameController(this, code, onMove: onMove);
}

typedef OnMove = void Function(Move move, PenteGame game);

/// Follows one online game and sends this player's moves.
class OnlineGameController extends ChangeNotifier {
  OnlineGameController(this.service, this.code, {this.onMove}) {
    _start();
  }

  static const outOfSyncMessage =
      "This game can't continue: a move came in that the rules don't allow. "
      'Start a new game.';

  final OnlineService service;
  final String code;
  final OnMove? onMove;

  StreamSubscription<Object?>? _sub;
  OnlineGameState? _state;
  PenteGame _game = PenteGame();
  int _round = -1;
  bool _sending = false;
  bool _disposed = false;
  String? _uid;
  bool _resetting = false;

  /// A problem that ends the game for this player, such as the game being
  /// gone or holding a move the rules don't allow.
  String? _fatal;

  /// The live connection was refused. Cleared when data arrives again.
  String? _connection;

  /// Why the game can't be shown right now, or null if all is well.
  String? get error => _fatal ?? _connection;

  OnlineGameState? get state => _state;
  PenteGame get game => _game;
  String? get uid => _uid;
  bool get sending => _sending;

  /// The color this player plays, once known.
  Player? get myColor =>
      _state == null || _uid == null ? null : _state!.colorOf(_uid!);

  bool get isHost => _state != null && _state!.host == _uid;

  OnlineStatus get status {
    if (error != null) return OnlineStatus.error;
    final s = _state;
    if (s == null) return OnlineStatus.connecting;
    final opponentLeft = s.left.any((id) => id != _uid);
    if (opponentLeft) return OnlineStatus.opponentLeft;
    if (s.guest == null) return OnlineStatus.waitingForOpponent;
    return OnlineStatus.playing;
  }

  bool get isMyTurn =>
      status == OnlineStatus.playing &&
      !_game.isOver &&
      _game.currentPlayer == myColor;

  bool get canMove => isMyTurn && !_sending;

  /// This player asked for a rematch of the current round.
  bool get iAskedRematch => _state?.rematch[_uid] == _state?.round;

  bool get opponentAskedRematch {
    final s = _state;
    if (s == null) return false;
    return s.rematch.entries.any((e) => e.key != _uid && e.value == s.round);
  }

  Future<void> _start() async {
    try {
      _uid = await service.auth.signIn();
    } catch (e) {
      _fatal = 'Could not connect. Check your internet connection.';
      _changed();
      return;
    }
    if (_disposed) return;
    // Coming back to a game clears an earlier "left" note. Best effort.
    service.db.put('games/$code/left/$_uid', null).catchError((_) {});
    _sub = service.db
        .watch('games/$code')
        .listen(
          _onData,
          onError: (Object e) {
            _connection = 'Lost access to this game.';
            _changed();
          },
        );
  }

  void _onData(Object? value) {
    final s = OnlineGameState.tryParse(value);
    if (s == null) {
      _fatal = 'This game no longer exists.';
      _changed();
      return;
    }
    _connection = null;
    _state = s;
    _syncGame(s);
    _maybeStartRematch(s);
    _changed();
  }

  /// Brings the local board up to date with the moves stored online.
  void _syncGame(OnlineGameState s) {
    final moves = s.moves;
    final fresh = s.round != _round || !_matchesHistory(moves);
    if (fresh) {
      _round = s.round;
      _game = PenteGame(tournamentRule: s.tournament);
    }
    final before = _game.moveCount;
    if (fresh && _fatal == outOfSyncMessage) _fatal = null;
    for (final p in moves.skip(_game.moveCount)) {
      if (!_game.isLegal(p)) {
        // Only a changed copy of the app could send this. Say so instead
        // of waiting forever for a move that can never arrive.
        _fatal = outOfSyncMessage;
        break;
      }
      _game.play(p);
    }
    // Sound for moves that just arrived (not for catching up on a whole game).
    if (!fresh && _game.moveCount == before + 1 && _game.lastMove != null) {
      final last = _game.lastMove!;
      if (last.player != myColor) onMove?.call(last, _game);
    }
  }

  bool _matchesHistory(List<Point> moves) {
    final h = _game.history;
    // While our move is on its way, an older copy may still arrive.
    if (moves.length < h.length && !_sending) return false;
    for (var i = 0; i < min(h.length, moves.length); i++) {
      if (h[i].point != moves[i]) return false;
    }
    return true;
  }

  /// Plays at [p] for this player. Returns false if it isn't allowed now.
  bool tap(Point p) {
    if (!canMove || !_game.isLegal(p)) return false;
    final n = _game.moveCount;
    _game.play(p);
    onMove?.call(_game.lastMove!, _game);
    _sending = true;
    _changed();
    service.db
        .patch('games/$code', {
          'moves/$n': {'r': p.row, 'c': p.col},
          'moveCount': n + 1,
        })
        .then(
          (_) {
            _sending = false;
            _changed();
          },
          onError: (Object e) async {
            debugPrint('Sending move failed: $e');
            _sending = false;
            // Put the board back to what is stored online.
            try {
              _onData(await service.db.get('games/$code'));
            } catch (_) {
              if (_game.moveCount > n) _game.undo();
              _changed();
            }
          },
        );
    return true;
  }

  /// Ask to play again. When both players have asked, the host starts a new
  /// round with colors swapped.
  Future<void> requestRematch() async {
    final s = _state;
    if (s == null || _uid == null) return;
    await service.db.put('games/$code/rematch/$_uid', s.round);
  }

  void _maybeStartRematch(OnlineGameState s) {
    if (!isHost || _resetting || s.guest == null) return;
    final asked = s.rematch;
    if (asked[s.host] != s.round || asked[s.guest] != s.round) return;
    _resetting = true;
    service.db
        .put('games/$code', {
          'host': s.host,
          'guest': s.guest,
          'hostColor': s.hostColor == Player.one ? 'two' : 'one',
          'tournament': s.tournament,
          'round': s.round + 1,
          'moveCount': 0,
          'createdAt': s.raw['createdAt'],
        })
        .catchError((Object e) => debugPrint('Rematch failed: $e'))
        .whenComplete(() => _resetting = false);
  }

  /// Tells the other player this one has left. Best effort.
  Future<void> leave() async {
    final s = _state;
    if (s == null || _uid == null) return;
    if (s.guest == null && isHost) return;
    try {
      await service.db.put('games/$code/left/$_uid', true);
    } catch (_) {}
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}

class _PrefsStorage implements AuthStorage {
  static const _key = 'online_refresh_token';

  @override
  Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> save(String refreshToken) async =>
      (await SharedPreferences.getInstance()).setString(_key, refreshToken);
}
