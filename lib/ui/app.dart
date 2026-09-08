import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pool_config.dart';
import '../state/providers.dart';
import 'cover_screen.dart';
import 'filtration_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Racine de l'application.
class AquaControlApp extends StatelessWidget {
  const AquaControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaControl',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const _Shell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Navigation principale.
///
/// UN SEUL niveau ici, quatre destinations. Le second niveau — saisie,
/// historique, liste complète des actions — s'ouvre par-dessus. C'est la
/// limite que le projet s'impose : « deux niveaux de navigation au maximum »,
/// parce qu'on ne cherche pas dans une arborescence avec une main occupée.
class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // L'amorçage démarre après la première image : l'application est déjà
    // affichée et utilisable avec les valeurs par défaut, et les valeurs
    // enregistrées la remplacent quand elles arrivent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(bootstrap(ProviderScope.containerOf(context)));
    });
  }

  static const List<String> _titles = <String>[
    'AquaControl',
    'Volet',
    'Filtration',
    'Réglages',
  ];

  @override
  Widget build(BuildContext context) {
    final PoolConfig config = ref.watch(poolConfigProvider);
    // Les couleurs d'état sont calibrées par thème : sans cet alignement, un
    // passage en mode sombre garderait les valeurs du mode clair et le
    // contraste tomberait sous la norme.
    AppTheme.applyBrightness(Theme.brightnessOf(context));

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
        ],
      ),
      body: switch (_index) {
        0 => const HomeScreen(),
        1 => const CoverScreen(),
        2 => const FiltrationScreen(),
        _ => const SettingsScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() => _index = index),
        // Les libellés restent toujours visibles : une icône seule se devine
        // mal au soleil, et personne n'a le temps d'apprendre des pictogrammes.
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
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Réglages',
          ),
        ],
      ),
    );
  }
}
