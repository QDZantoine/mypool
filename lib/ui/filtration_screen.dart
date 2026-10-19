import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
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
    final bool? pumpOn = ref.watch(
      telemetryProvider.select((TelemetryState s) => s.telemetry?.pumpOn),
    );
    final bool? heaterOn = ref.watch(
      telemetryProvider.select((TelemetryState s) => s.telemetry?.heaterOn),
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
        const SectionHeader(label: 'Commande des équipements (Relais)'),
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                secondary: Icon(
                  Icons.power_settings_new,
                  color: (pumpOn ?? false)
                      ? AppTheme.chlorine
                      : theme.colorScheme.outline,
                ),
                title: const Text('Pompe de filtration (Relais 1)'),
                subtitle: Text(
                  (pumpOn ?? false)
                      ? 'Relais activé — LED bleue allumée'
                      : 'Relais désactivé — LED bleue éteinte',
                ),
                value: pumpOn ?? false,
                onChanged: (bool value) async {
                  try {
                    await ref
                        .read(deviceDriverProvider)
                        .setRelay(DeviceChannel.pump, on: value);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Erreur: $e')));
                    }
                  }
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: Icon(
                  Icons.local_fire_department,
                  color: (heaterOn ?? false)
                      ? AppTheme.acid
                      : theme.colorScheme.outline,
                ),
                title: const Text('Chauffage (Relais 2)'),
                subtitle: Text(
                  (pumpOn ?? false)
                      ? ((heaterOn ?? false)
                            ? 'Relais activé — LED rouge allumée'
                            : 'Relais désactivé — LED rouge éteinte')
                      : 'Sécurité : la filtration doit être en marche',
                ),
                value: heaterOn ?? false,
                onChanged: (pumpOn ?? false)
                    ? (bool value) async {
                        try {
                          await ref
                              .read(deviceDriverProvider)
                              .setRelay(DeviceChannel.heater, on: value);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erreur: $e')),
                            );
                          }
                        }
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

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
