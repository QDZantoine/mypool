import 'dart:math' as math;

import '../../models/filtration_schedule.dart';
import 'pool_device_driver.dart';

class SimulationDriver implements PoolDeviceDriver {
  SimulationDriver({
    DateTime Function()? clock,
    this.coverTravel = const Duration(seconds: 90),
    this.latency = const Duration(milliseconds: 20),
    this.hasLimitSwitches = false,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final Duration coverTravel;

  final Duration latency;

  final bool hasLimitSwitches;

  final Map<DeviceChannel, DateTime> _pulseUntil = <DeviceChannel, DateTime>{};

  final Map<DeviceChannel, bool> _latched = <DeviceChannel, bool>{};

  double _openRatio = 0.0;

  DateTime? _integratedUntil;

  FiltrationSchedule? _schedule;

  bool _online = true;

  bool _disposed = false;

  int pulseCount = 0;

  void setOnline(bool online) {
    _online = online;
  }

  bool get isOnline => _online;

  double get coverOpenRatio {
    _integrate();
    return _openRatio;
  }

  FiltrationSchedule? get storedSchedule => _schedule;

  void calibrateCover({required bool open}) {
    _integrate();
    _openRatio = open ? 1.0 : 0.0;
  }

  void _integrate() {
    final DateTime now = _clock();
    final DateTime from = _integratedUntil ?? now;
    _integratedUntil = now;
    if (!now.isAfter(from)) {
      return;
    }

    final int travelMs = coverTravel.inMilliseconds;
    if (travelMs <= 0) {
      return;
    }

    double delta = 0.0;
    for (final DeviceChannel channel in <DeviceChannel>[
      DeviceChannel.coverOpen,
      DeviceChannel.coverClose,
    ]) {
      final DateTime? until = _pulseUntil[channel];
      if (until == null) {
        continue;
      }

      final DateTime end = until.isBefore(now) ? until : now;
      if (!end.isAfter(from)) {
        continue;
      }
      final double moved = end.difference(from).inMilliseconds / travelMs;
      delta += channel == DeviceChannel.coverOpen ? moved : -moved;
    }

    _openRatio = math.min(1.0, math.max(0.0, _openRatio + delta));
  }

  void _checkUsable() {
    if (_disposed) {
      throw const DeviceException(
        'La liaison avec le module a été fermée.',
        technicalDetail: 'SimulationDriver déjà libéré',
      );
    }
    if (!_online) {
      throw const DeviceException(
        'Le module ne répond pas. Vérifiez qu’il est alimenté et connecté.',
        technicalDetail: 'simulation hors ligne',
      );
    }
  }

  @override
  Future<void> pulse(DeviceChannel channel, {required Duration autoOff}) async {

    CoverSafety.checkCoverAutoOff(channel, autoOff);
    _checkUsable();
    _integrate();

    if (channel == DeviceChannel.coverOpen) {
      _pulseUntil.remove(DeviceChannel.coverClose);
    } else if (channel == DeviceChannel.coverClose) {
      _pulseUntil.remove(DeviceChannel.coverOpen);
    }

    _pulseUntil[channel] = _clock().add(autoOff);
    pulseCount++;
  }

  @override
  Future<void> setRelay(DeviceChannel channel, {required bool on}) async {
    if (channel == DeviceChannel.coverOpen ||
        channel == DeviceChannel.coverClose) {

      throw DeviceException(
        'Un volet ne se commande jamais en marche continue.',
        technicalDetail: 'setRelay refusé sur ${channel.name}',
      );
    }
    _checkUsable();
    _latched[channel] = on;
  }

  @override
  Future<bool> relayState(DeviceChannel channel) async {
    _checkUsable();
    _integrate();
    final DateTime? until = _pulseUntil[channel];
    if (until != null) {

      if (_clock().isBefore(until)) {
        return true;
      }
      _pulseUntil.remove(channel);
    }
    return _latched[channel] ?? false;
  }

  @override
  Future<double?> relayPower(DeviceChannel channel) async {
    _checkUsable();
    final bool on = await relayState(channel);
    if (!on) {
      return 0.0;
    }
    switch (channel) {

      case DeviceChannel.pump:
        return 450.0; 
      case DeviceChannel.heater:
        return 3000.0; 
      case DeviceChannel.coverOpen:
      case DeviceChannel.coverClose:
        return 120.0; 
    }
  }

  @override
  Future<bool?> inputState(DeviceInput input) async {
    _checkUsable();
    if (!hasLimitSwitches) {

      return null;
    }
    _integrate();
    switch (input) {
      case DeviceInput.coverOpenedLimit:
        return _openRatio >= 0.98;
      case DeviceInput.coverClosedLimit:
        return _openRatio <= 0.02;
    }
  }

  @override
  Future<Duration> ping() async {
    _checkUsable();
    return latency;
  }

  @override
  Future<void> pushFiltrationSchedule(FiltrationSchedule schedule) async {
    _checkUsable();
    _schedule = schedule;
  }

  @override
  Future<void> clearFiltrationSchedule() async {
    _checkUsable();
    _schedule = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _pulseUntil.clear();
  }
}
