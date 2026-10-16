import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/business_format.dart';

/// Displays the actual recorded GPS breadcrumb sequence and its timeline.
/// This is a trace plot (not a street/road map); every marker is a server-stored
/// GPS point and the connecting line follows timestamp order.
class GpsRouteView extends StatelessWidget {
  const GpsRouteView({
    super.key,
    required this.points,
    this.showTimeline = true,
  });

  final List<Map<String, dynamic>> points;
  final bool showTimeline;

  @override
  Widget build(BuildContext context) {
    final ordered = points.where(_validPoint).toList()
      ..sort((a, b) {
        final at = DateTime.tryParse('${a['recorded_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse('${b['recorded_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final compare = at.compareTo(bt);
        if (compare != 0) return compare;
        return (int.tryParse('${a['id']}') ?? 0)
            .compareTo(int.tryParse('${b['id']}') ?? 0);
      });
    final distanceKm = _distanceKm(ordered);
    final firstAt = ordered.isEmpty ? null : ordered.first['recorded_at'];
    final lastAt = ordered.isEmpty ? null : ordered.last['recorded_at'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric(context, 'GPS points', '${ordered.length}', Icons.place_outlined),
            _metric(context, 'Recorded travel', '${distanceKm.toStringAsFixed(2)} km', Icons.route_outlined),
            _metric(context, 'First point', firstAt == null ? '—' : BusinessFormat.dateTime(firstAt), Icons.play_arrow_rounded),
            _metric(context, 'Last point', lastAt == null ? '—' : BusinessFormat.dateTime(lastAt), Icons.stop_rounded),
          ],
        ),
        const SizedBox(height: 12),
        if (ordered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.location_off_outlined),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Is date ke liye koi GPS point server par record nahi hua. Route tabhi banega jab employee ka duty GPS enabled ho aur app location points upload kar raha ho.',
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            height: 250,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: _GpsTracePainter(
                points: ordered,
                lineColor: Theme.of(context).colorScheme.primary,
                startColor: Colors.green.shade700,
                endColor: Colors.red.shade700,
                gridColor: Theme.of(context).colorScheme.outlineVariant,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text('Recorded GPS trace · not a road map', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (showTimeline && ordered.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Route timeline', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (var i = 0; i < ordered.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
              ),
              title: Text(BusinessFormat.dateTime(ordered[i]['recorded_at'])),
              subtitle: Text(
                '${ordered[i]['latitude']}, ${ordered[i]['longitude']} · accuracy ${ordered[i]['accuracy_m'] ?? '—'} m',
              ),
              trailing: i == 0
                  ? const Icon(Icons.flag_outlined, color: Colors.green)
                  : i == ordered.length - 1
                      ? const Icon(Icons.location_on_outlined, color: Colors.red)
                      : null,
            ),
        ],
      ],
    );
  }

  static bool _validPoint(Map<String, dynamic> point) {
    final lat = double.tryParse('${point['latitude'] ?? point['lat'] ?? ''}');
    final lng = double.tryParse('${point['longitude'] ?? point['lng'] ?? ''}');
    return lat != null && lng != null && lat.isFinite && lng.isFinite &&
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  static Widget _metric(BuildContext context, String label, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(value, style: Theme.of(context).textTheme.labelLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _distanceKm(List<Map<String, dynamic>> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      final lat1 = _radians(double.parse('${points[i - 1]['latitude'] ?? points[i - 1]['lat']}'));
      final lon1 = _radians(double.parse('${points[i - 1]['longitude'] ?? points[i - 1]['lng']}'));
      final lat2 = _radians(double.parse('${points[i]['latitude'] ?? points[i]['lat']}'));
      final lon2 = _radians(double.parse('${points[i]['longitude'] ?? points[i]['lng']}'));
      final dLat = lat2 - lat1;
      final dLon = lon2 - lon1;
      final a = math.pow(math.sin(dLat / 2), 2) +
          math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
      total += 6371.0088 * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
    }
    return total;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

class _GpsTracePainter extends CustomPainter {
  const _GpsTracePainter({
    required this.points,
    required this.lineColor,
    required this.startColor,
    required this.endColor,
    required this.gridColor,
  });

  final List<Map<String, dynamic>> points;
  final Color lineColor;
  final Color startColor;
  final Color endColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 26.0;
    final rect = Rect.fromLTWH(pad, pad, math.max(1, size.width - pad * 2), math.max(1, size.height - pad * 2));
    final grid = Paint()..color = gridColor.withValues(alpha: .55)..strokeWidth = .7;
    for (var i = 1; i < 5; i++) {
      final x = rect.left + rect.width * i / 5;
      final y = rect.top + rect.height * i / 5;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    final coords = points.map((p) => (
      double.parse('${p['latitude'] ?? p['lat']}'),
      double.parse('${p['longitude'] ?? p['lng']}'),
    )).toList(growable: false);
    final minLat = coords.map((p) => p.$1).reduce(math.min);
    final maxLat = coords.map((p) => p.$1).reduce(math.max);
    final minLng = coords.map((p) => p.$2).reduce(math.min);
    final maxLng = coords.map((p) => p.$2).reduce(math.max);
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final span = math.max(math.max(latSpan, lngSpan), 0.00005);
    final usableW = rect.width;
    final usableH = rect.height;
    final projected = coords.map((p) => Offset(
      rect.left + (p.$2 - minLng) / (lngSpan == 0 ? 1 : lngSpan) * usableW,
      rect.bottom - (p.$1 - minLat) / (latSpan == 0 ? 1 : latSpan) * usableH,
    )).toList(growable: false);

    if (projected.length > 1) {
      final path = Path()..moveTo(projected.first.dx, projected.first.dy);
      for (final point in projected.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, Paint()..color = lineColor..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    }
    for (var i = 0; i < projected.length; i++) {
      final color = i == 0 ? startColor : i == projected.length - 1 ? endColor : lineColor;
      canvas.drawCircle(projected[i], i == 0 || i == projected.length - 1 ? 6 : 3.5, Paint()..color = color);
      if (i == 0 || i == projected.length - 1) {
        canvas.drawCircle(projected[i], 9, Paint()..color = color.withValues(alpha: .18));
      }
    }
    final textStyle = TextStyle(color: lineColor, fontSize: 10, fontWeight: FontWeight.w600);
    _drawLabel(canvas, coords.first.$1.toStringAsFixed(4), Offset(rect.left, rect.bottom + 8), textStyle);
    _drawLabel(canvas, coords.last.$1.toStringAsFixed(4), Offset(rect.right - 42, rect.top - 16), textStyle);
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: 72);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GpsTracePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor ||
      oldDelegate.gridColor != gridColor;
}
