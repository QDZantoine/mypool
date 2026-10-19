import '../../models/filtration_schedule.dart';
import '../../models/pool_config.dart';
import 'pool_device_driver.dart';

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

  }

  @override
  Future<void> dispose() async {}
}
