import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection_notifier.dart';
import '../models/cover_state.dart';
import '../models/pool_config.dart';
import '../state/cover_controller.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'widgets/hold_button.dart';
import 'widgets/safety_consent_sheet.dart';
import 'widgets/section_header.dart';
import 'widgets/value_display.dart';

/// Écran de pilotage du volet.
///
/// Il ne calcule rien et ne décide rien : les deux boutons appellent
/// [CoverController], qui porte les règles de sécurité. L'écran se contente
/// de refléter l'état et d'expliquer ce qui bloque.
class CoverScreen extends ConsumerWidget {
  const CoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final PoolConfig config = ref.watch(poolConfigProvider);
    final CoverStatus status = ref.watch(coverControllerProvider);
    final CoverController controller = ref.read(
      coverControllerProvider.notifier,
    );
    final ConnectionQuality connectionQuality =
        ref.watch(connectionNotifierProvider);
    final bool isConnectionOk = connectionQuality == ConnectionQuality.online;

    final bool canOperate =
        isConnectionOk && config.safetyConsentGiven && config.hasMotorisedCover;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppTheme.gutter,
        AppTheme.gutter,
        AppTheme.gutter,
        40 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: <Widget>[
        _PositionCard(status: status),
        if (!config.hasMotorisedCover) ...<Widget>[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.info_outline,
            color: AppTheme.unmeasured,
            text:
                'La couverture déclarée n’est pas un volet motorisé : rien '
                'à piloter.',
          ),
        ] else if (!config.safetyConsentGiven) ...<Widget>[
          const SizedBox(height: 12),
          _ConsentPrompt(
            onAccepted: () async {
              final bool accepted = await SafetyConsentSheet.show(context);
              if (accepted) {
                await ref
                    .read(poolConfigProvider.notifier)
                    .setSafetyConsent(given: true);
              }
            },
          ),
        ],
        if (!isConnectionOk) ...<Widget>[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.wifi_off,
            color: AppTheme.acid,
            text: connectionQuality.userNoticeMessage!,
          ),
        ] else ...<Widget>[
          if (status.errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.wifi_off,
              color: AppTheme.acid,
              text: status.errorMessage!,
            ),
          ],
          const SectionHeader(label: 'Commander'),
          Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: HoldButton(
                    label: 'Ouvrir',
                    icon: Icons.keyboard_double_arrow_up,
                    enabled: canOperate,
                    color: AppTheme.chlorine,
                    disabledExplanation: canOperate
                        ? null
                        : 'Avertissement à accepter',
                    // Doigt posé : la commande part et se répète.
                    onPressStart: () => controller.pressOpen(),
                    // Doigt relevé : la répétition s'arrête. Aucun ordre
                    // d'arrêt n'est envoyé, le matériel s'arrête seul.
                    onPressEnd: () => controller.release(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: HoldButton(
                    label: 'Fermer',
                    icon: Icons.keyboard_double_arrow_down,
                    enabled: canOperate,
                    color: AppTheme.chlorine,
                    disabledExplanation: canOperate
                        ? null
                        : 'Avertissement à accepter',
                    onPressStart: () => controller.pressClose(),
                    onPressEnd: () => controller.release(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Doigt appuyé pendant tout le mouvement, bassin sous les yeux. '
            'Au relâchement, le volet s’arrête en moins de deux secondes.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
        const SectionHeader(label: 'Recaler'),
        _CalibrationCard(
          enabled: canOperate && !status.isMoving,
          onDeclare: (bool open) => controller.declarePosition(open: open),
        ),
      ],
    );
  }
}

/// Position estimée, en grand, avec la mention qui va avec.
class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.status});

  final CoverStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CoverState cover = status.cover;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _positionLabel(cover.position).toUpperCase(),
              style: AppTheme.eyebrow.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: AppTheme.gap),
            ValueDisplay(
              value: '${(cover.openRatio * 100).round()}',
              unit: '%',
              size: ValueSize.large,
            ),
            const SizedBox(height: 12),
            // Une barre franche plutôt qu'un filet : c'est la seule
            // représentation de la position, elle doit se lire d'un coup
            // d'œil au soleil.
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: cover.openRatio,
                minHeight: 20,
                color: AppTheme.chlorine,
                backgroundColor: theme.colorScheme.outline.withValues(
                  alpha: 0.18,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Icon(
                  status.isMoving ? Icons.sync : Icons.pause_circle_outline,
                  size: 20,
                  color: status.isMoving
                      ? AppTheme.chlorine
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                // Flexible : « Ouverture en cours » déborde d'un écran étroit
                // si on le laisse à sa largeur naturelle.
                Expanded(
                  child: Text(
                    _motionLabel(cover.motion),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (cover.isEstimated) ...[
              const SizedBox(height: 12),
              // RÈGLE DE SÉCURITÉ N° 6 : sans capteur de fin de course, la
              // position est une estimation et doit être affichée comme telle.
              // La formulation dit d'où vient le chiffre, pas seulement qu'il
              // est approximatif.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.help_outline,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Position estimée, sans capteur. Vérifiez de vos yeux.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _positionLabel(CoverPosition position) {
    switch (position) {
      case CoverPosition.closed:
        return 'Volet fermé';
      case CoverPosition.open:
        return 'Volet ouvert';
      case CoverPosition.partiallyOpen:
        return 'Volet entrouvert';
      case CoverPosition.unknown:
        return 'Position inconnue';
    }
  }

  static String _motionLabel(CoverMotion motion) {
    switch (motion) {
      case CoverMotion.idle:
        return 'À l’arrêt';
      case CoverMotion.opening:
        return 'Ouverture en cours';
      case CoverMotion.closing:
        return 'Fermeture en cours';
    }
  }
}

class _ConsentPrompt extends StatelessWidget {
  const _ConsentPrompt({required this.onAccepted});

  final Future<void> Function() onAccepted;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.lock_outline, color: AppTheme.acid),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Commandes verrouillées',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Lisez l’avertissement de sécurité une fois pour débloquer les '
              'commandes.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAccepted,
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Lire l’avertissement'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalibrationCard extends StatelessWidget {
  const _CalibrationCard({required this.enabled, required this.onDeclare});

  final bool enabled;
  final void Function(bool open) onDeclare;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Si l’affichage ne correspond pas à ce que vous voyez, dites '
              'où en est le volet.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled ? () => onDeclare(false) : null,
                    child: const Text('Il est fermé'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled ? () => onDeclare(true) : null,
                    child: const Text('Il est ouvert'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}
