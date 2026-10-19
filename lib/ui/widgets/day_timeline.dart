import 'package:flutter/material.dart';

import '../../models/filtration_schedule.dart';
import '../theme.dart';

class DayTimeline extends StatelessWidget {
  const DayTimeline({required this.cycles, this.height = 34, super.key});

  final List<FiltrationCycle> cycles;
  final double height;

  static const int _minutesPerDay = 24 * 60;

  static const List<int> _ticks = <int>[0, 6, 12, 18];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      label: cycles.isEmpty
          ? 'Aucun créneau de filtration.'
          : 'Filtration de '
                '${cycles.map((FiltrationCycle c) => '${c.formattedStart} à '
                    '${c.formattedEnd}').join(', ')}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              return SizedBox(
                height: height,
                child: Stack(
                  children: <Widget>[

                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.14,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),

                    for (final int hour in _ticks)
                      if (hour > 0)
                        Positioned(
                          left: width * hour / 24,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 1,
                            color: theme.colorScheme.outline.withValues(
                              alpha: 0.28,
                            ),
                          ),
                        ),

                    for (final FiltrationCycle cycle in cycles)
                      for (final _Slice slice in _slicesOf(cycle))
                        Positioned(
                          left: width * slice.startMinute / _minutesPerDay,
                          top: 4,
                          bottom: 4,
                          width:
                              (width * slice.durationMinutes / _minutesPerDay)

                              .clamp(3.0, width),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTheme.chlorine,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppTheme.gap),

          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Stack(
                children: <Widget>[
                  SizedBox(height: 18, width: constraints.maxWidth),
                  for (final int hour in _ticks)
                    Positioned(
                      left: constraints.maxWidth * hour / 24,
                      child: Text(
                        '${hour}h',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  Positioned(
                    right: 0,
                    child: Text('24h', style: theme.textTheme.labelMedium),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static List<_Slice> _slicesOf(FiltrationCycle cycle) {
    final int start = cycle.startMinuteOfDay % _minutesPerDay;
    final int end = start + cycle.durationMinutes;
    if (end <= _minutesPerDay) {
      return <_Slice>[_Slice(start, cycle.durationMinutes)];
    }

    return <_Slice>[
      _Slice(start, _minutesPerDay - start),
      _Slice(0, end - _minutesPerDay),
    ];
  }
}

class _Slice {
  const _Slice(this.startMinute, this.durationMinutes);

  final int startMinute;
  final int durationMinutes;
}
