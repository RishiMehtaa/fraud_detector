import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/gestures.dart';
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

class _GraphCanvasState extends State<GraphCanvas> with SingleTickerProviderStateMixin {
  GraphNode? _hoveredNode;
  GraphEdge? _hoveredEdge;
  Offset _hoverPos = Offset.zero;
  late List<GraphNode> _nodes;
  bool _layoutDone = false;
  
  late AnimationController _anim;
  GraphNode? _draggedNode;
  
  final Map<String, Set<String>> _neighbors = {};

  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _pan = Offset.zero;
  Offset? _panStart;
  Offset? _panStartOffset;

  @override
  void initState() {
    super.initState();
    _nodes = List.from(widget.nodes);
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _computeLayout();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _computeLayout() {
    if (_nodes.isEmpty) return;
    
    _neighbors.clear();
    for (final e in widget.edges) {
      _neighbors.putIfAbsent(e.source, () => {}).add(e.target);
      _neighbors.putIfAbsent(e.target, () => {}).add(e.source);
    }

    final rng = Random(42);
    for (final n in _nodes) {
      if (n.position == Offset.zero) {
        n.position = Offset(rng.nextDouble() * 800, rng.nextDouble() * 600);
      }
    }

    const repulsion = 7000.0;
    const attraction = 0.1;
    const damping = 0.85;
    final vel = {for (final n in _nodes) n.id: Offset.zero};

    for (int iter = 0; iter < 100; iter++) {
      final force = {for (final n in _nodes) n.id: Offset.zero};

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

      for (final n in _nodes) {
        vel[n.id] = (vel[n.id]! + force[n.id]!) * damping;
        n.position += vel[n.id]!;
      }
    }

    _zoomToFit();
    _layoutDone = true;
    if (mounted) setState(() {});
  }

  void _zoomToFit() {
    if (_nodes.isEmpty) return;

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;

    for (final n in _nodes) {
      minX = min(minX, n.position.dx);
      maxX = max(maxX, n.position.dx);
      minY = min(minY, n.position.dy);
      maxY = max(maxY, n.position.dy);
    }

    final graphW = maxX - minX + 100;
    final graphH = maxY - minY + 100;
    
    // Assume a default view size if not yet rendered, or use constraints
    const viewW = 900.0; 
    const viewH = 700.0;

    final scaleW = viewW / graphW;
    final scaleH = viewH / graphH;
    
    _scale = min(scaleW, scaleH).clamp(0.4, 1.0);
    
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    
    _pan = Offset(viewW / 2, viewH / 2) - Offset(centerX, centerY) * _scale;
  }

  GraphNode? _nodeAt(Offset pos, double scale, Offset pan) {
    for (final n in _nodes.reversed) {
      final radius = _nodeRadius(n) * scale;
      final screen = n.position * scale + pan;
      if ((screen - pos).distance <= radius + 10) return n;
    }
    return null;
  }

  GraphEdge? _edgeAt(Offset pos, double scale, Offset pan) {
    final nodeMap = {for (final n in _nodes) n.id: n};
    for (final e in widget.edges) {
      final a = nodeMap[e.source];
      final b = nodeMap[e.target];
      if (a == null || b == null) continue;
      final pa = a.position * scale + pan;
      final pb = b.position * scale + pan;
      
      final d = _distToSegment(pos, pa, pb);
      if (d < 10.0) return e;
    }
    return null;
  }

  double _distToSegment(Offset p, Offset v, Offset w) {
    final l2 = (v - w).distanceSquared;
    if (l2 == 0) return (p - v).distance;
    final t = max(0.0, min(1.0, (p - v).dx * (w - v).dx + (p - v).dy * (w - v).dy) / l2);
    final proj = v + (w - v) * t;
    return (p - proj).distance;
  }

  double _nodeRadius(GraphNode n) {
    final vol = n.totalVolume;
    return 12 + (vol > 0 ? min(log(vol + 1) * 2.5, 28) : 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_layoutDone) return const Center(child: CircularProgressIndicator());

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          setState(() {
            final double scaleChange = exp(-pointerSignal.scrollDelta.dy / 250);
            _scale = (_scale * scaleChange).clamp(0.05, 10.0);
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (d) {
          final node = _nodeAt(d.localFocalPoint, _scale, _pan);
          if (node != null) {
            setState(() => _draggedNode = node);
          } else {
            _panStart = d.localFocalPoint;
            _panStartOffset = _pan;
            _baseScale = _scale;
          }
        },
        onScaleUpdate: (d) {
          if (_draggedNode != null) {
            setState(() {
              _draggedNode!.position += d.focalPointDelta / _scale;
            });
          } else {
            setState(() {
              if (d.scale != 1.0) {
                _scale = (_baseScale * d.scale).clamp(0.05, 10.0);
              }
              if (_panStart != null) {
                _pan = _panStartOffset! + d.localFocalPoint - _panStart!;
              }
            });
          }
        },
        onScaleEnd: (_) => setState(() {
          _draggedNode = null;
          _panStart = null;
        }),
      onTapUp: (d) {
        final node = _nodeAt(d.localPosition, _scale, _pan);
        if (node != null) widget.onNodeTap?.call(node);
      },
      child: MouseRegion(
        onHover: (d) {
          setState(() {
            _hoverPos = d.localPosition;
            _hoveredNode = _nodeAt(d.localPosition, _scale, _pan);
            _hoveredEdge = _edgeAt(d.localPosition, _scale, _pan);
          });
        },
        onExit: (_) => setState(() { _hoveredNode = null; _hoveredEdge = null; }),
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _anim,
              builder: (ctx, _) => CustomPaint(
                painter: _GraphPainter(
                  nodes: _nodes,
                  edges: widget.edges,
                  neighbors: _neighbors,
                  scale: _scale,
                  pan: _pan,
                  hoveredNode: _hoveredNode,
                  hoveredEdge: _hoveredEdge,
                  nodeRadius: _nodeRadius,
                  animValue: _anim.value,
                ),
                size: Size.infinite,
              ),
            ),
            if (_hoveredEdge != null)
              Positioned(
                left: _hoverPos.dx + 15,
                top: _hoverPos.dy + 15,
                child: Card(
                  color: const Color(0xEE1A1A2E),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('${_hoveredEdge!.type}: ₹${(_hoveredEdge!.amount/1000).toStringAsFixed(1)}K',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    ));
  }
}

class _GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final Map<String, Set<String>> neighbors;
  final double scale;
  final Offset pan;
  final GraphNode? hoveredNode;
  final GraphEdge? hoveredEdge;
  final double Function(GraphNode) nodeRadius;
  final double animValue;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.neighbors,
    required this.scale,
    required this.pan,
    required this.hoveredNode,
    required this.hoveredEdge,
    required this.nodeRadius,
    required this.animValue,
  });

  Offset _pos(GraphNode n) => n.position * scale + pan;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (final n in nodes) n.id: n};
    final isAnyHovered = hoveredNode != null;
    final hoverId = hoveredNode?.id;

    for (final e in edges) {
      final a = nodeMap[e.source];
      final b = nodeMap[e.target];
      if (a == null || b == null) continue;
      
      final isRelated = isAnyHovered && (e.source == hoverId || e.target == hoverId);
      final isEdgeHovered = hoveredEdge == e;
      final pa = _pos(a);
      final pb = _pos(b);

      final opacity = isAnyHovered ? (isRelated ? 0.7 : 0.05) : 0.15;
      final paint = Paint()
        ..color = isEdgeHovered ? Colors.yellow : (isRelated ? Colors.blueAccent : Colors.white).withOpacity(opacity)
        ..strokeWidth = isEdgeHovered ? 3.0 : (isRelated ? 2.0 : 1.0)
        ..style = PaintingStyle.stroke;

      canvas.drawLine(pa, pb, paint);

      if (!isAnyHovered || isRelated) {
        final t = (animValue + (e.hashCode % 100) / 100.0) % 1.0;
        final p = pa + (pb - pa) * t;
        canvas.drawCircle(p, 2.5 * scale.clamp(0.5, 1.5), Paint()..color = (isRelated ? Colors.blue : Colors.white).withOpacity(opacity + 0.2));
      }
    }

    for (final n in nodes) {
      final pos = _pos(n);
      final r = nodeRadius(n) * scale;
      final isHovered = n.id == hoverId;
      final isNeighbor = isAnyHovered && (neighbors[hoverId]?.contains(n.id) ?? false);
      final opacity = isAnyHovered ? (isHovered || isNeighbor ? 1.0 : 0.2) : 0.9;

      final color = RiskBadge.colorForScore(n.riskScore);
      
      if ((n.riskScore > 70 || isHovered) && opacity > 0.2) {
        canvas.drawCircle(pos, r + (isHovered ? 12 : 6), Paint()..color = color.withOpacity(0.2)..maskFilter = MaskFilter.blur(BlurStyle.normal, isHovered ? 15 : 10));
      }

      canvas.drawCircle(pos, r, Paint()..color = color.withOpacity(opacity));
      canvas.drawCircle(pos, r, Paint()..color = isHovered ? Colors.white : color.withOpacity(0.5)..strokeWidth = isHovered ? 3 : 1..style = PaintingStyle.stroke);

      if (isHovered || (isAnyHovered && isNeighbor && scale > 0.8)) {
        final tp = TextPainter(text: TextSpan(text: n.id, style: TextStyle(color: Colors.white, fontSize: (isHovered ? 13 : 11) * scale.clamp(0.5, 1.2), fontWeight: isHovered ? FontWeight.bold : FontWeight.normal, shadows: const [Shadow(blurRadius: 4, color: Colors.black)])), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, pos + Offset(-tp.width / 2, r + 10));
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}