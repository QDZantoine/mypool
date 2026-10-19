import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devices/pool_device_driver.dart';
import '../models/cover_state.dart';
import '../models/pool_config.dart';

typedef PeriodicTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer timer) onTick,
);

enum CoverRefusal {

  none,

  consentMissing,

  noMotorisedCover,

  deviceError,
}

class CoverStatus {
  const CoverStatus({
    this.cover = CoverState.unknownState,
    this.refusal = CoverRefusal.none,
    this.errorMessage,
  });

  final CoverState cover;
  final CoverRefusal refusal;

  final String? errorMessage;

  bool get isMoving => cover.isMoving;

  CoverStatus copyWith({
    CoverState? cover,
    CoverRefusal? refusal,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CoverStatus(
      cover: cover ?? this.cover,
      refusal: refusal ?? this.refusal,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'CoverStatus(${cover.position.name}, '
      '${cover.motion.name}, ${refusal.name})';
}

class CoverController extends StateNotifier<CoverStatus> {
  CoverController({
    required this._driver,
    required this._config,
    DateTime Function()? clock,
    PeriodicTimerFactory? timerFactory,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.periodic,
       super(const CoverStatus());

  final PoolDeviceDriver _driver;

  final PoolConfig Function() _config;

  final DateTime Function() _clock;
  final PeriodicTimerFactory _timerFactory;

  Timer? _holdTimer;

  DateTime? _movingSince;

  CoverMotion _direction = CoverMotion.idle;

  bool get isHeld => _holdTimer != null;

  Future<bool> pressOpen() => _press(CoverMotion.opening);

  Future<bool> pressClose() => _press(CoverMotion.closing);

  Future<bool> _press(CoverMotion direction) async {
    final PoolConfig config = _config();

    if (!config.safetyConsentGiven) {
      state = state.copyWith(refusal: CoverRefusal.consentMissing);
      return false;
    }
    if (!config.hasMotorisedCover) {
      state = state.copyWith(refusal: CoverRefusal.noMotorisedCover);
      return false;
    }

    if (_direction != CoverMotion.idle && _direction != direction) {
      _integrate();
      _stopRepeating();
    }

    _direction = direction;
    final bool sent = await _sendPulse();
    if (!sent) {
      return false;
    }

    _movingSince = _clock();
    state = state.copyWith(
      cover: state.cover.copyWith(motion: direction, lastMovedAt: _clock()),
      refusal: CoverRefusal.none,
      clearError: true,
    );

    _holdTimer ??= _timerFactory(
      CoverSafety.holdRepeatInterval,
      (Timer _) => unawaited(_tick()),
    );
    return true;
  }

  Future<void> release() async {
    if (_direction == CoverMotion.idle && _holdTimer == null) {
      return;
    }

    _stopRepeating();
    _integrateFrom(_movingSinceBeforeStop);
    _direction = CoverMotion.idle;
    state = state.copyWith(
      cover: state.cover.copyWith(motion: CoverMotion.idle),
    );
  }

  Future<void> _tick() async {
    if (_direction == CoverMotion.idle) {
      return;
    }
    _integrate();

    final bool reachedLimit = await _checkLimitSwitch();
    if (reachedLimit) {
      await release();
      return;
    }

    await _sendPulse();
  }

  Future<bool> _sendPulse() async {
    final DeviceChannel channel = _direction == CoverMotion.opening
        ? DeviceChannel.coverOpen
        : DeviceChannel.coverClose;
    try {
      await _driver.pulse(channel, autoOff: CoverSafety.holdTimeout);
      return true;
    } on DeviceException catch (error) {
      _stopRepeating();
      _direction = CoverMotion.idle;
      state = state.copyWith(
        cover: state.cover.copyWith(motion: CoverMotion.idle),
        refusal: CoverRefusal.deviceError,
        errorMessage: error.message,
      );
      return false;
    }
  }

  Future<bool> _checkLimitSwitch() async {
    final DeviceInput input = _direction == CoverMotion.opening
        ? DeviceInput.coverOpenedLimit
        : DeviceInput.coverClosedLimit;
    try {
      final bool? reached = await _driver.inputState(input);
      if (reached == null) {

        return false;
      }
      if (reached) {
        state = state.copyWith(
          cover: state.cover.copyWith(
            openRatio: _direction == CoverMotion.opening ? 1.0 : 0.0,
            position: _direction == CoverMotion.opening
                ? CoverPosition.open
                : CoverPosition.closed,
            isEstimated: false,
          ),
        );
      }
      return reached;
    } on DeviceException {

      return false;
    }
  }

  void _integrate() => _integrateFrom(_movingSince);

  void _integrateFrom(DateTime? since) {
    if (since == null || _direction == CoverMotion.idle) {
      return;
    }
    final DateTime now = _clock();
    _movingSince = now;

    final double travelSeconds = _config().coverTravelSeconds;
    if (travelSeconds <= 0) {
      return;
    }
    final double elapsed = now.difference(since).inMilliseconds / 1000.0;
    if (elapsed <= 0) {
      return;
    }

    final double delta = elapsed / travelSeconds;
    double ratio =
        state.cover.openRatio +
        (_direction == CoverMotion.opening ? delta : -delta);
    ratio = ratio.clamp(0.0, 1.0);

    state = state.copyWith(
      cover: state.cover.copyWith(
        openRatio: ratio,
        position: CoverState.positionFromRatio(ratio),
        lastMovedAt: now,
      ),
    );
  }

  DateTime? _movingSinceBeforeStop;

  void _stopRepeating() {
    _movingSinceBeforeStop = _movingSince;
    _holdTimer?.cancel();
    _holdTimer = null;
    _movingSince = null;
  }

  void declarePosition({required bool open}) {
    if (_direction != CoverMotion.idle) {
      return;
    }
    state = state.copyWith(
      cover: state.cover.copyWith(
        openRatio: open ? 1.0 : 0.0,
        position: open ? CoverPosition.open : CoverPosition.closed,
        isEstimated: true,
        lastMovedAt: _clock(),
      ),
    );
  }

  Future<void> refreshPump() async {
    try {
      final bool on = await _driver.relayState(DeviceChannel.pump);
      final double? power = await _driver.relayPower(DeviceChannel.pump);
      state = state.copyWith(
        cover: state.cover.copyWith(
          pump: on ? PumpState.on : PumpState.off,
          pumpPowerW: power,
        ),
        clearError: true,
      );
    } on DeviceException catch (error) {
      state = state.copyWith(
        cover: state.cover.copyWith(pump: PumpState.unknown),
        errorMessage: error.message,
      );
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }
}
