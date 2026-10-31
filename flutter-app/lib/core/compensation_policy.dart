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

  /// Effective dates sent to compensation APIs must be real calendar dates in
  /// the exact business-date format expected by the v7 backend.
  static bool validEffectiveDate(String text) {
    final raw = text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return false;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return false;
    final canonical =
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return canonical == raw;
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
    final negativePointsAllowed =
        kind == RewardAdjustmentKind.pointsAdjustment ||
        kind == RewardAdjustmentKind.penalty;
    if (!negativePointsAllowed && points < 0) {
      return 'Negative points require the explicit points-adjustment or penalty workflow.';
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

  static bool sameDesignation(String current, String next) {
    final currentCode = current.trim().toUpperCase();
    final nextCode = next.trim().toUpperCase();
    return currentCode.isNotEmpty &&
        nextCode.isNotEmpty &&
        currentCode == nextCode;
  }

  /// Client-side preflight only. The backend remains authoritative for
  /// eligibility thresholds, branch scope, maker-checker and final approval.
  static String? validatePromotionRequest({
    required String currentDesignation,
    required String nextDesignation,
    required double incrementAmount,
    required String effectiveFrom,
    required String reason,
  }) {
    if (currentDesignation.trim().isEmpty) {
      return 'Current designation is required.';
    }
    if (nextDesignation.trim().isEmpty) {
      return 'Next designation is required.';
    }
    if (sameDesignation(currentDesignation, nextDesignation)) {
      return 'Next designation must be different from the current designation.';
    }
    if (!incrementAmount.isFinite || incrementAmount < 0) {
      return 'Increment must be finite and non-negative.';
    }
    if (!validEffectiveDate(effectiveFrom)) {
      return 'Effective date must be a valid YYYY-MM-DD date.';
    }
    if (reason.trim().isEmpty) return 'Reason is required.';
    return null;
  }

  /// Promotion eligibility is only a recommendation/preflight. The backend
  /// must still require an explicit authorised approval.
  static bool promotionMayBeApproved(PromotionEligibilitySnapshot snapshot) =>
      snapshot.currentDesignation.trim().isNotEmpty &&
      snapshot.nextDesignation.trim().isNotEmpty &&
      !sameDesignation(
        snapshot.currentDesignation,
        snapshot.nextDesignation,
      ) &&
      snapshot.eligible;

  /// A designation promotion must never manufacture reporting-manager,
  /// branch-authority, role, or capability grants.
  static const bool promotionMutatesAuthority = false;
}
