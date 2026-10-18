import 'package:flutter_test/flutter_test.dart';

import 'package:five_stones/game/pente.dart';

/// Plays [moves] alternately, starting with player one.
PenteGame playAll(List<(int, int)> moves, {bool tournamentRule = false}) {
  final g = PenteGame(tournamentRule: tournamentRule);
  for (final (r, c) in moves) {
    g.play(Point(r, c));
  }
  return g;
}

void main() {
  group('opening', () {
    test('player one moves first and must play the center', () {
      final g = PenteGame();
      expect(g.currentPlayer, Player.one);
      expect(g.validate(const Point(0, 0)), MoveError.firstMoveMustBeCenter);
      g.play(const Point(9, 9));
      expect(g.at(const Point(9, 9)), Player.one);
      expect(g.currentPlayer, Player.two);
    });

    test('occupied and off-board points are rejected', () {
      final g = playAll([(9, 9)]);
      expect(g.validate(const Point(9, 9)), MoveError.occupied);
      expect(g.validate(const Point(19, 0)), MoveError.outOfBounds);
      expect(() => g.play(const Point(9, 9)), throwsArgumentError);
    });

    test('tournament rule keeps player one\'s second stone away', () {
      final g = playAll([(9, 9), (9, 10)], tournamentRule: true);
      expect(g.validate(const Point(11, 11)), MoveError.tournamentRule);
      expect(g.validate(const Point(12, 9)), isNull);
      expect(g.validate(const Point(6, 6)), isNull);
      // Without the rule, anywhere goes.
      final free = playAll([(9, 9), (9, 10)]);
      expect(free.validate(const Point(11, 11)), isNull);
    });

    test('tournament rule only applies to that one move', () {
      final g = playAll([
        (9, 9),
        (9, 10),
        (12, 9),
        (8, 8),
      ], tournamentRule: true);
      expect(g.validate(const Point(10, 10)), isNull);
    });
  });

  group('captures', () {
    test('flanking exactly two stones captures them', () {
      // X O O _  -> X plays the end.
      final g = playAll([(9, 9), (9, 10), (0, 0), (9, 11)]);
      final captured = g.play(const Point(9, 12));
      expect(captured, containsAll([const Point(9, 10), const Point(9, 11)]));
      expect(g.at(const Point(9, 10)), isNull);
      expect(g.at(const Point(9, 11)), isNull);
      expect(g.capturesOf(Player.one), 1);
      expect(g.capturesOf(Player.two), 0);
    });

    test('captures work diagonally and from the inner end', () {
      // One at (9,9) and (6,12); two at (8,10),(7,11): diagonal.
      final g = playAll([(9, 9), (8, 10), (0, 0), (7, 11)]);
      g.play(const Point(6, 12));
      expect(g.capturesOf(Player.one), 1);
      expect(g.at(const Point(8, 10)), isNull);
    });

    test('three stones in a row cannot be captured', () {
      final g = playAll([(9, 9), (9, 10), (0, 0), (9, 11), (0, 2), (9, 12)]);
      g.play(const Point(9, 13));
      expect(g.capturesOf(Player.one), 0);
      expect(g.at(const Point(9, 10)), Player.two);
    });

    test('a single stone cannot be captured', () {
      final g = playAll([(9, 9), (9, 10)]);
      g.play(const Point(9, 11));
      expect(g.capturesOf(Player.one), 0);
      expect(g.at(const Point(9, 10)), Player.two);
    });

    test('moving into a flanked spot is safe', () {
      // One at (9,9) and (9,12); two fills (9,10) then (9,11).
      final g = playAll([(9, 9), (9, 10), (9, 12), (0, 0), (0, 2)]);
      g.play(const Point(9, 11));
      expect(g.at(const Point(9, 10)), Player.two);
      expect(g.at(const Point(9, 11)), Player.two);
      expect(g.capturesOf(Player.one), 0);
    });

    test('one move can capture two pairs at once', () {
      // Two pairs to the right and below of (5,5).
      final g = playAll([
        (9, 9), (5, 6), //
        (5, 8), (5, 7),
        (8, 5), (6, 5),
        (0, 0), (7, 5),
      ]);
      final captured = g.play(const Point(5, 5));
      expect(captured.length, 4);
      expect(g.capturesOf(Player.one), 2);
    });

    test('five captured pairs wins', () {
      final g = PenteGame();
      g.play(const Point(9, 9));
      // Player two keeps feeding pairs in row r: (r,1),(r,2) flanked by
      // player one at (r,0) and (r,3).
      var spare = 0;
      for (var r = 0; r < 5; r++) {
        g.play(Point(r * 2, 1)); // two
        g.play(Point(r * 2, 0)); // one
        g.play(Point(r * 2, 2)); // two
        expect(g.winner, isNull);
        g.play(Point(r * 2, 3)); // one captures
        if (r < 4) {
          g.play(Point(18, spare)); // two passes time
          g.play(Point(16, spare)); // one passes time
          spare += 2;
        }
      }
      expect(g.capturesOf(Player.one), 5);
      expect(g.winner, Player.one);
      expect(g.winReason, WinReason.fiveCaptures);
      expect(g.isOver, isTrue);
    });
  });

  group('five in a row', () {
    test('horizontal five wins', () {
      final g = playAll([
        (9, 9),
        (0, 0),
        (9, 10),
        (0, 2),
        (9, 11),
        (0, 4),
        (9, 12),
        (0, 6),
      ]);
      expect(g.winner, isNull);
      g.play(const Point(9, 13));
      expect(g.winner, Player.one);
      expect(g.winReason, WinReason.fiveInARow);
      expect(g.winningLine.length, 5);
      expect(g.validate(const Point(1, 1)), MoveError.gameOver);
    });

    test('diagonal five wins for player two', () {
      final g = playAll([
        (9, 9),
        (0, 0),
        (18, 0),
        (1, 1),
        (18, 2),
        (2, 2),
        (18, 4),
        (3, 3),
        (18, 6),
      ]);
      g.play(const Point(4, 4));
      expect(g.winner, Player.two);
    });

    test('anti-diagonal five wins', () {
      final g = playAll([
        (9, 9),
        (0, 0),
        (8, 10),
        (0, 2),
        (7, 11),
        (0, 4),
        (6, 12),
        (0, 6),
      ]);
      g.play(const Point(5, 13));
      expect(g.winner, Player.one);
    });

    test('more than five in a row also wins', () {
      // Fill a gap to make six.
      final g = playAll([
        (9, 9),
        (0, 0),
        (9, 10),
        (0, 2),
        (9, 12),
        (0, 4),
        (9, 13),
        (0, 6),
        (9, 14),
        (0, 8),
      ]);
      g.play(const Point(9, 11));
      expect(g.winner, Player.one);
      expect(g.winningLine.length, 6);
    });

    test('four in a row does not win', () {
      final g = playAll([
        (9, 9),
        (0, 0),
        (9, 10),
        (0, 2),
        (9, 11),
        (0, 4),
        (9, 12),
      ]);
      expect(g.winner, isNull);
    });
  });

  group('undo', () {
    test('undo restores captured stones and turn', () {
      final g = playAll([(9, 9), (9, 10), (0, 0), (9, 11), (9, 12)]);
      expect(g.capturesOf(Player.one), 1);
      expect(g.undo(), isTrue);
      expect(g.at(const Point(9, 10)), Player.two);
      expect(g.at(const Point(9, 11)), Player.two);
      expect(g.at(const Point(9, 12)), isNull);
      expect(g.capturesOf(Player.one), 0);
      expect(g.currentPlayer, Player.one);
    });

    test('undo clears a win', () {
      final g = playAll([
        (9, 9),
        (0, 0),
        (9, 10),
        (0, 2),
        (9, 11),
        (0, 4),
        (9, 12),
        (0, 6),
        (9, 13),
      ]);
      expect(g.winner, Player.one);
      g.undo();
      expect(g.winner, isNull);
      expect(g.winningLine, isEmpty);
      expect(g.isLegal(const Point(9, 13)), isTrue);
    });

    test('undo on a new game does nothing', () {
      expect(PenteGame().undo(), isFalse);
    });
  });

  test('copy is independent of the original', () {
    final g = playAll([(9, 9), (9, 10)]);
    final c = g.copy();
    c.play(const Point(5, 5));
    expect(g.at(const Point(5, 5)), isNull);
    expect(g.moveCount, 2);
    expect(c.moveCount, 3);
    c.undo();
    c.undo();
    expect(g.at(const Point(9, 10)), Player.two);
  });

  test('legal moves on the first turn is just the center', () {
    expect(PenteGame().legalMoves().toList(), [const Point(9, 9)]);
  });
}
