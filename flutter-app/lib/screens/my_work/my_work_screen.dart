import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_paths.dart';
import '../../core/date_time_text.dart';
import '../../core/business_format.dart';
import '../../core/daily_order_math.dart';
import '../../core/daily_order_workflow.dart';
import '../../core/providers.dart';
import '../../core/stock_allocation.dart';
import '../../core/whole_pcs.dart';
import '../../core/ui_error.dart';
import '../../theme/excel_brand.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';

part 'my_work_attendance.dart';
part 'my_work_leave_visit.dart';
part 'my_work_daily.dart';
part 'my_work_daily_overview.dart';
part 'my_work_daily_order.dart';
part 'my_work_daily_closing.dart';
part 'my_work_daily_detail.dart';

class MyWorkScreen extends ConsumerStatefulWidget {
  const MyWorkScreen({
    super.key,
    this.initialSection = 'attendance',
    this.initialAction,
  });

  final String initialSection;
  final String? initialAction;

  @override
  ConsumerState<MyWorkScreen> createState() => _MyWorkScreenState();
}

class _MyWorkScreenState extends ConsumerState<MyWorkScreen> {
  int refresh = 0;
  String? message;
  bool _handledInitialAction = false;
  bool _dailyOrderOpening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _runInitialAction();
    });
  }

  Future<void> _runInitialAction() async {
    if (_handledInitialAction || !mounted || widget.initialAction == null)
      return;
    _handledInitialAction = true;
    try {
      switch (widget.initialAction) {
        case 'new_order':
          await _newDailyOrder();
          break;
        case 'leave':
          await _applyLeave();
          break;
        case 'field_visit':
          await _startVisit();
          break;
        case 'evening':
          final app = ref.read(appStateProvider);
          final api = ref.read(apiClientProvider);
          final rows = await _dailyRows(app, api);
          final candidates = rows
              .where(
                (row) =>
                    '${row['business_date'] ?? ''}' == app.businessDate &&
                    const {
                      'issued',
                      'evening_draft',
                    }.contains('${row['status']}'),
              )
              .toList()
            ..sort(
              (a, b) => (int.tryParse('${b['id']}') ?? 0).compareTo(
                int.tryParse('${a['id']}') ?? 0,
              ),
            );
          if (candidates.isEmpty) {
            if (mounted) {
              setState(
                () => message =
                    'No issued order is available for today’s evening closing.',
              );
            }
            return;
          }
          final row = candidates.first;
          await _dailyAction(
            int.parse('${row['id']}'),
            '${row['status']}' == 'evening_draft' ? 'evening_edit' : 'evening',
          );
          break;
      }
    } catch (e) {
      if (mounted) setState(() => message = UiError.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final tabs = <(String, Widget)>[];
    if (app.can('workforce.attendance.self')) {
      tabs.add(('Attendance & Duty', _attendance()));
    }
    if (app.canAny(const [
      'daily_order.self',
      'daily_order.others',
      'daily_order.approve',
      'daily_order.issue',
      'daily_order.review',
    ])) {
      tabs.add(('Daily Order', _daily()));
    }
    if (app.canAny(const [
      'workforce.leave.self',
      'workforce.field_visit.self',
    ])) {
      tabs.add(('Leave & Visit', _leaveVisit()));
    }
    if (tabs.isEmpty) {
      return const Center(child: Text('No authorised My Work functions.'));
    }
    final preferredLabel = switch (widget.initialSection) {
      'daily' => 'Daily Order',
      'leave_visit' => 'Leave & Visit',
      _ => 'Attendance & Duty',
    };
    final requestedIndex = tabs.indexWhere((tab) => tab.$1 == preferredLabel);
    final initialIndex = requestedIndex < 0 ? 0 : requestedIndex;
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIndex,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: BranchSelector(),
          ),
          TabBar(
            isScrollable: true,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
          Expanded(
            child: TabBarView(children: [for (final tab in tabs) tab.$2]),
          ),
        ],
      ),
    );
  }









  void _setFeatureState(VoidCallback update) => setState(update);

  Widget _feedbackBanner(String text) {
    final lower = text.toLowerCase();
    final isError = lower.contains('required') ||
        lower.contains('invalid') ||
        lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('not found') ||
        lower.contains('could not');
    final bg = isError ? const Color(0xFFFFF2F2) : ExcelBrand.primarySoft;
    final fg = isError ? const Color(0xFF8C2D2D) : ExcelBrand.primaryDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.info_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 20,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Position> _position() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission required.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }




  Map<String, dynamic>? _requestWithStatus(
    Map<String, dynamic> detail,
    String status,
  ) {
    final rows = ((detail['requests'] as List?) ?? const []).map(
      (e) => Map<String, dynamic>.from(e as Map),
    );
    for (final r in rows) {
      if ('${r['status']}' == status) return r;
    }
    return null;
  }
}
