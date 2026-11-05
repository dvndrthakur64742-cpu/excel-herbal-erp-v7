import 'package:flutter/material.dart';

/// Visual hierarchy shared by the Home and Reports workspaces.
/// Displays only caller-supplied, already-authorised information.
class WorkspaceBanner extends StatelessWidget {
  const WorkspaceBanner({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.footer,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final textTheme = Theme.of(context).textTheme;
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 20 : 30,
              vertical: compact ? 22 : 28,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF123127),
                  Color(0xFF16513C),
                  Color(0xFF0A7047),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16102F23),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 8,
                                color: Color(0xFF9AE6B7),
                              ),
                              const SizedBox(width: 9),
                              Flexible(
                                child: Text(
                                  eyebrow.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: const Color(0xFFB4EBCB),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            maxLines: compact ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: (compact
                                    ? textTheme.headlineSmall
                                    : textTheme.headlineMedium)
                                ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.18,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFD5E8DD),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 24),
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .11),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .17),
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 40),
                      ),
                    ],
                  ],
                ),
                if (footer != null) ...[
                  const SizedBox(height: 19),
                  footer!,
                ],
              ],
            ),
          );
        },
      );
}
