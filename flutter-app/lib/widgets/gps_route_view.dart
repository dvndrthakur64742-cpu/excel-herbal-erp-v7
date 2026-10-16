import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/business_format.dart';

/// Displays OpenStreetMap road tiles with the server-recorded GPS route overlaid.
/// Every route marker is a persisted point; the polyline is ordered by timestamp.
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
            _metric(context, 'Estimated GPS distance', '${distanceKm.toStringAsFixed(2)} km', Icons.route_outlined),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, 270);
              final viewport = _MapViewport.create(ordered, size);
              final first = Theme.of(context).colorScheme.primary;
              return Container(
                height: size.height,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Stack(
                  children: [
                    for (final tile in viewport.tiles)
                      Positioned(
                        left: tile.left,
                        top: tile.top,
                        width: 256,
                        height: 256,
                        child: Image.network(
                          'https://tile.openstreetmap.org/${viewport.zoom}/${tile.x}/${tile.y}.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFFE9E7DF),
                            child: Center(child: Icon(Icons.map_outlined, color: Color(0xFF777777))),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RoadRoutePainter(
                          positions: viewport.positions,
                          routeColor: first,
                          startColor: Colors.green.shade700,
                          endColor: Colors.red.shade700,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .94),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          child: Text('Road map · recorded GPS route', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 6,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0xEFFFFFFF)),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 9, color: Color(0xFF333333))),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        if (ordered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Route line connects recorded GPS samples in timestamp order. Estimated distance is straight-line distance between samples, not road/odometer distance.',
              style: Theme.of(context).textTheme.bodySmall,
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

class _MapTile {
  const _MapTile(this.x, this.y, this.left, this.top);
  final int x;
  final int y;
  final double left;
  final double top;
}

class _MapPoint {
  const _MapPoint(this.x, this.y);
  final double x;
  final double y;
}

class _MapViewport {
  const _MapViewport({
    required this.zoom,
    required this.tiles,
    required this.positions,
  });
  final int zoom;
  final List<_MapTile> tiles;
  final List<Offset> positions;

  static _MapViewport create(List<Map<String, dynamic>> points, Size size) {
    var zoom = 15;
    List<_MapPoint> projected = [];
    for (var candidate = 18; candidate >= 3; candidate--) {
      final current = points.map((p) => _project(
        double.parse('${p['latitude'] ?? p['lat']}'),
        double.parse('${p['longitude'] ?? p['lng']}'),
        candidate,
      )).toList();
      final xs = current.map((p) => p.x);
      final ys = current.map((p) => p.y);
      final width = xs.reduce((a, b) => math.max(a, b).toDouble()) - xs.reduce((a, b) => math.min(a, b).toDouble());
      final height = ys.reduce((a, b) => math.max(a, b).toDouble()) - ys.reduce((a, b) => math.min(a, b).toDouble());
      zoom = candidate;
      projected = current;
      if (width <= size.width - 64 && height <= size.height - 64) break;
    }
    final minX = projected.map((p) => p.x).reduce(math.min);
    final maxX = projected.map((p) => p.x).reduce(math.max);
    final minY = projected.map((p) => p.y).reduce(math.min);
    final maxY = projected.map((p) => p.y).reduce(math.max);
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final originX = centerX - size.width / 2;
    final originY = centerY - size.height / 2;
    final tileCount = 1 << zoom;
    final tiles = <_MapTile>[];
    for (var tx = (originX / 256).floor(); tx <= ((originX + size.width) / 256).floor(); tx++) {
      for (var ty = (originY / 256).floor(); ty <= ((originY + size.height) / 256).floor(); ty++) {
        if (ty < 0 || ty >= tileCount) continue;
        final wrappedX = ((tx % tileCount) + tileCount) % tileCount;
        tiles.add(_MapTile(wrappedX, ty, tx * 256 - originX, ty * 256 - originY));
      }
    }
    return _MapViewport(
      zoom: zoom,
      tiles: tiles,
      positions: projected.map((p) => Offset(p.x - originX, p.y - originY)).toList(),
    );
  }

  static _MapPoint _project(double latitude, double longitude, int zoom) {
    final lat = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    final world = 256.0 * (1 << zoom);
    final x = (longitude + 180) / 360 * world;
    final y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * world;
    return _MapPoint(x, y);
  }
}

class _RoadRoutePainter extends CustomPainter {
  const _RoadRoutePainter({
    required this.positions,
    required this.routeColor,
    required this.startColor,
    required this.endColor,
  });

  final List<Offset> positions;
  final Color routeColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;
    if (positions.length > 1) {
      final path = Path()..moveTo(positions.first.dx, positions.first.dy);
      for (final point in positions.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withValues(alpha: .92)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
      canvas.drawPath(path, Paint()
        ..color = routeColor
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
    }
    for (var i = 0; i < positions.length; i++) {
      final point = positions[i];
      final color = i == 0 ? startColor : i == positions.length - 1 ? endColor : routeColor;
      canvas.drawCircle(point, i == 0 || i == positions.length - 1 ? 7 : 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(point, i == 0 || i == positions.length - 1 ? 5 : 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _RoadRoutePainter oldDelegate) =>
      oldDelegate.positions != positions ||
      oldDelegate.routeColor != routeColor ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor;
}
