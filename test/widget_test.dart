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
  final box = tester.getRect(find.byKey(BoardView.boardKey));
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

  testWidgets('zoomed in, taps still land on the right intersection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = GameController(const GameSettings());
    await tester.pumpWidget(
      wrap(GameScreen(settings: const GameSettings(), controller: c)),
    );
    expect(find.text('Pinch, scroll or use + to zoom'), findsOneWidget);

    // Zoom in twice around the board's middle: 1.5 x 1.5 = 2.25x.
    await tester.tap(find.byKey(const Key('zoom-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zoom-in')));
    await tester.pumpAndSettle();
    expect(find.text('Drag to move around'), findsOneWidget);

    const scale = 2.25;
    final box = tester.getRect(find.byKey(BoardView.boardKey));
    final cell = box.width / 19;
    Future<void> tapZoomed(Point p) async {
      final board = Offset((p.col + 0.5) * cell, (p.row + 0.5) * cell);
      final mid = box.width / 2;
      final onScreen = Offset(
        mid + (board.dx - mid) * scale,
        mid + (board.dy - mid) * scale,
      );
      await tester.tapAt(box.topLeft + onScreen);
      await tester.pump();
    }

    await tapZoomed(const Point(9, 9));
    await tapZoomed(const Point(10, 11));
    await tapZoomed(const Point(7, 6));
    expect(c.game.at(const Point(9, 9)), Player.one);
    expect(c.game.at(const Point(10, 11)), Player.two);
    expect(c.game.at(const Point(7, 6)), Player.one);

    // Without zoom, that last screen spot would have been a different point.
    expect(c.game.moveCount, 3);

    // Dragging pans the board and does not place a stone.
    await tester.drag(find.byKey(BoardView.boardKey), const Offset(120, 80));
    await tester.pumpAndSettle();
    expect(c.game.moveCount, 3);

    // Reset shows the whole board again, and plain taps work as before.
    await tester.tap(find.byKey(const Key('zoom-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Pinch, scroll or use + to zoom'), findsOneWidget);
    await tapPoint(tester, const Point(12, 12));
    expect(c.game.at(const Point(12, 12)), Player.two);
  });

  testWidgets('resizing while zoomed keeps the board filling the view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = GameController(const GameSettings());
    await tester.pumpWidget(
      wrap(GameScreen(settings: const GameSettings(), controller: c)),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('zoom-in')));
      await tester.pumpAndSettle();
    }
    // Pan all the way to the bottom-right corner.
    await tester.drag(
      find.byKey(BoardView.boardKey),
      const Offset(-2000, -2000),
    );
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(600, 1000);
    await tester.pumpAndSettle();

    final side = tester.getSize(find.byKey(BoardView.boardKey)).width;
    final m = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    final scale = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    // Still zoomed, and not panned past the board's edge.
    expect(scale, closeTo(BoardView.maxZoom, 0.01));
    expect(t.x, greaterThanOrEqualTo(side - side * scale - 0.01));
    expect(t.y, greaterThanOrEqualTo(side - side * scale - 0.01));
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

  test('computer still moves if its search fails', () async {
    const settings = GameSettings(vsComputer: true);
    final c = GameController(
      settings,
      aiMove: (g, d) async => throw StateError('boom'),
    );
    c.tap(const Point(9, 9));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(c.game.moveCount, 2);
    expect(c.computerThinking, isFalse);
    expect(c.canHumanMove, isTrue);
  });

  test('computer still moves if it suggests an illegal point', () async {
    const settings = GameSettings(vsComputer: true);
    final c = GameController(
      settings,
      aiMove: (g, d) async => const Point(9, 9), // already taken
    );
    c.tap(const Point(9, 9));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(c.game.moveCount, 2);
    expect(c.canHumanMove, isTrue);
  });
}
