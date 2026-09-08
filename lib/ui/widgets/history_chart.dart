import 'package:flutter/material.dart';

import '../../models/water_reading.dart';
import '../theme.dart';

/// Un point de la courbe : un instant et une valeur.
class HistoryPoint {
  const HistoryPoint(this.at, this.value);

  final DateTime at;
  final double value;
}

/// Courbe d'historique d'un paramètre, peinte à la main.
///
/// Aucune bibliothèque de graphiques, et c'est un choix du projet : une
/// polyligne, une bande verte et deux dates ne justifient pas une dépendance
/// dont l'API change à chaque version majeure.
///
/// Ce que la courbe montre, et pourquoi :
///
/// - la **bande verte** de la plage idéale, en fond : elle répond à « est-ce
///   que c'était bon ? » sans lire aucun chiffre ;
/// - la **polyligne** des mesures, avec un point par mesure — les points
///   comptent, parce qu'une mesure hebdomadaire ne se lit pas comme une
///   courbe continue ;
/// - **deux dates seulement**, aux extrémités : un axe complet serait
///   illisible sur un téléphone au soleil.
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    required this.parameter,
    required this.points,
    this.height = 200,
    super.key,
  });

  final WaterParameter parameter;

  /// Points dans l'ordre chronologique, du plus ancien au plus récent.
  final List<HistoryPoint> points;

  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'Aucune mesure de ${parameter.label} enregistrée.'
                : 'Une seule mesure : il en faut deux pour tracer une '
                      'évolution.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _HistoryPainter(
              parameter: parameter,
              points: points,
              lineColor: theme.colorScheme.primary,
              gridColor: theme.dividerColor,
              labelStyle:
                  theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 16),
              labelColor: theme.colorScheme.outline,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              _formatDate(points.first.at),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              _formatDate(points.last.at),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }

  /// « 15/07 » — jour et mois suffisent pour une courbe de quelques semaines.
  static String _formatDate(DateTime date) {
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({
    required this.parameter,
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.labelStyle,
    required this.labelColor,
  });

  final WaterParameter parameter;
  final List<HistoryPoint> points;
  final Color lineColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final Color labelColor;

  /// Marge à gauche pour les libellés de valeur.
  static const double _leftGutter = 46.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTRB(
      _leftGutter,
      8,
      size.width - 4,
      size.height - 4,
    );
    if (plot.width <= 0 || plot.height <= 0) {
      return;
    }

    final _Bounds bounds = _computeBounds();

    _paintIdealBand(canvas, plot, bounds);
    _paintAxisLabels(canvas, plot, bounds);
    _paintLine(canvas, plot, bounds);
  }

  /// Échelle verticale.
  ///
  /// Elle inclut toujours la plage idéale, même si aucune mesure ne s'en
  /// approche : sans cela, une eau constamment hors plage donnerait une courbe
  /// plate au milieu du graphique, qui aurait l'air normale.
  _Bounds _computeBounds() {
    double min = parameter.idealMin;
    double max = parameter.idealMax;
    for (final HistoryPoint point in points) {
      if (point.value < min) {
        min = point.value;
      }
      if (point.value > max) {
        max = point.value;
      }
    }
    // Un peu d'air en haut et en bas, pour que la ligne ne colle pas au bord.
    final double span = max - min;
    final double padding = span == 0 ? 1.0 : span * 0.12;
    return _Bounds(min - padding, max + padding);
  }

  void _paintIdealBand(Canvas canvas, Rect plot, _Bounds bounds) {
    final double top = bounds.yFor(parameter.idealMax, plot);
    final double bottom = bounds.yFor(parameter.idealMin, plot);
    canvas.drawRect(
      Rect.fromLTRB(plot.left, top, plot.right, bottom),
      Paint()..color = AppTheme.inRange.withValues(alpha: 0.16),
    );
    // Bordures de la bande : elles restent visibles là où l'aplat vert se
    // confond avec le fond, en plein soleil.
    final Paint edge = Paint()
      ..color = AppTheme.inRange.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(plot.left, top), Offset(plot.right, top), edge);
    canvas.drawLine(
      Offset(plot.left, bottom),
      Offset(plot.right, bottom),
      edge,
    );
  }

  void _paintAxisLabels(Canvas canvas, Rect plot, _Bounds bounds) {
    for (final double value in <double>[
      parameter.idealMax,
      parameter.idealMin,
    ]) {
      final double y = bounds.yFor(value, plot);
      final TextPainter painter = TextPainter(
        text: TextSpan(
          // Sans unité : elle est dans le titre de la carte, la répéter
          // mangerait la largeur utile.
          text: _formatBare(value),
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _leftGutter - 6);
      painter.paint(
        canvas,
        Offset(_leftGutter - 6 - painter.width, y - painter.height / 2),
      );
    }
  }

  void _paintLine(Canvas canvas, Rect plot, _Bounds bounds) {
    final double stepX = points.length == 1
        ? 0
        : plot.width / (points.length - 1);

    final Path path = Path();
    final List<Offset> dots = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final Offset offset = Offset(
        plot.left + stepX * i,
        bounds.yFor(points[i].value, plot),
      );
      dots.add(offset);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Un point par mesure : une mesure hebdomadaire ne se lit pas comme une
    // courbe continue, et l'utilisateur doit voir combien de fois il a mesuré.
    final Paint dotPaint = Paint()..color = lineColor;
    for (final Offset dot in dots) {
      canvas.drawCircle(dot, 4, dotPaint);
    }
  }

  /// « 7,4 », « 120 » — virgule décimale, sans unité.
  String _formatBare(double value) {
    return value.toStringAsFixed(parameter.decimals).replaceAll('.', ',');
  }

  @override
  bool shouldRepaint(_HistoryPainter oldDelegate) {
    return oldDelegate.parameter != parameter ||
        oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor;
  }
}

/// Bornes verticales de la courbe.
class _Bounds {
  const _Bounds(this.min, this.max);

  final double min;
  final double max;

  /// Ordonnée d'une valeur dans la zone de tracé.
  ///
  /// L'axe est inversé par rapport au canevas : une valeur haute se dessine
  /// en haut.
  double yFor(double value, Rect plot) {
    final double span = max - min;
    if (span <= 0) {
      return plot.center.dy;
    }
    final double ratio = ((value - min) / span).clamp(0.0, 1.0);
    return plot.bottom - ratio * plot.height;
  }
}
