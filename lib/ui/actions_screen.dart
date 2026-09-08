import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dose_recommendation.dart';
import '../state/derived_providers.dart';
import 'widgets/dose_card.dart';

/// Toutes les actions à mener, dans l'ordre métier.
class ActionsScreen extends ConsumerWidget {
  const ActionsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ActionsScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<DoseRecommendation> actions = ref.watch(recommendationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('À faire')),
      body: actions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Rien à corriger d’après la dernière mesure.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'L’ordre compte. Le TAC tient le pH en place, et le pH '
                    'commande la part de chlore réellement active : corriger '
                    'le chlore en premier consommerait du produit pour rien.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                for (int i = 0; i < actions.length; i++)
                  DoseCard(action: actions[i], rank: i + 1),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.timer_outlined,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Entre deux corrections, laissez filtrer et '
                          'remesurez : une dose versée sur une mesure qui '
                          'n’est plus à jour se paie en produit et en '
                          'allers-retours.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
