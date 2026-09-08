import '../../models/filtration_schedule.dart';

/// Erreur matérielle, avec un message en français directement affichable.
///
/// Aucune trace technique ne doit atteindre l'interface : l'utilisateur est au
/// bord du bassin, il a besoin de savoir quoi faire, pas de lire un code HTTP.
/// Le détail technique va dans [technicalDetail], réservé aux journaux.
class DeviceException implements Exception {
  const DeviceException(this.message, {this.technicalDetail});

  /// Phrase affichable telle quelle, en français.
  final String message;

  /// Détail réservé au diagnostic. Jamais affiché.
  final String? technicalDetail;

  @override
  String toString() => 'DeviceException: $message';
}

/// Sorties pilotables du module.
///
/// Les deux canaux du volet ferment un contact **en parallèle des boutons
/// existants** du coffret : ils ne remplacent ni l'automate, ni les fins de
/// course, ni les temporisations d'origine (règle de sécurité n° 5).
enum DeviceChannel {
  /// Contact d'ouverture du volet.
  coverOpen,

  /// Contact de fermeture du volet.
  coverClose,

  /// Relais de la pompe de filtration.
  pump,

  /// Relais du chauffage. Exposé par le banc d'essai, hors périmètre de
  /// l'application v1 (addendum § 8).
  heater,
}

/// Entrées lisibles sur le module.
///
/// Elles n'existent que si l'installation remonte de vraies fins de course.
/// Sans elles, la position du volet reste une estimation.
enum DeviceInput { coverOpenedLimit, coverClosedLimit }

/// Invariants de sécurité du volet.
///
/// Ce ne sont pas des réglages : ils découlent de la norme NF P90-308 et de la
/// règle « aucun arrêt ne doit dépendre d'un ordre envoyé par le réseau ». Ils
/// ne sont donc pas dans [PoolConfig], qui est modifiable par l'utilisateur.
class CoverSafety {
  /// Intervalle de republication de l'ordre tant que le doigt est maintenu.
  ///
  /// 700 ms : assez court pour que deux pertes de message consécutives restent
  /// sous le délai de garde, assez long pour ne pas saturer la liaison.
  /// Valeur du contrat du banc d'essai (addendum § 4.1).
  static const Duration holdRepeatInterval = Duration(milliseconds: 700);

  /// Délai de garde porté par le MATÉRIEL : sans nouvel ordre, le mouvement
  /// s'arrête au bout de ce délai.
  ///
  /// 1 800 ms, soit deux intervalles de republication plus une marge. C'est
  /// aussi ce qui tient la règle de sécurité n° 2 : « le relais retombe seul
  /// en moins de 2 s ».
  static const Duration holdTimeout = Duration(milliseconds: 1800);

  /// Plafond absolu d'une temporisation matérielle sur un canal de volet.
  ///
  /// Au-delà, le volet continuerait de bouger plus de deux secondes après la
  /// disparition de l'application : ce n'est plus un homme mort.
  static const Duration maxCoverAutoOff = Duration(seconds: 2);

  /// Refuse une temporisation trop longue sur un canal de volet.
  ///
  /// Cette garde vit dans le contrat du pilote, et non dans le seul
  /// contrôleur : un pilote appelé depuis un futur écran, un test ou un
  /// script ne doit pas pouvoir contourner la limite.
  static void checkCoverAutoOff(DeviceChannel channel, Duration autoOff) {
    if (channel != DeviceChannel.coverOpen &&
        channel != DeviceChannel.coverClose) {
      return;
    }
    if (autoOff > maxCoverAutoOff || autoOff <= Duration.zero) {
      throw DeviceException(
        'Commande de volet refusée par sécurité.',
        technicalDetail:
            'autoOff=$autoOff hors de la plage '
            '(0, $maxCoverAutoOff] sur ${channel.name}',
      );
    }
  }
}

/// Contrat unique de tout matériel piloté par l'application.
///
/// Toute la variabilité matérielle est derrière cette interface : un nouveau
/// module se branche en écrivant une implémentation de plus, sans toucher au
/// moteur de dosage, aux contrôleurs ni aux écrans.
///
/// Aucune méthode ne prend de position cible. C'est délibéré : une commande
/// « va à 50 % » ferait exécuter au matériel un mouvement complet sans
/// supervision humaine, ce qu'interdit la règle de sécurité n° 3.
abstract class PoolDeviceDriver {
  /// Ferme un contact pendant [autoOff], la temporisation étant portée par le
  /// MATÉRIEL et non par cet appel.
  ///
  /// C'est le point central de la sécurité : l'application ne promet jamais
  /// d'envoyer un ordre d'arrêt. Si le téléphone se verrouille, perd le réseau
  /// ou plante juste après cet appel, le contact retombe quand même.
  Future<void> pulse(DeviceChannel channel, {required Duration autoOff});

  /// Force un relais dans un état stable, sans temporisation.
  ///
  /// Réservé à la pompe et au chauffage. Un canal de volet ne s'enclenche
  /// jamais de cette façon : il n'aurait plus de retombée automatique.
  Future<void> setRelay(DeviceChannel channel, {required bool on});

  /// État courant d'un relais.
  Future<bool> relayState(DeviceChannel channel);

  /// Puissance instantanée d'un relais, en watts, ou `null` si le module ne la
  /// mesure pas.
  ///
  /// Sert à détecter qu'un moteur tourne alors qu'on le croit à l'arrêt.
  Future<double?> relayPower(DeviceChannel channel);

  /// État d'une entrée, ou `null` si l'installation n'a pas ce capteur.
  ///
  /// Le `null` n'est pas un défaut : la plupart des coffrets ne remontent
  /// aucune fin de course, et l'interface doit alors présenter la position
  /// comme une estimation (règle de sécurité n° 6).
  Future<bool?> inputState(DeviceInput input);

  /// Vérifie la liaison et rend la latence mesurée.
  ///
  /// Lève une [DeviceException] si le module ne répond pas.
  Future<Duration> ping();

  /// Écrit le planning de filtration DANS le matériel.
  ///
  /// Le planning doit être exécuté par le module, pas par le téléphone : un
  /// téléphone éteint ne doit pas empêcher la piscine de filtrer. Un pilote
  /// incapable de stocker un planning lève une [DeviceException] explicite
  /// plutôt que de faire croire que c'est fait.
  Future<void> pushFiltrationSchedule(FiltrationSchedule schedule);

  /// Efface le planning stocké dans le matériel.
  Future<void> clearFiltrationSchedule();

  /// Libère les ressources de liaison (connexion MQTT, client HTTP, minuteurs).
  ///
  /// N'est pas une opération métier : elle existe parce qu'un pilote réseau
  /// doit pouvoir fermer sa connexion quand l'utilisateur change de matériel
  /// dans les réglages.
  Future<void> dispose();
}
