import '../../models/filtration_schedule.dart';

class DeviceException implements Exception {
  const DeviceException(this.message, {this.technicalDetail});

  final String message;

  final String? technicalDetail;

  @override
  String toString() => 'DeviceException: $message';
}

enum DeviceChannel {

  coverOpen,

  coverClose,

  pump,

  heater,
}

enum DeviceInput { coverOpenedLimit, coverClosedLimit }

class CoverSafety {

  static const Duration holdRepeatInterval = Duration(milliseconds: 700);

  static const Duration holdTimeout = Duration(milliseconds: 1800);

  static const Duration maxCoverAutoOff = Duration(seconds: 2);

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

abstract class PoolDeviceDriver {

  Future<void> pulse(DeviceChannel channel, {required Duration autoOff});

  Future<void> setRelay(DeviceChannel channel, {required bool on});

  Future<bool> relayState(DeviceChannel channel);

  Future<double?> relayPower(DeviceChannel channel);

  Future<bool?> inputState(DeviceInput input);

  Future<Duration> ping();

  Future<void> pushFiltrationSchedule(FiltrationSchedule schedule);

  Future<void> clearFiltrationSchedule();

  Future<void> dispose();
}
