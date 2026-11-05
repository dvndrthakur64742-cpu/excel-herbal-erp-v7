import 'package:excel_herbal_erp/core/delegation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 9, 14, 10);
  final end = DateTime(2026, 9, 14, 18);

  ActingDelegation grant({
    int delegator = 10,
    int delegate = 20,
    int branch = 3,
    String action = 'daily.final_post',
    String reason = 'BM approved leave',
    bool active = true,
  }) {
    return ActingDelegation(
      delegatorEmployeeId: delegator,
      delegateEmployeeId: delegate,
      branchId: branch,
      actionCode: action,
      startsAt: start,
      endsAt: end,
      reason: reason,
      active: active,
    );
  }

  test('valid delegation is exact action, branch and time bound', () {
    final result = DelegationPolicy.validateDraft(
      delegation: grant(),
      delegatorAuthorisedBranches: const {3},
      delegatorAuthorisedActions: const {'daily.final_post'},
      delegateIsActiveEmployee: true,
    );

    expect(result.isValid, isTrue);
  });

  test('self delegation is rejected', () {
    final result = DelegationPolicy.validateDraft(
      delegation: grant(delegator: 10, delegate: 10),
      delegatorAuthorisedBranches: const {3},
      delegatorAuthorisedActions: const {'daily.final_post'},
      delegateIsActiveEmployee: true,
    );

    expect(result.isValid, isFalse);
    expect(result.errors.join(' '), contains('Self delegation'));
  });

  test('delegator cannot delegate authority they do not own', () {
    final result = DelegationPolicy.validateDraft(
      delegation: grant(),
      delegatorAuthorisedBranches: const {3},
      delegatorAuthorisedActions: const {'daily.issue'},
      delegateIsActiveEmployee: true,
    );

    expect(result.isValid, isFalse);
    expect(result.errors.join(' '), contains('not authorised for this action'));
  });

  test('overlapping delegation for same action and branch is blocked', () {
    final result = DelegationPolicy.validateDraft(
      delegation: grant(delegate: 21),
      delegatorAuthorisedBranches: const {3},
      delegatorAuthorisedActions: const {'daily.final_post'},
      delegateIsActiveEmployee: true,
      existing: [grant()],
    );

    expect(result.isValid, isFalse);
    expect(result.errors.join(' '), contains('Overlapping delegation'));
  });

  test('delegated authority is not a generic branch grant', () {
    final delegation = grant();

    expect(
      DelegationPolicy.canExerciseDelegatedAuthority(
        delegation: delegation,
        actingEmployeeId: 20,
        branchId: 3,
        actionCode: 'daily.issue',
        at: DateTime(2026, 9, 14, 12),
        delegateIsActiveEmployee: true,
        delegatorStillAuthorised: true,
      ),
      isFalse,
    );
  });

  test('cross branch action is rejected unless exact branch matches grant', () {
    final delegation = grant();

    expect(
      DelegationPolicy.canExerciseDelegatedAuthority(
        delegation: delegation,
        actingEmployeeId: 20,
        branchId: 4,
        actionCode: 'daily.final_post',
        at: DateTime(2026, 9, 14, 12),
        delegateIsActiveEmployee: true,
        delegatorStillAuthorised: true,
      ),
      isFalse,
    );
  });

  test('expired or revoked delegation cannot be exercised', () {
    expect(
      DelegationPolicy.canExerciseDelegatedAuthority(
        delegation: grant(),
        actingEmployeeId: 20,
        branchId: 3,
        actionCode: 'daily.final_post',
        at: DateTime(2026, 9, 15, 12),
        delegateIsActiveEmployee: true,
        delegatorStillAuthorised: true,
      ),
      isFalse,
    );
    expect(
      DelegationPolicy.canExerciseDelegatedAuthority(
        delegation: grant(active: false),
        actingEmployeeId: 20,
        branchId: 3,
        actionCode: 'daily.final_post',
        at: DateTime(2026, 9, 14, 12),
        delegateIsActiveEmployee: true,
        delegatorStillAuthorised: true,
      ),
      isFalse,
    );
  });

  test('delegation never defeats maker-checker separation', () {
    expect(
      DelegationPolicy.canExerciseDelegatedAuthority(
        delegation: grant(),
        actingEmployeeId: 20,
        branchId: 3,
        actionCode: 'daily.final_post',
        at: DateTime(2026, 9, 14, 12),
        delegateIsActiveEmployee: true,
        delegatorStillAuthorised: true,
        transactionMakerEmployeeId: 20,
      ),
      isFalse,
    );
  });

  test('automatic fallback stays inside branch and uses highest available senior', () {
    final picked = DelegationPolicy.selectSameBranchFallback(
      primaryAuthorityUnavailable: true,
      branchId: 3,
      candidates: const [
        FallbackAuthorityCandidate(
          employeeId: 31,
          branchId: 3,
          authorityRank: 20,
          availability: EmployeeAvailability.available,
          canPerformAction: true,
        ),
        FallbackAuthorityCandidate(
          employeeId: 32,
          branchId: 3,
          authorityRank: 30,
          availability: EmployeeAvailability.available,
          canPerformAction: true,
        ),
        FallbackAuthorityCandidate(
          employeeId: 99,
          branchId: 4,
          authorityRank: 100,
          availability: EmployeeAvailability.available,
          canPerformAction: true,
        ),
      ],
    );

    expect(picked?.employeeId, 32);
  });

  test('automatic fallback does not activate while primary is available', () {
    final picked = DelegationPolicy.selectSameBranchFallback(
      primaryAuthorityUnavailable: false,
      branchId: 3,
      candidates: const [
        FallbackAuthorityCandidate(
          employeeId: 31,
          branchId: 3,
          authorityRank: 20,
          availability: EmployeeAvailability.available,
          canPerformAction: true,
        ),
      ],
    );

    expect(picked, isNull);
  });

  test('leave, no check-in and manual unavailable candidates are skipped', () {
    final picked = DelegationPolicy.selectSameBranchFallback(
      primaryAuthorityUnavailable: true,
      branchId: 3,
      candidates: const [
        FallbackAuthorityCandidate(
          employeeId: 31,
          branchId: 3,
          authorityRank: 50,
          availability: EmployeeAvailability.approvedLeave,
          canPerformAction: true,
        ),
        FallbackAuthorityCandidate(
          employeeId: 32,
          branchId: 3,
          authorityRank: 40,
          availability: EmployeeAvailability.notCheckedIn,
          canPerformAction: true,
        ),
        FallbackAuthorityCandidate(
          employeeId: 33,
          branchId: 3,
          authorityRank: 30,
          availability: EmployeeAvailability.manuallyUnavailable,
          canPerformAction: true,
        ),
        FallbackAuthorityCandidate(
          employeeId: 34,
          branchId: 3,
          authorityRank: 20,
          availability: EmployeeAvailability.available,
          canPerformAction: true,
        ),
      ],
    );

    expect(picked?.employeeId, 34);
  });
}
