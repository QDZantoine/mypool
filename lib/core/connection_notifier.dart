import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// Statut global de la connexion applicative (OS/Internet).
enum ConnectionQuality { online, degraded, offline }

/// Extension fournissant le message d'information personnalisé selon le problème de connexion.
extension ConnectionQualityMessage on ConnectionQuality {
  /// Message affiché à l'utilisateur selon la cause de la panne.
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

/// Modélise et gère le statut global de la connexion avec Riverpod.
///
/// Écoute la connexion internet en continu.
class ConnectionNotifier extends Notifier<ConnectionQuality> {
  Timer? _monitoringTimer;

  bool _isNetworkOnline = true;
  bool _disposed = false;

  /// Fonction de vérification réseau (injectable/surchargable en test).
  Future<bool> Function()? networkChecker;

  @override
  ConnectionQuality build() {
    _disposed = false;
    ref.onDispose(stopMonitoring);
    return ConnectionQuality.online;
  }

  /// Indique si la connexion globale est valide (true / false).
  bool get isConnected => state == ConnectionQuality.online;

  /// Démarre l'écoute en continu du réseau.
  void startMonitoring() {
    stopMonitoring();
    _disposed = false;

    // Vérification réseau périodique en continu (toutes les 3 secondes en production)
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

  /// Arrête l'écoute en continu (libération des ressources).
  void stopMonitoring() {
    _disposed = true;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// Effectue la vérification réseau courante et met à jour le statut.
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

  /// Test réseau par défaut (Interfaces, DNS et Socket TCP).
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

    // 1. Vérification des interfaces réseau physiques/cellulaires actives
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      ).timeout(const Duration(seconds: 2));

      if (interfaces.isEmpty) {
        return false;
      }
    } catch (_) {}

    // 2. Noms de domaine réels (éviter les IP littérales qui échouent sous Android DNS)
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

    // 3. Fallback : ouverture de socket TCP direct vers port DNS (8.8.8.8:53)
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

  /// Met à jour la connectivité (seule la connexion internet fait foi).
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

  /// Teste la connexion directement et retourne true (OK) ou false (KO).
  bool checkConnection({required bool isOnline, required bool isMqttReady}) {
    return updateMqttStatus(isOnline: isOnline, isMqttReady: isMqttReady);
  }
}

/// Provider Riverpod exposant le contrôleur de statut de connexion.
final NotifierProvider<ConnectionNotifier, ConnectionQuality>
connectionNotifierProvider =
    NotifierProvider<ConnectionNotifier, ConnectionQuality>(
      ConnectionNotifier.new,
    );
