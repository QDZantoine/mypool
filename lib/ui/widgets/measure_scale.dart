import 'package:flutter/material.dart';

import '../../models/water_reading.dart';
import '../theme.dart';

/// L'instrument de lecture de l'application.
///
/// C'est un nuancier de bandelette, transposé à l'écran : une échelle de
/// couleurs graduée, la plage conseillée encadrée par deux montants, et un
/// repère sur la valeur mesurée. Personne n'a besoin d'apprendre à le lire —
/// c'est ainsi qu'on lit l'eau d'une piscine depuis quarante ans.
///
/// Il répond à « est-ce que c'est bon ? » AVANT que le chiffre ne soit lu, ce
/// qui est exactement ce qu'on demande à un écran regardé à bout de bras.
///
/// Les couleurs viennent des vrais réactifs ([AppTheme.scaleFor]) : le pH vire
/// au jaune côté acide et au magenta côté alcalin, comme le rouge de phénol.
class MeasureScale extends StatelessWidget {
  const MeasureScale({
    required this.parameter,
    required this.value,
    this.height = 14,
    this.showBounds = true,
    super.key,
  });

  final WaterParameter parameter;

  /// `null` quand rien n'a été mesuré : l'échelle est alors grisée et sans
  /// repère, plutôt que montrée avec un curseur à zéro.
  final double? value;

  final double height;

  /// Affiche les trois graduations sous l'échelle.
  final bool showBounds;

  /// Étendue affichée.
  ///
  /// L'échelle acceptable, élargie de 15 % de chaque côté : une valeur juste
  /// au-delà doit rester visible sur le bord, sinon le repère se colle à
  /// l'extrémité et on ne voit plus de combien on dépasse.
  double get _min => parameter.acceptableMin - _acceptableSpan * 0.15;
  double get _max => parameter.acceptableMax + _acceptableSpan * 0.15;
  double get _acceptableSpan =>
      parameter.acceptableMax - parameter.acceptableMin;

  double _positionOf(double v) => ((v - _min) / (_max - _min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final ParameterStatus status = parameter.statusOf(value);
    final bool measured = value != null;

    // Un lecteur d'écran ne voit rien d'un dégradé et d'un repère. Sans cette
    // annonce, toute l'information portée par l'échelle serait perdue : c'est
    // exactement le cas que la règle « ne pas transmettre par la couleur
    // seule » vise.
    return Semantics(
      label: measured
          ? '${parameter.label} : ${_bare(value!)}'
                '${parameter.unit.isEmpty ? '' : ' ${parameter.unit}'}, '
                '${AppTheme.labelForStatus(status)}. '
                'Plage conseillée de ${_bare(parameter.idealMin)} '
                'à ${_bare(parameter.idealMax)}.'
          : '${parameter.label} non mesuré. Plage conseillée de '
                '${_bare(parameter.idealMin)} à '
                '${_bare(parameter.idealMax)}.',
      // Les graduations chiffrées sont déjà dans l'annonce ci-dessus : les
      // laisser lisibles séparément ferait tout entendre deux fois.
      excludeSemantics: true,
      child: _buildScale(context, status, measured),
    );
  }

  Widget _buildScale(
    BuildContext context,
    ParameterStatus status,
    bool measured,
  ) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double idealLeft = _positionOf(parameter.idealMin) * width;
        final double idealRight = _positionOf(parameter.idealMax) * width;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: height + 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  // L'échelle colorée.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(height / 2),
                      child: Container(
                        height: height,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: measured
                                ? AppTheme.scaleFor(parameter)
                                : <Color>[
                                    AppTheme.unmeasured.withValues(alpha: 0.18),
                                    AppTheme.unmeasured.withValues(alpha: 0.28),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Les deux montants de la plage conseillée : ils encadrent la
                  // zone où l'eau est bonne, comme la fenêtre d'un nuancier.
                  Positioned(
                    left: idealLeft,
                    top: 4,
                    child: _Bracket(height: height + 10),
                  ),
                  Positioned(
                    left: idealRight - _Bracket.width,
                    top: 4,
                    child: _Bracket(height: height + 10),
                  ),
                  // Le repère de la valeur mesurée. Il glisse jusqu'à sa
                  // position : c'est la seule animation de l'écran, et elle
                  // sert à faire remarquer qu'une nouvelle mesure est arrivée.
                  if (measured)
                    AnimatedPositioned(
                      // Le glissement du repère est supprimé quand
                      // l'utilisateur a demandé moins d'animations : il ne
                      // porte qu'un agrément, la valeur reste lisible sans.
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppTheme.motion,
                      curve: Curves.easeOutCubic,
                      left: (_positionOf(value!) * width - _Marker.width / 2)
                          .clamp(0.0, width - _Marker.width),
                      top: 0,
                      child: _Marker(
                        color: AppTheme.colorForStatus(status),
                        height: height + 18,
                      ),
                    ),
                ],
              ),
            ),
            if (showBounds) ...[
              const SizedBox(height: AppTheme.gap),
              Row(
                children: <Widget>[
                  Text(
                    _bare(parameter.acceptableMin),
                    style: theme.textTheme.labelMedium,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_bare(parameter.idealMin)}'
                        ' – '
                        '${_bare(parameter.idealMax)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppTheme.inRange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _bare(parameter.acceptableMax),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// Valeur sans unité, avec virgule décimale.
  String _bare(double v) =>
      v.toStringAsFixed(parameter.decimals).replaceAll('.', ',');
}

/// Montant de la plage conseillée : un trait vertical fin, plein hauteur.
class _Bracket extends StatelessWidget {
  const _Bracket({required this.height});

  static const double width = 2.0;

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.inRange,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Repère de la valeur : une aiguille, comme sur un cadran.
class _Marker extends StatelessWidget {
  const _Marker({required this.color, required this.height});

  static const double width = 14.0;

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: <Widget>[
          // La pointe en haut désigne la graduation sans la masquer.
          CustomPaint(
            size: const Size(width, 7),
            painter: _TrianglePainter(color),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 4,
                height: height - 7,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
