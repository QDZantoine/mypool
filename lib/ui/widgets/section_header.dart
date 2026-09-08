import 'package:flutter/material.dart';

import '../theme.dart';

/// Titre de section : un micro-libellé en capitales, un filet, une action.
///
/// Le filet part du texte et court jusqu'au bord : il sépare sans peser, et
/// donne à chaque bloc son assise. C'est le seul ornement de l'écran.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.action,
    this.onAction,
    super.key,
  });

  final String label;

  /// Libellé d'une action, quand la section en propose une.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 12),
      child: Row(
        children: <Widget>[
          // Flexible, et sur deux lignes au besoin : un libellé long comme
          // « À TESTER À LA BANDELETTE » ne tient pas à côté d'une action sur
          // un écran étroit, et le tronquer le rendrait incompréhensible.
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 2,
              style: AppTheme.eyebrow.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.28),
            ),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              // 44 px de haut au minimum, et la zone tactile n'est pas
              // rognée : un bouton de 36 px se rate une fois sur trois avec
              // une main mouillée.
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(48, 44),
                ),
                child: Text(action!.toUpperCase(), style: AppTheme.eyebrow),
              ),
            ),
        ],
      ),
    );
  }
}
