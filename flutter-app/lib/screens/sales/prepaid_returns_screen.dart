import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';

/// Branch-scoped prepaid return and MANUAL refund-evidence workspace.
///
/// There is no payout, stock posting, journal reversal or GST credit note
/// action in this screen. Server authority and maker/checker checks are final.
class PrepaidReturnsScreen extends ConsumerStatefulWidget {
  const PrepaidReturnsScreen({super.key});

  @override
  ConsumerState<PrepaidReturnsScreen> createState() =>
      _PrepaidReturnsScreenState();
}

class _PrepaidReturnsScreenState extends ConsumerState<PrepaidReturnsScreen> {
  int? _loadedBranch;
  int? _selectedId;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _returns = [];
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _evidence = [];
  List<Map<String, dynamic>> _originalPayments = [];

  static int? _id(dynamic value) => int.tryParse(value.toString());
  static Map<String, dynamic> _map(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload({int? selectedId}) async {
    if (_busy) return;
    final branch = ref.read(appStateProvider).currentBranchId;
    if (branch == null) {
      setState(() {
        _loadedBranch = null;
        _returns = [];
        _detail = null;
        _selectedId = null;
        _evidence = [];
        _originalPayments = [];
      });
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final list = await api.get(ApiPaths.prepaidReturns,
          query: {'branch_id': branch});
      final id = selectedId ??
          (branch == _loadedBranch ? _selectedId : null);
      final detail = id == null
          ? null : _map(await api.get(ApiPaths.prepaidReturn(id)));
      final proof = id == null ? <Map<String, dynamic>>[] :
          (await api.get(ApiPaths.prepaidRefundEvidence(id)) as List)
              .map(_map).toList();
      final orderId = detail == null ? null : _id(detail['order_id']);
      final order = orderId == null ? null :
          _map(await api.get(ApiPaths.prepaidOrder(orderId)));
      final payments = order == null ? <Map<String, dynamic>>[] :
          ((order['payments'] as List?) ?? const [])
              .map(_map).toList();
      // A late response from the previous branch must never reach the UI.
      if (!mounted ||
          ref.read(appStateProvider).currentBranchId != branch) return;
      setState(() {
        _loadedBranch = branch;
        _selectedId = id;
        _returns = (list as List).map(_map).toList();
        _detail = detail;
        _evidence = proof;
        _originalPayments = payments;
      });
    } catch (error) {
      if (mounted) setState(() => _error = UiError.message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _perform(Future<dynamic> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      await _reload(selectedId: _selectedId);
    } catch (error) {
      if (mounted) setState(() {
        _busy = false;
        _error = UiError.message(error);
      });
    }
  }

  Future<String?> _referenceDialog(String title, String field,
      {int min = 6, String? explanation}) async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (explanation != null) Text(explanation),
            TextFormField(
              controller: controller,
              maxLength: 120,
              decoration: InputDecoration(labelText: field),
              validator: (value) => (value ?? '').trim().length >= min
                  ? null : 'At least $min characters required.',
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(ctx, controller.text.trim());
            }
          }, child: const Text('Continue')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _inspect(int id) async {
    final value = await _referenceDialog('Confirm physical receipt',
        'Physical receipt reference',
        explanation: 'Check returned goods in person. This does not '
            'restore saleable stock or issue a refund.');
    if (value == null || !mounted) return;
    await _perform(() => ref.read(apiClientProvider).post(
        ApiPaths.prepaidReturnInspect(id),
        data: {'inspection_reference': value}));
  }

  Future<void> _decide(int id, bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve return' : 'Reject return'),
        content: Text(approve
            ? 'A different authorized employee must approve. '
              'Approval moves the request to refund_pending; '
              'no payment or credit note is posted.'
            : 'Reject this physically inspected return?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(approve ? 'Approve request' : 'Reject request')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() => ref.read(apiClientProvider).post(
        ApiPaths.prepaidReturnDecision(id), data: {'approve': approve}));
  }

  Future<void> _submitEvidence(int returnId,
      Map<String, dynamic> payment) async {
    final reference = await _referenceDialog('Record refund evidence',
        'Cash receipt / UPI reference',
        explanation: 'Evidence only. Do not enter a proposed future '
            'payment as if it were disbursed. An independent reviewer '
            'must manually verify the record.');
    if (reference == null || !mounted) return;
    final paymentId = _id(payment['id']);
    if (paymentId == null) return;
    await _perform(() => ref.read(apiClientProvider).post(
        ApiPaths.prepaidRefundEvidence(returnId),
        data: {
          'original_payment_id': paymentId,
          'amount': payment['amount'],
          'evidence_reference': reference,
        }));
  }

  Future<void> _verifyEvidence(Map<String, dynamic> evidence) async {
    final reference = await _referenceDialog('Verify evidence independently',
        'Independent verification reference',
        explanation: 'Review actual Cash/UPI evidence before confirming. '
            'This is a manual check, NOT a bank payout confirmation.');
    if (reference == null || !mounted) return;
    final proofId = _id(evidence['id']);
    if (proofId == null) return;
    await _perform(() => ref.read(apiClientProvider).post(
        ApiPaths.prepaidRefundEvidenceVerify(proofId),
        data: {'verification_reference': reference}));
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final branch = app.currentBranchId;
    if (branch != _loadedBranch && !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) _reload();
      });
    }
    // Hide previous branch records immediately, including while a reload runs.
    final visibleBranch = branch != null && branch == _loadedBranch;
    final detail = visibleBranch ? _detail : null;
    final visibleReturns = visibleBranch
        ? _returns : <Map<String, dynamic>>[];
    final check = detail?['refund_evidence_check'] is Map
        ? Map<String, dynamic>.from(detail!['refund_evidence_check'] as Map)
        : <String, dynamic>{};
    final blockers = (check['blockers'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prepaid Returns'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : () => _reload()),
        ],
      ),
      body: SafeArea(child: Column(children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Full-order return intake and manual Cash/UPI evidence. '
              'No refund payout, GST credit note, journal reversal or '
              'saleable-stock release is available in this version.'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        if (detail != null)
          Flexible(
            flex: 3,
            child: SingleChildScrollView(
              child: Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Return #${detail['id']}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('Order #${detail['order_id']} · Status: ${detail['status']}'),
                      Text('Requested full amount: ₹${detail['refund_amount']}'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        if (detail['status'] == 'requested' &&
                            app.can('finance.reversal.approve'))
                          OutlinedButton(
                            onPressed: _busy ? null :
                                () => _inspect(_id(detail['id'])!),
                            child: const Text('Inspect physical return')),
                        if (detail['status'] == 'received' &&
                            app.can('finance.reversal.approve')) ...[
                          OutlinedButton(
                            onPressed: _busy ? null :
                                () => _decide(_id(detail['id'])!, true),
                            child: const Text('Approve evidence intake')),
                          OutlinedButton(
                            onPressed: _busy ? null :
                                () => _decide(_id(detail['id'])!, false),
                            child: const Text('Reject return')),
                        ],
                      ]),
                      if (detail['status'] == 'refund_pending') ...[
                        const Divider(),
                        Text(check['evidence_complete'] == true
                            ? 'Supporting evidence reconciled (NOT refunded)'
                            : 'Evidence incomplete; refund cannot be posted'),
                        Text('Verified evidence: ₹${check['verified_evidence_amount'] ?? '0.00'}'),
                        if (blockers.isNotEmpty)
                          Text('Review blockers: ${blockers.join(', ')}'),
                        const SizedBox(height: 8),
                        for (final payment in _originalPayments)
                          ListTile(
                            dense: true,
                            title: Text("${payment['method']} · ₹${payment['amount']}"),
                            subtitle: Text('Original payment #${payment['id']}'),
                            trailing: app.can('finance.reversal.create') &&
                                !_evidence.any((e) =>
                                  _id(e['order_payment_id']) ==
                                      _id(payment['id']))
                                ? TextButton(
                                    onPressed: _busy ? null : () =>
                                        _submitEvidence(_id(detail['id'])!,
                                            payment),
                                    child: const Text('Record evidence'))
                                : null,
                          ),
                        for (final proof in _evidence)
                          ListTile(
                            dense: true,
                            title: Text("${proof['method']} evidence · ${proof['status']}"),
                            subtitle: Text('Original payment #${proof['order_payment_id']}'),
                            trailing: proof['status'] == 'evidence_submitted' &&
                                    ((proof['method'] == 'upi' &&
                                        app.can('finance.bank_reconcile')) ||
                                    (proof['method'] == 'cash' &&
                                        app.can('finance.reversal.approve')))
                                ? TextButton(
                                    onPressed: _busy ? null :
                                        () => _verifyEvidence(proof),
                                    child: const Text('Verify manually'))
                                : null,
                          ),
                      ],
                      const Divider(),
                      const Text('No money has been refunded by ERP. '
                          'Original invoice, stock ledger and accounting '
                          'remain unchanged.'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Divider(),
        Expanded(
          flex: 2,
          child: branch == null
              ? const Center(child: Text('Select an authorized branch.'))
              : visibleReturns.isEmpty
                  ? Center(child: Text(visibleBranch
                      ? 'No prepaid return requests.'
                      : 'Loading authorised branch returns...'))
                  : ListView.builder(
                      itemCount: visibleReturns.length,
                      itemBuilder: (ctx, index) {
                        final item = visibleReturns[index];
                        final id = _id(item['id']);
                        return ListTile(
                          selected: _selectedId == id,
                          title: Text("Return #${item['id']} · ${item['status']}"),
                          subtitle: Text("Order #${item['order_id']} · ₹${item['refund_amount']}"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy || id == null
                              ? null : () => _reload(selectedId: id),
                        );
                      },
                    ),
        ),
      ])),
    );
  }
}
