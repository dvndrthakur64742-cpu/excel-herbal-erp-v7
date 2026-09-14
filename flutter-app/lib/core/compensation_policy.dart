enum RewardAdjustmentKind {
  incentive,
  bonus,
  recognition,
  penalty,
  pointsAdjustment,
}

final class SalaryStructureDraft {
  const SalaryStructureDraft({
    required this.monthlyBasic,
    required this.hra,
    required this.fixedAllowance,
    required this.otherFixed,
  });

  final double monthlyBasic;
  final double hra;
  final double fixedAllowance;
  final double otherFixed;

  double get fixedMonthlyTotal =>
      monthlyBasic + hra + fixedAllowance + otherFixed;
}

final class PromotionEligibilitySnapshot {
  const PromotionEligibilitySnapshot({
    required this.currentDesignation,
    required this.nextDesignation,
    required this.points,
    required this.minimumPoints,
    required this.workingDays,
    required this.minimumWorkingDays,
    required this.averagePoints,
    required this.minimumAveragePoints,
  });

  final String currentDesignation;
  final String nextDesignation;
  final double points;
  final double minimumPoints;
  final int workingDays;
  final int minimumWorkingDays;
  final double averagePoints;
  final double minimumAveragePoints;

  bool get pointsEligible => points >= minimumPoints;
  bool get daysEligible => workingDays >= minimumWorkingDays;
  bool get averageEligible => averagePoints >= minimumAveragePoints;
  bool get eligible => pointsEligible && daysEligible && averageEligible;
}

abstract final class CompensationPolicy {
  /// Salary inputs are magnitudes. Negative values must never encode a hidden
  /// deduction or penalty; those belong to an explicit adjustment workflow.
  static String? validateSalaryStructure(SalaryStructureDraft draft) {
    final values = <double>[
      draft.monthlyBasic,
      draft.hra,
      draft.fixedAllowance,
      draft.otherFixed,
    ];
    if (values.any((value) => !value.isFinite || value < 0)) {
      return 'Salary structure values must be finite and non-negative.';
    }
    if (draft.fixedMonthlyTotal <= 0) {
      return 'Salary structure fixed monthly total must be greater than zero.';
    }
    return null;
  }

  static String? validateRewardAdjustment({
    required RewardAdjustmentKind kind,
    required double amount,
    required double points,
    required String reason,
  }) {
    if (reason.trim().isEmpty) return 'Reason is required.';
    if (!amount.isFinite || !points.isFinite) {
      return 'Amount and points must be finite.';
    }
    if (amount < 0) {
      return 'Amount must be a positive magnitude; use penalty type for deductions.';
    }
    if (kind != RewardAdjustmentKind.pointsAdjustment && points < 0) {
      return 'Negative points require the explicit points-adjustment workflow.';
    }
    if (kind == RewardAdjustmentKind.pointsAdjustment && points == 0) {
      return 'Points adjustment cannot be zero.';
    }
    if (kind != RewardAdjustmentKind.pointsAdjustment &&
        amount == 0 &&
        points == 0) {
      return 'Amount or points is required.';
    }
    return null;
  }

  static double signedPayrollAmount(
    RewardAdjustmentKind kind,
    double magnitude,
  ) {
    final normalized = magnitude.abs();
    return kind == RewardAdjustmentKind.penalty ? -normalized : normalized;
  }

  static bool makerCheckerAllowed({
    required int creatorEmployeeId,
    required int checkerEmployeeId,
  }) => creatorEmployeeId > 0 &&
      checkerEmployeeId > 0 &&
      creatorEmployeeId != checkerEmployeeId;

  /// Promotion eligibility is only a recommendation/preflight. The backend
  /// must still require an explicit authorised approval.
  static bool promotionMayBeApproved(PromotionEligibilitySnapshot snapshot) =>
      snapshot.currentDesignation.trim().isNotEmpty &&
      snapshot.nextDesignation.trim().isNotEmpty &&
      snapshot.currentDesignation.trim().toUpperCase() !=
          snapshot.nextDesignation.trim().toUpperCase() &&
      snapshot.eligible;

  /// A designation promotion must never manufacture reporting-manager,
  /// branch-authority, role, or capability grants.
  static const bool promotionMutatesAuthority = false;
}
