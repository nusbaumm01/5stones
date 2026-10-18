/// Classic Pente rules on a square board.
///
/// - Player one moves first, and their first stone goes on the center point.
/// - Placing a stone so that exactly two opponent stones are flanked in a
///   straight line (X O O X) removes those two stones as a captured pair.
///   Moving into a flanked position yourself is safe.
/// - A player wins with five or more stones in a row, or five captured pairs.
/// - Optional tournament rule: player one's second stone must be at least
///   three points away from the center.
library;

enum Player {
  one,
  two;

  Player get opponent => this == Player.one ? Player.two : Player.one;
}

/// A board intersection.
class Point {
  const Point(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is Point && other.row == row && other.col == col;

  @override
  int get hashCode => row * 1000 + col;

  @override
  String toString() => '($row, $col)';
}

enum WinReason { fiveInARow, fiveCaptures }

/// Why a move was not allowed.
enum MoveError {
  gameOver,
  outOfBounds,
  occupied,
  firstMoveMustBeCenter,
  tournamentRule,
}

/// One move and what it captured, so it can be undone.
class Move {
  const Move(this.player, this.point, this.captured);

  final Player player;
  final Point point;
  final List<Point> captured;
}

class PenteGame {
  PenteGame({this.size = 19, this.tournamentRule = false})
    : assert(size >= 7 && size.isOdd),
      _cells = List<Player?>.filled(size * size, null);

  /// Board width and height. Odd, so there is a center point.
  final int size;

  /// When true, player one's second stone must be 3+ points from the center.
  final bool tournamentRule;

  final List<Player?> _cells;
  final List<Move> _history = [];
  final Map<Player, int> _captures = {Player.one: 0, Player.two: 0};

  Player _current = Player.one;
  Player? _winner;
  WinReason? _winReason;
  List<Point> _winningLine = const [];

  static const int capturesToWin = 5;
  static const List<(int, int)> _directions = [(0, 1), (1, 0), (1, 1), (1, -1)];

  Point get center => Point(size ~/ 2, size ~/ 2);
  Player get currentPlayer => _current;
  Player? get winner => _winner;
  WinReason? get winReason => _winReason;
  bool get isOver => _winner != null || isDraw;

  /// The board is full and nobody won.
  bool get isDraw => _winner == null && _history.length >= _stoneSlotsUsed;
  int get _stoneSlotsUsed => size * size + _totalCapturedStones;
  int get _totalCapturedStones =>
      (_captures[Player.one]! + _captures[Player.two]!) * 2;

  /// The five-or-more stones that won the game, if won by a row.
  List<Point> get winningLine => List.unmodifiable(_winningLine);
  List<Move> get history => List.unmodifiable(_history);
  Move? get lastMove => _history.isEmpty ? null : _history.last;
  int get moveCount => _history.length;

  /// Number of pairs [player] has captured.
  int capturesOf(Player player) => _captures[player]!;

  bool inBounds(Point p) =>
      p.row >= 0 && p.row < size && p.col >= 0 && p.col < size;

  Player? at(Point p) => _cells[p.row * size + p.col];

  void _set(Point p, Player? value) => _cells[p.row * size + p.col] = value;

  /// Returns null if [p] is a legal move for the current player.
  MoveError? validate(Point p) {
    if (isOver) return MoveError.gameOver;
    if (!inBounds(p)) return MoveError.outOfBounds;
    if (at(p) != null) return MoveError.occupied;
    if (_history.isEmpty && p != center) return MoveError.firstMoveMustBeCenter;
    if (tournamentRule && _history.length == 2 && !_farFromCenter(p)) {
      return MoveError.tournamentRule;
    }
    return null;
  }

  bool isLegal(Point p) => validate(p) == null;

  bool _farFromCenter(Point p) =>
      (p.row - center.row).abs() >= 3 || (p.col - center.col).abs() >= 3;

  /// All legal moves for the current player.
  Iterable<Point> legalMoves() sync* {
    if (isOver) return;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final p = Point(r, c);
        if (isLegal(p)) yield p;
      }
    }
  }

  /// Places a stone for the current player. Throws [ArgumentError] when the
  /// move is illegal. Returns the stones captured by this move.
  List<Point> play(Point p) {
    final error = validate(p);
    if (error != null) {
      throw ArgumentError('Illegal move at $p: ${error.name}');
    }
    final player = _current;
    _set(p, player);
    final captured = _findCaptures(p, player);
    for (final c in captured) {
      _set(c, null);
    }
    _captures[player] = _captures[player]! + captured.length ~/ 2;
    _history.add(Move(player, p, captured));

    if (_captures[player]! >= capturesToWin) {
      _winner = player;
      _winReason = WinReason.fiveCaptures;
    } else {
      final line = _longestLineThrough(p, player);
      if (line.length >= 5) {
        _winner = player;
        _winReason = WinReason.fiveInARow;
        _winningLine = line;
      }
    }
    _current = player.opponent;
    return captured;
  }

  /// Takes back the last move. Returns false if there is nothing to undo.
  bool undo() {
    if (_history.isEmpty) return false;
    final move = _history.removeLast();
    _set(move.point, null);
    for (final c in move.captured) {
      _set(c, move.player.opponent);
    }
    _captures[move.player] =
        _captures[move.player]! - move.captured.length ~/ 2;
    _current = move.player;
    _winner = null;
    _winReason = null;
    _winningLine = const [];
    return true;
  }

  /// Stones that placing [player] at [p] would capture (in pairs).
  List<Point> capturesFor(Point p, Player player) => _findCaptures(p, player);

  List<Point> _findCaptures(Point p, Player player) {
    final result = <Point>[];
    final foe = player.opponent;
    for (final (dr, dc) in _directions) {
      for (final sign in const [1, -1]) {
        final a = Point(p.row + dr * sign, p.col + dc * sign);
        final b = Point(p.row + 2 * dr * sign, p.col + 2 * dc * sign);
        final end = Point(p.row + 3 * dr * sign, p.col + 3 * dc * sign);
        if (inBounds(end) &&
            at(a) == foe &&
            at(b) == foe &&
            at(end) == player) {
          result
            ..add(a)
            ..add(b);
        }
      }
    }
    return result;
  }

  List<Point> _longestLineThrough(Point p, Player player) {
    var best = <Point>[];
    for (final (dr, dc) in _directions) {
      final line = <Point>[p];
      for (final sign in const [1, -1]) {
        var q = Point(p.row + dr * sign, p.col + dc * sign);
        while (inBounds(q) && at(q) == player) {
          if (sign == 1) {
            line.add(q);
          } else {
            line.insert(0, q);
          }
          q = Point(q.row + dr * sign, q.col + dc * sign);
        }
      }
      if (line.length > best.length) best = line;
    }
    return best;
  }

  /// A copy with the same position and history, for the computer to search.
  PenteGame copy() {
    final g = PenteGame(size: size, tournamentRule: tournamentRule);
    g._cells.setAll(0, _cells);
    g._history.addAll(_history);
    g._captures.addAll(_captures);
    g._current = _current;
    g._winner = _winner;
    g._winReason = _winReason;
    g._winningLine = _winningLine;
    return g;
  }
}
