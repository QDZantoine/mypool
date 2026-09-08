import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
import '../models/chemical_product.dart';
import '../models/mqtt_settings.dart';
import '../models/pool_config.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/safety_consent_sheet.dart';

/// Réglages : le bassin, les produits, la liaison.
///
/// Deux réglages ont un effet direct sur la justesse des doses, et l'écran le
/// dit : le VOLUME, qui multiplie tout, et la CONCENTRATION des produits, qui
/// divise tout.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final PoolConfig config = ref.watch(poolConfigProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: <Widget>[
        const _Section(title: 'Le bassin'),
        Card(
          child: Column(
            children: <Widget>[
              _NumberTile(
                label: 'Volume',
                unit: 'm³',
                value: config.volumeM3,
                helper:
                    'Le volume multiplie toutes les doses : une erreur de '
                    '10 % ici fait 10 % d’écart sur chaque produit versé.',
                onChanged: (double value) =>
                    ref.read(poolConfigProvider.notifier).edit(volumeM3: value),
              ),
              const Divider(height: 1),
              _NumberTile(
                label: 'Longueur',
                unit: 'm',
                value: config.lengthM,
                onChanged: (double value) =>
                    ref.read(poolConfigProvider.notifier).edit(lengthM: value),
              ),
              _NumberTile(
                label: 'Largeur',
                unit: 'm',
                value: config.widthM,
                onChanged: (double value) =>
                    ref.read(poolConfigProvider.notifier).edit(widthM: value),
              ),
              _NumberTile(
                label: 'Profondeur moyenne',
                unit: 'm',
                value: config.averageDepthM,
                onChanged: (double value) => ref
                    .read(poolConfigProvider.notifier)
                    .edit(averageDepthM: value),
              ),
              ListTile(
                title: Text(
                  'Ces dimensions donnent '
                  '${_number(config.volumeFromDimensions)} m³',
                  style: theme.textTheme.bodyLarge,
                ),
                subtitle: const Text(
                  'Pour un bassin rectangulaire à fond plat.',
                ),
                trailing: TextButton(
                  onPressed: () => ref
                      .read(poolConfigProvider.notifier)
                      .useVolumeFromDimensions(),
                  child: const Text('Utiliser'),
                ),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: <Widget>[
              _EnumTile<TreatmentType>(
                label: 'Traitement',
                value: config.treatment,
                values: TreatmentType.values,
                nameOf: _treatmentLabel,
                onChanged: (TreatmentType value) => ref
                    .read(poolConfigProvider.notifier)
                    .edit(treatment: value),
              ),
              _EnumTile<FilterType>(
                label: 'Filtre',
                value: config.filter,
                values: FilterType.values,
                nameOf: _filterLabel,
                onChanged: (FilterType value) =>
                    ref.read(poolConfigProvider.notifier).edit(filter: value),
              ),
              _EnumTile<CoverType>(
                label: 'Couverture',
                value: config.cover,
                values: CoverType.values,
                nameOf: _coverLabel,
                onChanged: (CoverType value) =>
                    ref.read(poolConfigProvider.notifier).edit(cover: value),
              ),
            ],
          ),
        ),
        const _Section(title: 'La pompe'),
        Card(
          child: Column(
            children: <Widget>[
              _NumberTile(
                label: 'Débit annoncé',
                unit: 'm³/h',
                value: config.pumpFlowM3PerHour,
                helper: 'Celui de la plaque du constructeur.',
                onChanged: (double value) => ref
                    .read(poolConfigProvider.notifier)
                    .edit(pumpFlowM3PerHour: value),
              ),
              _NumberTile(
                label: 'Rendement',
                unit: '%',
                value: config.pumpEfficiency * 100,
                helper:
                    'Pertes de charge, filtre encrassé, paniers pleins. '
                    '75 % est une valeur courante.',
                onChanged: (double value) => ref
                    .read(poolConfigProvider.notifier)
                    .edit(pumpEfficiency: value / 100),
              ),
              _NumberTile(
                label: 'Course du volet',
                unit: 's',
                value: config.coverTravelSeconds,
                helper:
                    'Chronométrez une ouverture complète. C’est ce qui '
                    'permet d’estimer la position du volet.',
                onChanged: (double value) => ref
                    .read(poolConfigProvider.notifier)
                    .edit(coverTravelSeconds: value),
              ),
            ],
          ),
        ),
        const _Section(title: 'Les produits'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Recopiez le pourcentage écrit sur l’emballage. Un chlore à '
              '56 % pris pour du 90 %, c’est un tiers de dose en moins.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
        for (final ChemicalRole role in ChemicalRole.values)
          _ProductTile(
            product: config.inventory.forRole(role),
            onChanged: (ChemicalProduct product) =>
                ref.read(poolConfigProvider.notifier).declareProduct(product),
          ),
        const _Section(title: 'La liaison'),
        _LinkSection(config: config),
        const _Section(title: 'Sécurité'),
        Card(
          child: SwitchListTile(
            title: const Text('Avertissement du volet accepté'),
            subtitle: Text(
              config.safetyConsentGiven
                  ? 'Les commandes du volet sont actives.'
                  : 'Les commandes du volet sont verrouillées.',
            ),
            value: config.safetyConsentGiven,
            onChanged: (bool value) async {
              if (!value) {
                await ref
                    .read(poolConfigProvider.notifier)
                    .setSafetyConsent(given: false);
                return;
              }
              // Réactiver passe toujours par la relecture de l'avertissement :
              // un interrupteur qu'on rebascule sans rien lire viderait la
              // règle n° 4 de son sens.
              final bool accepted = await SafetyConsentSheet.show(context);
              if (accepted) {
                await ref
                    .read(poolConfigProvider.notifier)
                    .setSafetyConsent(given: true);
              }
            },
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

  static String _treatmentLabel(TreatmentType type) {
    switch (type) {
      case TreatmentType.stabilizedChlorine:
        return 'Chlore stabilisé (galets)';
      case TreatmentType.unstabilizedChlorine:
        return 'Chlore non stabilisé';
      case TreatmentType.salt:
        return 'Électrolyse au sel';
      case TreatmentType.bromine:
        return 'Brome';
      case TreatmentType.activeOxygen:
        return 'Oxygène actif';
    }
  }

  static String _filterLabel(FilterType type) {
    switch (type) {
      case FilterType.sand:
        return 'Sable';
      case FilterType.glass:
        return 'Verre filtrant';
      case FilterType.cartridge:
        return 'Cartouche';
      case FilterType.diatomaceousEarth:
        return 'Diatomée';
      case FilterType.zeolite:
        return 'Zéolite';
    }
  }

  static String _coverLabel(CoverType type) {
    switch (type) {
      case CoverType.submerged:
        return 'Volet immergé';
      case CoverType.outOfWater:
        return 'Volet hors d’eau';
      case CoverType.bars:
        return 'Couverture à barres';
      case CoverType.bubbleCover:
        return 'Bâche à bulles';
      case CoverType.none:
        return 'Aucune';
    }
  }
}

/// Réglages de liaison, et test de la liaison.
class _LinkSection extends ConsumerWidget {
  const _LinkSection({required this.config});

  final PoolConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final MqttSettings mqtt = ref.watch(mqttSettingsProvider);

    return Column(
      children: <Widget>[
        Card(
          child: _EnumTile<DriverKind>(
            label: 'Type de liaison',
            value: config.driver,
            values: DriverKind.values,
            nameOf: _driverLabel,
            onChanged: (DriverKind value) =>
                ref.read(poolConfigProvider.notifier).edit(driver: value),
          ),
        ),
        if (config.driver == DriverKind.mqtt)
          Card(
            child: Column(
              children: <Widget>[
                _TextTile(
                  label: 'Adresse du broker',
                  value: mqtt.host,
                  onChanged: (String value) =>
                      ref.read(mqttSettingsProvider.notifier).edit(host: value),
                ),
                _NumberTile(
                  label: 'Port',
                  unit: '',
                  value: mqtt.port.toDouble(),
                  onChanged: (double value) => ref
                      .read(mqttSettingsProvider.notifier)
                      .edit(port: value.round()),
                ),
                _TextTile(
                  label: 'Identifiant de l’installation',
                  value: mqtt.deviceId,
                  helper:
                      'Au moins ${MqttSettings.minimumDeviceIdLength} '
                      'caractères, tirés au hasard. Sur un broker public, '
                      'c’est la seule chose qui sépare votre bassin de celui '
                      'des autres.',
                  onChanged: (String value) => ref
                      .read(mqttSettingsProvider.notifier)
                      .edit(deviceId: value),
                ),
                if (mqtt.isPublicBroker)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.warning_amber_rounded, color: AppTheme.acid),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ce broker est public : n’importe qui peut y '
                            'publier. Réservez-le à la simulation, jamais à '
                            'un vrai volet.',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  title: const Text('Tester la liaison'),
                  subtitle: Text(
                    mqtt.isUsable
                        ? 'Demande son état au module et mesure le délai.'
                        : 'Renseignez d’abord l’adresse et l’identifiant.',
                  ),
                  trailing: const Icon(Icons.network_check),
                  enabled: mqtt.isUsable,
                  onTap: mqtt.isUsable ? () => _testLink(context, ref) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _testLink(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Test en cours…')));
    try {
      final Duration latency = await ref
          .read(telemetryProvider.notifier)
          .testConnection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Module joignable, réponse en ${latency.inMilliseconds} ms.',
          ),
        ),
      );
    } on DeviceException catch (error) {
      // Le message est déjà en français et affichable : aucune trace
      // technique n'atteint l'écran.
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  static String _driverLabel(DriverKind kind) {
    switch (kind) {
      case DriverKind.simulation:
        return 'Simulation (sans matériel)';
      case DriverKind.localModule:
        return 'Module local — à venir';
      case DriverKind.homeAssistant:
        return 'Home Assistant — à venir';
      case DriverKind.mqtt:
        return 'Carte ESP32 en MQTT';
    }
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onChanged});

  final ChemicalProduct product;
  final void Function(ChemicalProduct) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(product.label),
        subtitle: Text(
          '${_percent(product.activePercent)} de ${product.activeSubstance}',
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () async {
          final double? value = await _askNumber(
            context,
            title: product.label,
            label: 'Matière active',
            unit: '%',
            initial: product.activePercent,
            helper: 'Le pourcentage écrit sur l’emballage.',
          );
          if (value != null) {
            onChanged(product.copyWith(activePercent: value));
          }
        },
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

class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.label,
    required this.unit,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final String unit;
  final double value;
  final String? helper;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // La valeur est sur la même ligne que le libellé, et l'explication passe
    // DESSOUS. L'inverse — vu sur appareil — faisait lire quatre lignes de
    // texte avant d'arriver au chiffre qu'on venait chercher.
    return ListTile(
      title: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
          const SizedBox(width: 12),
          Text(
            unit.isEmpty ? _format(value) : '${_format(value)} $unit',
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppTheme.chlorine,
            ),
          ),
        ],
      ),
      subtitle: helper == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(helper!, style: theme.textTheme.bodyMedium),
            ),
      trailing: const Icon(Icons.chevron_right, size: 22),
      onTap: () async {
        final double? entered = await _askNumber(
          context,
          title: label,
          label: label,
          unit: unit,
          initial: value,
          helper: helper,
        );
        if (entered != null) {
          onChanged(entered);
        }
      },
    );
  }

  static String _format(double value) {
    final String text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return text.replaceAll('.', ',');
  }
}

class _TextTile extends StatelessWidget {
  const _TextTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final String value;
  final String? helper;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value.isEmpty ? (helper ?? 'Non renseigné') : value),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final String? entered = await _askText(
          context,
          title: label,
          initial: value,
          helper: helper,
        );
        if (entered != null) {
          onChanged(entered);
        }
      },
    );
  }
}

class _EnumTile<T> extends StatelessWidget {
  const _EnumTile({
    required this.label,
    required this.value,
    required this.values,
    required this.nameOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) nameOf;
  final void Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(nameOf(value)),
      trailing: const Icon(Icons.expand_more),
      onTap: () async {
        final T? chosen = await showModalBottomSheet<T>(
          context: context,
          builder: (BuildContext context) => SafeArea(
            child: RadioGroup<T>(
              groupValue: value,
              onChanged: (T? selected) => Navigator.of(context).pop(selected),
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final T option in values)
                    RadioListTile<T>(
                      title: Text(nameOf(option)),
                      value: option,
                    ),
                ],
              ),
            ),
          ),
        );
        if (chosen != null && chosen != value) {
          onChanged(chosen);
        }
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 24, bottom: 4),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// Demande un nombre. Accepte la virgule décimale.
Future<double?> _askNumber(
  BuildContext context, {
  required String title,
  required String label,
  required String unit,
  required double initial,
  String? helper,
}) {
  return showDialog<double>(
    context: context,
    builder: (BuildContext context) => _NumberDialog(
      title: title,
      label: label,
      unit: unit,
      initial: initial,
      helper: helper,
    ),
  );
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String initial,
  String? helper,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) =>
        _TextDialog(title: title, initial: initial, helper: helper),
  );
}

/// Le contrôleur de saisie appartient au dialogue lui-même.
///
/// Le libérer depuis la fonction appelante, juste après `showDialog`, le
/// détruisait alors que le champ était encore dans l'arbre pendant
/// l'animation de fermeture — ce qui faisait échouer une assertion de Flutter
/// sur les dépendances de focus.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.label,
    required this.unit,
    required this.initial,
    this.helper,
  });

  final String title;
  final String label;
  final String unit;
  final double initial;
  final String? helper;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == widget.initial.roundToDouble()
        ? widget.initial.toStringAsFixed(0)
        : widget.initial.toString().replaceAll('.', ','),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.unit.isEmpty ? null : widget.unit,
          helperText: widget.helper,
          helperMaxLines: 4,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            // La virgule est acceptée : c'est ce que le clavier français
            // propose.
            double.tryParse(_controller.text.trim().replaceAll(',', '.')),
          ),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, this.helper});

  final String title;
  final String initial;
  final String? helper;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          helperText: widget.helper,
          helperMaxLines: 5,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
