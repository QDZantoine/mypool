import 'package:flutter/material.dart';

import '../../models/water_reading.dart';
import '../theme.dart';

class MeasureScale extends StatelessWidget {
  const MeasureScale({
    required this.parameter,
    required this.value,
    this.height = 14,
    this.showBounds = true,
    super.key,
  });

  final WaterParameter parameter;

  final double? value;

  final double height;

  final bool showBounds;

  double get _min => parameter.acceptableMin - _acceptableSpan * 0.15;
  double get _max => parameter.acceptableMax + _acceptableSpan * 0.15;
  double get _acceptableSpan =>
      parameter.acceptableMax - parameter.acceptableMin;

  double _positionOf(double v) => ((v - _min) / (_max - _min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final ParameterStatus status = parameter.statusOf(value);
    final bool measured = value != null;

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

                  if (measured)
                    AnimatedPositioned(

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

  String _bare(double v) =>
      v.toStringAsFixed(parameter.decimals).replaceAll('.', ',');
}

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
