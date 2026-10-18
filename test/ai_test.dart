import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:five_stones/game/ai.dart';
import 'package:five_stones/game/pente.dart';

PenteGame playAll(List<(int, int)> moves) {
  final g = PenteGame();
  for (final (r, c) in moves) {
    g.play(Point(r, c));
  }
  return g;
}

void main() {
  for (final level in Difficulty.values) {
    group(level.label, () {
      test('completes five in a row when it can', () {
        // Player one has four in a row; it's player one's turn.
        final g = playAll([
          (9, 9),
          (3, 3),
          (9, 10),
          (3, 5),
          (9, 11),
          (3, 7),
          (9, 12),
          (3, 9),
        ]);
        final move = PenteAi(level, random: Random(1)).chooseMove(g);
        g.play(move);
        expect(g.winner, Player.one);
      });

      test('takes the fifth capture to win', () {
        final g = PenteGame();
        g.play(const Point(9, 9));
        var spare = 0;
        for (var r = 0; r < 4; r++) {
          g.play(Point(r * 2, 1));
          g.play(Point(r * 2, 0));
          g.play(Point(r * 2, 2));
          g.play(Point(r * 2, 3));
          g.play(Point(18, spare));
          g.play(Point(16, spare));
          spare += 3;
        }
        // Set up a fifth capturable pair: one at (12,0), two at (12,1),(12,2).
        g.play(const Point(12, 1));
        g.play(const Point(12, 0));
        g.play(const Point(12, 2));
        expect(g.capturesOf(Player.one), 4);
        final move = PenteAi(level, random: Random(1)).chooseMove(g);
        g.play(move);
        expect(g.winner, Player.one);
      });
    });
  }

  for (final level in [Difficulty.medium, Difficulty.hard]) {
    test('${level.label} blocks an open four', () {
      // Player two has an open three-to-four; one must block.
      final g = playAll([
        (9, 9),
        (5, 5),
        (12, 12),
        (5, 6),
        (14, 3),
        (5, 7),
        (2, 15),
        (5, 8),
      ]);
      final move = PenteAi(level, random: Random(1)).chooseMove(g);
      expect(move, anyOf(const Point(5, 4), const Point(5, 9)));
    });
  }

  test('hard thinks fast enough in the midgame', () {
    final g = playAll([
      (9, 9),
      (9, 10),
      (10, 10),
      (8, 8),
      (10, 9),
      (10, 8),
      (11, 9),
      (8, 9),
      (12, 9),
      (13, 9),
      (11, 11),
      (12, 12),
    ]);
    final sw = Stopwatch()..start();
    PenteAi(Difficulty.hard).chooseMove(g);
    sw.stop();
    // Generous limit for slow CI machines running in debug mode.
    expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('hard beats easy in most games', () {
    var hardWins = 0;
    const games = 4;
    for (var i = 0; i < games; i++) {
      final g = PenteGame();
      final hardIsOne = i.isEven;
      final hard = PenteAi(Difficulty.hard, random: Random(i));
      final easy = PenteAi(Difficulty.easy, random: Random(100 + i));
      while (!g.isOver && g.moveCount < 120) {
        final hardTurn = (g.currentPlayer == Player.one) == hardIsOne;
        g.play((hardTurn ? hard : easy).chooseMove(g));
      }
      final hardPlayer = hardIsOne ? Player.one : Player.two;
      if (g.winner == hardPlayer) hardWins++;
    }
    expect(hardWins, greaterThanOrEqualTo(3));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
