enum EmployeeAvailability {
  available,
  approvedLeave,
  notCheckedIn,
  manuallyUnavailable,
}

class ActingDelegation {
  const ActingDelegation({
    required this.delegatorEmployeeId,
    required this.delegateEmployeeId,
    required this.branchId,
    required this.actionCode,
    required this.startsAt,
    required this.endsAt,
    required this.reason,
    this.active = true,
  });

  final int delegatorEmployeeId;
  final int delegateEmployeeId;
  final int branchId;
  final String actionCode;
  final DateTime startsAt;
  final DateTime endsAt;
  final String reason;
  final bool active;

  bool isEffectiveAt(DateTime at) {
    return active &&
        !at.isBefore(startsAt) &&
        !at.isAfter(endsAt);
  }
}

class DelegationValidation {
  const DelegationValidation(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

class FallbackAuthorityCandidate {
  const FallbackAuthorityCandidate({
    required this.employeeId,
    required this.branchId,
    required this.authorityRank,
    required this.availability,
    required this.canPerformAction,
  });

  final int employeeId;
  final int branchId;

  /// Higher value means a more senior authority inside the same branch scope.
  final int authorityRank;
  final EmployeeAvailability availability;
  final bool canPerformAction;
}

class DelegationPolicy {
  const DelegationPolicy._();

  static DelegationValidation validateDraft({
    required ActingDelegation delegation,
    required Set<int> delegatorAuthorisedBranches,
    required Set<String> delegatorAuthorisedActions,
    required bool delegateIsActiveEmployee,
    Iterable<ActingDelegation> existing = const <ActingDelegation>[],
  }) {
    final errors = <String>[];
    final action = delegation.actionCode.trim();
    final reason = delegation.reason.trim();

    if (delegation.delegatorEmployeeId <= 0 || delegation.delegateEmployeeId <= 0) {
      errors.add('Delegator and delegate must be valid employees.');
    }
    if (delegation.delegatorEmployeeId == delegation.delegateEmployeeId) {
      errors.add('Self delegation is not allowed.');
    }
    if (delegation.branchId <= 0) {
      errors.add('Delegation requires one exact branch.');
    }
    if (action.isEmpty) {
      errors.add('Delegation requires one exact action.');
    }
    if (reason.isEmpty) {
      errors.add('Delegation reason is required.');
    }
    if (!delegation.endsAt.isAfter(delegation.startsAt)) {
      errors.add('Delegation end must be after start.');
    }
    if (!delegatorAuthorisedBranches.contains(delegation.branchId)) {
      errors.add('Delegator is not authorised for this branch.');
    }
    if (!delegatorAuthorisedActions.contains(action)) {
      errors.add('Delegator is not authorised for this action.');
    }
    if (!delegateIsActiveEmployee) {
      errors.add('Delegate must be an active employee.');
    }

    for (final current in existing) {
      if (!current.active) continue;
      if (current.branchId != delegation.branchId) continue;
      if (current.actionCode.trim() != action) continue;
      if (current.delegatorEmployeeId != delegation.delegatorEmployeeId) continue;
      if (_windowsOverlap(current, delegation)) {
        errors.add(
          'Overlapping delegation for the same action and branch is not allowed.',
        );
        break;
      }
    }

    return DelegationValidation(List.unmodifiable(errors));
  }

  static bool canExerciseDelegatedAuthority({
    required ActingDelegation delegation,
    required int actingEmployeeId,
    required int branchId,
    required String actionCode,
    required DateTime at,
    required bool delegateIsActiveEmployee,
    required bool delegatorStillAuthorised,
    int? transactionMakerEmployeeId,
  }) {
    if (!delegation.active ||
        !delegateIsActiveEmployee ||
        !delegatorStillAuthorised) {
      return false;
    }
    if (actingEmployeeId != delegation.delegateEmployeeId) return false;
    if (branchId != delegation.branchId) return false;
    if (actionCode.trim() != delegation.actionCode.trim()) return false;
    if (!delegation.isEffectiveAt(at)) return false;

    // Delegation must never defeat maker-checker separation.
    if (transactionMakerEmployeeId != null &&
        transactionMakerEmployeeId == actingEmployeeId) {
      return false;
    }

    return true;
  }

  static FallbackAuthorityCandidate? selectSameBranchFallback({
    required bool primaryAuthorityUnavailable,
    required int branchId,
    required Iterable<FallbackAuthorityCandidate> candidates,
    int? transactionMakerEmployeeId,
  }) {
    if (!primaryAuthorityUnavailable) return null;

    final eligible = candidates.where((candidate) {
      if (candidate.branchId != branchId) return false;
      if (!candidate.canPerformAction) return false;
      if (candidate.availability != EmployeeAvailability.available) return false;
      if (transactionMakerEmployeeId != null &&
          candidate.employeeId == transactionMakerEmployeeId) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final rank = b.authorityRank.compareTo(a.authorityRank);
        if (rank != 0) return rank;
        return a.employeeId.compareTo(b.employeeId);
      });

    return eligible.isEmpty ? null : eligible.first;
  }

  static bool _windowsOverlap(ActingDelegation a, ActingDelegation b) {
    return !a.endsAt.isBefore(b.startsAt) && !b.endsAt.isBefore(a.startsAt);
  }
}
