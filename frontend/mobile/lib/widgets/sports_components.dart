import 'package:flutter/material.dart';

import '../theme/sports_app_theme.dart';

/// Uppercase navy section label (reference: bold headings, all caps).
class SportsSectionTitle extends StatelessWidget {
  const SportsSectionTitle(
    this.text, {
    super.key,
    this.action,
    this.bottomSpacing = 12,
    this.fontSize = 12,
    this.color = SportsAppColors.accentBlue900,
  });

  final String text;
  final Widget? action;
  final double bottomSpacing;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    fontSize: fontSize,
                  ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Category chip row (white card, cyan when selected).
class SportsCategoryBubble extends StatelessWidget {
  const SportsCategoryBubble({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.width = 100,
    this.iconSize = 28,
    this.verticalPadding = 10,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final double iconSize;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      overlayColor: sportsAppInkNoHoverOverlay(),
        child: Container(
        width: width,
        padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? SportsAppColors.cyan.withValues(alpha: 0.12) : SportsAppColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? SportsAppColors.cyan : SportsAppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: SportsAppColors.navy.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? SportsAppColors.cyan : SportsAppColors.textMuted,
              size: iconSize,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    height: 1.15,
                    color: selected ? SportsAppColors.navy : SportsAppColors.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
