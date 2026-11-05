/// Read-only, plain-English guidance for the prepaid return lifecycle.
///
/// The backend owns state transitions, approvals, evidence and branch scope.
/// Recording or verifying evidence never means ERP has paid a refund,
/// generated a credit note or restored stock.
class PrepaidReturnGuidance {
  const PrepaidReturnGuidance({
    required this.title,
    required this.explanation,
  });

  final String title;
  final String explanation;

  static PrepaidReturnGuidance forStatus({
    required String status,
    required bool evidenceComplete,
  }) {
    switch (status) {
      case 'requested':
        return const PrepaidReturnGuidance(
          title: 'Next: physical inspection',
          explanation:
              'An authorised reviewer must check the returned goods in person. '
              'No stock is released and no refund is paid.',
        );
      case 'received':
        return const PrepaidReturnGuidance(
          title: 'Next: independent return decision',
          explanation:
              'A different authorised reviewer must approve or reject the '
              'inspected return. No refund has been paid.',
        );
      case 'refund_pending':
        if (evidenceComplete) {
          return const PrepaidReturnGuidance(
            title: 'Evidence checked — no payout recorded',
            explanation:
                'Supporting refund evidence has been reconciled. '
                'ERP cannot pay a refund, issue a credit note or release stock '
                'in this version. Finance must follow its authorised '
                'external settlement process.',
          );
        }
        return const PrepaidReturnGuidance(
          title: 'Next: record and verify refund evidence',
          explanation:
              'Record evidence for the original payment and have a different '
              'authorised reviewer verify it. Evidence is not proof that ERP '
              'disbursed a refund.',
        );
      case 'rejected':
        return const PrepaidReturnGuidance(
          title: 'Return rejected',
          explanation:
              'This request was rejected. Review the recorded decision. '
              'The original invoice, stock ledger and accounting remain unchanged.',
        );
      default:
        return const PrepaidReturnGuidance(
          title: 'Review return status with Finance',
          explanation:
              'This return state needs an authorised review. Do not infer '
              'a payout, credit note, journal reversal or stock release.',
        );
    }
  }
}
