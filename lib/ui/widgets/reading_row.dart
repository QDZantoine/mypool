import 'package:flutter/material.dart';

import '../../models/water_reading.dart';
import '../theme.dart';
import 'measure_scale.dart';
import 'value_display.dart';

/// Une mesure : son nom, sa valeur, son échelle de lecture.
///
/// La valeur est à droite et en grand, l'échelle dessous sur toute la largeur.
/// L'œil descend donc du nom à la valeur puis à la position dans la plage —
/// et s'arrête dès qu'il a sa réponse.
class ReadingRow extends StatelessWidget {
  const ReadingRow({
    required this.parameter,
    required this.value,
    this.age,
    this.onTap,
    super.key,
  });

  final WaterParameter parameter;

  /// `null` si non mesuré. Jamais remplacé par un zéro.
  final double? value;

  /// Depuis combien de temps la mesure date, quand cela compte.
  ///
  /// Affiché pour les paramètres qu'on teste à la main : un TAC d'il y a trois
  /// semaines n'a pas la même valeur qu'un TAC d'hier, et le savoir change la
  /// confiance qu'on accorde à la dose calculée.
  final Duration? age;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ParameterStatus status = parameter.statusOf(value);
    final Color statusColor = AppTheme.colorForStatus(status);

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gutter,
        vertical: 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      parameter.label.toUpperCase(),
                      style: AppTheme.eyebrow.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: AppTheme.gap * 2),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppTheme.gap * 2),
                        // Flexible et tronqué au besoin : « non mesuré · il y
                        // a 12 jours » ne tient pas à côté d'une valeur à
                        // trois chiffres sur un écran étroit.
                        Flexible(
                          child: Text(
                            age == null
                                ? AppTheme.labelForStatus(status)
                                : '${AppTheme.labelForStatus(status)} · '
                                      '${_formatAge(age!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.gap * 3),
              // La valeur et son unité forment un bloc aligné à droite : les
              // lignes successives dessinent ainsi une colonne bien rangée,
              // comme sur un relevé.
              ValueDisplay(
                value: value == null ? null : _bare(value!),
                unit: parameter.unit,
                size: ValueSize.small,
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          MeasureScale(parameter: parameter, value: value),
        ],
      ),
    );

    // Une seule annonce pour toute la ligne : sans ce regroupement, un
    // lecteur d'écran énonce « TAC », « trop bas », « 60 », « mg/L » et
    // l'échelle séparément, et l'utilisateur doit recomposer la phrase.
    //
    // Le regroupement ENGLOBE le bouton, il n'est pas dedans : sinon le nœud
    // du bouton reste sans libellé et le lecteur annonce « bouton » tout seul.
    if (onTap == null) {
      return MergeSemantics(child: content);
    }
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: content,
        ),
      ),
    );
  }

  String _bare(double v) =>
      v.toStringAsFixed(parameter.decimals).replaceAll('.', ',');

  /// « à l'instant », « il y a 3 h », « il y a 12 jours »
  static String _formatAge(Duration age) {
    if (age.inMinutes < 2) {
      return 'à l’instant';
    }
    if (age.inHours < 1) {
      return 'il y a ${age.inMinutes} min';
    }
    if (age.inHours < 24) {
      return 'il y a ${age.inHours} h';
    }
    final int days = age.inDays;
    return 'il y a $days jour${days > 1 ? 's' : ''}';
  }
}
