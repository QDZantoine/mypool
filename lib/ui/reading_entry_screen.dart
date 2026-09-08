import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/water_reading.dart';
import '../state/derived_providers.dart';
import '../state/providers.dart';
import '../state/telemetry_controller.dart';
import 'theme.dart';
import 'widgets/measure_scale.dart';
import 'widgets/section_header.dart';

/// Saisie des valeurs qu'aucune sonde ne mesure.
///
/// L'écran a changé de nature : ce n'est plus « saisir une mesure », c'est
/// « compléter ce que la sonde ne sait pas lire ». Le pH et la température
/// n'y figurent qu'en repli, quand aucune sonde ne parle — sinon les
/// reproposer inviterait à écraser une mesure fraîche par un souvenir.
///
/// Deux principes du projet gouvernent le reste :
///
/// - **on saisit ce qu'on a mesuré** : aucun champ n'est obligatoire, et un
///   champ vide reste vide, il ne devient jamais zéro ;
/// - **aucune donnée à saisir deux fois** : les champs partent de la dernière
///   valeur connue, qu'il suffit de corriger.
class ReadingEntryScreen extends ConsumerStatefulWidget {
  const ReadingEntryScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReadingEntryScreen()));
  }

  @override
  ConsumerState<ReadingEntryScreen> createState() => _ReadingEntryScreenState();
}

class _ReadingEntryScreenState extends ConsumerState<ReadingEntryScreen> {
  final Map<WaterParameter, TextEditingController> _controllers =
      <WaterParameter, TextEditingController>{};
  final Map<WaterParameter, double?> _values = <WaterParameter, double?>{};
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    for (final WaterParameter parameter in WaterParameter.values) {
      _controllers[parameter] = TextEditingController();
      _controllers[parameter]!.addListener(() => _onChanged(parameter));
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Remplit les champs avec la dernière valeur connue, une seule fois.
  ///
  /// Une seule fois : réappliquer à chaque reconstruction écraserait ce que
  /// l'utilisateur est en train de taper.
  void _seed(WaterReading? previous) {
    if (_seeded || previous == null) {
      return;
    }
    _seeded = true;
    for (final WaterParameter parameter in WaterParameter.values) {
      final double? value = previous.valueOf(parameter);
      if (value != null) {
        _controllers[parameter]!.text = _format(value, parameter);
        _values[parameter] = value;
      }
    }
  }

  void _onChanged(WaterParameter parameter) {
    final double? parsed = _read(parameter);
    if (_values[parameter] != parsed) {
      // L'échelle de lecture suit la frappe : on voit tout de suite si la
      // valeur qu'on saisit tombe dans la plage.
      setState(() => _values[parameter] = parsed);
    }
  }

  static String _format(double value, WaterParameter parameter) =>
      value.toStringAsFixed(parameter.decimals).replaceAll('.', ',');

  /// Lit un champ. Rend `null` s'il est vide ou illisible.
  ///
  /// La virgule est acceptée : c'est ce que propose le clavier français, et
  /// refuser « 7,2 » serait absurde.
  double? _read(WaterParameter parameter) {
    final String raw = _controllers[parameter]!.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final WaterReading reading = WaterReading(
      // L'heure de saisie est lue ici, dans l'interface : le domaine ne
      // touche jamais à l'horloge.
      takenAt: DateTime.now(),
      ph: _read(WaterParameter.ph),
      freeChlorine: _read(WaterParameter.freeChlorine),
      combinedChlorine: _read(WaterParameter.combinedChlorine),
      tac: _read(WaterParameter.tac),
      th: _read(WaterParameter.th),
      stabilizer: _read(WaterParameter.stabilizer),
      salt: _read(WaterParameter.salt),
      temperature: _read(WaterParameter.temperature),
    );

    if (reading.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez au moins une valeur mesurée.')),
      );
      return;
    }

    final NavigatorState navigator = Navigator.of(context);
    await ref.read(readingsProvider.notifier).record(reading);
    if (navigator.mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TelemetryState telemetry = ref.watch(telemetryProvider);
    final List<WaterParameter> manual = ref.watch(manualParametersProvider);
    _seed(ref.read(lastEnteredReadingProvider));

    // Le pH et la température ne sont proposés que si aucune sonde ne les
    // suit : les redemander alors qu'une mesure fraîche existe inviterait à
    // l'écraser par un souvenir.
    final List<WaterParameter> fallback = telemetry.hasLiveValues
        ? const <WaterParameter>[]
        : sensorParameters;

    return Scaffold(
      appBar: AppBar(title: const Text('Compléter les mesures')),
      body: ListView(
        // Réserve la barre de gestes ET le clavier : un champ de saisie
        // recouvert par le clavier est un champ qu'on ne peut pas corriger.
        padding: EdgeInsets.fromLTRB(
          AppTheme.gutter,
          10,
          AppTheme.gutter,
          40 +
              MediaQuery.viewPaddingOf(context).bottom +
              MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: <Widget>[
          Text(
            'Ces valeurs ne se lisent qu’à la bandelette. Laissez vide ce '
            'que vous n’avez pas testé.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 6),
          if (telemetry.hasLiveValues)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _SensorNote(
                ph: telemetry.livePh,
                temperatureC: telemetry.liveTemperatureC,
              ),
            ),
          for (final WaterParameter parameter in manual)
            _Field(
              parameter: parameter,
              controller: _controllers[parameter]!,
              value: _values[parameter],
            ),
          if (fallback.isNotEmpty) ...[
            const SectionHeader(label: 'Faute de sonde'),
            Text(
              'Aucune sonde ne les remonte. Saisissez-les pour des doses '
              'justes.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            for (final WaterParameter parameter in fallback)
              _Field(
                parameter: parameter,
                controller: _controllers[parameter]!,
                value: _values[parameter],
              ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}

/// Un champ, son échelle de lecture, et l'état de ce qu'on vient de taper.
class _Field extends StatelessWidget {
  const _Field({
    required this.parameter,
    required this.controller,
    required this.value,
  });

  final WaterParameter parameter;
  final TextEditingController controller;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ParameterStatus status = parameter.statusOf(value);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  parameter.label.toUpperCase(),
                  style: AppTheme.eyebrow.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (value != null)
                Text(
                  AppTheme.labelForStatus(status),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.colorForStatus(status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              // Chiffres, virgule et point : le clavier français propose la
              // virgule, les claviers numériques anglais le point.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: theme.textTheme.titleLarge,
            decoration: InputDecoration(
              hintText: '—',
              suffixText: parameter.unit.isEmpty ? null : parameter.unit,
              suffixStyle: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 12),
          MeasureScale(parameter: parameter, value: value),
        ],
      ),
    );
  }
}

/// Ce que la sonde mesure déjà, pour qu'on ne le ressaisisse pas.
class _SensorNote extends StatelessWidget {
  const _SensorNote({required this.ph, required this.temperatureC});

  final double? ph;
  final double? temperatureC;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.chlorine.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.chlorine.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.sensors, size: 20, color: AppTheme.chlorine),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'La sonde suit le pH'
              '${ph == null ? '' : ' (${ph!.toStringAsFixed(2).replaceAll('.', ',')})'}'
              ' et la température'
              '${temperatureC == null ? '' : ' (${temperatureC!.toStringAsFixed(1).replaceAll('.', ',')} °C)'}'
              '. Rien à ressaisir.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
