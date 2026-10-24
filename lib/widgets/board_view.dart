import 'package:flutter/material.dart';

import '../game/pente.dart';

/// Colors for each player's stones.
const Color stoneOneColor = Color(0xFFF7F3EA); // white, moves first
const Color stoneTwoColor = Color(0xFF1E1E22); // black

Color stoneColor(Player p) => p == Player.one ? stoneOneColor : stoneTwoColor;

/// The wooden board with its stones. Tap or click an intersection to play.
///
/// The board can be zoomed for precise placement: pinch and drag on touch
/// screens, scroll wheel or trackpad on desktop, or the +/- buttons below it.
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

  /// Key of the square board area (excluding the zoom controls).
  static const boardKey = Key('board');

  static const double minZoom = 1;
  static const double maxZoom = 3;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView>
    with SingleTickerProviderStateMixin {
  static const double _controlsHeight = 44;
  static const double _buttonStep = 1.5;

  final TransformationController _zoom = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Matrix4>? _tween;
  Point? _hover;
  double _side = 0;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoomChanged);
    _anim.addListener(() {
      if (_tween != null) _zoom.value = _tween!.value;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _zoom.dispose();
    super.dispose();
  }

  double get _scale => _zoom.value.getMaxScaleOnAxis();

  void _onZoomChanged() => setState(() {});

  /// Zoom by [factor] around the middle of the visible board.
  void _zoomBy(double factor) {
    final current = _zoom.value;
    final scale = (_scale * factor).clamp(BoardView.minZoom, BoardView.maxZoom);
    final f = scale / _scale;
    final c = _side / 2;
    final next = Matrix4.identity()
      ..translateByDouble(c, c, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-c, -c, 0, 1)
      ..multiply(current);
    _animateTo(_clamp(next));
  }

  void _reset() => _animateTo(Matrix4.identity());

  /// The zoom offset is in pixels, so when the board changes size (window
  /// resize, iPad rotation) scale it to keep the same part of the board in
  /// view instead of showing empty space past the edge.
  void _onResize(double oldSide, double newSide) {
    if (oldSide <= 0 || _scale <= BoardView.minZoom) return;
    _anim.stop();
    final ratio = newSide / oldSide;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final t = _zoom.value.getTranslation();
      final s = _scale;
      _zoom.value = _clamp(
        Matrix4.identity()
          ..translateByDouble(t.x * ratio, t.y * ratio, 0, 1)
          ..scaleByDouble(s, s, 1, 1),
      );
    });
  }

  /// Keep the board filling the view (no empty space past its edges).
  Matrix4 _clamp(Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    final min = _side - _side * s;
    final t = m.getTranslation();
    return Matrix4.identity()
      ..translateByDouble(t.x.clamp(min, 0), t.y.clamp(min, 0), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _animateTo(Matrix4 target) {
    _tween = Matrix4Tween(
      begin: _zoom.value,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = [
          constraints.maxWidth,
          constraints.maxHeight - _controlsHeight,
        ].reduce((a, b) => a < b ? a : b).clamp(0.0, double.infinity);
        if (side != _side) _onResize(_side, side);
        _side = side;
        final scale = _scale;
        final zoomed = scale > BoardView.minZoom + 0.01;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              key: BoardView.boardKey,
              dimension: side,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(side / 19 * 0.3),
                child: InteractiveViewer(
                  transformationController: _zoom,
                  minScale: BoardView.minZoom,
                  maxScale: BoardView.maxZoom,
                  onInteractionStart: (_) => _anim.stop(),
                  child: _board(side),
                ),
              ),
            ),
            SizedBox(
              width: side,
              height: _controlsHeight,
              child: _ZoomControls(
                zoomed: zoomed,
                canZoomIn: scale < BoardView.maxZoom - 0.01,
                onZoomIn: () => _zoomBy(_buttonStep),
                onZoomOut: zoomed ? () => _zoomBy(1 / _buttonStep) : null,
                onReset: zoomed ? _reset : null,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _board(double side) {
    // Positions here are in board coordinates: Flutter undoes the zoom
    // transform before handing us localPosition, so taps land correctly.
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
            zoom: _scale,
            hover:
                widget.enabled && _hover != null && widget.game.isLegal(_hover!)
                ? _hover
                : null,
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.zoomed,
    required this.canZoomIn,
    required this.onZoomIn,
    this.onZoomOut,
    this.onReset,
  });

  final bool zoomed;
  final bool canZoomIn;
  final VoidCallback onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            zoomed ? 'Drag to move around' : 'Pinch, scroll or use + to zoom',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          key: const Key('zoom-out'),
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
          icon: const Icon(Icons.zoom_out),
        ),
        IconButton(
          key: const Key('zoom-in'),
          tooltip: 'Zoom in',
          onPressed: canZoomIn ? onZoomIn : null,
          icon: const Icon(Icons.zoom_in),
        ),
        IconButton(
          key: const Key('zoom-reset'),
          tooltip: 'Show whole board',
          onPressed: onReset,
          icon: const Icon(Icons.fit_screen),
        ),
      ],
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.game,
    required this.moveCount,
    this.zoom = 1,
    this.hover,
  });

  final PenteGame game;
  final int moveCount; // repaint key: the game object itself is mutable
  final Point? hover;
  final double zoom; // keeps grid lines thin when zoomed in

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
      ..strokeWidth = (cell * 0.04).clamp(0.6, 1.5) / zoom.clamp(1, 2);
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
      old.moveCount != moveCount ||
      old.hover != hover ||
      old.game != game ||
      old.zoom != zoom;
}
