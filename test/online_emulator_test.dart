// Online play against the local Firebase emulator. Run with:
//   firebase emulators:exec --only auth,database --project demo-5stones \
//     "flutter test test/online_emulator_test.dart"
// Skipped when the emulator isn't running.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:five_stones/game/pente.dart';
import 'package:five_stones/online/firebase_rest.dart';
import 'package:five_stones/online/online_game.dart';

final bool emulator =
    Platform.environment['FIREBASE_DATABASE_EMULATOR_HOST'] != null;

OnlineService player() => OnlineService(FirebaseConfig.emulator());

Future<void> until(bool Function() ok, {String? what}) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('two players create, join, play, and rematch', () async {
    final alice = player();
    final bob = player();
    final code = await alice.createGame(
      hostPlaysFirst: true,
      tournament: false,
    );
    expect(isValidCode(code), isTrue);

    final a = alice.open(code);
    await until(
      () => a.status == OnlineStatus.waitingForOpponent,
      what: 'host to see the new game',
    );

    await bob.joinGame(code);
    final b = bob.open(code);
    await until(
      () =>
          a.status == OnlineStatus.playing && b.status == OnlineStatus.playing,
      what: 'both to be playing',
    );
    expect(a.myColor, Player.one);
    expect(b.myColor, Player.two);
    expect(a.isMyTurn, isTrue);
    expect(b.isMyTurn, isFalse);

    // Black can't move first.
    expect(b.tap(const Point(9, 9)), isFalse);

    // White builds five in a row while black plays elsewhere.
    for (var i = 0; i < 5; i++) {
      expect(a.tap(Point(9, 9 + i)), isTrue, reason: 'white move $i');
      await until(() => b.game.moveCount == 2 * i + 1, what: 'black sees');
      if (i == 4) break;
      expect(b.tap(Point(0, i)), isTrue, reason: 'black move $i');
      await until(() => a.game.moveCount == 2 * i + 2, what: 'white sees');
    }
    expect(b.game.winner, Player.one);
    expect(a.game.winner, Player.one);

    // Both ask for a rematch: a fresh board with colors swapped.
    await b.requestRematch();
    await until(() => a.opponentAskedRematch, what: 'rematch request');
    await a.requestRematch();
    await until(
      () => a.state!.round == 1 && b.state!.round == 1 && b.game.moveCount == 0,
      what: 'new round',
    );
    expect(a.myColor, Player.two);
    expect(b.myColor, Player.one);
    expect(b.tap(const Point(9, 9)), isTrue);
    await until(() => a.game.moveCount == 1, what: 'first move of round 2');

    // Leaving shows up for the other player.
    await b.leave();
    await until(
      () => a.status == OnlineStatus.opponentLeft,
      what: 'leave notice',
    );

    a.dispose();
    b.dispose();
  }, skip: emulator ? false : 'Firebase emulator not running');

  test('server rules stop cheating and a third player joining', () async {
    final alice = player();
    final bob = player();
    final carol = player();
    final code = await alice.createGame(
      hostPlaysFirst: false,
      tournament: false,
    );
    await bob.joinGame(code);
    // Joining again is fine (rejoin), but a third person can't.
    await bob.joinGame(code);
    await expectLater(
      carol.joinGame(code),
      throwsA(
        isA<JoinException>().having((e) => e.error, 'error', JoinError.full),
      ),
    );

    Future<void> move(OnlineService who, int n, int r, int c) =>
        who.db.patch('games/$code', {
          'moves/$n': {'r': r, 'c': c},
          'moveCount': n + 1,
        });
    Matcher denied = throwsA(
      isA<FirebaseException>().having(
        (e) => e.permissionDenied,
        'denied',
        true,
      ),
    );

    // Bob plays white this time. The host can't move for him.
    await expectLater(move(alice, 0, 9, 9), denied);
    await expectLater(move(carol, 0, 9, 9), denied);
    await move(bob, 0, 9, 9);
    // Not Bob's turn now, and moves can't skip numbers or be rewritten.
    await expectLater(move(bob, 1, 9, 10), denied);
    await expectLater(move(alice, 0, 9, 10), denied);
    await expectLater(move(alice, 2, 9, 10), denied);
    await move(alice, 1, 9, 10);

    // The guest can't take over or reset the game.
    await expectLater(bob.db.put('games/$code/host', bob.auth.uid), denied);
    await expectLater(bob.db.put('games/$code/moveCount', 0), denied);
    await expectLater(
      carol.db.put('games/$code', {
        'host': carol.auth.uid,
        'hostColor': 'one',
        'tournament': false,
        'round': 0,
        'moveCount': 0,
        'createdAt': 0,
      }),
      denied,
    );
    // Nobody can list every game.
    await expectLater(carol.db.get('games'), denied);

    // The host can't rewrite the game either: swap colors to take Bob's
    // turn, wipe the board, speak for Bob, or delete the game.
    await expectLater(
      alice.db.patch('games/$code', {'hostColor': 'one'}),
      denied,
    );
    await expectLater(
      alice.db.patch('games/$code', {'moves': null, 'moveCount': 0}),
      denied,
    );
    await expectLater(alice.db.put('games/$code/moveCount', 0), denied);
    await expectLater(
      alice.db.put('games/$code/rematch/${bob.auth.uid}', 0),
      denied,
    );
    await expectLater(
      alice.db.put('games/$code/left/${bob.auth.uid}', true),
      denied,
    );
    await expectLater(alice.db.put('games/$code', null), denied);
    // A new round needs both players to ask for it first.
    await expectLater(
      alice.db.put('games/$code', {
        'host': alice.auth.uid,
        'guest': bob.auth.uid,
        'hostColor': 'one',
        'tournament': false,
        'round': 1,
        'moveCount': 0,
        'createdAt': 0,
      }),
      denied,
    );

    final s = OnlineGameState.tryParse(await carol.db.get('games/$code'))!;
    expect(s.moves, const [Point(9, 9), Point(9, 10)]);
  }, skip: emulator ? false : 'Firebase emulator not running');

  test('a move the rules do not allow stops the game with a message', () async {
    final alice = player();
    final bob = player();
    final code = await alice.createGame(
      hostPlaysFirst: true,
      tournament: false,
    );
    await bob.joinGame(code);
    final a = alice.open(code);
    await until(() => a.status == OnlineStatus.playing, what: 'playing');
    expect(a.tap(const Point(9, 9)), isTrue);
    await until(() => !a.sending, what: 'move sent');

    // A changed app plays on the occupied center point. The server can't
    // check that, so the honest player's app has to.
    await bob.db.patch('games/$code', {
      'moves/1': {'r': 9, 'c': 9},
      'moveCount': 2,
    });
    await until(() => a.status == OnlineStatus.error, what: 'out of sync');
    expect(a.error, OnlineGameController.outOfSyncMessage);
    expect(a.canMove, isFalse);
    a.dispose();
  }, skip: emulator ? false : 'Firebase emulator not running');

  test('joining a code that does not exist', () async {
    await expectLater(
      player().joinGame('ZZZZZZ'),
      throwsA(
        isA<JoinException>().having(
          (e) => e.error,
          'error',
          JoinError.notFound,
        ),
      ),
    );
  }, skip: emulator ? false : 'Firebase emulator not running');
}
