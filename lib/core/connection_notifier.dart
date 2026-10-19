import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

enum ConnectionQuality { online, degraded, offline }

extension ConnectionQualityMessage on ConnectionQuality {

  String? get userNoticeMessage {
    switch (this) {
      case ConnectionQuality.offline:
      case ConnectionQuality.degraded:
        return 'Problème de connexion, veuillez vérifier votre connexion internet.';
      case ConnectionQuality.online:
        return null;
    }
  }
}

class ConnectionNotifier extends Notifier<ConnectionQuality> {
  Timer? _monitoringTimer;

  bool _isNetworkOnline = true;
  bool _disposed = false;

  Future<bool> Function()? networkChecker;

  @override
  ConnectionQuality build() {
    _disposed = false;
    ref.onDispose(stopMonitoring);
    return ConnectionQuality.online;
  }

  bool get isConnected => state == ConnectionQuality.online;

  void startMonitoring() {
    stopMonitoring();
    _disposed = false;

    bool isTestEnv = false;
    try {
      isTestEnv =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      isTestEnv = true;
    }

    if (!isTestEnv) {
      _monitoringTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!_disposed) {
          unawaited(checkNetworkContinuously());
        }
      });
    }

    unawaited(checkNetworkContinuously());
  }

  void stopMonitoring() {
    _disposed = true;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  Future<bool> checkNetworkContinuously() async {
    if (_disposed) return isConnected;

    final bool online = networkChecker != null
        ? await networkChecker!()
        : await _defaultCheckNetworkOnline();

    if (_disposed) return isConnected;

    _isNetworkOnline = online;

    try {
      final driver = ref.read(mqttDriverProvider);
      if (driver != null && online && !driver.isModuleOnline) {
        unawaited(driver.start());
      }
    } catch (_) {}

    updateMqttStatus(isOnline: _isNetworkOnline, isMqttReady: true);
    return isConnected;
  }

  static Future<bool> _defaultCheckNetworkOnline() async {
    bool isTestEnv = false;
    try {
      isTestEnv =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      isTestEnv = true;
    }
    if (isTestEnv) {
      return true;
    }

    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      ).timeout(const Duration(seconds: 2));

      if (interfaces.isEmpty) {
        return false;
      }
    } catch (_) {}

    try {
      final List<InternetAddress> result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final List<InternetAddress> result = await InternetAddress.lookup('cloudflare.com')
          .timeout(const Duration(seconds: 4));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final Socket socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {}

    try {
      final Socket socket = await Socket.connect(
        '1.1.1.1',
        53,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {}

    return false;
  }

  bool updateMqttStatus({required bool isOnline, required bool isMqttReady}) {
    _isNetworkOnline = isOnline;

    if (!isOnline) {
      state = ConnectionQuality.offline;
    } else {
      state = ConnectionQuality.online;
      try {
        ref.read(coverControllerProvider.notifier).clearError();
      } catch (_) {}
    }
    return isConnected;
  }

  bool checkConnection({required bool isOnline, required bool isMqttReady}) {
    return updateMqttStatus(isOnline: isOnline, isMqttReady: isMqttReady);
  }
}

final NotifierProvider<ConnectionNotifier, ConnectionQuality>
connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionQuality>(
      ConnectionNotifier.new,
    );
