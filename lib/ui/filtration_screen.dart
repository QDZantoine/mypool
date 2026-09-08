import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/filtration_planner.dart';
import '../models/filtration_schedule.dart';
import '../models/pool_config.dart';
import '../state/derived_providers.dart';
import '../state/providers.dart';
import '../state/telemetry_controller.dart';
import 'theme.dart';
import 'widgets/day_timeline.dart';
import 'widgets/section_header.dart';
import 'widgets/value_display.dart';

/// Planning de filtration conseillé.
///
/// L'écran explique d'où vient la durée : sans le « pourquoi », un utilisateur
/// à qui on annonce 13 h de filtration croit à une erreur.
class FiltrationScreen extends ConsumerWidget {
  const FiltrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final PoolConfig config = ref.watch(poolConfigProvider);
    final double? temperature = ref.watch(waterTemperatureProvider);
    final FiltrationSchedule? plan = ref.watch(filtrationPlanProvider);
    final Duration turnover = ref.watch(turnoverProvider);

    final bool filterAlert = ref.watch(
      telemetryProvider.select((TelemetryState s) => s.filterAlert),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppTheme.gutter,
        AppTheme.gutter,
        AppTheme.gutter,
        40 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: <Widget>[
        if (filterAlert) ...<Widget>[
          _Banner(
            icon: Icons.cleaning_services_outlined,
            tone: AppTheme.drift,
            title: 'Filtre à nettoyer',
            text:
                'La pompe a dépassé son quota d’heures depuis le dernier '
                'lavage. Un filtre encrassé filtre moins et consomme plus.',
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'DURÉE CONSEILLÉE AUJOURD’HUI',
                  style: AppTheme.eyebrow.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                if (plan == null)
                  const EmptyValue(
                    label: 'Température inconnue',
                    hint:
                        'La durée de filtration suit la température de '
                        'l’eau. Mesurez-la pour obtenir un planning.',
                  )
                else ...<Widget>[
                  ValueDisplay(
                    value: FiltrationCycle.formatDuration(
                      plan.recommendedMinutes,
                    ),
                    size: ValueSize.large,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    FiltrationPlanner.explain(
                      temperatureC: temperature!,
                      turnover: turnover,
                      recommended: plan.recommended,
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (plan != null && plan.cycles.isNotEmpty) ...[
          const SectionHeader(label: 'La journée'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.gutter),
              child: DayTimeline(cycles: plan.cycles),
            ),
          ),
          const SectionHeader(label: 'Créneaux'),
          for (final FiltrationCycle cycle in plan.cycles)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: Icon(
                    Icons.schedule,
                    size: 26,
                    color: AppTheme.chlorine,
                  ),
                  title: Text(
                    '${cycle.formattedStart} – ${cycle.formattedEnd}',
                    style: theme.textTheme.titleLarge,
                  ),
                  subtitle: Text(cycle.formattedDuration),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Le créneau le plus long couvre les heures chaudes : c’est là '
              'que le chlore se consomme le plus vite et que les algues '
              'démarrent.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Le bassin', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _Line(label: 'Volume', value: '${_number(config.volumeM3)} m³'),
                _Line(
                  label: 'Débit utile',
                  value: '${_number(config.effectiveFlowM3PerHour)} m³/h',
                  detail:
                      '${_number(config.pumpFlowM3PerHour)} m³/h annoncés, '
                      'à ${(config.pumpEfficiency * 100).round()} % de '
                      'rendement',
                ),
                _Line(
                  label: 'Une rotation complète',
                  value: FiltrationCycle.formatDuration(turnover.inMinutes),
                  detail: 'temps pour que toute l’eau passe dans le filtre',
                ),
                if (plan != null)
                  _Line(
                    label: 'Rotations par jour',
                    value: _number(plan.turnoverCount),
                  ),
              ],
            ),
          ),
        ),
        if (config.driver == DriverKind.mqtt) ...<Widget>[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.phonelink_off,
            tone: AppTheme.drift,
            title: 'Planning non mémorisé',
            text:
                'En liaison MQTT, le module n’enregistre pas le planning : '
                'la filtration s’arrête si le téléphone est éteint.',
          ),
        ],
      ],
    );
  }

  /// « 40 », « 7,5 » — virgule décimale, sans décimale inutile.
  static String _number(double value) {
    final String text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return text.replaceAll('.', ',');
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(value, style: theme.textTheme.titleMedium),
            ],
          ),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

/// Bandeau d'information, avec son titre et son explication.
///
/// Un titre en gras suivi d'une phrase : le titre suffit à savoir de quoi il
/// s'agit, la phrase à savoir quoi en faire. Un pavé de texte sans titre
/// oblige à tout lire pour décider si ça concerne.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.tone,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(color: tone),
                ),
                const SizedBox(height: AppTheme.gap),
                Text(text, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
