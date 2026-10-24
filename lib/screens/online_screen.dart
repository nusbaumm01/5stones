import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/pente.dart';
import '../online/firebase_rest.dart';
import '../online/online_game.dart';
import '../sound.dart';
import '../widgets/board_view.dart';
import 'game_screen.dart' show InfoPanel;
import 'home_screen.dart' show showRules;

/// Start an online game or join one with a code.
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({
    super.key,
    required this.service,
    this.tournamentRule = false,
  });

  final OnlineService service;
  final bool tournamentRule;

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  final _code = TextEditingController();
  bool _hostFirst = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await action();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OnlineGameScreen(service: widget.service, code: code),
        ),
      );
    } on JoinException catch (e) {
      _error = e.message;
    } on FirebaseException catch (e) {
      debugPrint('$e');
      _error = 'Something went wrong talking to the server. Try again.';
    } catch (e) {
      debugPrint('$e');
      _error = 'Could not connect. Check your internet connection.';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _create() => _run(
    () => widget.service.createGame(
      hostPlaysFirst: _hostFirst,
      tournament: widget.tournamentRule,
    ),
  );

  void _join() {
    final code = normalizeCode(_code.text);
    if (!isValidCode(code)) {
      setState(() => _error = 'Game codes are 6 letters and numbers.');
      return;
    }
    _run(() async {
      await widget.service.joinGame(code);
      return code;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Play online')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Start a game',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "You'll get a code to send to your friend.",
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('I go first'),
                            subtitle: Text(
                              _hostFirst ? 'You play white' : 'You play black',
                            ),
                            value: _hostFirst,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _hostFirst = v),
                          ),
                          FilledButton.icon(
                            key: const Key('create-online'),
                            onPressed: _busy ? null : _create,
                            icon: const Icon(Icons.add),
                            label: const Text('Create game'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Join a game',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('join-code'),
                            controller: _code,
                            enabled: !_busy,
                            textCapitalization: TextCapitalization.characters,
                            autocorrect: false,
                            maxLength: 7,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              letterSpacing: 4,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'CODE',
                              counterText: '',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _join(),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            key: const Key('join-online'),
                            onPressed: _busy ? null : _join,
                            icon: const Icon(Icons.login),
                            label: const Text('Join'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const Key('online-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains that this build can't play online yet.
class OnlineUnavailableScreen extends StatelessWidget {
  const OnlineUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Play online')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Online play isn't switched on in this version of the app yet.",
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// An online game: waits for the opponent, then shows the board.
class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({
    super.key,
    required this.service,
    required this.code,
    this.controller,
  });

  final OnlineService service;
  final String code;

  /// For tests: supply a controller instead of creating one.
  final OnlineGameController? controller;

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  late final OnlineGameController _c =
      widget.controller ?? widget.service.open(widget.code, onMove: _playSound);
  final SoundService _sound = SoundService.instance;

  static void _playSound(Move move, PenteGame game) {
    final sfx = game.winner != null
        ? Sfx.win
        : move.captured.isNotEmpty
        ? Sfx.capture
        : Sfx.place;
    SoundService.instance.play(sfx);
  }

  @override
  void dispose() {
    _c.leave();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  String _name(Player p) => p == _c.myColor ? 'You' : 'Opponent';

  String _status(PenteGame g) {
    if (g.winner != null) {
      final how = g.winReason == WinReason.fiveCaptures
          ? 'five captures'
          : 'five in a row';
      return g.winner == _c.myColor
          ? 'You win with $how!'
          : 'Opponent wins with $how!';
    }
    if (g.isDraw) return 'Draw: the board is full.';
    if (!_c.isMyTurn) return "Opponent's move";
    if (g.moveCount == 0) return 'Your move: start in the center';
    if (g.tournamentRule && g.moveCount == 2) {
      return 'Your move (3+ points from center)';
    }
    return 'Your move';
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _sound]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Online · ${widget.code}'),
            actions: [
              IconButton(
                tooltip: _sound.enabled ? 'Mute sound' : 'Turn sound on',
                onPressed: () => _sound.setEnabled(!_sound.enabled),
                icon: Icon(_sound.enabled ? Icons.volume_up : Icons.volume_off),
              ),
              IconButton(
                tooltip: 'How to play',
                onPressed: () => showRules(context),
                icon: const Icon(Icons.help_outline),
              ),
            ],
          ),
          body: SafeArea(child: _body(context)),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (_c.status) {
      case OnlineStatus.connecting:
        return const Center(child: CircularProgressIndicator());
      case OnlineStatus.error:
        return _message(context, _c.error ?? 'Something went wrong.');
      case OnlineStatus.waitingForOpponent:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Send this code to your friend',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  widget.code,
                  key: const Key('game-code'),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy code'),
                ),
                const SizedBox(height: 24),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Waiting for them to join…'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'They open 5Stones, tap Play online, and enter the code.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      case OnlineStatus.opponentLeft:
      case OnlineStatus.playing:
        return _game(context);
    }
  }

  Widget _message(BuildContext context, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    ),
  );

  Widget _game(BuildContext context) {
    final g = _c.game;
    final left = _c.status == OnlineStatus.opponentLeft;
    Widget? extra;
    VoidCallback? onRematch;
    var rematchLabel = 'Play again';
    if (left) {
      extra = const Text(
        'Your opponent left the game.',
        key: Key('opponent-left'),
        textAlign: TextAlign.center,
      );
    } else if (g.isOver) {
      if (_c.iAskedRematch) {
        extra = const Text(
          'Waiting for your opponent to accept…',
          textAlign: TextAlign.center,
        );
      } else {
        onRematch = _c.requestRematch;
        if (_c.opponentAskedRematch) {
          rematchLabel = 'Accept rematch';
          extra = const Text(
            'Your opponent wants a rematch.',
            textAlign: TextAlign.center,
          );
        }
      }
    }
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight * 1.25;
        final board = Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: BoardView(game: g, enabled: _c.canMove, onTap: _c.tap),
          ),
        );
        final panel = InfoPanel(
          status: left && !g.isOver ? 'Game ended' : _status(g),
          game: g,
          nameOf: _name,
          thinking: !g.isOver && !left && !_c.isMyTurn,
          wide: wide,
          onNewGame: onRematch,
          newGameLabel: rematchLabel,
          extra: extra,
        );
        return wide
            ? Row(
                children: [
                  Expanded(child: board),
                  SizedBox(width: 260, child: panel),
                ],
              )
            : Column(
                children: [
                  panel,
                  Expanded(child: board),
                ],
              );
      },
    );
  }
}
