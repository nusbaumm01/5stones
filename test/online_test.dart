import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:five_stones/game/pente.dart';
import 'package:five_stones/main.dart';
import 'package:five_stones/online/firebase_rest.dart';
import 'package:five_stones/online/online_game.dart';

void main() {
  test('game codes are 6 easy-to-read characters', () {
    final r = Random(1);
    for (var i = 0; i < 100; i++) {
      final code = newGameCode(r);
      expect(isValidCode(code), isTrue, reason: code);
      expect(code, isNot(matches(RegExp('[01IO]'))));
    }
    expect(normalizeCode(' k7p-3qx '), 'K7P3QX');
    expect(isValidCode('K7P3Q'), isFalse);
    expect(isValidCode('K7P3Q0'), isFalse);
  });

  test('reads server-sent events', () async {
    const body =
        'event: put\ndata: {"path":"/","data":{"a":1}}\n\n'
        'event: keep-alive\ndata: null\n\n'
        'event: patch\ndata: {"path":"/","data":{"b":2}}\n\n';
    final events = await parseServerSentEvents(
      Stream.fromIterable([
        utf8.encode(body.substring(0, 20)),
        utf8.encode(body.substring(20)),
      ]),
    ).toList();
    expect(events.map((e) => e.name), ['put', 'keep-alive', 'patch']);
    expect(jsonDecode(events.first.data), {
      'path': '/',
      'data': {'a': 1},
    });
  });

  test('applies put and patch updates to a local copy', () {
    final t = JsonTree();
    t.apply('/', {'host': 'h', 'moveCount': 0});
    t.apply('/', {
      'moves/0': {'r': 9, 'c': 9},
      'moveCount': 1,
    }, merge: true);
    t.apply('/guest', 'g');
    expect(t.value, {
      'host': 'h',
      'guest': 'g',
      'moveCount': 1,
      'moves': {
        '0': {'r': 9, 'c': 9},
      },
    });
    t.apply('/guest', null);
    expect((t.value as Map).containsKey('guest'), isFalse);
    // Firebase may send numbered children as a list.
    t.apply('/moves', [
      {'r': 9, 'c': 9},
      {'r': 9, 'c': 10},
    ]);
    t.apply('/moves/2', {'r': 1, 'c': 1});
    final s = OnlineGameState.tryParse(t.value)!;
    expect(s.moves, const [Point(9, 9), Point(9, 10), Point(1, 1)]);
  });

  test('decodes game data and player colors', () {
    final s = OnlineGameState.tryParse({
      'host': 'h',
      'guest': 'g',
      'hostColor': 'two',
      'round': 2,
      'moveCount': 1,
      'moves': [
        {'r': 9, 'c': 9},
      ],
      'rematch': {'h': 2, 'g': 1},
      'left': {'g': true},
    })!;
    expect(s.colorOf('h'), Player.two);
    expect(s.colorOf('g'), Player.one);
    expect(s.moves, const [Point(9, 9)]);
    expect(s.rematch, {'h': 2, 'g': 1});
    expect(s.left, {'g'});
    expect(OnlineGameState.tryParse(null), isNull);
    expect(OnlineGameState.tryParse({'moveCount': 0}), isNull);
  });

  testWidgets('home screen offers online play', (tester) async {
    await tester.pumpWidget(const FiveStonesApp());
    await tester.tap(find.byKey(const Key('play-online')));
    await tester.pumpAndSettle();
    // Test builds have no Firebase project, so online play is off.
    expect(find.textContaining("isn't switched on"), findsOneWidget);
  });
}
