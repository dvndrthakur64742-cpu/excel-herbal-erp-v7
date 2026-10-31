import 'package:flutter_test/flutter_test.dart';

import 'package:excel_herbal_erp/core/api_paths.dart';

void main() {
  test('salary reward promotion paths are explicit and scoped', () {
    expect(ApiPaths.salaryStructures, '/payroll/salary-structures');
    expect(
      ApiPaths.salaryStructureApprove(12),
      '/payroll/salary-structures/12/approve',
    );
    expect(ApiPaths.performanceRewards, '/performance/rewards');
    expect(ApiPaths.rewardDecision(7), '/performance/rewards/7/decision');
    expect(ApiPaths.rewardPay(7), '/performance/rewards/7/pay');
    expect(ApiPaths.performancePromotions, '/performance/promotions');
    expect(
      ApiPaths.promotionDecision(9),
      '/performance/promotions/9/decision',
    );
  });
}
