import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/risk_badge.dart';

class GraphNode {
  final String id;
  final double riskScore;
  final String accountType;
  final double totalVolume;
  final List<String> triggeredPatterns;
  Offset position;

  GraphNode({
    required this.id,
    required this.riskScore,
    required this.accountType,
    required this.totalVolume,
    required this.triggeredPatterns,
    this.position = Offset.zero,
  });

  factory GraphNode.fromJson(Map<String, dynamic> j) => GraphNode(
        id: j['id'] as String,
        riskScore: (j['risk_score'] as num? ?? 0).toDouble(),
        accountType: j['account_type'] as String? ?? 'C',
        totalVolume: (j['total_volume'] as num? ?? 0).toDouble(),
        triggeredPatterns:
            (j['triggered_patterns'] as List<dynamic>? ?? [])
                .map((e) => e as String)
                .toList(),
      );
}

class GraphEdge {
  final String source;
  final String target;
  final double amount;
  final String type;

  const GraphEdge({
    required this.source,
    required this.target,
    required this.amount,
    required this.type,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> j) => GraphEdge(
        source: j['source'] as String,
        target: j['target'] as String,
        amount: (j['amount'] as num? ?? 0).toDouble(),
        type: j['type'] as String? ?? '',
      );
}

class GraphCanvas extends StatefulWidget {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final void Function(GraphNode)? onNodeTap;

  const GraphCanvas({
    super.key,
    required this.nodes,
    required this.edges,
    this.onNodeTap,
  });

  @override
  State<GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<GraphCanvas> {
  String? _hoveredEdgeKey;
  GraphNode? _hoveredNode;
  Offset _hoverPos = Offset.zero;
  late List<GraphNode> _nodes;
  bool _layoutDone = false;

  @override
  void initState() {
    super.initState();
    _nodes = List.from(widget.nodes);
    _computeLayout();
  }

  @override
  void didUpdateWidget(GraphCanvas old) {
    super.didUpdateWidget(old);
    if (old.nodes != widget.nodes) {
      _nodes = List.from(widget.nodes);
      _layoutDone = false;
      _computeLayout();
    }
  }

  void _computeLayout() {
    if (_nodes.isEmpty) return;
    // Degree map
    final degree = <String, int>{};
    for (final e in widget.edges) {
      degree[e.source] = (degree[e.source] ?? 0) + 1;
      degree[e.target] = (degree[e.target] ?? 0) + 1;
    }

    const w = 900.0;
    const h = 700.0;
    final rng = Random(42);

    // Initial random positions
    for (final n in _nodes) {
      n.position = Offset(rng.nextDouble() * w, rng.nextDouble() * h);
    }

    // Simple force-directed: 80 iterations
    const repulsion = 4000.0;
    const attraction = 0.05;
    const damping = 0.85;
    final vel = {for (final n in _nodes) n.id: Offset.zero};

    for (int iter = 0; iter < 80; iter++) {
      final force = {for (final n in _nodes) n.id: Offset.zero};

      // Repulsion
      for (int i = 0; i < _nodes.length; i++) {
        for (int j = i + 1; j < _nodes.length; j++) {
          final a = _nodes[i];
          final b = _nodes[j];
          final delta = a.position - b.position;
          final dist = max(delta.distance, 1.0);
          final f = repulsion / (dist * dist);
          final dir = delta / dist;
          force[a.id] = force[a.id]! + dir * f;
          force[b.id] = force[b.id]! - dir * f;
        }
      }

      // Attraction (edges)
      final nodeMap = {for (final n in _nodes) n.id: n};
      for (final e in widget.edges) {
        final a = nodeMap[e.source];
        final b = nodeMap[e.target];
        if (a == null || b == null) continue;
        final delta = b.position - a.position;
        final dist = max(delta.distance, 1.0);
        final f = attraction * dist;
        final dir = delta / dist;
        force[a.id] = force[a.id]! + dir * f;
        force[b.id] = force[b.id]! - dir * f;
      }

      // Update positions
      for (final n in _nodes) {
        vel[n.id] = (vel[n.id]! + force[n.id]!) * damping;
        n.position = Offset(
          (n.position.dx + vel[n.id]!.dx).clamp(40.0, w - 40),
          (n.position.dy + vel[n.id]!.dy).clamp(40.0, h - 40),
        );
      }
    }

    _layoutDone = true;
    if (mounted) setState(() {});
  }

  GraphNode? _nodeAt(Offset pos, double scale, Offset pan) {
    for (final n in _nodes.reversed) {
      final radius = _nodeRadius(n);
      final screen = n.position * scale + pan;
      if ((screen - pos).distance <= radius * scale + 4) return n;
    }
    return null;
  }

  double _nodeRadius(GraphNode n) {
    final vol = n.totalVolume;
    return 10 + (vol > 0 ? min(log(vol + 1) * 2, 24) : 0);
  }

  // Transform state
  double _scale = 1.0;
  Offset _pan = Offset.zero;
  Offset? _panStart;
  Offset? _panStartOffset;

  @override
  Widget build(BuildContext context) {
    if (!_layoutDone) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onScaleStart: (d) {
        _panStart = d.focalPoint;
        _panStartOffset = _pan;
      },
      onScaleUpdate: (d) {
        setState(() {
          _scale = (_scale * d.scale).clamp(0.3, 4.0);
          if (_panStart != null) {
            _pan = _panStartOffset! + d.focalPoint - _panStart!;
          }
        });
      },
      onTapUp: (d) {
        final node = _nodeAt(d.localPosition, _scale, _pan);
        if (node != null) widget.onNodeTap?.call(node);
      },
      child: MouseRegion(
        onHover: (d) {
          setState(() {
            _hoverPos = d.localPosition;
            _hoveredNode = _nodeAt(d.localPosition, _scale, _pan);
          });
        },
        onExit: (_) => setState(() {
          _hoveredNode = null;
          _hoveredEdgeKey = null;
        }),
        child: CustomPaint(
          painter: _GraphPainter(
            nodes: _nodes,
            edges: widget.edges,
            scale: _scale,
            pan: _pan,
            hoveredNode: _hoveredNode,
            nodeRadius: _nodeRadius,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final double scale;
  final Offset pan;
  final GraphNode? hoveredNode;
  final double Function(GraphNode) nodeRadius;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.scale,
    required this.pan,
    required this.hoveredNode,
    required this.nodeRadius,
  });

  Offset _pos(GraphNode n) => n.position * scale + pan;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (final n in nodes) n.id: n};

    // Draw edges
    for (final e in edges) {
      final a = nodeMap[e.source];
      final b = nodeMap[e.target];
      if (a == null || b == null) continue;
      final pa = _pos(a);
      final pb = _pos(b);

      final paint = Paint()
        ..color = Colors.white.withOpacity(0.12)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      // Arrow
      canvas.drawLine(pa, pb, paint);

      // Arrowhead
      final dir = (pb - pa);
      final dist = dir.distance;
      if (dist < 1) continue;
      final unit = dir / dist;
      final arrowTip = pb - unit * (nodeRadius(b) * scale + 2);
      final arrowLeft = arrowTip - _rotate(unit, 0.4) * 8 * scale.clamp(0.5, 1.5);
      final arrowRight = arrowTip - _rotate(unit, -0.4) * 8 * scale.clamp(0.5, 1.5);

      final arrowPaint = Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(arrowTip.dx, arrowTip.dy)
        ..lineTo(arrowLeft.dx, arrowLeft.dy)
        ..lineTo(arrowRight.dx, arrowRight.dy)
        ..close();
      canvas.drawPath(path, arrowPaint);
    }

    // Draw nodes
    for (final n in nodes) {
      final pos = _pos(n);
      final r = nodeRadius(n) * scale;
      final color = RiskBadge.colorForScore(n.riskScore);
      final isHovered = hoveredNode?.id == n.id;

      // Glow for high-risk or hovered
      if (n.riskScore > 60 || isHovered) {
        final glowPaint = Paint()
          ..color = color.withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(pos, r + 6, glowPaint);
      }

      // Node circle
      final nodePaint = Paint()..color = color.withOpacity(0.85);
      canvas.drawCircle(pos, r, nodePaint);

      // Border
      final borderPaint = Paint()
        ..color = isHovered ? Colors.white : color.withOpacity(0.6)
        ..strokeWidth = isHovered ? 2 : 1
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pos, r, borderPaint);

      // Label for hovered node
      if (isHovered && r > 6) {
        final tp = TextPainter(
          text: TextSpan(
            text: n.id,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11 * scale.clamp(0.6, 1.2),
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final bgRect = Rect.fromCenter(
          center: pos + Offset(0, r + 14 * scale),
          width: tp.width + 12,
          height: tp.height + 6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
          Paint()..color = const Color(0xDD1A1A2E),
        );
        tp.paint(
            canvas, pos + Offset(-tp.width / 2, r + 11 * scale));
      }
    }
  }

  Offset _rotate(Offset v, double angle) {
    return Offset(
      v.dx * cos(angle) - v.dy * sin(angle),
      v.dx * sin(angle) + v.dy * cos(angle),
    );
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.scale != scale ||
      old.pan != pan ||
      old.hoveredNode != hoveredNode ||
      old.nodes != nodes;
}