import 'package:flutter/material.dart';

import '../game/pente.dart';

/// Colors for each player's stones.
const Color stoneOneColor = Color(0xFFF7F3EA); // white, moves first
const Color stoneTwoColor = Color(0xFF1E1E22); // black

Color stoneColor(Player p) => p == Player.one ? stoneOneColor : stoneTwoColor;

/// The wooden board with its stones. Tap or click an intersection to play.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.game,
    required this.onTap,
    this.enabled = true,
  });

  final PenteGame game;
  final void Function(Point) onTap;
  final bool enabled;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  Point? _hover;

  Point? _pointAt(Offset local, double side) {
    final n = widget.game.size;
    final cell = side / n;
    final col = (local.dx / cell).floor();
    final row = (local.dy / cell).floor();
    final p = Point(row, col);
    return widget.game.inBounds(p) ? p : null;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          return MouseRegion(
            cursor: widget.enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onHover: (e) {
              final p = _pointAt(e.localPosition, side);
              if (p != _hover) setState(() => _hover = p);
            },
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final p = _pointAt(d.localPosition, side);
                if (p != null && widget.enabled) widget.onTap(p);
              },
              child: CustomPaint(
                size: Size.square(side),
                painter: _BoardPainter(
                  game: widget.game,
                  moveCount: widget.game.moveCount,
                  hover:
                      widget.enabled &&
                          _hover != null &&
                          widget.game.isLegal(_hover!)
                      ? _hover
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.game, required this.moveCount, this.hover});

  final PenteGame game;
  final int moveCount; // repaint key: the game object itself is mutable
  final Point? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final n = game.size;
    final cell = size.width / n;
    Offset at(Point p) => Offset((p.col + 0.5) * cell, (p.row + 0.5) * cell);

    // Wood background.
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.3)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE6BE7E), Color(0xFFD4A35E)],
        ).createShader(rect),
    );

    // Grid.
    final line = Paint()
      ..color = const Color(0xFF5A3E1B)
      ..strokeWidth = (cell * 0.04).clamp(0.6, 1.5);
    for (var i = 0; i < n; i++) {
      final v = (i + 0.5) * cell;
      canvas.drawLine(
        Offset(cell / 2, v),
        Offset(size.width - cell / 2, v),
        line,
      );
      canvas.drawLine(
        Offset(v, cell / 2),
        Offset(v, size.height - cell / 2),
        line,
      );
    }

    // Center and guide points (3 and 6 from center).
    final c = n ~/ 2;
    final dot = Paint()..color = const Color(0xFF5A3E1B);
    for (final dr in const [-6, -3, 0, 3, 6]) {
      for (final dc in const [-6, -3, 0, 3, 6]) {
        if ((dr.abs() == 6 || dc.abs() == 6) && dr.abs() != dc.abs()) {
          continue;
        }
        if ((dr == 0) != (dc == 0)) continue;
        final p = Point(c + dr, c + dc);
        if (game.inBounds(p)) canvas.drawCircle(at(p), cell * 0.1, dot);
      }
    }

    // Winning line highlight.
    final win = game.winningLine;
    if (win.length >= 2) {
      canvas.drawLine(
        at(win.first),
        at(win.last),
        Paint()
          ..color = const Color(0xCCD7263D)
          ..strokeWidth = cell * 0.22
          ..strokeCap = StrokeCap.round,
      );
    }

    // Stones.
    final radius = cell * 0.44;
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        final p = Point(r, col);
        final owner = game.at(p);
        if (owner != null) _stone(canvas, at(p), radius, owner, 1);
      }
    }

    // Last move marker.
    final last = game.lastMove;
    if (last != null && game.at(last.point) == last.player) {
      canvas.drawCircle(
        at(last.point),
        radius * 0.28,
        Paint()..color = const Color(0xFFD7263D),
      );
    }

    // Hover preview.
    if (hover != null) {
      _stone(canvas, at(hover!), radius, game.currentPlayer, 0.45);
    }
  }

  void _stone(Canvas canvas, Offset o, double r, Player p, double opacity) {
    final base = stoneColor(p);
    canvas.drawCircle(
      o + Offset(r * 0.08, r * 0.12),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.25 * opacity),
    );
    final shader = RadialGradient(
      center: const Alignment(-0.35, -0.4),
      radius: 1.0,
      colors: p == Player.one
          ? [Colors.white, base, const Color(0xFFCFC8B8)]
          : [const Color(0xFF55555E), base, Colors.black],
      stops: const [0, 0.55, 1],
    ).createShader(Rect.fromCircle(center: o, radius: r));
    canvas.drawCircle(
      o,
      r,
      Paint()
        ..shader = shader
        ..color = Colors.white.withValues(alpha: opacity),
    );
    if (opacity < 1) {
      // Shaders ignore paint opacity; overlay to fade the preview.
      canvas.drawCircle(
        o,
        r,
        Paint()..color = const Color(0xFFDDB26E).withValues(alpha: 1 - opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.moveCount != moveCount || old.hover != hover || old.game != game;
}
