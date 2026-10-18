import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/pente.dart';
import '../widgets/board_view.dart';
import 'home_screen.dart' show showRules;

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.settings, this.controller});

  final GameSettings settings;

  /// For tests: supply a controller instead of creating one.
  final GameController? controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController _c =
      widget.controller ?? GameController(widget.settings);

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  String _name(Player p) {
    final color = p == Player.one ? 'White' : 'Black';
    final cpu = widget.settings.computerPlayer;
    if (cpu == null) return color;
    return p == cpu ? 'Computer' : 'You';
  }

  String _status(PenteGame g) {
    if (g.winner != null) {
      final w = g.winner!;
      final how = g.winReason == WinReason.fiveCaptures
          ? 'five captures'
          : 'five in a row';
      final who = _name(w);
      return who == 'You' ? 'You win with $how!' : '$who wins with $how!';
    }
    if (g.isDraw) return 'Draw: the board is full.';
    if (_c.computerThinking) return 'Computer is thinking…';
    final who = _name(g.currentPlayer);
    if (g.moveCount == 0) {
      return who == 'You' ? 'Your move: start in the center' : '$who to move';
    }
    if (g.tournamentRule && g.moveCount == 2) {
      final note = '(3+ points from center)';
      return who == 'You' ? 'Your move $note' : '$who to move $note';
    }
    return who == 'You' ? 'Your move' : '$who to move';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final title = s.vsComputer
        ? 'Versus computer · ${s.difficulty.label}'
        : 'Two players';
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final g = _c.game;
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                tooltip: 'How to play',
                onPressed: () => showRules(context),
                icon: const Icon(Icons.help_outline),
              ),
              IconButton(
                key: const Key('undo'),
                tooltip: 'Undo',
                onPressed: _c.canUndo ? _c.undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                key: const Key('new-game'),
                tooltip: 'New game',
                onPressed: _c.newGame,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth > box.maxHeight * 1.25;
                final board = Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: BoardView(
                      game: g,
                      enabled: _c.canHumanMove,
                      onTap: _c.tap,
                    ),
                  ),
                );
                final panel = _InfoPanel(
                  status: _status(g),
                  game: g,
                  nameOf: _name,
                  thinking: _c.computerThinking,
                  wide: wide,
                  onNewGame: g.isOver ? _c.newGame : null,
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
            ),
          ),
        );
      },
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.status,
    required this.game,
    required this.nameOf,
    required this.thinking,
    required this.wide,
    this.onNewGame,
  });

  final String status;
  final PenteGame game;
  final String Function(Player) nameOf;
  final bool thinking;
  final bool wide;
  final VoidCallback? onNewGame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final players = [
      for (final p in Player.values)
        _PlayerRow(
          name: nameOf(p),
          player: p,
          captures: game.capturesOf(p),
          active: !game.isOver && game.currentPlayer == p,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        mainAxisAlignment: wide
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (thinking) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  status,
                  key: const Key('status'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: game.isOver ? FontWeight.bold : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (wide)
            ...players
          else
            Row(children: [for (final row in players) Expanded(child: row)]),
          if (onNewGame != null) ...[
            const SizedBox(height: 8),
            Center(
              child: FilledButton(
                onPressed: onNewGame,
                child: const Text('Play again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.player,
    required this.captures,
    required this.active,
  });

  final String name;
  final Player player;
  final int captures;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: active
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          _Dot(color: stoneColor(player), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Tooltip(
            message: '$captures of 5 pairs captured',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: _Dot(
                      color: i < captures
                          ? stoneColor(player.opponent)
                          : Colors.transparent,
                      size: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade600, width: 1),
      ),
    );
  }
}
