import '../../models/filtration_schedule.dart';
import '../../models/pool_config.dart';
import 'pool_device_driver.dart';

/// Pilote pour un type de liaison qui n'est pas encore écrit.
///
/// Il existe pour que l'application démarre quand même : une configuration
/// qui désigne un matériel non implémenté ne doit pas donner un écran noir au
/// lancement, sinon l'utilisateur n'a plus aucun moyen de changer de liaison
/// dans les réglages.
///
/// Toute opération échoue avec une phrase affichable. C'est délibérément un
/// échec et non un repli silencieux vers la simulation : croire qu'on pilote
/// sa piscine alors qu'on ne pilote rien est le pire des deux résultats,
/// surtout pour un volet.
class UnavailableDriver implements PoolDeviceDriver {
  const UnavailableDriver(this.kind);

  final DriverKind kind;

  String get _label {
    switch (kind) {
      case DriverKind.localModule:
        return 'le module local';
      case DriverKind.homeAssistant:
        return 'Home Assistant';
      case DriverKind.mqtt:
        return 'la liaison MQTT';
      case DriverKind.simulation:
        return 'la simulation';
    }
  }

  Never _unavailable(String operation) {
    throw DeviceException(
      'La liaison par $_label n’est pas encore disponible dans cette '
      'version. Choisissez un autre type de liaison dans les réglages.',
      technicalDetail: '$operation non implémenté pour ${kind.name}',
    );
  }

  @override
  Future<void> pulse(DeviceChannel channel, {required Duration autoOff}) async {
    // La garde de sécurité s'applique avant tout : une temporisation illégale
    // reste un défaut de programmation, même sur un pilote indisponible.
    CoverSafety.checkCoverAutoOff(channel, autoOff);
    _unavailable('pulse');
  }

  @override
  Future<void> setRelay(DeviceChannel channel, {required bool on}) async =>
      _unavailable('setRelay');

  @override
  Future<bool> relayState(DeviceChannel channel) async =>
      _unavailable('relayState');

  @override
  Future<double?> relayPower(DeviceChannel channel) async =>
      _unavailable('relayPower');

  @override
  Future<bool?> inputState(DeviceInput input) async =>
      _unavailable('inputState');

  @override
  Future<Duration> ping() async => _unavailable('ping');

  @override
  Future<void> pushFiltrationSchedule(FiltrationSchedule schedule) async =>
      _unavailable('pushFiltrationSchedule');

  @override
  Future<void> clearFiltrationSchedule() async {
    // Rien n'a jamais été écrit : échouer ici empêcherait un changement de
    // matériel de se terminer.
  }

  @override
  Future<void> dispose() async {}
}
