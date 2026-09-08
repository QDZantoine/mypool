import 'package:flutter/material.dart';

import '../../models/filtration_schedule.dart';
import '../theme.dart';

/// Les créneaux de filtration posés sur une journée de 24 h.
///
/// Une liste de « 10:45 – 17:15 » demande de reconstruire mentalement la
/// journée pour répondre à la seule question qu'on se pose : est-ce que ça
/// tourne quand j'en ai besoin ? La bande y répond d'un regard — on voit les
/// blocs, on voit les trous, on voit que le plus long couvre l'après-midi.
///
/// Même langage visuel que le nuancier de mesure : une bande, des zones, des
/// graduations. L'application n'a ainsi qu'une seule façon de montrer une
/// échelle.
class DayTimeline extends StatelessWidget {
  const DayTimeline({required this.cycles, this.height = 34, super.key});

  final List<FiltrationCycle> cycles;
  final double height;

  static const int _minutesPerDay = 24 * 60;

  /// Heures graduées sous la bande.
  ///
  /// Quatre repères seulement : minuit, 6 h, midi, 18 h. Un axe complet
  /// serait illisible sur un téléphone au soleil, et personne n'a besoin de
  /// lire l'heure exacte ici — les horaires précis sont dans la liste.
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
                    // Le fond : la journée entière, pompe à l'arrêt.
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
                    // Les repères d'heure, sous les créneaux pour ne pas les
                    // barrer.
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
                    // Les créneaux. Un créneau qui passe minuit est dessiné en
                    // deux morceaux : la journée est un cycle, pas une ligne.
                    for (final FiltrationCycle cycle in cycles)
                      for (final _Slice slice in _slicesOf(cycle))
                        Positioned(
                          left: width * slice.startMinute / _minutesPerDay,
                          top: 4,
                          bottom: 4,
                          width:
                              (width * slice.durationMinutes / _minutesPerDay)
                              // Un créneau court doit rester visible.
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
          // Les graduations, réparties comme les repères au-dessus.
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

  /// Découpe un créneau en morceaux affichables.
  static List<_Slice> _slicesOf(FiltrationCycle cycle) {
    final int start = cycle.startMinuteOfDay % _minutesPerDay;
    final int end = start + cycle.durationMinutes;
    if (end <= _minutesPerDay) {
      return <_Slice>[_Slice(start, cycle.durationMinutes)];
    }
    // Passe minuit : la fin repart du début de la bande.
    return <_Slice>[
      _Slice(start, _minutesPerDay - start),
      _Slice(0, end - _minutesPerDay),
    ];
  }
}

/// Un morceau de créneau, entièrement contenu dans la journée.
class _Slice {
  const _Slice(this.startMinute, this.durationMinutes);

  final int startMinute;
  final int durationMinutes;
}
