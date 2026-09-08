import 'package:flutter/material.dart';

import '../theme.dart';

/// Une valeur mesurée et son unité.
///
/// Existe pour deux raisons vues sur appareil :
///
/// - **l'unité ne doit jamais avoir la taille du nombre.** Un « % » de 76 px
///   à côté d'un « 22 » de 76 px pèse autant que la mesure et déséquilibre
///   toute la carte. Elle est ici calée à 42 % de la hauteur du chiffre et
///   posée sur sa ligne de base.
/// - **une valeur absente n'est pas un tiret géant.** Un « — » rendu en
///   grande taille devient un trait plein qu'on prend pour une barre de
///   chargement. Le vide s'écrit donc en mots, dans la taille du texte
///   courant.
class ValueDisplay extends StatelessWidget {
  const ValueDisplay({
    required this.value,
    this.unit,
    this.size = ValueSize.medium,
    this.color,
    this.emptyLabel = 'non mesuré',
    this.alignEnd = false,
    super.key,
  });

  /// Valeur déjà mise en forme, ou `null` si rien n'a été mesuré.
  final String? value;

  final String? unit;
  final ValueSize size;
  final Color? color;

  /// Ce qui s'affiche à la place du nombre quand il n'y a rien.
  final String emptyLabel;

  final bool alignEnd;

  /// Part de la hauteur du chiffre attribuée à l'unité.
  ///
  /// 42 % : l'unité reste lisible sans peser autant que la mesure. À taille
  /// égale, un « % » de 76 px à côté d'un « 22 » de 76 px déséquilibre toute
  /// la carte — c'est ce qui a été constaté sur appareil.
  static const double unitScale = 0.42;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle numberStyle = switch (size) {
      ValueSize.large => theme.textTheme.displayLarge!,
      ValueSize.medium => theme.textTheme.displayMedium!,
      ValueSize.small => theme.textTheme.displaySmall!,
    };

    if (value == null) {
      // En mots, à la taille du texte courant : c'est une phrase, pas une
      // mesure.
      return Text(
        emptyLabel,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }

    final double unitSize = (numberStyle.fontSize ?? 32) * unitScale;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          text: value,
          style: numberStyle.copyWith(color: color),
          children: <InlineSpan>[
            if (unit != null && unit!.isNotEmpty)
              TextSpan(
                // Espace fine INSÉCABLE (U+202F) avant l'unité : la
                // typographie française l'exige devant « % », et l'insécable
                // évite qu'une unité se retrouve seule sur une ligne.
                text: '\u202F${unit!}',
                style: numberStyle.copyWith(
                  color: color ?? theme.colorScheme.outline,
                  fontSize: unitSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Les trois tailles de valeur du système.
enum ValueSize { large, medium, small }

/// Un état vide, écrit et non dessiné.
///
/// Remplace le tiret géant qui apparaissait quand une carte n'avait rien à
/// montrer : à 76 px, un « — » devient un trait plein qu'on prend pour un
/// élément d'interface en panne.
class EmptyValue extends StatelessWidget {
  const EmptyValue({required this.label, this.hint, super.key});

  /// Ce qui manque, en trois mots.
  final String label;

  /// Comment l'obtenir.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.remove_circle_outline,
              size: 22,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: AppTheme.gap * 2),
          Text(hint!, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}
