import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ai.dart';
import 'pente.dart';

/// Game options picked on the home screen.
class GameSettings {
  const GameSettings({
    this.vsComputer = false,
    this.difficulty = Difficulty.medium,
    this.humanPlaysFirst = true,
    this.tournamentRule = false,
  });

  final bool vsComputer;
  final Difficulty difficulty;
  final bool humanPlaysFirst;
  final bool tournamentRule;

  /// The player the computer controls, or null in a two-player game.
  Player? get computerPlayer =>
      vsComputer ? (humanPlaysFirst ? Player.two : Player.one) : null;
}

/// Runs one game: human moves, the computer's turns, undo and restart.
class GameController extends ChangeNotifier {
  GameController(
    this.settings, {
    Future<Point> Function(PenteGame, Difficulty)? aiMove,
    this.onMove,
  }) : _aiMove = aiMove ?? _defaultAiMove {
    _game = PenteGame(tournamentRule: settings.tournamentRule);
    _maybeComputerTurn();
  }

  final GameSettings settings;

  /// Called after every stone is placed, by a person or the computer.
  final void Function(Move move, PenteGame game)? onMove;
  final Future<Point> Function(PenteGame, Difficulty) _aiMove;
  late PenteGame _game;

  bool _thinking = false;
  int _generation = 0;
  bool _disposed = false;

  PenteGame get game => _game;
  bool get computerThinking => _thinking;

  bool get isComputerTurn =>
      !_game.isOver && _game.currentPlayer == settings.computerPlayer;

  bool get canHumanMove => !_game.isOver && !isComputerTurn && !_thinking;

  bool get canUndo {
    if (_thinking) return false;
    if (settings.computerPlayer == null) return _game.moveCount > 0;
    // Undo takes back to the human's previous turn.
    return _game.history.any((m) => m.player != settings.computerPlayer);
  }

  static Future<Point> _defaultAiMove(PenteGame game, Difficulty d) {
    final seed = Random().nextInt(1 << 31);
    if (kIsWeb) {
      return Future(() => computeAiMove((game.copy(), d, seed)));
    }
    return compute(computeAiMove, (game.copy(), d, seed));
  }

  /// Plays at [p] for the human. Returns false if the move isn't allowed.
  bool tap(Point p) {
    if (!canHumanMove || !_game.isLegal(p)) return false;
    _game.play(p);
    onMove?.call(_game.lastMove!, _game);
    _changed();
    _maybeComputerTurn();
    return true;
  }

  void undo() {
    if (!canUndo) return;
    _generation++;
    _game.undo();
    while (settings.computerPlayer != null &&
        _game.moveCount > 0 &&
        _game.currentPlayer == settings.computerPlayer) {
      _game.undo();
    }
    _changed();
    _maybeComputerTurn();
  }

  void newGame() {
    _generation++;
    _thinking = false;
    _game = PenteGame(tournamentRule: settings.tournamentRule);
    _changed();
    _maybeComputerTurn();
  }

  Future<void> _maybeComputerTurn() async {
    if (!isComputerTurn || _thinking) return;
    final gen = _generation;
    _thinking = true;
    _changed();
    // A short pause so the computer's reply doesn't feel instant.
    final pause = Future<void>.delayed(const Duration(milliseconds: 350));
    final move = await _aiMove(_game, settings.difficulty);
    await pause;
    if (_disposed || gen != _generation) return;
    _thinking = false;
    if (_game.isLegal(move)) {
      _game.play(move);
      onMove?.call(_game.lastMove!, _game);
    }
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
