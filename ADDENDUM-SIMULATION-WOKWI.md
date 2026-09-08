# Addendum au cahier des charges — banc d'essai Wokwi (ESP32 + MQTT)

Complète `CAHIER-DES-CHARGES.md`. Le § 6 de celui-ci (architecture
matérielle sur relais HTTP local) reste la **cible de déploiement**.
Ce document décrit un **banc d'essai** : un ESP32 simulé sous Wokwi, qui permet
de développer et de valider toute l'application — y compris la logique de
sécurité de la bâche — sans matériel et sans toucher au coffret.

Version 1.0 — 7 septembre 2026

---

## 1. Ce que le banc d'essai apporte

| Sans banc d'essai | Avec |
|---|---|
| Le pilotage de la bâche ne se teste qu'avec le vrai volet | Testable sur un servo simulé, en boucle |
| Attendre la livraison du matériel pour écrire le pilote | Le pilote s'écrit et se teste dès maintenant |
| La coupure réseau en pleine manœuvre se teste… en coupant le wifi de la maison | Il suffit d'arrêter de publier |
| Les mesures viennent de la saisie manuelle | Un curseur fait varier le pH en direct |

Le banc d'essai apporte aussi une chose que la cible n'a pas : des **sondes**.
Dans le montage, le pH et la température remontent tout seuls. L'application
doit donc savoir traiter des mesures automatiques en plus des mesures saisies —
ce qui prépare l'arrivée d'une vraie sonde de température (§ 13 du plan de
développement).

### 1.1 Décision d'architecture

L'application supporte **deux pilotes** derrière la même interface
`PoolDeviceDriver` :

| Pilote | Transport | Usage |
|---|---|---|
| `ShellyDriver` | HTTP local | Déploiement réel sur le coffret existant |
| `WokwiMqttDriver` | MQTT | Banc d'essai, et toute future carte ESP32 |
| `SimulationDriver` | aucun | Tests unitaires, développement hors ligne |

Le choix se fait dans les réglages (`DriverKind`). Aucune couche au-dessus du
pilote ne change : ni le moteur de dosage, ni les écrans, ni les contrôleurs.
C'est exactement ce que le § 9 du cahier des charges cherchait à garantir.

---

## 2. Correspondance des composants

Wokwi n'a pas de sonde de piscine : on transpose.

| Fonction réelle | Composant Wokwi | Broche | Transposition |
|---|---|---|---|
| Cerveau et liaison | ESP32 DevKit v1 | — | Wifi `Wokwi-GUEST` + MQTT |
| Sonde pH | Potentiomètre | GPIO 34 | 0–4095 → 0–14, centre = pH 7 |
| Température de l'eau | Capteur NTC | GPIO 35 | Steinhart-Hart, B = 3950 |
| Bâche à rouleau | Servomoteur | GPIO 18 | 0° ouverte, 180° fermée, course 12 s |
| Pompe de filtration | Module relais | GPIO 23 | + LED bleue sur GPIO 22 |
| Chauffage | Module relais | GPIO 19 | + LED rouge sur GPIO 21 |
| État de la liaison | LED verte | GPIO 4 | Allumée quand MQTT est connecté |

### 2.1 Deux pièges à connaître

**Les entrées analogiques doivent rester sur ADC1 (GPIO 32 à 39).** Sur un vrai
ESP32, l'ADC2 devient inutilisable dès que le wifi est actif — les lectures
renvoient n'importe quoi. Le simulateur, lui, ne s'en plaint pas : un montage
qui marche sous Wokwi sur GPIO 25 échouera silencieusement sur la carte réelle.
D'où le choix de 34 et 35.

**L'ADC réel n'est pas linéaire.** Wokwi donne une conversion parfaite ; un
ESP32 réel présente une erreur de plusieurs dizaines de millivolts et sature
vers 3,1 V. Une vraie sonde demandera donc une calibration en deux points, que
la simulation ne peut pas révéler. La conversion est isolée dans une fonction
unique du firmware (`phFromRaw`) pour que ce soit le seul endroit à reprendre.

### 2.2 Différences avec le matériel réel

| Point | Simulation | Réel |
|---|---|---|
| Servomoteur | suffit à montrer le mouvement | un volet de piscine se pilote par les boutons du coffret, jamais par un servo |
| Alimentation | tout en 3,3 V | un servo veut 5 V et une alimentation séparée ; un relais de pompe veut un contacteur |
| Sonde pH | potentiomètre linéaire | sonde à électrode, ~−59 mV/pH, calibration deux points, remplacement tous les 2 ans |
| NTC | courbe théorique | dispersion des composants, câble long, dérive |
| Broker | public, sans authentification | broker local avec identifiants — voir § 6 |

---

## 3. Contrat MQTT

Base de tous les topics : `aquacontrol/<deviceId>`, où `<deviceId>` est une
chaîne aléatoire longue. Sur un broker public, **c'est la seule chose qui sépare
vos topics de ceux des autres**.

### 3.1 Publications de l'ESP32 vers l'application

| Topic | Rétention | Contenu |
|---|---|---|
| `…/state/telemetry` | oui | JSON complet, toutes les 2 s |
| `…/state/online` | oui | `1` à la connexion, `0` via le testament MQTT |
| `…/state/alert/filter` | oui | `1` quand le compteur de la pompe dépasse le seuil |

Trame de télémétrie :

```json
{
  "deviceId": "a7f3c1e9b2",
  "ph": 7.24,
  "phRaw": 2117,
  "tempC": 26.4,
  "cover":  { "position": 0.420, "motion": "opening", "estimated": true },
  "pump":   { "on": true, "runMinutes": 312 },
  "heater": { "on": false, "auto": true, "setpointC": 27.0 },
  "filterAlert": false,
  "uptimeS": 1834
}
```

`motion` vaut `idle`, `opening` ou `closing`. `position` va de 0,0 (fermée) à
1,0 (ouverte).

**Pourquoi la rétention** : une application qui se connecte reçoit
immédiatement le dernier état connu, au lieu d'afficher un écran vide pendant
deux secondes. **Pourquoi le testament** : si l'ESP32 disparaît sans prévenir
(coupure de courant), le broker publie `0` sur `…/state/online`. L'application
sait que l'installation est hors ligne sans avoir à le deviner par un délai
d'attente.

### 3.2 Commandes de l'application vers l'ESP32

Payloads textuels courts, jamais du JSON : pas de bibliothèque à embarquer, pas
de trame malformée à gérer dans un chemin critique.

| Topic | Payloads | Effet |
|---|---|---|
| `…/cmd/cover` | `open` \| `close` \| `stop` | **un ordre = une pression maintenue**, voir § 4 |
| `…/cmd/cover-calibrate` | `open` \| `closed` | recale la position déclarée par l'utilisateur |
| `…/cmd/pump` | `on` \| `off` | marche forcée de la pompe |
| `…/cmd/heater` | `on` \| `off` \| `auto` | chauffage — hors périmètre de l'application v1 |
| `…/cmd/setpoint` | nombre, 10 à 32 | consigne de température, en °C |
| `…/cmd/filter-reset` | `1` | remet le compteur d'heures à zéro après nettoyage |

Qualité de service **1** dans les deux sens : une commande de bâche perdue est
un mouvement qui s'interrompt, une télémétrie perdue est un état figé à
l'écran.

---

## 4. Sécurité de la bâche — transposition en MQTT

Le § 5 du cahier des charges impose que **la temporisation d'arrêt vive dans le
matériel**, jamais dans l'application. En HTTP local, c'est le `toggle_after`
du relais. En MQTT, c'est un mécanisme d'homme mort dans le firmware.

### 4.1 Le mécanisme

```
Doigt appuyé dans l'application
   |
   |-- publie "open" immédiatement
   |-- puis republie "open" toutes les 700 ms
   |
   v
ESP32 : chaque message reçu prolonge le mouvement de 1800 ms

Doigt relâché  ──> plus de message ──> 1800 ms plus tard, arrêt
Wifi coupé     ──> plus de message ──> 1800 ms plus tard, arrêt
Appli tuée     ──> plus de message ──> 1800 ms plus tard, arrêt
Broker HS      ──> plus de message ──> 1800 ms plus tard, arrêt
```

Le firmware coupe en plus le mouvement **immédiatement** si le wifi tombe,
sans attendre le délai de garde.

### 4.2 Ce qui est interdit dans le firmware

- Recevoir une **position cible** (« va à 50 % ») : l'ESP32 exécuterait alors
  un mouvement complet sans supervision. Le protocole n'a délibérément pas de
  commande de ce type.
- Toute programmation, tout automatisme, tout déclenchement par capteur sur la
  bâche.
- Faire dépendre l'arrêt d'un message `stop` : ce message existe par confort
  (arrêt immédiat au relâchement), mais l'arrêt fonctionne sans lui.

### 4.3 Ce que le banc d'essai permet enfin de tester

C'est son intérêt principal. Cinq essais à faire, dans Wokwi :

| Essai | Manipulation | Résultat attendu |
|---|---|---|
| Relâchement | arrêter de publier | le servo s'arrête en < 2 s |
| Perte de liaison | stopper l'application | idem |
| Broker injoignable | couper le réseau du téléphone | idem |
| Fin de course | maintenir jusqu'au bout | arrêt à 0° / 180°, `motion` repasse à `idle` |
| Ordre inversé | envoyer `close` pendant une ouverture | changement de sens sans à-coup |

Le quatrième essai vaut le détour : sur du matériel réel, ce sont les fins de
course du coffret qui arrêtent le volet, pas le firmware. Ici, le firmware
borne la position lui-même — c'est un comportement propre au simulateur, à ne
pas prendre pour un modèle du réel.

---

## 5. Mesures automatiques : comment l'application les traite

Le montage remonte du pH et une température toutes les 2 s. Les enregistrer
tous dans l'historique le noierait : 43 200 lignes par jour pour une piscine
dont le pH bouge en trois jours.

**Règle retenue :**

- La télémétrie alimente un **état courant** affiché en direct sur le tableau
  de bord, non persisté.
- Une mesure n'entre dans l'historique que dans deux cas : l'utilisateur la
  valide, ou un **échantillonnage automatique** l'enregistre au plus une fois
  par heure, et seulement si une valeur a bougé de façon significative
  (0,1 unité de pH, 0,5 °C).
- Une mesure issue d'une sonde est marquée comme telle (`source: sensor`) :
  une bandelette et une sonde non calibrée ne se valent pas, et l'historique
  doit permettre de les distinguer.

Cette règle demande un champ `source` sur `WaterReading` — c'est le seul ajout
au modèle de données du § 8 du cahier des charges.

---

## 6. Sécurité du transport

Le broker public `broker.hivemq.com` est **ouvert à tous** : n'importe qui peut
lire vos topics et publier dessus. Dans le montage Wokwi, rien de physique
n'est branché : le risque se limite à voir un servo bouger tout seul.

**Règles :**

1. Broker public **uniquement** pour la simulation.
2. `deviceId` long et tiré au hasard, jamais un nom devinable.
3. Aucune donnée personnelle dans les topics.
4. **Jamais un vrai volet sur un broker public**, quelles que soient les
   précautions : un identifiant obscur n'est pas une authentification.

Pour la suite : Mosquitto sur le réseau local (Raspberry Pi, NAS ou conteneur),
avec identifiants et, si le broker est exposé, TLS. Le firmware et le pilote
Flutter n'ont alors qu'à changer d'adresse et à passer un couple
identifiant/mot de passe — le contrat de la § 3 ne bouge pas.

---

## 7. Le montage

Trois fichiers, à coller dans un nouveau projet Wokwi (**New Project → ESP32 →
Arduino**) :

| Fichier | Rôle |
|---|---|
| `sketch.ino` | le firmware |
| `diagram.json` | le montage et le câblage |
| `libraries.txt` | `PubSubClient` et `ESP32Servo` |

`WiFi.h` et `Preferences.h` font partie du cœur ESP32 : elles ne se déclarent
pas dans `libraries.txt`.

### 7.1 Avant de lancer

Dans `sketch.ino`, remplacer `DEVICE_ID` par une chaîne aléatoire à soi. Les
topics en découlent, ils sont affichés dans la console série au démarrage.

### 7.2 Vérification en cinq minutes, sans l'application

Avec n'importe quel client MQTT (MQTT Explorer, ou `mosquitto_sub`/`_pub`) :

```bash
# Voir remonter la télémétrie
mosquitto_sub -h broker.hivemq.com -t 'aquacontrol/VOTRE_ID/state/#' -v

# Démarrer la pompe : le relais claque, la LED bleue s'allume
mosquitto_pub -h broker.hivemq.com -t 'aquacontrol/VOTRE_ID/cmd/pump' -m on

# Ouvrir la bâche pendant 3 s, en imitant le maintien du doigt
for i in $(seq 1 5); do
  mosquitto_pub -h broker.hivemq.com \
    -t 'aquacontrol/VOTRE_ID/cmd/cover' -m open
  sleep 0.7
done
# Le servo doit s'arrêter de lui-même moins de 2 s après la dernière
# publication. Si ce n'est pas le cas, la sécurité ne fonctionne pas :
# ne pas aller plus loin.
```

Ce dernier essai est la validation la plus importante du montage. À faire avant
d'écrire une ligne du pilote Flutter.

### 7.3 Ce qu'on manipule pendant la simulation

- Le **potentiomètre** fait varier le pH : le tourner vers 8,0 doit faire
  apparaître une correction de pH moins dans l'application.
- Le **capteur NTC** a un curseur de température : descendre à 18 °C doit
  réduire la durée de filtration conseillée.
- La **LED verte** dit si la liaison MQTT tient.
- Le **compteur du filtre** est réglé à 30 minutes de pompe (au lieu de 200 h)
  pour voir l'alerte se déclencher pendant une session.

---

## 8. Impact sur le cahier des charges

| Référence | Modification |
|---|---|
| § 2.2 Hors périmètre | Le chauffage entre dans le **montage** mais pas dans l'application v1 : le firmware l'expose, l'appli ne l'affiche pas encore |
| § 6.5 Contrat logiciel | Inchangé. `WokwiMqttDriver` est une troisième implémentation |
| § 8.1 Modèle de données | Ajout d'un champ `source` (`manual` \| `sensor`) sur `WaterReading` |
| § 9.4 Dépendances | Ajout de `mqtt_client` (paquet Dart), utilisé uniquement par le nouveau pilote |
| F1.9 Réglages matériel | Ajout du type de liaison MQTT : adresse du broker, port, `deviceId`, identifiants |
| F5.9 Planning dans le module | **Limite à assumer** : le firmware n'embarque pas d'horloge programmable. En mode MQTT, le planning est exécuté par l'application. Acceptable pour un banc d'essai, inacceptable en production — c'est l'une des raisons pour lesquelles la cible reste le relais HTTP |
| § 5 Sécurité | Inchangé dans ses exigences ; § 4 ci-dessus en donne la transposition MQTT |
| § 11 Recette | Les critères A3 et A5 deviennent testables **sans matériel réel** |

### 8.1 Un mot sur F5.9

Le cahier des charges exige que la filtration tourne téléphone éteint. Un ESP32
peut le faire — il faudrait lui ajouter une horloge NTP et un planning stocké
en mémoire non volatile. Ce n'est pas fait, parce que ce n'est pas le rôle du
banc d'essai. Mais si l'ESP32 devait un jour devenir la cible, **c'est le
premier chantier à ouvrir** : sans lui, la piscine ne filtre plus quand le
téléphone est en vacances.

---

## 9. Prompt Claude Code — firmware ESP32

À utiliser dans un dossier `firmware/` séparé du projet Flutter, en y plaçant
d'abord `sketch.ino`, `diagram.json`, `libraries.txt` et ce document.

```
Lis ADDENDUM-SIMULATION-WOKWI.md, en particulier les § 3 et § 4.

Le firmware sketch.ino est un premier jet fonctionnel mais non compilé.
Travail attendu :

1. Revue de compilation : vérifie les signatures, les types, les
   bibliothèques (PubSubClient, ESP32Servo), et corrige ce qui ne compilerait
   pas sous arduino-cli avec le cœur ESP32. Signale ce que tu changes.

2. Revue de la sécurité de la bâche, § 4. Réponds explicitement à ces
   questions, et corrige si la réponse ne va pas :
   - existe-t-il un chemin de code qui fasse bouger le servo sans qu'un
     message soit arrivé depuis moins de COVER_HOLD_TIMEOUT_MS ?
   - le mouvement s'arrête-t-il si millis() déborde (après 49 jours) ?
   - le mouvement s'arrête-t-il si le wifi tombe, sans attendre le délai de
     garde ?
   - une reconnexion MQTT peut-elle relivrer un ancien message "open" retenu
     par le broker et relancer un mouvement tout seul ? (Les topics de
     commande ne DOIVENT jamais être publiés avec rétention — vérifie que
     rien dans le firmware n'en dépend.)

3. Robustesse :
   - le compteur d'heures de la pompe ne doit pas écrire en flash à chaque
     minute (usure) ;
   - le verrou « pas de chauffage sans filtration » doit tenir quel que soit
     le chemin d'appel ;
   - la trame de télémétrie ne doit jamais dépasser la taille du buffer
     PubSubClient, ni celle du tampon snprintf.

4. Ajoute au sketch une commande de diagnostic sur .../cmd/ping qui republie
   immédiatement la télémétrie, utile pour tester la liaison depuis l'appli.

Ne change ni le contrat MQTT du § 3, ni le brochage du § 2 : le pilote Flutter
est écrit contre eux. Si tu penses qu'un changement est nécessaire, dis-le
avant de le faire.
```

---

## 10. Prompt Claude Code — pilote MQTT côté Flutter

À utiliser dans le projet Flutter, après la phase 3 du plan de développement
(l'interface `PoolDeviceDriver` doit exister).

```
Lis CAHIER-DES-CHARGES.md (§ 5, § 6.5, F5, F6) et
ADDENDUM-SIMULATION-WOKWI.md (§ 3, § 4, § 5, § 8) avant de commencer.

Objectif : ajouter un troisième pilote matériel, en MQTT, pour le banc d'essai
ESP32/Wokwi. Les pilotes existants ne changent pas.

1. pubspec.yaml : ajoute mqtt_client. Aucune autre dépendance.

2. lib/data/devices/wokwi_mqtt_driver.dart : implémente PoolDeviceDriver
   exactement selon le contrat du § 3 de l'addendum.
   - pulse(target, autoOff) publie une commande de bâche ("open" ou "close"
     selon la cible) sur .../cmd/cover, en QoS 1. Le paramètre autoOff n'est
     PAS envoyé : la temporisation vit dans le firmware. Documente-le en
     commentaire, c'est un point de sécurité, pas un oubli.
   - setRelay publie "on"/"off" sur .../cmd/pump.
   - relayState, relayPower et inputState lisent le dernier état reçu par
     télémétrie ; ils ne déclenchent aucune requête.
   - ping publie sur .../cmd/ping et attend une télémétrie fraîche, avec un
     délai maximal.
   - pushFiltrationSchedule lève une DeviceException expliquant que le
     firmware du banc d'essai n'embarque pas de planning autonome, et que la
     filtration est donc pilotée par l'application dans ce mode (§ 8.1).
   - Reconnexion automatique avec backoff, et abonnement à
     .../state/# rétabli après chaque reconnexion.
   - JAMAIS de publication en rétention sur un topic .../cmd/ : un ordre de
     bâche retenu par le broker serait relivré à la prochaine connexion et
     relancerait un mouvement tout seul.

3. lib/data/devices/telemetry.dart : le modèle de la trame reçue
   (PoolTelemetry), avec un parsing tolérant — un champ manquant ou du mauvais
   type ne doit pas faire tomber le flux.

4. state/ : un provider qui expose la dernière télémétrie et l'état en ligne
   (topic .../state/online et testament MQTT). Le tableau de bord affiche le
   pH et la température en direct quand la liaison est là, et signale
   clairement quand elle ne l'est pas.

5. Échantillonnage automatique selon le § 5 de l'addendum : au plus une mesure
   par heure dans l'historique, et seulement si le pH a bougé de 0,1 ou la
   température de 0,5 °C. Ajoute le champ source (manual | sensor) à
   WaterReading, avec la migration SQLite correspondante et la mise à jour des
   tests d'aller-retour JSON.

6. Réglages : type de liaison MQTT, adresse du broker, port, deviceId,
   identifiants optionnels. Le bouton « Tester la liaison » utilise ping().

7. Tests : parsing d'une trame complète, d'une trame partielle et d'une trame
   invalide ; règle d'échantillonnage (une mesure par heure, seuils de
   variation) ; et un test qui vérifie qu'aucune publication de commande n'est
   faite avec le drapeau de rétention.

Contrainte de sécurité, non négociable : le CoverController n'est pas modifié.
Il continue d'envoyer une impulsion toutes les 700 ms tant que le doigt est
posé, et l'arrêt reste porté par le firmware. Si le passage en MQTT semble
appeler un assouplissement de cette mécanique, dis-le au lieu de le faire.
```

---

## 11. Ordre de travail conseillé

1. Monter le projet Wokwi et le faire tourner (§ 7).
2. **Valider la sécurité de la bâche au client MQTT** (§ 7.2) — avant toute
   ligne de Dart.
3. Faire passer le firmware par le prompt du § 9, relancer les essais du § 4.3.
4. Écrire le pilote MQTT côté Flutter (§ 10).
5. Reprendre les essais du § 4.3, cette fois depuis l'application : doigt
   relâché, application tuée, mode avion, wifi coupé.
6. Reprendre les critères d'acceptation A3, A4 et A5 du cahier des charges.

L'étape 2 avant l'étape 4 n'est pas une précaution de style : si la
temporisation du firmware ne fonctionne pas, tout ce qui est écrit au-dessus
donne une fausse impression de sécurité.
