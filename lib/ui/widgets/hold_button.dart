import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Bouton qui n'agit que tant qu'un doigt est maintenu dessus.
///
/// RÈGLE DE SÉCURITÉ N° 1, matérialisée : « Aucun mouvement du volet sans
/// doigt maintenu sur le bouton. Le relâchement arrête le mouvement. Utiliser
/// un [Listener] (`onPointerDown`/`onPointerUp`/`onPointerCancel`), jamais un
/// `onTap`. »
///
/// Pourquoi pas `GestureDetector` : ses rappels `onTapDown`/`onTapUp` passent
/// par l'arène de gestes de Flutter. Un ancêtre qui gagne l'arène — une liste
/// défilable, un `PageView`, un `Dismissible` — annule le geste et le
/// `onTapUp` N'ARRIVE JAMAIS. Le doigt serait relevé sans que personne ne le
/// sache. Un [Listener] reçoit les événements de pointeur brut, avant toute
/// arbitration, donc [onPressEnd] est appelé quoi qu'il arrive.
///
/// Et pourquoi jamais `onTap` : un appui bref déclencherait un mouvement qui
/// se poursuivrait après le relâchement, ce qui est exactement ce que la norme
/// NF P90-308 interdit pour un volet de piscine.
class HoldButton extends StatefulWidget {
  const HoldButton({
    required this.label,
    required this.icon,
    required this.onPressStart,
    required this.onPressEnd,
    this.enabled = true,
    this.color,
    this.disabledExplanation,
    super.key,
  });

  final String label;
  final IconData icon;

  /// Appelé quand le doigt se pose.
  final VoidCallback onPressStart;

  /// Appelé quand le doigt se relève, sort du bouton, ou que le système
  /// interrompt le geste (appel entrant, verrouillage, notification).
  ///
  /// Il n'existe aucun chemin où le doigt cesse d'appuyer sans que ce rappel
  /// soit invoqué : c'est la propriété qui rend le bouton sûr.
  final VoidCallback onPressEnd;

  final bool enabled;
  final Color? color;

  /// Pourquoi le bouton est inactif, affiché sous le libellé.
  ///
  /// Un bouton grisé sans explication laisse l'utilisateur chercher ; ici il
  /// faut lui dire d'accepter l'avertissement de sécurité.
  final String? disabledExplanation;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  bool _held = false;

  void _start(PointerDownEvent event) {
    if (!widget.enabled || _held) {
      return;
    }
    setState(() => _held = true);
    widget.onPressStart();
  }

  /// Fin d'appui, quelle qu'en soit la cause.
  ///
  /// Appelé depuis `onPointerUp`, `onPointerCancel` ET la sortie de la zone :
  /// un doigt qui glisse hors du bouton doit arrêter le mouvement, comme sur
  /// un bouton physique dont on retire la main.
  void _end() {
    if (!_held) {
      return;
    }
    setState(() => _held = false);
    widget.onPressEnd();
  }

  @override
  void dispose() {
    // Le widget disparaît alors qu'un doigt était posé : changement d'écran,
    // rotation, fermeture de l'application. Le mouvement doit s'arrêter.
    //
    // L'appel est reporté d'une microtâche, et c'est nécessaire : `dispose`
    // survient pendant le démontage de l'arbre, moment où Riverpod interdit
    // de modifier un provider. Un appel direct lèverait une exception, et
    // l'arrêt ne passerait PAS — le pire résultat possible ici.
    //
    // Le report est sans conséquence sur la sécurité : une microtâche
    // s'exécute avant le prochain tour de boucle d'événements, donc bien
    // avant la republication suivante (700 ms), et le matériel garde de toute
    // façon son délai de garde de 1 800 ms.
    if (_held) {
      _held = false;
      final VoidCallback onPressEnd = widget.onPressEnd;
      scheduleMicrotask(onPressEnd);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = widget.color ?? theme.colorScheme.primary;
    final Color background = widget.enabled
        ? (_held ? base : base.withValues(alpha: 0.16))
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = widget.enabled
        ? (_held ? theme.colorScheme.onPrimary : base)
        : theme.disabledColor;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      hint:
          'Maintenez le doigt appuyé. Le mouvement s’arrête au '
          'relâchement.',
      child: Listener(
        // Les quatre événements de pointeur brut. `onPointerCancel` est le
        // plus important des trois derniers : c'est lui qui couvre l'appel
        // entrant et le verrouillage de l'écran.
        onPointerDown: _start,
        onPointerUp: (PointerUpEvent event) => _end(),
        onPointerCancel: (PointerCancelEvent event) => _end(),
        // Un doigt qui sort de la zone relâche aussi.
        onPointerMove: (PointerMoveEvent event) {
          if (!_held) {
            return;
          }
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          if (box == null) {
            return;
          }
          if (!box.size.contains(box.globalToLocal(event.position))) {
            _end();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          // 160 ms : au-dessus du plancher de 150 ms en dessous duquel un
          // changement d'état n'est plus perçu comme une réponse au geste,
          // mais comme un saut.
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          constraints: const BoxConstraints(
            minHeight: AppTheme.touchTarget * 1.6,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.enabled ? base : theme.dividerColor,
              width: _held ? 3 : 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(widget.icon, size: 40, color: foreground),
              const SizedBox(height: 8),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(color: foreground),
              ),
              if (!widget.enabled && widget.disabledExplanation != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.disabledExplanation!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.disabledColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
