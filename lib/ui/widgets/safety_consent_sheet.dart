import 'package:flutter/material.dart';

import '../theme.dart';

/// Avertissement de sécurité du volet, à accepter avant toute commande.
///
/// RÈGLE DE SÉCURITÉ N° 4 : sans acceptation, aucune commande de volet
/// n'agit. Le texte n'est pas une décharge de responsabilité : il explique ce
/// que l'utilisateur doit faire, parce qu'un volet de piscine est un
/// dispositif de sécurité au sens de la norme NF P90-308 et qu'une personne
/// peut se trouver dans le bassin.
///
/// Le bouton d'acceptation est volontairement le second, et l'annulation est
/// mise au même niveau visuel : rien n'incite à accepter sans lire.
class SafetyConsentSheet extends StatelessWidget {
  const SafetyConsentSheet({super.key});

  /// Affiche l'avertissement. Rend `true` si l'utilisateur a accepté.
  static Future<bool> show(BuildContext context) async {
    final bool? accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Non annulable par un glissement vers le bas : accepter ou refuser doit
      // être un geste conscient.
      isDismissible: false,
      enableDrag: false,
      builder: (BuildContext context) => const SafetyConsentSheet(),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      // Défilable : sur un petit téléphone, l'avertissement ne doit ni être
      // tronqué ni pousser les deux boutons hors de l'écran. Un texte de
      // sécurité qu'on ne peut pas lire jusqu'au bout ne vaut rien.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.acid,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Avant de piloter le volet',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Un volet de piscine est un dispositif de sécurité. Une '
              'personne ou un animal peut se trouver dans le bassin ou sur '
              'la couverture.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            const _Rule(
              icon: Icons.visibility,
              text:
                  'Ne commandez le volet que si vous VOYEZ le bassin '
                  'entièrement, du début à la fin du mouvement.',
            ),
            const _Rule(
              icon: Icons.touch_app,
              text:
                  'Le mouvement ne dure que tant que votre doigt reste '
                  'appuyé. Relâchez et il s’arrête.',
            ),
            const _Rule(
              icon: Icons.wifi_off,
              text:
                  'Si le réseau tombe ou si l’application se ferme, le '
                  'volet s’arrête tout seul en moins de deux secondes.',
            ),
            const _Rule(
              icon: Icons.help_outline,
              text:
                  'La position affichée est une estimation, pas une '
                  'mesure : vérifiez toujours de vos yeux.',
            ),
            const SizedBox(height: 8),
            Text(
              'Le coffret d’origine garde toutes ses sécurités. Cette '
              'application ne fait qu’appuyer sur ses boutons à votre place.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Plus tard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('J’ai compris'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
