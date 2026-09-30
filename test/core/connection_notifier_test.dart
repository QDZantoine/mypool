import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypool/core/connection_notifier.dart';

void main() {
  group('ConnectionNotifier', () {
    test('initialise avec ConnectionQuality.online et isConnected true', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ConnectionQuality state =
          container.read(connectionNotifierProvider);
      final bool isConnected =
          container.read(connectionNotifierProvider.notifier).isConnected;

      expect(state, ConnectionQuality.online);
      expect(isConnected, isTrue);
    });

    test('updateMqttStatus règle offline si isOnline est false', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ConnectionNotifier notifier =
          container.read(connectionNotifierProvider.notifier);

      final bool ok = notifier.updateMqttStatus(
        isOnline: false,
        isMqttReady: true,
      );

      expect(container.read(connectionNotifierProvider), ConnectionQuality.offline);
      expect(
        ConnectionQuality.offline.userNoticeMessage,
        contains('connexion internet'),
      );
      expect(ok, isFalse);
      expect(notifier.isConnected, isFalse);
    });

    test('updateMqttStatus règle online si isOnline est true', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ConnectionNotifier notifier =
          container.read(connectionNotifierProvider.notifier);

      final bool ok = notifier.updateMqttStatus(
        isOnline: true,
        isMqttReady: false,
      );

      expect(container.read(connectionNotifierProvider), ConnectionQuality.online);
      expect(ok, isTrue);
      expect(notifier.isConnected, isTrue);
    });

    test('checkConnection retourne la même valeur booléenne que isConnected', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ConnectionNotifier notifier =
          container.read(connectionNotifierProvider.notifier);

      expect(notifier.checkConnection(isOnline: true, isMqttReady: true), isTrue);
      expect(notifier.checkConnection(isOnline: false, isMqttReady: true), isFalse);
      expect(notifier.checkConnection(isOnline: true, isMqttReady: false), isTrue);
    });

    test('checkNetworkContinuously met à jour l’état en continu selon networkChecker', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final ConnectionNotifier notifier =
          container.read(connectionNotifierProvider.notifier);

      bool mockOnline = true;
      notifier.networkChecker = () async => mockOnline;

      await notifier.checkNetworkContinuously();
      expect(notifier.isConnected, isTrue);

      mockOnline = false;
      await notifier.checkNetworkContinuously();
      expect(notifier.isConnected, isFalse);
      expect(container.read(connectionNotifierProvider), ConnectionQuality.offline);
    });
  });
}
