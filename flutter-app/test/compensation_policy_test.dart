import 'package:flutter_test/flutter_test.dart';

import 'package:excel_herbal_erp/core/compensation_policy.dart';

void main() {
  group('salary structure', () {
    test('accepts positive effective fixed components', () {
      const draft = SalaryStructureDraft(
        monthlyBasic: 10000,
        hra: 2000,
        fixedAllowance: 500,
        otherFixed: 250,
      );
      expect(CompensationPolicy.validateSalaryStructure(draft), isNull);
      expect(draft.fixedMonthlyTotal, 12750);
    });

    test('negative value cannot silently encode deduction', () {
      const draft = SalaryStructureDraft(
        monthlyBasic: 10000,
        hra: 0,
        fixedAllowance: -500,
        otherFixed: 0,
      );
      expect(CompensationPolicy.validateSalaryStructure(draft), isNotNull);
    });

    test('zero salary structure is blocked', () {
      const draft = SalaryStructureDraft(
        monthlyBasic: 0,
        hra: 0,
        fixedAllowance: 0,
        otherFixed: 0,
      );
      expect(CompensationPolicy.validateSalaryStructure(draft), isNotNull);
    });

    test('effective date must be an exact real calendar date', () {
      expect(CompensationPolicy.validEffectiveDate('2026-09-15'), isTrue);
      expect(CompensationPolicy.validEffectiveDate('2026-02-30'), isFalse);
      expect(CompensationPolicy.validEffectiveDate('15-09-2026'), isFalse);
      expect(CompensationPolicy.validEffectiveDate('2026-9-15'), isFalse);
    });
  });

  group('reward and penalty', () {
    test('penalty uses explicit positive magnitude and signed payroll effect', () {
      expect(
        CompensationPolicy.validateRewardAdjustment(
          kind: RewardAdjustmentKind.penalty,
          amount: 750,
          points: 0,
          reason: 'Approved disciplinary deduction',
        ),
        isNull,
      );
      expect(
        CompensationPolicy.signedPayrollAmount(
          RewardAdjustmentKind.penalty,
          750,
        ),
        -750,
      );
    });

    test('penalty can carry an explicit negative points consequence', () {
      expect(
        CompensationPolicy.validateRewardAdjustment(
          kind: RewardAdjustmentKind.penalty,
          amount: 750,
          points: -25,
          reason: 'Approved disciplinary deduction and points consequence',
        ),
        isNull,
      );
    });

    test('negative monetary input is rejected for every workflow', () {
      expect(
        CompensationPolicy.validateRewardAdjustment(
          kind: RewardAdjustmentKind.bonus,
          amount: -100,
          points: 0,
          reason: 'bad encoding',
        ),
        isNotNull,
      );
    });

    test('negative points are blocked outside penalty or points adjustment', () {
      expect(
        CompensationPolicy.validateRewardAdjustment(
          kind: RewardAdjustmentKind.bonus,
          amount: 100,
          points: -5,
          reason: 'Invalid hidden points deduction',
        ),
        isNotNull,
      );
    });

    test('points adjustment is explicit and cannot be zero', () {
      expect(
        CompensationPolicy.validateRewardAdjustment(
          kind: RewardAdjustmentKind.pointsAdjustment,
          amount: 0,
          points: -25,
          reason: 'Approved correction',
        ),
        isNull,
      );
      expect(
        CompensationPolicy.validateRewardAdjustment(
          kind: RewardAdjustmentKind.pointsAdjustment,
          amount: 0,
          points: 0,
          reason: 'No-op',
        ),
        isNotNull,
      );
    });

    test('maker checker is mandatory', () {
      expect(
        CompensationPolicy.makerCheckerAllowed(
          creatorEmployeeId: 17,
          checkerEmployeeId: 17,
        ),
        isFalse,
      );
      expect(
        CompensationPolicy.makerCheckerAllowed(
          creatorEmployeeId: 17,
          checkerEmployeeId: 18,
        ),
        isTrue,
      );
    });
  });

  group('promotion', () {
    test('eligibility uses server supplied thresholds', () {
      const snapshot = PromotionEligibilitySnapshot(
        currentDesignation: 'TRN',
        nextDesignation: 'TRAINER',
        points: 675,
        minimumPoints: 650,
        workingDays: 26,
        minimumWorkingDays: 25,
        averagePoints: 29,
        minimumAveragePoints: 29,
      );
      expect(snapshot.eligible, isTrue);
      expect(CompensationPolicy.promotionMayBeApproved(snapshot), isTrue);
    });

    test('eligibility never auto grants authority', () {
      expect(CompensationPolicy.promotionMutatesAuthority, isFalse);
    });

    test('same designation cannot be treated as promotion', () {
      const snapshot = PromotionEligibilitySnapshot(
        currentDesignation: 'ASM',
        nextDesignation: 'ASM',
        points: 2000,
        minimumPoints: 1000,
        workingDays: 30,
        minimumWorkingDays: 25,
        averagePoints: 70,
        minimumAveragePoints: 40,
      );
      expect(CompensationPolicy.promotionMayBeApproved(snapshot), isFalse);
      expect(CompensationPolicy.sameDesignation(' asm ', 'ASM'), isTrue);
    });

    test('request preflight rejects missing current designation', () {
      expect(
        CompensationPolicy.validatePromotionRequest(
          currentDesignation: '',
          nextDesignation: 'SM',
          incrementAmount: 500,
          effectiveFrom: '2026-09-15',
          reason: 'Progression request',
        ),
        isNotNull,
      );
    });

    test('request preflight rejects invalid date and same designation', () {
      expect(
        CompensationPolicy.validatePromotionRequest(
          currentDesignation: 'ASM',
          nextDesignation: 'ASM',
          incrementAmount: 500,
          effectiveFrom: '2026-09-15',
          reason: 'No real promotion',
        ),
        isNotNull,
      );
      expect(
        CompensationPolicy.validatePromotionRequest(
          currentDesignation: 'ASM',
          nextDesignation: 'SM',
          incrementAmount: 500,
          effectiveFrom: '2026-02-30',
          reason: 'Approved progression',
        ),
        isNotNull,
      );
    });

    test('request preflight accepts controlled progression input', () {
      expect(
        CompensationPolicy.validatePromotionRequest(
          currentDesignation: 'ASM',
          nextDesignation: 'SM',
          incrementAmount: 500,
          effectiveFrom: '2026-09-15',
          reason: 'Approved progression',
        ),
        isNull,
      );
    });
  });
}
