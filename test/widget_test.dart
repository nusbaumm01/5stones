import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:five_stones/game/ai.dart';
import 'package:five_stones/game/game_controller.dart';
import 'package:five_stones/game/pente.dart';
import 'package:five_stones/main.dart';
import 'package:five_stones/screens/game_screen.dart';
import 'package:five_stones/widgets/board_view.dart';

/// Taps the board at intersection [p] (19x19 board).
Future<void> tapPoint(WidgetTester tester, Point p) async {
  final box = tester.getRect(find.byType(BoardView));
  final cell = box.width / 19;
  await tester.tapAt(
    box.topLeft + Offset((p.col + 0.5) * cell, (p.row + 0.5) * cell),
  );
  await tester.pump();
}

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('home screen offers both game modes', (tester) async {
    await tester.pumpWidget(const FiveStonesApp());
    expect(find.text('5Stones'), findsOneWidget);
    expect(find.text('Two players'), findsOneWidget);
    expect(find.text('Play the computer'), findsOneWidget);
    expect(find.text('Hard'), findsOneWidget);
  });

  testWidgets('two-player game: place stones, capture, undo', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = GameController(const GameSettings());
    await tester.pumpWidget(
      wrap(GameScreen(settings: const GameSettings(), controller: c)),
    );
    expect(find.text('White to move'), findsOneWidget);

    // Off-center first move is ignored.
    await tapPoint(tester, const Point(0, 0));
    expect(c.game.moveCount, 0);

    for (final p in const [
      Point(9, 9),
      Point(9, 10),
      Point(0, 0),
      Point(9, 11),
      Point(9, 12),
    ]) {
      await tapPoint(tester, p);
    }
    expect(c.game.moveCount, 5);
    expect(c.game.capturesOf(Player.one), 1);
    expect(find.text('Black to move'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undo')));
    await tester.pump();
    expect(c.game.capturesOf(Player.one), 0);
    expect(c.game.at(const Point(9, 10)), Player.two);

    await tester.tap(find.byKey(const Key('new-game')));
    await tester.pump();
    expect(c.game.moveCount, 0);
  });

  testWidgets('computer replies, and undo takes back both moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const settings = GameSettings(
      vsComputer: true,
      difficulty: Difficulty.easy,
    );
    // Run the computer synchronously so the test doesn't need isolates.
    final c = GameController(
      settings,
      aiMove: (g, d) async => PenteAi(d).chooseMove(g),
    );
    await tester.pumpWidget(
      wrap(GameScreen(settings: settings, controller: c)),
    );
    expect(find.text('Your move: start in the center'), findsOneWidget);

    await tapPoint(tester, const Point(9, 9));
    expect(find.text('Computer is thinking…'), findsOneWidget);
    // Taps are ignored while the computer thinks.
    await tapPoint(tester, const Point(3, 3));
    expect(c.game.at(const Point(3, 3)), isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(c.game.moveCount, 2);
    expect(find.text('Your move'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undo')));
    await tester.pump();
    expect(c.game.moveCount, 0);
  });

  testWidgets('computer moves first when the human chooses black', (
    tester,
  ) async {
    const settings = GameSettings(vsComputer: true, humanPlaysFirst: false);
    final c = GameController(
      settings,
      aiMove: (g, d) async => PenteAi(d).chooseMove(g),
    );
    await tester.pumpWidget(
      wrap(GameScreen(settings: settings, controller: c)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(c.game.at(const Point(9, 9)), Player.one);
    expect(c.canHumanMove, isTrue);
  });

  testWidgets('starting from home opens a game', (tester) async {
    await tester.pumpWidget(const FiveStonesApp());
    await tester.tap(find.byKey(const Key('play-two-players')));
    await tester.pumpAndSettle();
    expect(find.byType(BoardView), findsOneWidget);
    expect(find.text('White to move'), findsOneWidget);
  });

  test('onMove reports every stone, with captures', () {
    final moves = <Move>[];
    final c = GameController(
      const GameSettings(),
      onMove: (m, g) => moves.add(m),
    );
    for (final p in const [
      Point(9, 9),
      Point(9, 10),
      Point(0, 0),
      Point(9, 11),
      Point(9, 12),
    ]) {
      c.tap(p);
    }
    expect(moves.length, 5);
    expect(moves.last.captured.length, 2);
  });
}
