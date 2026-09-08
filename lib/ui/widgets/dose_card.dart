import 'package:flutter/material.dart';

import '../../models/dose_recommendation.dart';
import '../theme.dart';

/// Une action à mener, avec sa dose, son pourquoi et son avertissement.
///
/// Trois règles du projet se voient ici :
///
/// - la quantité est mise en forme par le métier ([DoseRecommendation]), avec
///   virgule décimale et bascule g/kg, ml/L ;
/// - l'explication dit toujours POURQUOI, jamais « maintenez un pH correct » ;
/// - toute dose porte son avertissement quand il y en a un, et il n'est
///   jamais repliable.
class DoseCard extends StatelessWidget {
  const DoseCard({required this.action, this.rank, super.key});

  final DoseRecommendation action;

  /// Rang d'affichage, de 1 à n. L'ordre est métier, pas cosmétique :
  /// TAC, puis pH, puis chlore, puis l'équilibre.
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
            // La quantité, en très gros : c'est ce qu'on vient chercher, le
            // bidon déjà en main.
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
              // L'avertissement n'est jamais repliable ni tronqué : c'est une
              // exigence du projet, pas une décoration.
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

  /// « 90 % », « 9,6 % » — virgule décimale, sans décimale inutile.
  static String _percent(double value) {
    final String text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '${text.replaceAll('.', ',')} %';
  }
}
