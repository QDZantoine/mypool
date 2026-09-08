# AquaControl — contexte projet

Application Flutter de gestion de piscine : chimie de l'eau et doses de
produits, planning de filtration, pilotage du volet roulant, conseils
d'entretien.

**Lis `CAHIER-DES-CHARGES.md` avant toute modification.** Il fait foi sur le
périmètre, les formules et les exigences de sécurité. Ce fichier-ci ne contient
que les règles à ne jamais perdre de vue.

---

## Règles de sécurité — non négociables

Le volet de piscine est un **dispositif de sécurité** relevant de la norme
NF P90-308. Ces règles ne s'assouplissent pas pour gagner en confort
d'utilisation, et ne se contournent pas pour simplifier le code.

1. **Aucun mouvement du volet sans doigt maintenu** sur le bouton. Le
   relâchement arrête le mouvement. Utiliser un `Listener`
   (`onPointerDown`/`onPointerUp`/`onPointerCancel`), jamais un `onTap`.
2. **La temporisation d'arrêt vit dans le matériel**, pas dans l'application
   (`toggle_after` du module). Si le téléphone se verrouille, perd le réseau ou
   plante, le relais retombe seul en moins de 2 s. Aucun arrêt ne doit dépendre
   d'un ordre envoyé par le réseau.
3. **Aucune fermeture programmée, planifiée, automatique ou déclenchée par un
   capteur.** Le volet ne bouge que sur action humaine en cours.
4. **Consentement obligatoire** : sans acceptation de l'avertissement de
   sécurité, aucune commande de volet n'agit.
5. **Le coffret d'origine garde ses sécurités.** Le module ajouté ferme un
   contact en parallèle des boutons existants ; il ne remplace jamais
   l'automate, les fins de course ou les temporisations.
6. **La position du volet sans capteur est une estimation** et doit être
   affichée comme telle.

Si une demande semble impliquer d'assouplir l'une de ces règles, le dire au
lieu de le faire.

---

## Règles métier

- **L'ordre des corrections est du métier, pas de la présentation** :
  TAC → pH → chlore → stabilisant/TH/sel. Le TAC stabilise le pH ; le pH
  commande l'efficacité du chlore. Ne jamais s'appuyer sur la stabilité du tri
  de Dart : trier explicitement sur (priorité, ordre d'ajout).
- **Les coefficients de dosage viennent de l'annexe A du cahier des charges.**
  Ne pas les changer sans raison écrite en commentaire. Chaque coefficient porte
  son unité et son origine.
- **Les doses dépendent de la concentration du produit déclaré** par
  l'utilisateur : 90 % de chlore actif ≠ 56 % ≠ 9,6 %. Ne jamais figer une
  concentration dans le code de calcul.
- **Chlore cible plafonné à 4 mg/L**, même si la règle des 7,5 % du stabilisant
  donne plus : au-delà le bassin n'est pas baignable, et la réponse à un
  stabilisant saturé est le renouvellement d'eau.
- **Arrondir l'écart de pH au centième** avant tout calcul : `7.8 - 7.2` vaut
  `0.6000000000000005` en virgule flottante, ce qui fait passer le nombre
  d'apports de 2 à 3.
- **La filtration est exécutée par le module**, pas par le téléphone : le
  planning est écrit dans le matériel. Un téléphone éteint ne doit pas empêcher
  la piscine de filtrer.
- **Toute dose affichée porte son avertissement** quand il y en a un : baignade
  interdite après un choc, chute de pH lors d'une correction de TAC, chlore non
  stabilisé si le stabilisant est saturé, fractionnement des gros apports.

---

## Architecture

```
ui/       écrans et widgets — ne calcule rien
state/    contrôleurs Riverpod — orchestrent, ne calculent rien
domain/   moteurs métier PURS — testables sans Flutter
data/     persistance (SQLite, préférences) et pilotes matériels
models/   structures immuables
```

Dépendances : `ui → state → domain/data → models`. Jamais l'inverse.

**`domain/` n'importe ni `flutter/material.dart`, ni `sqflite`, ni `http`.**
C'est cette contrainte qui rend le moteur de dosage testable à 100 %, et cette
couverture est un objectif du projet.

Toute la variabilité matérielle est derrière l'interface `PoolDeviceDriver`
(`pulse`, `setRelay`, `relayState`, `relayPower`, `inputState`, `ping`,
`pushFiltrationSchedule`, `clearFiltrationSchedule`). Trois implémentations :
simulation, module local (Shelly RPC), Home Assistant. Un nouveau matériel = une
implémentation de plus, sans toucher au reste.

---

## Conventions de code

- Modèles **immuables** : champs `final`, `copyWith`, `toJson`/`fromJson`.
- `fromJson` **tolérant** : une donnée corrompue retombe sur les valeurs par
  défaut, elle ne lève pas d'exception. L'application doit toujours s'ouvrir.
- Erreurs matérielles : `DeviceException` avec un **message en français
  directement affichable**. Jamais de trace technique dans l'interface.
- Commentaires en français, sur le *pourquoi* et non le *quoi*. Les valeurs
  numériques métier portent toujours leur unité et leur justification.
- Pas de `print` : `avoid_print` est activé.
- `flutter analyze` doit rester à zéro avertissement.
- Format des nombres à l'affichage : **virgule décimale** (`7,2` — `1,44 kg`).

---

## Dépendances

Liste fermée. Ne pas en ajouter sans nécessité démontrée :

`flutter_riverpod` · `sqflite` + `path` · `shared_preferences` · `http` ·
`flutter_local_notifications` · `flutter_lints`

**Pas de bibliothèque de graphiques** : les courbes d'historique sont un
`CustomPainter` maison. Une polyligne, une bande verte et deux dates ne
justifient pas une dépendance dont l'API change à chaque version majeure.

---

## Tests

- `domain/` : couverture **100 %**. Chaque valeur attendue est justifiée par le
  calcul, en commentaire au-dessus de l'assertion.
- Modèles : aller-retour JSON, **y compris avec un JSON corrompu**.
- `SimulationDriver` : vérifier qu'une impulsion **retombe bien toute seule** —
  ce test est le garde-fou de la règle de sécurité n° 2.
- `CoverController` : le relâchement arrête les impulsions ; sans consentement,
  aucune commande ne part.
- Écrire les tests **en même temps** que le code métier, pas après.

```bash
flutter analyze
flutter test
flutter test --coverage
```

---

## Ton des textes de l'application

Français, explicatif, direct, jamais culpabilisant. Chaque conseil dit
*pourquoi* : « à pH 7,2 environ 60 % du chlore est actif, à 8,0 il n'en reste
qu'un quart » est utile ; « maintenez un pH correct » ne l'est pas.

L'utilisateur se sert de l'application **debout au bord du bassin, au soleil,
une main occupée** : gros chiffres, contraste élevé, deux niveaux de navigation
au maximum, aucune donnée à saisir deux fois.
