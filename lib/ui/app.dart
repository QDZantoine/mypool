import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection_notifier.dart';
import '../models/pool_config.dart';
import '../state/providers.dart';
import '../widgets/weather/weather_page.dart';
import '../widgets/weather/weather_providers.dart';
import 'cover_screen.dart';
import 'filtration_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'splash_screen.dart';
import 'theme.dart';

class AquaControlApp extends StatelessWidget {
  const AquaControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaControl',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ShellView extends ConsumerStatefulWidget {
  const ShellView({super.key});

  @override
  ConsumerState<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends ConsumerState<ShellView> {
  int _index = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(bootstrap(ProviderScope.containerOf(context)));
    });
  }

  static const List<String> _titles = <String>[
    'AquaControl',
    'Volet',
    'Filtration',
    'Météo',
    'Réglages',
  ];

  @override
  Widget build(BuildContext context) {
    final PoolConfig config = ref.watch(poolConfigProvider);
    final ConnectionQuality connectionQuality =
        ref.watch(connectionNotifierProvider);

    AppTheme.applyBrightness(Theme.brightnessOf(context));

    final bool isOffline = connectionQuality == ConnectionQuality.offline ||
        connectionQuality == ConnectionQuality.degraded;

    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? config.name : _titles[_index]),
        actions: <Widget>[
          if (_index == 0)
            IconButton(
              tooltip: 'Historique',
              icon: const Icon(Icons.show_chart),
              onPressed: () => HistoryScreen.open(context),
            ),
          if (_index == 3)
            IconButton(
              tooltip: 'Actualiser la météo',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(userPositionProvider);
                ref.invalidate(currentWeatherCoordinatesProvider);
                ref.invalidate(alertWeatherCoordinatesProvider);
              },
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (isOffline)
            Container(
              width: double.infinity,
              color: AppTheme.drift.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.wifi_off_rounded, color: AppTheme.drift, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      connectionQuality.userNoticeMessage ??
                          'Mode hors-ligne : utilisation du cache local et de la BDD SQLite.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.drift,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: switch (_index) {
              0 => const HomeScreen(),
              1 => const CoverScreen(),
              2 => const FiltrationScreen(),
              3 => const WeatherPage(),
              _ => const SettingsScreen(),
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() => _index = index),

        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Eau',
          ),
          NavigationDestination(
            icon: Icon(Icons.roller_shades_closed_outlined),
            selectedIcon: Icon(Icons.roller_shades_closed),
            label: 'Volet',
          ),
          NavigationDestination(
            icon: Icon(Icons.loop_outlined),
            selectedIcon: Icon(Icons.loop),
            label: 'Filtration',
          ),
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: 'Météo',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Réglages',
          ),
        ],
      ),
    );
  }
}
