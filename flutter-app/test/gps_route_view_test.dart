import 'package:excel_herbal_erp/widgets/gps_route_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('daily GPS route renders trace metrics and timestamped points', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GpsRouteView(
              points: [
                {
                  'id': 1,
                  'latitude': 31.9500,
                  'longitude': 76.5400,
                  'accuracy_m': 5,
                  'recorded_at': '2026-10-16T05:00:00Z',
                },
                {
                  'id': 2,
                  'latitude': 31.9600,
                  'longitude': 76.5500,
                  'accuracy_m': 6,
                  'recorded_at': '2026-10-16T05:05:00Z',
                },
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('GPS points'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Estimated GPS distance'), findsOneWidget);
    expect(find.text('Route timeline'), findsOneWidget);
    expect(find.text('Road map · recorded GPS route'), findsOneWidget);
    expect(find.textContaining('© OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('empty route explains that no GPS points were recorded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GpsRouteView(points: [])),
      ),
    );
    expect(find.textContaining('koi GPS point server par record nahi hua'), findsOneWidget);
  });
}
