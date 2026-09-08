import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/water_balance.dart';
import '../models/dose_recommendation.dart';
import '../models/water_reading.dart';
import '../state/derived_providers.dart';
import '../state/providers.dart';
import '../state/telemetry_controller.dart';
import 'actions_screen.dart';
import 'reading_entry_screen.dart';
import 'theme.dart';
import 'widgets/dose_card.dart';
import 'widgets/live_panel.dart';
import 'widgets/reading_row.dart';
import 'widgets/section_header.dart';

/// Accueil.
///
/// L'écran est organisé par ORIGINE DE LA MESURE, et non par ordre
/// alphabétique ou par importance chimique. C'est ce qui répond à la question
/// réelle de l'utilisateur : qu'est-ce qui se surveille tout seul, et
/// qu'est-ce que je dois aller tester moi-même ?
///
/// L'ordre des blocs suit ce qu'on vient chercher :
///   1. l'eau est-elle bonne (verdict, en mots) ;
///   2. qu'est-ce que je verse (l'action la plus urgente, avec sa dose) ;
///   3. ce qui est suivi en continu ;
///   4. ce qui reste à tester à la main, avec l'âge de la dernière mesure.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WaterReading? reading = ref.watch(effectiveReadingProvider);
    final WaterReading? entered = ref.watch(lastEnteredReadingProvider);
    final List<DoseRecommendation> actions = ref.watch(recommendationsProvider);
    final TelemetryState telemetry = ref.watch(telemetryProvider);
    final WaterBalanceResult? balance = ref.watch(waterBalanceProvider);
    final List<WaterParameter> manual = ref.watch(manualParametersProvider);

    final _Verdict verdict = _Verdict.from(
      reading: reading,
      actions: actions,
      telemetry: telemetry,
    );

    return RefreshIndicator(
      color: AppTheme.chlorine,
      onRefresh: () => ref.read(readingsProvider.notifier).load(),
      child: ListView(
        // Le bas réserve la hauteur de la barre de gestes : sans cela, la
        // dernière carte passe sous l'indicateur d'accueil et son contenu
        // devient inatteignable.
        padding: EdgeInsets.fromLTRB(
          AppTheme.gutter,
          AppTheme.gutter,
          AppTheme.gutter,
          40 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: <Widget>[
          LivePanel(
            verdict: verdict.title,
            detail: verdict.detail,
            tone: verdict.tone,
            isLive: telemetry.hasLiveValues,
            linkLabel: verdict.linkLabel,
            ph: reading?.ph,
            temperatureC: reading?.temperature,
            // L'action n'apparaît que quand il n'y a rien à montrer : une
            // fois les mesures là, le panneau redevient un cadran et le
            // bouton irait en concurrence avec l'action à mener.
            actionLabel: reading == null ? 'Saisir une mesure' : null,
            onAction: reading == null
                ? () => ReadingEntryScreen.open(context)
                : null,
          ),

          if (actions.isNotEmpty) ...[
            SectionHeader(
              label: actions.length == 1 ? 'À faire' : 'À faire, dans l’ordre',
              action: actions.length > 1 ? 'Les ${actions.length}' : null,
              onAction: actions.length > 1
                  ? () => ActionsScreen.open(context)
                  : null,
            ),
            // Une seule action détaillée : l'ordre est chimique, et verser le
            // chlore avant d'avoir corrigé le pH consomme du produit pour
            // rien.
            DoseCard(action: actions.first, rank: 1),
            if (actions.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Le reste après avoir filtré et remesuré.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],

          // Les blocs de mesure ne s'affichent que s'il y a quelque chose à
          // lire. Deux échelles vides n'apprennent rien et occupent l'écran
          // que l'invitation à mesurer devrait remplir.
          if (reading != null) ...<Widget>[
            const SectionHeader(label: 'Suivi en continu'),
            _Panel(
              children: <Widget>[
                for (final WaterParameter parameter in sensorParameters)
                  ReadingRow(
                    parameter: parameter,
                    value: reading.valueOf(parameter),
                  ),
              ],
            ),
            if (!telemetry.hasLiveValues)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  telemetry.errorMessage ??
                      'Sans sonde, ces valeurs viennent de votre saisie.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],

          if (entered != null) ...<Widget>[
            SectionHeader(
              label: 'À tester à la bandelette',
              action: 'Saisir',
              onAction: () => ReadingEntryScreen.open(context),
            ),
            _Panel(
              children: <Widget>[
                for (final WaterParameter parameter in manual)
                  ReadingRow(
                    parameter: parameter,
                    value: entered.valueOf(parameter),
                    age: _ageOf(entered, parameter, telemetry),
                    onTap: () => ReadingEntryScreen.open(context),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Le TAC change la dose de pH : testez-le une fois par mois.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Le TAC, le TH et le stabilisant ne se lisent qu’à la '
                'bandelette, et le TAC change la dose de pH.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

          if (balance != null) ...[
            const SectionHeader(label: 'Équilibre calco-carbonique'),
            _BalancePanel(balance: balance),
          ],
        ],
      ),
    );
  }

  /// Âge de la mesure manuelle, quand la valeur existe.
  static Duration? _ageOf(
    WaterReading entered,
    WaterParameter parameter,
    TelemetryState telemetry,
  ) {
    if (entered.valueOf(parameter) == null) {
      return null;
    }
    // L'instant de référence vient de la sonde quand elle parle, sinon de
    // l'horloge : c'est le seul endroit de l'application qui la lit, et c'est
    // pour un affichage, pas pour un calcul.
    final DateTime now = telemetry.telemetry?.receivedAt ?? DateTime.now();
    final Duration age = now.difference(entered.takenAt);
    return age.isNegative ? Duration.zero : age;
  }
}

/// Ce que l'écran annonce en premier.
class _Verdict {
  const _Verdict({
    required this.title,
    required this.detail,
    required this.tone,
    required this.linkLabel,
  });

  final String title;
  final String detail;
  final Color tone;
  final String linkLabel;

  /// Compose le verdict.
  ///
  /// Il dit d'abord ce qui compte : s'il y a quelque chose à verser, c'est ça
  /// le verdict. « Eau équilibrée » n'a de sens que si rien n'est à corriger.
  static _Verdict from({
    required WaterReading? reading,
    required List<DoseRecommendation> actions,
    required TelemetryState telemetry,
  }) {
    final String linkLabel = telemetry.hasLiveValues
        ? 'Sonde connectée'
        : telemetry.isModuleOnline
        ? 'Sonde silencieuse'
        : 'Sonde hors ligne';

    if (reading == null || reading.isEmpty) {
      return _Verdict(
        title: 'Pas encore de mesure',
        detail: 'Testez l’eau à la bandelette, ou connectez une sonde.',
        tone: AppTheme.unmeasured,
        linkLabel: linkLabel,
      );
    }

    if (actions.isEmpty) {
      return _Verdict(
        title: 'Rien à verser',
        detail: 'Toutes les valeurs mesurées sont dans leur plage.',
        tone: AppTheme.inRange,
        linkLabel: linkLabel,
      );
    }

    final DoseRecommendation first = actions.first;
    return _Verdict(
      title: first.title,
      detail: first.quantity > 0
          ? '${first.formattedQuantity}'
                '${first.product == null ? '' : ' de ${first.product!.label}'}'
                '${first.isSplit ? ', en ${first.splitCount} apports' : ''}.'
          : first.explanation,
      tone: AppTheme.colorForPriority(first.priority),
      linkLabel: linkLabel,
    );
  }
}

/// Groupe de lignes de mesure, séparées par des filets.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.gutter,
                ),
                child: Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outline
                      .withValues(alpha: 0.15),
                ),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel({required this.balance});

  final WaterBalanceResult balance;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = switch (balance.verdict) {
      WaterBalanceVerdict.balanced => AppTheme.inRange,
      WaterBalanceVerdict.corrosive => AppTheme.acid,
      WaterBalanceVerdict.scaling => AppTheme.drift,
      WaterBalanceVerdict.unknown => AppTheme.unmeasured,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Text(
                    'INDICE DE LANGELIER',
                    style: AppTheme.eyebrow.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                Text(
                  balance.formattedIndex,
                  style: theme.textTheme.displaySmall?.copyWith(color: tone),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              WaterBalance.explain(balance.verdict),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
