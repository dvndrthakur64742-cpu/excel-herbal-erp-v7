import 'package:flutter/material.dart';

import '../core/business_format.dart';

/// A shared, readable status badge for operational ERP screens.
///
/// Semantic text and an icon are always shown, so the meaning does not rely
/// on colour alone. Status is visual only: access rights remain server-owned.
class ErpStatusBadge extends StatelessWidget {
  const ErpStatusBadge({
    super.key,
    required this.status,
    this.label,
  });

  final String status;
  /// Optional workflow-specific wording, e.g. Issued -> Evening Pending.
  final String? label;

  static StatusBadgeTone toneFor(String rawStatus) {
    switch (rawStatus.trim().toLowerCase()) {
      case 'completed':
      case 'received':
      case 'verified':
      case 'posted':
      case 'paid':
        return const StatusBadgeTone(
          Color(0xFFDEF4E6),
          Color(0xFF135C35),
          Icons.check_circle_outline_rounded,
        );
      case 'evening_draft':
      case 'morning_draft':
      case 'draft':
        return const StatusBadgeTone(
          Color(0xFFE1EEFF),
          Color(0xFF174B83),
          Icons.edit_note_rounded,
        );
      case 'evening_submitted':
      case 'stock_requested':
      case 'submitted':
      case 'pending':
      case 'approved':
      case 'issued':
      case 'in_transit':
        return const StatusBadgeTone(
          Color(0xFFFFE8C7),
          Color(0xFF754400),
          Icons.schedule_rounded,
        );
      case 'cancelled':
      case 'rejected':
      case 'mismatch':
        return const StatusBadgeTone(
          Color(0xFFFFE1E1),
          Color(0xFF8C2525),
          Icons.highlight_off_rounded,
        );
      default:
        return const StatusBadgeTone(
          Color(0xFFEDF0F3),
          Color(0xFF35445A),
          Icons.info_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(status);
    final displayLabel = label ?? BusinessFormat.status(status);
    return Semantics(
      label: 'Status: $displayLabel',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tone.icon, color: tone.foreground, size: 15),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  displayLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tone.foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusBadgeTone {
  const StatusBadgeTone(this.background, this.foreground, this.icon);
  final Color background;
  final Color foreground;
  final IconData icon;
}
