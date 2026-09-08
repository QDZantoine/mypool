import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/dose_recommendation.dart';
import 'package:mypool/models/water_reading.dart';
import 'package:mypool/ui/theme.dart';

void main() {
  group('couleurs et libellés d’état', () {
    test('chaque état a une couleur et un libellé', () {
      for (final ParameterStatus status in ParameterStatus.values) {
        expect(AppTheme.colorForStatus(status), isA<Color>());
        expect(
          AppTheme.labelForStatus(status),
          isNotEmpty,
          reason: status.name,
        );
      }
    });

    test('le code couleur suit la gravité', () {
      // Vert dans la plage, ambre en dehors, rouge au-delà de l'acceptable.
      expect(AppTheme.colorForStatus(ParameterStatus.ideal), AppTheme.inRange);
      expect(AppTheme.colorForStatus(ParameterStatus.low), AppTheme.drift);
      expect(AppTheme.colorForStatus(ParameterStatus.high), AppTheme.drift);
      expect(AppTheme.colorForStatus(ParameterStatus.veryLow), AppTheme.acid);
      expect(AppTheme.colorForStatus(ParameterStatus.veryHigh), AppTheme.acid);
      // Gris sans mesure : rien à conclure n'est pas la même chose que « bon ».
      expect(
        AppTheme.colorForStatus(ParameterStatus.unknown),
        AppTheme.unmeasured,
      );
    });

    test('les libellés d’état ne culpabilisent pas', () {
      // Le ton du projet : explicatif, direct, jamais culpabilisant.
      for (final ParameterStatus status in ParameterStatus.values) {
        final String label = AppTheme.labelForStatus(status);
        expect(label, isNot(contains('!')));
        expect(label.toLowerCase(), isNot(contains('danger')));
        expect(label.toLowerCase(), isNot(contains('mauvais')));
      }
    });

    test('chaque rang d’action a une couleur', () {
      for (final ActionPriority priority in ActionPriority.values) {
        expect(AppTheme.colorForPriority(priority), isA<Color>());
      }
      // L'urgence se distingue du reste.
      expect(AppTheme.colorForPriority(ActionPriority.urgent), AppTheme.acid);
      expect(
        AppTheme.colorForPriority(ActionPriority.information),
        AppTheme.chlorine,
      );
    });
  });

  group('lisibilité au soleil', () {
    test('les chiffres mesurés sont très grands', () {
      final ThemeData theme = AppTheme.light();
      // Une valeur se lit à bout de bras, une main occupée.
      expect(theme.textTheme.displayLarge!.fontSize, greaterThanOrEqualTo(56));
      expect(theme.textTheme.displayMedium!.fontSize, greaterThanOrEqualTo(40));
    });

    test('le corps de texte ne descend jamais sous 16 px', () {
      // Ces styles portent les phrases qu'on lit vraiment, au soleil.
      final ThemeData theme = AppTheme.light();
      for (final TextStyle? style in <TextStyle?>[
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
      ]) {
        expect(style!.fontSize, greaterThanOrEqualTo(16));
      }
    });

    test('le micro-libellé tient sa lisibilité de sa forme', () {
      // Il est plus petit que le corps de texte, et c'est assumé : à cette
      // taille, ce sont les capitales et l'espacement qui le rendent lisible,
      // pas les pixels. Il ne porte jamais de phrase, seulement une étiquette.
      // Mais il ne descend pas sous 12 px, le plancher en dessous duquel un
      // texte cesse d'être lisible quelles que soient ses formes.
      expect(AppTheme.eyebrow.fontSize, greaterThanOrEqualTo(12));
      expect(AppTheme.eyebrow.fontSize, lessThan(16));
      expect(AppTheme.eyebrow.fontWeight, FontWeight.w700);
      expect(AppTheme.eyebrow.letterSpacing, greaterThanOrEqualTo(1.0));
    });

    test('aucun style du thème ne descend sous 12 px', () {
      final ThemeData theme = AppTheme.light();
      final Map<String, TextStyle?> styles = <String, TextStyle?>{
        'displayLarge': theme.textTheme.displayLarge,
        'displayMedium': theme.textTheme.displayMedium,
        'displaySmall': theme.textTheme.displaySmall,
        'headlineMedium': theme.textTheme.headlineMedium,
        'titleLarge': theme.textTheme.titleLarge,
        'titleMedium': theme.textTheme.titleMedium,
        'bodyLarge': theme.textTheme.bodyLarge,
        'bodyMedium': theme.textTheme.bodyMedium,
        'labelLarge': theme.textTheme.labelLarge,
        'labelMedium': theme.textTheme.labelMedium,
      };
      styles.forEach((String name, TextStyle? style) {
        expect(style!.fontSize, greaterThanOrEqualTo(12), reason: name);
      });
    });

    test('les micro-interactions restent dans la fenêtre de 150 à 300 ms', () {
      // En dessous de 150 ms un changement d'état est perçu comme un saut,
      // au-delà de 300 ms comme une lenteur.
      expect(AppTheme.motion.inMilliseconds, greaterThanOrEqualTo(150));
      expect(AppTheme.motion.inMilliseconds, lessThanOrEqualTo(300));
    });

    test('les chiffres mesurés sont tabulaires', () {
      // Une valeur qui passe de 7,24 à 7,31 ne doit pas faire danser la mise
      // en page, comme sur un cadran.
      final ThemeData theme = AppTheme.light();
      for (final TextStyle? style in <TextStyle?>[
        theme.textTheme.displayLarge,
        theme.textTheme.displayMedium,
        theme.textTheme.displaySmall,
        theme.textTheme.labelMedium,
      ]) {
        expect(
          style!.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });

    test('les grands nombres sont resserrés', () {
      // C'est ce resserrement qui leur donne l'air d'un cadran plutôt que
      // d'un titre d'article.
      final ThemeData theme = AppTheme.light();
      expect(theme.textTheme.displayLarge!.letterSpacing, lessThan(0));
      expect(theme.textTheme.displayMedium!.letterSpacing, lessThan(0));
    });

    test('les boutons dépassent la cible tactile minimale', () {
      final ThemeData theme = AppTheme.light();
      // 56 px au lieu des 48 px de Material : une main mouillée rate une
      // petite cible.
      expect(AppTheme.touchTarget, greaterThanOrEqualTo(56));
      expect(
        theme.filledButtonTheme.style!.minimumSize!
            .resolve(<WidgetState>{})!
            .height,
        AppTheme.touchTarget,
      );
    });

    test('les deux thèmes existent et diffèrent', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });
  });
}
