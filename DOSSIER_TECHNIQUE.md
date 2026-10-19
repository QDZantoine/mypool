# Dossier Technique - Application AquaControl (IoT Pool Management)

> **Projet IoT - AquaControl**  
> **Auteurs** : QUENDEZ Antoine et RIGAUD Luc
> **Technologies principales** : Flutter, Riverpod, SQLite, MQTT, Node-RED, InfluxDB, Wokwi (ESP32).

---

## 1. Présentation Générale & Vision Produit

**AquaControl** est une application mobile IoT conçue pour la gestion complète et automatisée des piscines pour les particuliers :
- **Analyse & chimie de l'eau** : Calcul automatique de l'Indice de Langelier et recommandations précises de dosage (pH+, pH-, Chlore, TAC, Stabilisant).
- **Pilotage de la filtration** : Calcul dynamique du temps et des créneaux de filtration en fonction de la température de l'eau et de la puissance de la pompe.
- **Contrôle du volet roulant** : Télécommande sécurisée et retour d'état en direct via le banc IoT.
- **Intégration météo** : Géolocalisation automatique et récupération des conditions et alertes météo.
**Information** : Dans ce POC seul le ph est utilisé en bdd, le chlore, TAC, etc, sont mockés. les commandes sont envoyées au banc de test (wokwi). La filtration est aussi simulée.

---

## 2. Architecture Logicielle Mobile (MVVM & Layering Flutter)

L'application respecte une séparation stricte des responsabilités en **4 couches indépendantes**, associées à la gestion d'état réactive via **Flutter Riverpod**.

```mermaid
graph TD
    subgraph UI ["Couche UI (lib/ui)"]
        UI_Screens[Screens: Home, Volet, Filtration, Météo, Réglages, History]
        UI_Widgets[Widgets réutilisables & Accessible Design]
    end

    subgraph State ["Couche State Management / ViewModel (lib/state, lib/core)"]
        RP_Providers[Riverpod Notifiers & Providers]
        Connection_Notifier[ConnectionNotifier & Offline Health]
    end

    subgraph Domain ["Couche Métier / Domaine Pur (lib/domain)"]
        Chemistry_Engine[ChemistryEngine (Doses & Taylor)]
        Water_Balance[WaterBalance (Langelier Index)]
        Filtration_Planner[FiltrationPlanner (Créneaux & Durée)]
        Reading_Sampler[ReadingSampler (Prélèvements)]
    end

    subgraph Data ["Couche Données & Services (lib/data, lib/services)"]
        SQLite_DB[(SQLite ReadingsDatabase)]
        Settings_Store[(SharedPreferences Settings)]
        NodeRed_Service[NodeRedService / InfluxDB API]
        Weather_Service[WeatherService HTTPS]
        MQTT_Driver[WokwiMqttDriver / MqttTransport]
    end

    UI_Screens --> RP_Providers
    RP_Providers --> Chemistry_Engine
    RP_Providers --> Water_Balance
    RP_Providers --> Filtration_Planner
    RP_Providers --> Connection_Notifier
    RP_Providers --> SQLite_DB
    RP_Providers --> Settings_Store
    RP_Providers --> MQTT_Driver
    RP_Providers --> NodeRed_Service
    RP_Providers --> Weather_Service
```

### Détail des Couches

1. **Vues & Interface Utilisateur (`lib/ui/`)** :
   - Interfaces développées sous Material 3 avec thèmes clair et sombre calibrés.
   - Respect strict des normes d'accessibilité (contraste WCAG AA 4,5:1 vérifié par tests unitaires, cibles tactiles de 56 px).
2. **Gestion d'État / ViewModels (`lib/state/` et `lib/core/`)** :
   - Utilisation de **Riverpod** (`NotifierProvider`, `StateNotifierProvider`).
   - `ConnectionNotifier` suit l'état du réseau en temps réel et propage les coupures/rétablissements.
3. **Domaine & Métier (`lib/domain/`)** :
   - Code pur Dart, sans dépendances UI ni frameworks, 100 % couvert par des tests unitaires.
   - Implémentation fidèle des équations physiques et chimiques (Indice de Langelier, régulation du pH selon le TAC, planification découpage de filtration).
4. **Données & Communication (`lib/data/` & `lib/services/`)** :
   - Abstractions par répertoires et pilotes (`ReadingsRepository`, `MqttTransport`, `PoolDeviceDriver`).

---

## 3. Intégration IoT & Protocole de Communication

Le système interagit avec les capteurs et actionneurs de la piscine via **deux niveaux de communication complémentaires** :

| Protocole | Usage / Composant | Justification Technique |
| :--- | :--- | :--- |
| **MQTT** *(Publish/Subscribe)* | Communication en direct avec l'ESP32 / Wokwi (`lib/data/devices/wokwi_mqtt_driver.dart`). | • Légèreté et faible surcoût réseau pour microcontrôleur ESP32.<br>• Réactivité temps réel pour la télémétrie (pH, temp).<br>• Fiabilité des commandes du volet et de la filtration avec accusés de réception et messages de statut (LWT / Retained). |
| **HTTP / REST (JSON)** | Interrogation de Node-RED / InfluxDB (`lib/services/node_red_service.dart`). | • Récupération d'historiques longs filtrés/échantillonnés.<br>• Facilité d'intégration avec la base temporelle InfluxDB. |
| **HTTPS (TLS)** | Service Météo externe (`lib/services/weather-service.dart`). | • Flux chiffré TLS obligatoire pour les données géolocalisées et clés d'API externes. |

---

## 4. Stratégie Offline-First & Résilience Réseau

L'application a été conçue pour fonctionner de manière fluide **même sans connexion internet ou sans capteur IoT actif** :

1. **Persistance Locale SQLite (`ReadingsDatabase`)** :
   - Chaque mesure d'eau (saisie manuelle ou trame capteur) est immédiatement enregistrée dans une base de données SQLite locale (`aquacontrol.db`).
   - L'historique, les calculs et les conseils de dosage sont toujours accessibles hors-ligne.
2. **Surveillance & Résilience Réseau (`ConnectionNotifier`)** :
   - Un processus d'arrière-plan teste régulièrement la connectivité physique (Interfaces réseau, requêtes DNS et pings TCP socket).
   - En cas d'interruption réseau, une **bannière visuelle d'avertissement** apparaît sur l'application ("*Mode hors-ligne : utilisation du cache local et de la BDD SQLite*").
3. **Reconnexion Intelligent & Fallback** :
   - Si la sonde IoT devient indisponible, l'application bascule automatiquement sur les données de la dernière saisie manuelle ou le simulateur sans bloquer l'interface ni lever d'exception non gérée.
   - Dès le rétablissement d'Internet, le pilote MQTT tente automatiquement une reconnexion silencieuse.

---

## 5. Sécurité des Flux et des Données

1. **Sécurité des Flux en Transit (TLS / SSL)** :
   - Connexions MQTT configurables sur le port sécurisé `8883` avec chiffrement **TLS/SSL** (compatible brokers cloud comme HiveMQ).
   - Toutes les requêtes HTTP externes vers le service Météo sont exécutées exclusivement sur le protocole sécurisé **HTTPS**.
2. **Sécurité des Données au Repos** :
   - Utilisation de requêtes SQL préparées (`sqflite` avec `whereArgs` et sérialisation sécurisée) afin d'exclure tout risque d'injection SQL.
   - Isolation du stockage local dans le bac à sable applicatif Android / iOS.
   - Gestion des clés et secrets via variables d'environnement `.env` (exclus du contrôle de version).

---

## 6. Banc d'Essai & Simulation IoT (Wokwi / Node-RED / ESP32)

Un banc d'essai complet basé sur un microcontrôleur **ESP32 sous Wokwi** et un serveur **Node-RED** est intégré au projet :

- **Firmware ESP32 & Wokwi** : Déclaré dans `firmware/` et `diagram.json`.
- **Node-RED / InfluxDB** : Endpoint `/api/ph-history` permettant de collecter et restituer l'historique des mesures pH.
- **Basculement transparent** : En mode développement ou démonstration, l'application peut communiquer indifféremment avec le banc Wokwi virtuel ou le simulateur logiciel interne.

---

## 7. Assurance Qualité & Validation Automatisée

Le projet intègre une suite d'essais automatisés couvrant l'ensemble de la chaîne de traitement (plus de **620 tests unitaires et widgets**) :

- **Moteur chimique** : Validation des dosages selon les équations de Taylor et Langelier.
- **Planificateur de filtration** : Vérification du découpage chronologique sans chevauchement.
- **Pilotes IoT** : Tests unitaires mockés du protocole MQTT, du retry et des timeouts network.

```bash
# Commande d'exécution de la suite de tests
flutter test
```
