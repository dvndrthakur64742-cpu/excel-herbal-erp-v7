import 'package:flutter/material.dart';

import '../theme/excel_brand.dart';

/// Consistent ERP branding for sign-in, desktop sidebar and mobile drawer.
///
/// The compiled asset is preferred. A missing/corrupt bundle must never
/// produce an empty white logo container, especially on a login screen.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.width,
    required this.height,
    this.assetPath = 'assets/branding/excel-herbal-logo.webp',
  });

  final double width;
  final double height;

  /// Allows a missing-asset regression test without touching production assets.
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final compact = width <= 72;
    return Semantics(
      label: 'Excel Herbal',
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          child: ColoredBox(
            color: Colors.white,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Center(
                child: compact
                    ? const Icon(
                        Icons.spa_outlined,
                        color: ExcelBrand.primaryDark,
                        size: 27,
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.spa_outlined,
                              size: 22,
                              color: ExcelBrand.primaryDark,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Excel Herbal',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: ExcelBrand.primaryDark,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
