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
    expect(ApiPaths.rewardSettlementPreflight(7),
        '/performance/rewards/7/settlement-preflight');
    expect(ApiPaths.performancePromotions, '/performance/promotions');
    expect(ApiPaths.performancePromotionEmployees, '/performance/promotion-employees');
    expect(ApiPaths.performanceRewardEmployees, '/performance/reward-employees');
    expect(
      ApiPaths.promotionDecision(9),
      '/performance/promotions/9/decision',
    );
  });
}
