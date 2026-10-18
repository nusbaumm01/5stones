import 'dart:math';

import 'pente.dart';

enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const Difficulty(this.label);
  final String label;
}

/// Picks a move for the current player.
///
/// It looks a few moves ahead (more on harder levels) and scores each
/// position by counting how close each side is to five in a row and to five
/// captures. Easy plays loosely and sometimes misses things on purpose.
class PenteAi {
  PenteAi(this.difficulty, {Random? random}) : _random = random ?? Random();

  final Difficulty difficulty;
  final Random _random;

  static const double _win = 1e9;

  /// Score for a run of N of one player's stones inside a 5-cell window
  /// that the other player has no stones in.
  static const List<double> _windowScore = [0, 1, 12, 120, 1500, 0];

  /// Value of having captured N pairs. Grows steeply toward five.
  static const List<double> _captureScore = [0, 300, 800, 2000, 6000, _win];

  int get _depth => switch (difficulty) {
    Difficulty.easy => 1,
    Difficulty.medium => 2,
    Difficulty.hard => 3,
  };

  int get _breadth => switch (difficulty) {
    Difficulty.easy => 30,
    Difficulty.medium => 12,
    Difficulty.hard => 10,
  };

  Point chooseMove(PenteGame original) {
    final game = original.copy();
    final me = game.currentPlayer;
    final candidates = _orderedCandidates(game);
    if (candidates.isEmpty) {
      throw StateError('No legal moves');
    }
    if (candidates.length == 1) return candidates.first.$1;

    // Take a win if there is one.
    for (final (p, _) in candidates) {
      game.play(p);
      final won = game.winner == me;
      game.undo();
      if (won) return p;
    }

    if (difficulty == Difficulty.easy) return _easyPick(game, candidates);

    var best = candidates.first.$1;
    var bestScore = -double.infinity;
    var alpha = -double.infinity;
    const beta = double.infinity;
    for (final (p, _) in candidates.take(_breadth)) {
      game.play(p);
      final score = -_negamax(game, _depth - 1, -beta, -alpha);
      game.undo();
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
      if (score > alpha) alpha = score;
    }
    return best;
  }

  /// Easy blocks an open win most of the time, otherwise picks one of the
  /// top few moves at random.
  Point _easyPick(PenteGame game, List<(Point, double)> candidates) {
    final block = _blockingMove(game);
    if (block != null && _random.nextDouble() < 0.7) return block;
    final pool = candidates.take(min(5, candidates.length)).toList();
    return pool[_random.nextInt(pool.length)].$1;
  }

  /// A point where the opponent would win next turn, if there is one.
  Point? _blockingMove(PenteGame game) {
    final foe = game.currentPlayer.opponent;
    for (final p in _nearbyEmpty(game)) {
      final line = _runThrough(game, p, foe);
      if (line >= 5) return p;
      if (game.capturesOf(foe) == PenteGame.capturesToWin - 1 &&
          game.capturesFor(p, foe).isNotEmpty) {
        return p;
      }
    }
    return null;
  }

  int _runThrough(PenteGame game, Point p, Player player) {
    var best = 0;
    for (final (dr, dc) in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      var n = 1;
      for (final s in const [1, -1]) {
        var q = Point(p.row + dr * s, p.col + dc * s);
        while (game.inBounds(q) && game.at(q) == player) {
          n++;
          q = Point(q.row + dr * s, q.col + dc * s);
        }
      }
      if (n > best) best = n;
    }
    return best;
  }

  double _negamax(PenteGame game, int depth, double alpha, double beta) {
    if (game.winner != null) {
      // The player who just moved won; bad for the side to move.
      // Prefer faster wins and slower losses.
      return -_win - depth;
    }
    if (depth == 0 || game.isDraw) return evaluate(game, game.currentPlayer);

    var best = -double.infinity;
    for (final (p, _) in _orderedCandidates(game).take(_breadth)) {
      game.play(p);
      final score = -_negamax(game, depth - 1, -beta, -alpha);
      game.undo();
      if (score > best) best = score;
      if (score > alpha) alpha = score;
      if (alpha >= beta) break;
    }
    return best == -double.infinity ? 0 : best;
  }

  /// Legal moves near existing stones, best-looking first.
  List<(Point, double)> _orderedCandidates(PenteGame game) {
    var points = _nearbyEmpty(game).where(game.isLegal).toList();
    if (points.isEmpty) points = game.legalMoves().toList();
    final mover = game.currentPlayer;
    final scored = <(Point, double)>[];
    for (final p in points) {
      game.play(p);
      final s = game.winner == mover ? _win : evaluate(game, mover);
      game.undo();
      scored.add((p, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored;
  }

  /// Empty points within two steps of any stone.
  Iterable<Point> _nearbyEmpty(PenteGame game) {
    final n = game.size;
    final mark = List<bool>.filled(n * n, false);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (game.at(Point(r, c)) == null) continue;
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            final rr = r + dr, cc = c + dc;
            if (rr < 0 || rr >= n || cc < 0 || cc >= n) continue;
            if (game.at(Point(rr, cc)) == null) mark[rr * n + cc] = true;
          }
        }
      }
    }
    return [
      for (var i = 0; i < mark.length; i++)
        if (mark[i]) Point(i ~/ n, i % n),
    ];
  }

  /// How good the position is for [player] (positive is good).
  static double evaluate(PenteGame game, Player player) {
    final foe = player.opponent;
    if (game.winner == player) return _win;
    if (game.winner == foe) return -_win;

    var mine = _captureScore[game.capturesOf(player)];
    var theirs = _captureScore[game.capturesOf(foe)];
    final n = game.size;

    for (final (dr, dc) in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          final endR = r + dr * 4, endC = c + dc * 4;
          if (endR < 0 || endR >= n || endC < 0 || endC >= n) continue;
          var a = 0, b = 0;
          for (var k = 0; k < 5; k++) {
            final s = game.at(Point(r + dr * k, c + dc * k));
            if (s == player) {
              a++;
            } else if (s == foe) {
              b++;
            }
          }
          if (a > 0 && b == 0) mine += _windowScore[a];
          if (b > 0 && a == 0) theirs += _windowScore[b];
        }
      }
    }

    // Pairs that can be captured next turn are a liability.
    mine -= 150 * _exposedPairs(game, player);
    theirs -= 150 * _exposedPairs(game, foe);

    // The side to move gets to act on its threats first.
    if (game.currentPlayer == player) {
      mine *= 1.2;
    } else {
      theirs *= 1.2;
    }
    return mine - theirs;
  }

  /// Number of [player]'s pairs flanked by an opponent stone on one side and
  /// an empty point on the other.
  static int _exposedPairs(PenteGame game, Player player) {
    final foe = player.opponent;
    final n = game.size;
    var count = 0;
    for (final (dr, dc) in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          final p0 = Point(r, c);
          final p3 = Point(r + dr * 3, c + dc * 3);
          if (!game.inBounds(p3)) continue;
          final s1 = game.at(Point(r + dr, c + dc));
          final s2 = game.at(Point(r + dr * 2, c + dc * 2));
          if (s1 != player || s2 != player) continue;
          final a = game.at(p0), b = game.at(p3);
          if ((a == foe && b == null) || (a == null && b == foe)) count++;
        }
      }
    }
    return count;
  }
}

/// Entry point for running the computer's turn off the main thread.
Point computeAiMove((PenteGame, Difficulty, int) args) {
  final (game, difficulty, seed) = args;
  return PenteAi(difficulty, random: Random(seed)).chooseMove(game);
}
