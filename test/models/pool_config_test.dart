import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/models/chemical_product.dart';
import 'package:mypool/models/pool_config.dart';

void main() {
  group('valeurs par défaut', () {
    test('une piscine utilisable immediatement', () {
      const PoolConfig config = PoolConfig();

      expect(config.volumeM3, 40.0);
      expect(config.lengthM, 8.0);
      expect(config.widthM, 4.0);
      expect(config.averageDepthM, 1.25);
      expect(config.treatment, TreatmentType.stabilizedChlorine);
      expect(config.filter, FilterType.sand);
      expect(config.cover, CoverType.submerged);
      expect(config.pumpFlowM3PerHour, 10.0);
      expect(config.pumpEfficiency, 0.75);
      expect(config.coverTravelSeconds, 90.0);
      expect(config.driver, DriverKind.simulation);
      // Aucun consentement de sécurité tant que l’utilisateur ne l’a pas donne.
      expect(config.safetyConsentGiven, isFalse);
    });

    test('les dimensions par défaut donnent bien 40 m3', () {
      const PoolConfig config = PoolConfig();
      // 8 x 4 x 1,25 = 40 m3
      expect(config.volumeFromDimensions, closeTo(40.0, 1e-9));
      expect(config.volumeFromDimensions, closeTo(config.volumeM3, 1e-9));
    });

    test('débit utile = débit nominal x rendement', () {
      const PoolConfig config = PoolConfig();
      // 10 x 0,75 = 7,5 m3/h
      expect(config.effectiveFlowM3PerHour, closeTo(7.5, 1e-9));
    });

    test('l’inventaire par défaut est complet', () {
      const PoolConfig config = PoolConfig();
      for (final ChemicalRole role in ChemicalRole.values) {
        expect(config.inventory.products[role], isNotNull, reason: role.name);
      }
    });
  });

  group('proprietes deduites du traitement', () {
    test('chlore stabilisé', () {
      const PoolConfig config = PoolConfig();
      expect(config.usesChlorine, isTrue);
      expect(config.usesStabilizedChlorine, isTrue);
    });

    test(
      'electrolyse au sel : du chlore, mais pas de stabilisant accumule',
      () {
        final PoolConfig config = const PoolConfig().copyWith(
          treatment: TreatmentType.salt,
        );
        expect(config.usesChlorine, isTrue);
        expect(config.usesStabilizedChlorine, isFalse);
      },
    );

    test('oxygène actif : aucun chlore', () {
      final PoolConfig config = const PoolConfig().copyWith(
        treatment: TreatmentType.activeOxygen,
      );
      expect(config.usesChlorine, isFalse);
    });

    test('seuls les volets roulants se pilotent', () {
      expect(const PoolConfig().hasMotorisedCover, isTrue);
      expect(
        const PoolConfig()
            .copyWith(cover: CoverType.outOfWater)
            .hasMotorisedCover,
        isTrue,
      );
      // Une bâche à bulles n’est pas un dispositif de sécurité pilotable.
      expect(
        const PoolConfig()
            .copyWith(cover: CoverType.bubbleCover)
            .hasMotorisedCover,
        isFalse,
      );
      expect(
        const PoolConfig().copyWith(cover: CoverType.none).hasMotorisedCover,
        isFalse,
      );
    });
  });

  group('copyWith', () {
    test('ne modifie que le champ demande', () {
      const PoolConfig base = PoolConfig();
      final PoolConfig modified = base.copyWith(volumeM3: 60.0);

      expect(modified.volumeM3, 60.0);
      expect(modified.lengthM, base.lengthM);
      expect(modified.treatment, base.treatment);
      expect(modified, isNot(base));
    });

    test('sans argument, rend un objet égal', () {
      const PoolConfig base = PoolConfig();
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
    });
  });

  group('aller-retour JSON', () {
    test('une configuration complète survit au passage par JSON', () {
      final PoolConfig original = const PoolConfig().copyWith(
        name: 'Bassin nord',
        volumeM3: 62.5,
        lengthM: 10.0,
        widthM: 5.0,
        averageDepthM: 1.25,
        treatment: TreatmentType.salt,
        filter: FilterType.glass,
        cover: CoverType.outOfWater,
        pumpFlowM3PerHour: 14.0,
        pumpEfficiency: 0.8,
        coverTravelSeconds: 120.0,
        driver: DriverKind.homeAssistant,
        safetyConsentGiven: true,
      );

      final PoolConfig restored = PoolConfig.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(restored, original);
    });

    test('l’inventaire modifie survit aussi', () {
      final ChemicalInventory inventory = ChemicalInventory.standard
          .withProduct(
            ChemicalInventory.defaultFor(ChemicalRole.chlorineSlow)
                .copyWith(activePercent: 56.0, label: 'Mes galets'),
          );
      final PoolConfig original = const PoolConfig().copyWith(
        inventory: inventory,
      );

      final PoolConfig restored = PoolConfig.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(
        restored.inventory.forRole(ChemicalRole.chlorineSlow).activePercent,
        56.0,
      );
      expect(restored, original);
    });
  });

  group('JSON corrompu', () {
    test('un JSON vide rend la configuration par défaut', () {
      expect(PoolConfig.fromJson(<String, dynamic>{}), const PoolConfig());
    });

    test(
      'null, une chaine ou une liste rendent la configuration par defaut',
      () {
        // L’application doit toujours s’ouvrir, même si la préférence à été
        // ecrasee par autre chose qu’un objet.
        expect(PoolConfig.fromJson(null), const PoolConfig());
        expect(PoolConfig.fromJson('pas du json'), const PoolConfig());
        expect(PoolConfig.fromJson(<int>[1, 2, 3]), const PoolConfig());
      },
    );

    test('des types incoherents retombent sur les défauts', () {
      final PoolConfig restored = PoolConfig.fromJson(<String, dynamic>{
        'name': 42,
        'volumeM3': 'beaucoup',
        'treatment': 'plasma_froid',
        'filter': <String, dynamic>{},
        'cover': true,
        'pumpFlowM3PerHour': null,
        'driver': 'telepathie',
        'inventory': 'perdu',
        'safetyConsentGiven': 'peut-etre',
      });

      expect(restored, const PoolConfig());
    });

    test('les valeurs numériques ecrites en chaîne sont acceptees', () {
      final PoolConfig restored = PoolConfig.fromJson(<String, dynamic>{
        'volumeM3': '62.5',
        // Virgule décimale : une version anterieure pouvait l’ecrire ainsi.
        'pumpEfficiency': '0,8',
      });

      expect(restored.volumeM3, 62.5);
      expect(restored.pumpEfficiency, 0.8);
    });

    test('les valeurs aberrantes sont bornées, pas rejetees', () {
      final PoolConfig restored = PoolConfig.fromJson(<String, dynamic>{
        'volumeM3': -40.0,
        'pumpEfficiency': 9.0,
        'coverTravelSeconds': 100000.0,
        'averageDepthM': 0.0,
      });

      // Volume borne à 1 m3 minimum : une dose calculée sur -40 m3 serait
      // négative, une dose calculée sur 1 m3 est simplement fausse mais visible.
      expect(restored.volumeM3, 1.0);
      // Un rendement au-delà de 1 n’a pas de sens physique.
      expect(restored.pumpEfficiency, 1.0);
      expect(restored.coverTravelSeconds, 600.0);
      expect(restored.averageDepthM, 0.2);
    });

    test('un consentement de sécurité ne se devine pas', () {
      // Tout ce qui n’est pas un `true` explicite vaut « non consenti ».
      expect(
        PoolConfig.fromJson(<String, dynamic>{'safetyConsentGiven': 'oui'})
            .safetyConsentGiven,
        isFalse,
      );
      expect(
        PoolConfig.fromJson(<String, dynamic>{'safetyConsentGiven': null})
            .safetyConsentGiven,
        isFalse,
      );
      expect(
        PoolConfig.fromJson(<String, dynamic>{'safetyConsentGiven': true})
            .safetyConsentGiven,
        isTrue,
      );
    });

    test('un enum stocke en index reste lisible', () {
      // Compatibilité avec des données écrites en numérique.
      expect(
        PoolConfig.fromJson(<String, dynamic>{'treatment': 2}).treatment,
        TreatmentType.values[2],
      );
      // Un index hors bornes retombe sur le défaut.
      expect(
        PoolConfig.fromJson(<String, dynamic>{'treatment': 99}).treatment,
        TreatmentType.stabilizedChlorine,
      );
    });
  });

  test('le transport MQTT du banc d’essai est sélectionnable', () {
    // Ajouté en fin d’énumération : les valeurs déjà écrites sur le disque ne
    // sont pas décalées.
    expect(DriverKind.values.last, DriverKind.mqtt);
    expect(
      PoolConfig.fromJson(<String, dynamic>{'driver': 'mqtt'}).driver,
      DriverKind.mqtt,
    );
    // Le défaut ne change pas : la simulation, utilisable sans appairage.
    expect(const PoolConfig().driver, DriverKind.simulation);
  });

  test('Kind est l’alias du genre de pilote', () {
    // Nom court du paragraphe 8.1, conserve pour compatibilité.
    const Kind kind = DriverKind.simulation;
    expect(kind, DriverKind.simulation);
  });
}
