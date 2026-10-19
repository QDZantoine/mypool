import 'package:flutter/material.dart';

import '../theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.action,
    this.onAction,
    super.key,
  });

  final String label;

  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 12),
      child: Row(
        children: <Widget>[

          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 2,
              style: AppTheme.eyebrow.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.28),
            ),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),

              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(48, 44),
                ),
                child: Text(action!.toUpperCase(), style: AppTheme.eyebrow),
              ),
            ),
        ],
      ),
    );
  }
}
