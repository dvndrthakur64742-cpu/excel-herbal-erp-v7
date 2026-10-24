import 'package:flutter/material.dart';

import 'employee_cashier_evidence_uat.dart';

/// Disposable UAT transport integration for the existing Finance Review.
/// Caller owns a server-authenticated, GET-only UAT adapter. Office V7 never
/// supplies this callback. No fake Cashier or PSP verification on live builds.
class FinanceEvidenceUatApiLoader extends StatefulWidget {
  const FinanceEvidenceUatApiLoader({
    super.key,
    required this.getAuthenticatedUatPage,
    required this.companyId,
    required this.branchId,
    required this.employeeId,
    required this.from,
    required this.to,
  });

  final Future<dynamic> Function() getAuthenticatedUatPage;
  final int companyId;
  final int branchId;
  final int employeeId;
  final String from;
  final String to;

  @override
  State<FinanceEvidenceUatApiLoader> createState() =>
      _FinanceEvidenceUatApiLoaderState();
}

class _FinanceEvidenceUatApiLoaderState
    extends State<FinanceEvidenceUatApiLoader> {
  late Future<CashierEvidenceUatPage> _request;

  Future<CashierEvidenceUatPage> _read() async {
    final response = await widget.getAuthenticatedUatPage();
    if (!mounted) throw StateError('Stale Finance evidence request.');
    return CashierEvidenceUatPage.fromResponse(
      response: response,
      companyId: widget.companyId,
      branchId: widget.branchId,
      employeeId: widget.employeeId,
      from: widget.from,
      to: widget.to,
    );
  }

  @override
  void initState() {
    super.initState();
    _request = _read();
  }

  @override
  void didUpdateWidget(covariant FinanceEvidenceUatApiLoader old) {
    super.didUpdateWidget(old);
    if (old.companyId != widget.companyId ||
        old.branchId != widget.branchId ||
        old.employeeId != widget.employeeId ||
        old.from != widget.from ||
        old.to != widget.to ||
        old.getAuthenticatedUatPage != widget.getAuthenticatedUatPage) {
      _request = _read();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<CashierEvidenceUatPage>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Card(
              child: ListTile(
                leading: CircularProgressIndicator(),
                title: Text('Checking isolated Finance evidence…'),
              ),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Card(
              child: ListTile(
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('UAT Cashier evidence unavailable'),
                subtitle: Text(
                  'No Cash receipt or Finance approval is verified by this screen.',
                ),
              ),
            );
          }
          return CashierEvidenceUatSection(page: snapshot.data!);
        },
      );
}
