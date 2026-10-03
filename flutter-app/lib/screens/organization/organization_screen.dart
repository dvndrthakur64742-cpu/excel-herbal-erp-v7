import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_paths.dart';
import '../../core/business_format.dart';
import '../../core/commercial_integrity.dart';
import '../../core/providers.dart';
import '../../core/transaction_guardrails.dart';
import '../../core/overlay_transition.dart';
import '../../core/open_document.dart';
import '../../core/ui_error.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';
import '../../widgets/business_date_field.dart';
import '../../widgets/records_list.dart';
import '../../widgets/module_workspace.dart';
import '../common/record_detail_screen.dart';
import 'hr_lifecycle_screen.dart';

part 'organization_branches.dart';
part 'organization_documents.dart';
part 'organization_employees.dart';
part 'organization_products.dart';

class OrganizationScreen extends ConsumerStatefulWidget {
  const OrganizationScreen({super.key});
  @override
  ConsumerState<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends ConsumerState<OrganizationScreen> {
  int refresh = 0;
  String? message;

  void _setOrganizationState(VoidCallback update) => setState(update);

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final api = ref.watch(apiClientProvider);
    final tabs = <(String, Widget)>[];
    if (app.canAny(const [
      'organization.branch.view',
      'organization.branch.manage',
    ])) {
      tabs.add(('Branches', _branchesTab(app)));
    }
    if (app.canAny(const [
      'organization.employee.view',
      'organization.employee.manage',
    ])) {
      tabs.add(('Employees', _employeesTab(app, api)));
    }
    if (app.canAny(const [
      'organization.hr.view',
      'organization.hr.manage',
      'organization.hr.review',
    ])) {
      tabs.add((
        'HR Lifecycle',
        const HrLifecycleScreen(embedded: true),
      ));
    }
    if (app.canAny(const ['catalog.product.view', 'catalog.product.manage'])) {
      tabs.add(('Products', _productsTab(app, api)));
    }
    if (tabs.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No authorised organization functions.')),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Organization & Masters'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ModuleWorkspaceHeader(
                  title: 'Organization & Masters',
                  subtitle:
                      'Branches, employees, HR lifecycle and product masters in one authorised workspace.',
                  icon: Icons.corporate_fare_outlined,
                  contextLabel: app.currentBranchName,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: BranchSelector(),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ModuleMessageBanner(message: message!),
                ),
              Expanded(
                child: TabBarView(children: [for (final tab in tabs) tab.$2]),
              ),
            ],
          ),
        ),
      ),
    );
  }















  CommercialValues _commercialValues({
    required TextEditingController mrp,
    required TextEditingController sale,
    required TextEditingController ho,
    required TextEditingController bm,
    required TextEditingController salary,
    required TextEditingController office,
    required TextEditingController points,
    required TextEditingController purchaseCost,
  }) {
    final parsedMrp = CommercialIntegrity.parseRequired(mrp.text);
    final parsedSale = CommercialIntegrity.parseRequired(sale.text);
    final parsedHo = CommercialIntegrity.parseRequired(ho.text);
    final parsedBm = CommercialIntegrity.parseRequired(bm.text);
    final parsedSalary = CommercialIntegrity.parseRequired(salary.text);
    final parsedOffice = CommercialIntegrity.parseRequired(office.text);
    final parsedPoints = CommercialIntegrity.parseRequired(points.text);
    final parsedPurchase = CommercialIntegrity.parseRequired(purchaseCost.text);
    final error = CommercialIntegrity.validate(
      mrp: parsedMrp,
      salePrice: parsedSale,
      hoAmount: parsedHo,
      bmProfit: parsedBm,
      salaryFund: parsedSalary,
      officeExpense: parsedOffice,
      points: parsedPoints,
      purchaseCost: parsedPurchase,
    );
    if (error != null) throw Exception(error);
    return CommercialIntegrity.values(
      mrp: parsedMrp!,
      salePrice: parsedSale!,
      hoAmount: parsedHo!,
      bmProfit: parsedBm!,
      salaryFund: parsedSalary!,
      officeExpense: parsedOffice!,
      points: parsedPoints!,
      purchaseCost: parsedPurchase!,
    );
  }

  void _disposeControllers(Iterable<TextEditingController> controllers) {
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  Widget _moneyPair(
    TextEditingController a,
    String aLabel,
    TextEditingController b,
    String bLabel,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final first = TextField(
          controller: a,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: aLabel),
        );
        final second = TextField(
          controller: b,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: bLabel),
        );
        if (c.maxWidth < 480)
          return Column(children: [first, const SizedBox(height: 10), second]);
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
