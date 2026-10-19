import 'package:flutter/material.dart';

import '../../models/dose_recommendation.dart';
import '../theme.dart';

class DoseCard extends StatelessWidget {
  const DoseCard({required this.action, this.rank, super.key});

  final DoseRecommendation action;

  final int? rank;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = AppTheme.colorForPriority(action.priority);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (rank != null)
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$rank',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (rank != null) const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    action.title,
                    style: theme.textTheme.titleLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (action.quantity > 0) ...[
              Text(
                action.formattedQuantity,
                style: theme.textTheme.displayMedium,
              ),
              if (action.product != null)
                Text(
                  'de ${action.product!.label} '
                  '(${_percent(action.product!.activePercent)} de matière '
                  'active)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              if (action.isSplit) ...[
                const SizedBox(height: 6),
                Text(
                  'soit ${action.splitCount} apports de '
                  '${action.formattedQuantityPerDose}',
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ],
              const SizedBox(height: 12),
            ],
            Text(action.explanation, style: theme.textTheme.bodyLarge),
            if (action.warning != null) ...[
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.acid.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.acid.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded, color: AppTheme.acid),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        action.warning!,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _percent(double value) {
    final String text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '${text.replaceAll('.', ',')} %';
  }
}
