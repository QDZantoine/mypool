# AquaControl (`mypool`) - Application Mobile IoT de Gestion de Piscine

![AquaControl Banner](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![State Management](https://img.shields.io/badge/State--Management-Riverpod-blue)
![Database](https://img.shields.io/badge/Database-SQLite-003B57?logo=sqlite)
![IoT Protocol](https://img.shields.io/badge/Protocol-MQTT%20%7C%20REST%20%7C%20HTTPS-orange)
![Tests](https://img.shields.io/badge/Tests-622%20passing-brightgreen)

AquaControl est une application Flutter mobile IoT conçue pour le contrôle et l'automatisation complète d'une piscine résidentielle :
- **Chimie de l'eau** : Calcul automatique de l'Indice de Langelier et recommandations précises de traitement de l'eau.
- **Pilotage de la filtration** : Calcul dynamique du temps de filtration selon la température et planification automatique par créneaux.
- **Commande du volet roulant** : Contrôle sécurisé du volet (ouverture/fermeture) avec retour d'état temps réel.
- **Météo & Alertes** : Géolocalisation et prévisions météo intégrées pour adapter le traitement.
- **Intégration IoT & Node-RED** : Connexion MQTT bidirectionnelle avec banc ESP32 (Wokwi) et récupération de l'historique pH InfluxDB via Node-RED.

---

## 📄 Dossier Technique & Grille d'Évaluation

Un **Dossier Technique** complet justifiant l'architecture logicielle, le choix des protocoles, la stratégie offline-first et les mesures de sécurité est disponible dans [`DOSSIER_TECHNIQUE.md`](./DOSSIER_TECHNIQUE.md).

### Synthèse du respect de la Grille d'Évaluation :

1. **Architecture Mobile (Flutter / MVVM)** :
   - Découpage strict des couches (`UI`, `State/Riverpod`, `Domain`, `Data/Repository`).
   - Interface Material 3 responsive et conforme aux règles d'accessibilité (contraste WCAG AA 4,5:1).
2. **Intégration IoT & Réseau** :
   - MQTT (Wokwi / ESP32) pour le contrôle temps réel.
   - HTTP REST pour Node-RED & InfluxDB.
   - HTTPS pour le service météo externe.
3. **Robustesse & Offline-First** :
   - Persistance locale complète sous **SQLite** (`aquacontrol.db`).
   - Détection en temps réel de la connectivité via `ConnectionNotifier`.
   - Bannière d'avertissement visuelle lors des coupures réseau et basculement automatique sur les données locales.
   - Processus de retry intelligent à la reconnexion.
4. **Sécurité & Dossier Technique** :
   - Chiffrement TLS / HTTPS pour les flux de transit (MQTT Port 8883 / Weather HTTPS API).
   - Sanitisation et requêtes SQL préparées contre l'injection.
   - Dossier technique complet rédigé (`DOSSIER_TECHNIQUE.md`).

---

## 🚀 Lancer l'Application

### Prérequis
- Flutter SDK (>= 3.13)
- Dart SDK

### Commandes
```bash
# 1. Installer les dépendances
flutter pub get

# 2. Exécuter l'application
flutter run

# 3. Lancer la suite complète de tests unitaires et widgets (622 tests)
flutter test
```

---

## 🧪 Simulation IoT & Wokwi
Pour simuler le banc d'essai ESP32 :
- Fichier de schéma du circuit : [`diagram.json`](./diagram.json)
- Addendum de simulation Wokwi : [`ADDENDUM-SIMULATION-WOKWI.md`](./ADDENDUM-SIMULATION-WOKWI.md)
