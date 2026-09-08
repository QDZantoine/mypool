/*
 * AquaControl — banc d'essai ESP32 sous Wokwi
 * ------------------------------------------------------------------
 * Simule l'installation de la piscine pour développer l'application
 * Flutter sans matériel : sondes pH et température, bâche à rouleau,
 * pompe de filtration, chauffage.
 *
 * Correspondance des composants (Wokwi n'a pas de sonde de piscine) :
 *
 *   Potentiomètre  ->  sonde pH        (0..4095 converti en 0..14)
 *   Capteur NTC    ->  température de l'eau
 *   Servomoteur    ->  bâche           (0° ouverte, 180° fermée)
 *   Relais + LED bleue  ->  pompe de filtration
 *   Relais + LED rouge  ->  chauffage
 *   LED verte      ->  état de la liaison MQTT
 *
 * ------------------------------------------------------------------
 * SÉCURITÉ — à lire avant de modifier la partie bâche
 *
 * La bâche ne bouge que tant que l'application envoie des ordres
 * répétés (« homme mort »). Si les messages s'arrêtent — application
 * fermée, téléphone verrouillé, wifi coupé, broker injoignable — le
 * mouvement s'arrête tout seul en moins de COVER_HOLD_TIMEOUT_MS.
 *
 * Cette temporisation vit ICI, dans le firmware, et nulle part
 * ailleurs. C'est la transposition du `toggle_after` d'un relais du
 * commerce, et de l'exigence d'action maintenue de la norme
 * NF P90-308. Ne la remplacez pas par un ordre d'arrêt envoyé par
 * l'application : un ordre qui doit traverser le réseau pour arrêter
 * un volet n'est pas une sécurité.
 *
 * Trois protections complètent le délai de garde :
 *
 *   1. Toute opération susceptible de bloquer la boucle (connexion
 *      wifi, connexion MQTT) est précédée d'un arrêt de la bâche.
 *      Une boucle bloquée est une boucle qui ne peut plus arrêter un
 *      mouvement.
 *   2. La rétention est effacée sur les topics de commande à chaque
 *      connexion, et les ordres reçus dans la seconde qui suit un
 *      abonnement sont ignorés. Sans cela, un « open » retenu par le
 *      broker relancerait un mouvement à chaque reconnexion, sans
 *      personne devant la piscine.
 *   3. Rien n'est publié depuis le callback MQTT : PubSubClient
 *      partage un seul tampon entre réception et émission.
 *
 * Ce montage est un SIMULATEUR. Le broker public utilisé ci-dessous
 * est ouvert à tous : n'importe qui peut publier sur ces topics. Ce
 * n'est acceptable que parce que rien de physique n'est branché.
 * Ne pointez jamais un vrai volet sur un broker public.
 * ------------------------------------------------------------------
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ESP32Servo.h>
#include <Preferences.h>
#include <math.h>

// ==================================================================
//  Configuration
// ==================================================================

// Réseau simulé de Wokwi : SSID fixe, sans mot de passe.
// Préciser le canal 6 accélère nettement la connexion.
const char *WIFI_SSID = "Wokwi-GUEST";
const char *WIFI_PASS = "";
const int   WIFI_CHANNEL = 6;

// Broker public, pour la simulation uniquement.
const char *MQTT_HOST = "broker.hivemq.com";
const uint16_t MQTT_PORT = 1883;

// Identifiant de l'installation.
const char *DEVICE_ID = "a7f3c1e9b2";

// Base de tous les topics : aquacontrol/<DEVICE_ID>/...
// Dimensionnés pour un DEVICE_ID de 64 caractères : la taille est
// vérifiée au démarrage, un identifiant trop long est signalé plutôt
// que tronqué en silence.
const size_t DEVICE_ID_MAX = 64;
char topicBase[16 + DEVICE_ID_MAX];
char topicTelemetry[sizeof(topicBase) + 24];
char topicOnline[sizeof(topicBase) + 24];
char topicAlertFilter[sizeof(topicBase) + 24];
char topicCmdWildcard[sizeof(topicBase) + 8];
char topicCmdCover[sizeof(topicBase) + 12];

// ---- Broches ------------------------------------------------------
// Les entrées analogiques doivent rester sur ADC1 (GPIO 32 à 39) :
// sur un vrai ESP32, l'ADC2 est inutilisable dès que le wifi est
// actif. Le simulateur est plus tolérant, le matériel réel ne l'est
// pas — autant prendre l'habitude tout de suite.
const int PIN_PH         = 34;  // potentiomètre  (ADC1_CH6)
const int PIN_NTC        = 35;  // capteur NTC    (ADC1_CH7)
const int PIN_SERVO      = 18;  // servo bâche
const int PIN_RELAY_PUMP = 23;  // relais pompe
const int PIN_LED_PUMP   = 22;  // LED bleue
const int PIN_RELAY_HEAT = 19;  // relais chauffage
const int PIN_LED_HEAT   = 21;  // LED rouge
const int PIN_LED_LINK   = 4;   // LED verte : liaison MQTT

// ---- Bâche --------------------------------------------------------
// Durée d'une course complète. 12 s en simulation pour que le
// mouvement soit observable ; un volet réel prend 60 à 120 s.
const unsigned long COVER_TRAVEL_MS = 12000;

// Au-delà de ce délai sans nouvel ordre, le mouvement s'arrête.
// Doit rester nettement supérieur à la cadence d'envoi de
// l'application (700 ms), et assez court pour que l'arrêt soit
// immédiat à l'échelle humaine.
const unsigned long COVER_HOLD_TIMEOUT_MS = 1800;

// Fenêtre pendant laquelle les ordres de bâche sont ignorés après un
// abonnement. Les messages retenus par le broker sont livrés dès
// l'abonnement : cette fenêtre les neutralise même si l'effacement de
// rétention a échoué. 1 000 ms suffit largement, et coûte au pire une
// pression de doigt à refaire.
const unsigned long COVER_SUBSCRIBE_GRACE_MS = 1000;

// 0° = bâche ouverte, 180° = bâche fermée.
const int SERVO_ANGLE_OPEN   = 0;
const int SERVO_ANGLE_CLOSED = 180;

// ---- Chauffage ----------------------------------------------------
// L'hystérésis évite que le relais claque en continu autour de la
// consigne. Sur du matériel réel, ce battement détruit le contacteur
// et l'échangeur.
const float HEATER_HYSTERESIS_C = 0.5;

// ---- Filtre -------------------------------------------------------
// Alerte de nettoyage après ce nombre de minutes de pompe.
// 200 h en usage réel ; 30 min ici pour voir l'alerte se déclencher
// pendant une session de test.
const uint32_t FILTER_ALERT_MINUTES = 30;

// Période d'écriture du compteur en mémoire non volatile, en minutes
// de pompe. La NVS supporte environ 100 000 cycles d'écriture : une
// écriture par heure de pompe donne plus de vingt ans de marge, une
// écriture toutes les dix minutes en donnait moins de quatre.
const uint32_t PUMP_PERSIST_EVERY_MINUTES = 60;

// ---- Cadences -----------------------------------------------------
const unsigned long SENSOR_PERIOD_MS    = 500;
const unsigned long TELEMETRY_PERIOD_MS = 2000;
const unsigned long MQTT_RETRY_MS       = 3000;

// Le wifi n'est jamais attendu indéfiniment : une tentative dure au
// plus ce délai, puis la boucle reprend la main. Sans cela, une
// coupure durable fige tout le firmware — plus de télémétrie, plus de
// console, plus rien à diagnostiquer.
const unsigned long WIFI_ATTEMPT_TIMEOUT_MS = 8000;

// Délai de socket de PubSubClient, en secondes. La valeur par défaut
// (15 s) bloque la boucle un quart de minute quand le broker ne
// répond pas.
const uint16_t MQTT_SOCKET_TIMEOUT_S = 4;

// ==================================================================
//  État
// ==================================================================

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
Servo coverServo;
Preferences prefs;

// Mesures lissées. L'ADC est bruité : une moyenne glissante évite
// d'envoyer un pH qui saute de 0,2 unité entre deux trames.
const int SMOOTH_SAMPLES = 10;
int phSamples[SMOOTH_SAMPLES];
int ntcSamples[SMOOTH_SAMPLES];
int sampleCount = 0;      // échantillons réellement disponibles
int sampleIndex = 0;      // prochaine case à écrire

float phValue = 7.0;
int   phRaw = 2048;
float waterTempC = 25.0;

// Bâche : position de 0,0 (fermée) à 1,0 (ouverte).
float coverPosition = 0.0;
int   coverHoldDir = 0;              // -1 fermeture, 0 arrêt, +1 ouverture
unsigned long coverLastHoldMs = 0;   // dernier ordre reçu
unsigned long coverLastStepMs = 0;

// Instant du dernier abonnement, pour la fenêtre de garde.
unsigned long lastSubscribeMs = 0;
bool subscribed = false;

// Pompe et compteur d'heures.
bool pumpOn = false;
uint32_t pumpRunMinutes = 0;
uint32_t pumpPersistedMinutes = 0;
unsigned long pumpMinuteAccumulatorMs = 0;
bool filterAlert = false;

// Chauffage.
bool heaterOn = false;
bool heaterAuto = false;
float heaterSetpointC = 27.0;
bool heaterBlockedLogged = false;

unsigned long lastSensorMs = 0;
unsigned long lastTelemetryMs = 0;
unsigned long lastMqttAttemptMs = 0;

// Publications demandées depuis le callback MQTT, exécutées dans la
// boucle : PubSubClient partage un seul tampon entre réception et
// émission, publier pendant le traitement d'un message reçu corrompt
// l'un ou l'autre.
bool pendingTelemetry = false;
bool pendingFilterAlert = false;

// ==================================================================
//  Mise en route
// ==================================================================

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println(F("=== AquaControl — simulateur ESP32 ==="));

  pinMode(PIN_RELAY_PUMP, OUTPUT);
  pinMode(PIN_LED_PUMP, OUTPUT);
  pinMode(PIN_RELAY_HEAT, OUTPUT);
  pinMode(PIN_LED_HEAT, OUTPUT);
  pinMode(PIN_LED_LINK, OUTPUT);
  applyPump(false);
  applyHeater(false);
  digitalWrite(PIN_LED_LINK, LOW);

  analogReadResolution(12);           // 0..4095
  analogSetAttenuation(ADC_11db);     // pleine échelle jusqu'à ~3,3 V

  coverServo.setPeriodHertz(50);
  coverServo.attach(PIN_SERVO, 500, 2400);
  coverServo.write(angleFor(coverPosition));

  // Le compteur d'heures de la pompe survit à un redémarrage : c'est
  // une donnée d'entretien, pas une variable de session.
  prefs.begin("aquacontrol", false);
  pumpRunMinutes = prefs.getUInt("pumpMin", 0);
  pumpPersistedMinutes = pumpRunMinutes;
  filterAlert = pumpRunMinutes >= FILTER_ALERT_MINUTES;
  // uint32_t vaut `unsigned long` sur ESP32 : %u attend `unsigned int`.
  // Le cast explicite garde le format juste sur toute cible.
  Serial.printf("Compteur pompe restauré : %lu min\n",
                (unsigned long)pumpRunMinutes);

  buildTopics();

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onMqttMessage);
  // Le tampon par défaut de PubSubClient (256 octets) est trop court
  // pour la trame de télémétrie complète.
  mqtt.setBufferSize(512);
  mqtt.setSocketTimeout(MQTT_SOCKET_TIMEOUT_S);

  ensureWifi();
}

void buildTopics() {
  const size_t idLength = strlen(DEVICE_ID);
  if (idLength > DEVICE_ID_MAX) {
    // Tronquer en silence donnerait des topics différents de ceux que
    // l'application écoute, et un montage muet sans explication.
    Serial.printf("DEVICE_ID trop long (%u > %u caractères)\n",
                  (unsigned)idLength, (unsigned)DEVICE_ID_MAX);
  }

  snprintf(topicBase, sizeof(topicBase), "aquacontrol/%s", DEVICE_ID);
  snprintf(topicTelemetry, sizeof(topicTelemetry), "%s/state/telemetry", topicBase);
  snprintf(topicOnline, sizeof(topicOnline), "%s/state/online", topicBase);
  snprintf(topicAlertFilter, sizeof(topicAlertFilter), "%s/state/alert/filter", topicBase);
  snprintf(topicCmdWildcard, sizeof(topicCmdWildcard), "%s/cmd/#", topicBase);
  snprintf(topicCmdCover, sizeof(topicCmdCover), "%s/cmd/cover", topicBase);

  Serial.print(F("Topic de base : "));
  Serial.println(topicBase);
}

/*
 * Tente une connexion wifi, avec un délai maximal.
 *
 * La bâche est arrêtée AVANT la tentative : cette fonction bloque la
 * boucle, et une boucle bloquée ne peut plus arrêter un mouvement.
 */
bool ensureWifi() {
  if (WiFi.status() == WL_CONNECTED) {
    return true;
  }

  stopCover("liaison wifi indisponible");
  digitalWrite(PIN_LED_LINK, LOW);
  subscribed = false;

  Serial.print(F("Wifi "));
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS, WIFI_CHANNEL);

  const unsigned long startedAt = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - startedAt > WIFI_ATTEMPT_TIMEOUT_MS) {
      Serial.println(F(" échec, nouvelle tentative au prochain tour"));
      return false;
    }
    delay(150);
    Serial.print('.');
  }

  Serial.print(F(" connecté, IP "));
  Serial.println(WiFi.localIP());
  return true;
}

// ==================================================================
//  Boucle principale
// ==================================================================

void loop() {
  if (!ensureWifi()) {
    // Sans wifi, rien d'autre n'a de sens ce tour-ci. La bâche a déjà
    // été arrêtée par ensureWifi().
    return;
  }

  if (!mqtt.connected()) {
    digitalWrite(PIN_LED_LINK, LOW);
    subscribed = false;
    if (millis() - lastMqttAttemptMs > MQTT_RETRY_MS) {
      lastMqttAttemptMs = millis();
      // connectMqtt() peut bloquer jusqu'au délai de socket : on
      // arrête la bâche avant, pour la même raison que pour le wifi.
      stopCover("liaison MQTT en cours de rétablissement");
      connectMqtt();
    }
  } else {
    mqtt.loop();
    digitalWrite(PIN_LED_LINK, HIGH);
  }

  const unsigned long now = millis();

  if (now - lastSensorMs >= SENSOR_PERIOD_MS) {
    lastSensorMs = now;
    readSensors();
  }

  // Appelé à chaque tour : c'est là que vit la sécurité de la bâche.
  updateCover();

  updateHeater();
  countPumpTime();

  // Publications demandées depuis le callback, exécutées ici.
  if (pendingTelemetry) {
    pendingTelemetry = false;
    lastTelemetryMs = now;
    publishTelemetry();
  }
  if (pendingFilterAlert) {
    pendingFilterAlert = false;
    publishFilterAlert();
  }

  if (now - lastTelemetryMs >= TELEMETRY_PERIOD_MS) {
    lastTelemetryMs = now;
    publishTelemetry();
  }
}

// ==================================================================
//  Liaison MQTT
// ==================================================================

void connectMqtt() {
  char clientId[32 + DEVICE_ID_MAX];
  snprintf(clientId, sizeof(clientId), "aquacontrol-esp32-%s", DEVICE_ID);

  Serial.print(F("MQTT... "));

  // Testament (Last Will) : si l'ESP32 disparaît sans prévenir, le
  // broker publie « 0 » sur le topic de présence. L'application sait
  // ainsi que l'installation est hors ligne sans avoir à deviner.
  const bool ok = mqtt.connect(
      clientId,
      nullptr, nullptr,
      topicOnline, 1, true, "0",
      true);

  if (!ok) {
    Serial.printf("échec (code %d)\n", mqtt.state());
    return;
  }

  Serial.println(F("connecté"));
  mqtt.publish(topicOnline, "1", true);

  clearRetainedCommands();

  mqtt.subscribe(topicCmdWildcard, 1);
  lastSubscribeMs = millis();
  subscribed = true;
  Serial.print(F("Abonné à "));
  Serial.println(topicCmdWildcard);

  publishTelemetry();
  publishFilterAlert();
}

/*
 * Efface les messages de commande retenus par le broker.
 *
 * Un payload vide publié en rétention supprime le message retenu d'un
 * topic (spécification MQTT). C'est la parade au scénario le plus
 * dangereux du montage : un « open » resté retenu sur
 * .../cmd/cover serait relivré à CHAQUE abonnement, et relancerait un
 * mouvement de bâche sans que personne n'ait appuyé.
 *
 * L'application a l'interdiction de publier ses commandes en
 * rétention, mais le firmware ne s'appuie pas sur ce bon
 * comportement : sur un broker public, n'importe qui peut publier.
 */
void clearRetainedCommands() {
  static const char *commandLeaves[] = {
      "cover", "cover-calibrate", "pump", "heater",
      "setpoint", "filter-reset", "ping"};

  char topic[sizeof(topicBase) + 24];
  for (unsigned int i = 0; i < sizeof(commandLeaves) / sizeof(commandLeaves[0]); i++) {
    snprintf(topic, sizeof(topic), "%s/cmd/%s", topicBase, commandLeaves[i]);
    mqtt.publish(topic, "", true);
  }
}

void onMqttMessage(char *topic, byte *payload, unsigned int length) {
  // Payloads volontairement textuels et courts : pas de JSON à parser
  // pour une commande, donc pas de dépendance à une bibliothèque et
  // pas de trame malformée à gérer dans un chemin critique.
  char value[24];
  const unsigned int copyLength = length < sizeof(value) - 1 ? length : sizeof(value) - 1;
  memcpy(value, payload, copyLength);
  value[copyLength] = '\0';

  // Ne garder que le dernier segment du topic : « cover », « pump »...
  const char *leaf = strrchr(topic, '/');
  leaf = (leaf == nullptr) ? topic : leaf + 1;

  // Un payload vide est l'effacement de rétention que nous venons
  // nous-mêmes de publier : il ne commande rien.
  if (copyLength == 0) {
    return;
  }

  Serial.printf("<- %s : %s\n", leaf, value);

  if (strcmp(leaf, "cover") == 0) {
    handleCoverCommand(value);
  } else if (strcmp(leaf, "pump") == 0) {
    applyPump(strcmp(value, "on") == 0);
  } else if (strcmp(leaf, "heater") == 0) {
    handleHeaterCommand(value);
  } else if (strcmp(leaf, "setpoint") == 0) {
    const float requested = atof(value);
    if (requested >= 10.0 && requested <= 32.0) {
      heaterSetpointC = requested;
      Serial.printf("Consigne : %.1f C\n", heaterSetpointC);
    }
  } else if (strcmp(leaf, "filter-reset") == 0) {
    resetFilterCounter();
  } else if (strcmp(leaf, "ping") == 0) {
    // Diagnostic de liaison : republie l'état immédiatement, sans
    // attendre la prochaine période de télémétrie. La publication est
    // différée à la boucle, jamais faite depuis ce callback.
    pendingTelemetry = true;
    pendingFilterAlert = true;
  } else if (strcmp(leaf, "cover-calibrate") == 0) {
    handleCalibrateCommand(value);
  }
}

// ==================================================================
//  Bâche — le cœur de la sécurité
// ==================================================================

/*
 * Un message « open » ou « close » n'est pas un ordre de mouvement
 * complet : c'est une pression de doigt maintenue pendant un instant.
 * L'application en envoie un toutes les 700 ms tant que l'utilisateur
 * appuie. Chaque message ne prolonge le mouvement que de
 * COVER_HOLD_TIMEOUT_MS.
 */
void handleCoverCommand(const char *value) {
  if (strcmp(value, "stop") == 0) {
    // Cet ordre existe par confort, pour un arrêt immédiat au
    // relâchement. L'arrêt ne dépend jamais de lui : sans ce message,
    // le délai de garde fait le travail.
    stopCover("ordre d'arrêt");
    return;
  }

  const bool wantsOpen = strcmp(value, "open") == 0;
  const bool wantsClose = strcmp(value, "close") == 0;
  if (!wantsOpen && !wantsClose) {
    return;
  }

  // Fenêtre de garde après abonnement : un ordre arrivé maintenant est
  // très probablement un message retenu relivré par le broker, pas un
  // doigt posé sur l'écran.
  if (subscribed && millis() - lastSubscribeMs < COVER_SUBSCRIBE_GRACE_MS) {
    Serial.println(F("Ordre de bâche ignoré : trop proche de l'abonnement"));
    return;
  }

  // Butée déjà atteinte : accepter l'ordre ferait osciller l'état
  // publié entre « opening » et « idle » à chaque message.
  if (wantsOpen && coverPosition >= 1.0) {
    stopCover("bâche déjà ouverte");
    return;
  }
  if (wantsClose && coverPosition <= 0.0) {
    stopCover("bâche déjà fermée");
    return;
  }

  coverHoldDir = wantsOpen ? +1 : -1;
  coverLastHoldMs = millis();
}

/*
 * Recalage de la position déclarée par l'utilisateur, qui voit la
 * bâche. Refusé pendant un mouvement : recaler en pleine manœuvre
 * donnerait une position fantaisiste, et faire sauter le servo pendant
 * qu'il tourne n'a pas d'équivalent sur du matériel réel.
 */
void handleCalibrateCommand(const char *value) {
  if (coverHoldDir != 0) {
    Serial.println(F("Recalage refusé : la bâche est en mouvement"));
    return;
  }
  if (strcmp(value, "open") == 0) {
    coverPosition = 1.0;
  } else if (strcmp(value, "closed") == 0) {
    coverPosition = 0.0;
  } else {
    return;
  }
  coverLastStepMs = millis();
  coverServo.write(angleFor(coverPosition));
  Serial.printf("Position recalée à %d %%\n", (int)(coverPosition * 100));
}

void updateCover() {
  const unsigned long now = millis();

  // LE garde-fou : plus d'ordre depuis trop longtemps, on arrête.
  // La soustraction est faite sur des entiers non signés, donc elle
  // reste juste au débordement de millis() (tous les 49 jours) : à
  // cheval sur le débordement, now - coverLastHoldMs rend bien la
  // durée écoulée et non une valeur énorme.
  if (coverHoldDir != 0 && now - coverLastHoldMs > COVER_HOLD_TIMEOUT_MS) {
    stopCover("plus d'ordre reçu");
    return;
  }

  if (coverHoldDir == 0) {
    coverLastStepMs = now;
    return;
  }

  // Avance proportionnelle au temps écoulé : la course complète prend
  // COVER_TRAVEL_MS, quelle que soit la fréquence de la boucle.
  const unsigned long elapsed = now - coverLastStepMs;
  if (elapsed == 0) return;
  coverLastStepMs = now;

  const float step = (float)elapsed / (float)COVER_TRAVEL_MS;
  coverPosition += coverHoldDir * step;

  if (coverPosition <= 0.0) {
    coverPosition = 0.0;
    stopCover("bâche fermée");
  } else if (coverPosition >= 1.0) {
    coverPosition = 1.0;
    stopCover("bâche ouverte");
  }

  coverServo.write(angleFor(coverPosition));
}

void stopCover(const char *reason) {
  if (coverHoldDir != 0) {
    Serial.printf("Bâche arrêtée (%s) à %d %%\n", reason, (int)(coverPosition * 100));
  }
  coverHoldDir = 0;
  coverLastStepMs = millis();
}

int angleFor(float position) {
  // position 0,0 -> 180° (fermée) ; 1,0 -> 0° (ouverte)
  const float angle = SERVO_ANGLE_CLOSED +
                      position * (SERVO_ANGLE_OPEN - SERVO_ANGLE_CLOSED);
  return (int)lround(angle);
}

const char *coverMotionLabel() {
  if (coverHoldDir > 0) return "opening";
  if (coverHoldDir < 0) return "closing";
  return "idle";
}

// ==================================================================
//  Sondes
// ==================================================================

void readSensors() {
  phSamples[sampleIndex] = analogRead(PIN_PH);
  ntcSamples[sampleIndex] = analogRead(PIN_NTC);
  sampleIndex = (sampleIndex + 1) % SMOOTH_SAMPLES;
  if (sampleCount < SMOOTH_SAMPLES) sampleCount++;

  long phSum = 0;
  long ntcSum = 0;
  for (int i = 0; i < sampleCount; i++) {
    phSum += phSamples[i];
    ntcSum += ntcSamples[i];
  }

  phRaw = (int)(phSum / sampleCount);
  phValue = phFromRaw(phRaw);
  waterTempC = celsiusFromRaw((int)(ntcSum / sampleCount));
}

/*
 * Conversion du potentiomètre en pH.
 *
 * Une vraie sonde pH délivre une tension autour de 0 V à pH 7, avec
 * environ -59 mV par unité de pH, et se calibre sur deux solutions
 * tampon. Rien de tout cela ici : le potentiomètre balaie simplement
 * l'échelle 0..14, position centrale = pH 7.
 *
 * Le jour où une vraie sonde remplace le potentiomètre, seule cette
 * fonction change — c'est la raison de l'isoler.
 */
float phFromRaw(int raw) {
  const float value = (float)raw * 14.0 / 4095.0;
  return roundf(value * 100.0) / 100.0;
}

/*
 * Thermistance NTC 10 kΩ, coefficient B = 3950 : la formule de
 * l'exemple officiel du composant Wokwi.
 *
 * Si la température évolue à l'envers du curseur, c'est que le
 * diviseur est câblé dans l'autre sens : remplacer
 * (4095/analog - 1) par (analog/(4095 - analog)).
 */
float celsiusFromRaw(int raw) {
  if (raw <= 0) raw = 1;
  if (raw >= 4095) raw = 4094;

  const float BETA = 3950.0;
  const float T0 = 298.15;   // 25 °C en kelvins
  const float ratio = 4095.0 / (float)raw - 1.0;
  const float kelvin = 1.0 / (log(ratio) / BETA + 1.0 / T0);
  const float celsius = kelvin - 273.15;

  return roundf(celsius * 10.0) / 10.0;
}

// ==================================================================
//  Pompe, chauffage, filtre
// ==================================================================

void applyPump(bool on) {
  pumpOn = on;
  digitalWrite(PIN_RELAY_PUMP, on ? HIGH : LOW);
  digitalWrite(PIN_LED_PUMP, on ? HIGH : LOW);

  // Le chauffage ne doit jamais tourner sans circulation d'eau :
  // l'échangeur se met en sécurité au mieux, se détruit au pire.
  if (!on && heaterOn) {
    applyHeater(false);
    Serial.println(F("Chauffage coupé : la pompe est à l'arrêt"));
  }
}

void handleHeaterCommand(const char *value) {
  if (strcmp(value, "auto") == 0) {
    heaterAuto = true;
    Serial.println(F("Chauffage en régulation automatique"));
    return;
  }
  heaterAuto = false;
  applyHeater(strcmp(value, "on") == 0);
}

void applyHeater(bool on) {
  // Verrou de sécurité, appliqué quel que soit l'appelant : commande
  // manuelle, régulation automatique ou mise en route.
  if (on && !pumpOn) {
    heaterOn = false;
    digitalWrite(PIN_RELAY_HEAT, LOW);
    digitalWrite(PIN_LED_HEAT, LOW);
    if (!heaterBlockedLogged) {
      Serial.println(F("Chauffage refusé : pas de filtration en marche"));
      heaterBlockedLogged = true;
    }
    return;
  }
  heaterBlockedLogged = false;
  heaterOn = on;
  digitalWrite(PIN_RELAY_HEAT, on ? HIGH : LOW);
  digitalWrite(PIN_LED_HEAT, on ? HIGH : LOW);
}

void updateHeater() {
  if (!heaterAuto) return;

  // Sans filtration, la régulation n'a rien à tenter : appeler
  // applyHeater(true) à chaque tour ne ferait que se heurter au
  // verrou, des dizaines de fois par seconde.
  if (!pumpOn) {
    if (heaterOn) applyHeater(false);
    return;
  }

  // Hystérésis : on chauffe sous consigne - 0,5 °C, on coupe au-dessus
  // de consigne + 0,5 °C. Entre les deux, on ne touche à rien.
  if (!heaterOn && waterTempC < heaterSetpointC - HEATER_HYSTERESIS_C) {
    applyHeater(true);
  } else if (heaterOn && waterTempC > heaterSetpointC + HEATER_HYSTERESIS_C) {
    applyHeater(false);
  }
}

void countPumpTime() {
  static unsigned long lastTick = 0;
  const unsigned long now = millis();
  const unsigned long delta = now - lastTick;
  lastTick = now;

  if (!pumpOn || delta > 5000) return;   // ignorer les sauts (reconnexion)

  pumpMinuteAccumulatorMs += delta;
  if (pumpMinuteAccumulatorMs < 60000UL) return;

  pumpMinuteAccumulatorMs -= 60000UL;
  pumpRunMinutes++;

  // Écriture espacée : la mémoire flash a un nombre de cycles limité.
  // Au pire, un redémarrage fait perdre moins d'une heure de compteur,
  // ce qui est sans conséquence pour une alerte de nettoyage.
  if (pumpRunMinutes - pumpPersistedMinutes >= PUMP_PERSIST_EVERY_MINUTES) {
    persistPumpCounter();
  }

  if (!filterAlert && pumpRunMinutes >= FILTER_ALERT_MINUTES) {
    filterAlert = true;
    persistPumpCounter();
    pendingFilterAlert = true;
    Serial.printf("ALERTE filtre : %lu min de pompe\n",
                  (unsigned long)pumpRunMinutes);
  }
}

void persistPumpCounter() {
  prefs.putUInt("pumpMin", pumpRunMinutes);
  pumpPersistedMinutes = pumpRunMinutes;
}

void resetFilterCounter() {
  pumpRunMinutes = 0;
  pumpMinuteAccumulatorMs = 0;
  filterAlert = false;
  persistPumpCounter();
  // Publication différée : cette fonction est appelée depuis le
  // callback MQTT.
  pendingFilterAlert = true;
  Serial.println(F("Compteur filtre remis à zéro"));
}

void publishFilterAlert() {
  if (!mqtt.connected()) return;
  mqtt.publish(topicAlertFilter, filterAlert ? "1" : "0", true);
}

// ==================================================================
//  Télémétrie
// ==================================================================

/*
 * Trame construite à la main plutôt qu'avec une bibliothèque JSON :
 * la structure est fixe et connue, et cela évite de dépendre d'une
 * bibliothèque dont l'API change entre versions majeures.
 *
 * Le tampon est dimensionné pour le pire cas (identifiant de 64
 * caractères, tous les nombres à leur largeur maximale) et le retour
 * de snprintf est vérifié : une trame tronquée serait un JSON invalide
 * que l'application rejetterait sans pouvoir dire pourquoi.
 */
void publishTelemetry() {
  if (!mqtt.connected()) return;

  char payload[320 + DEVICE_ID_MAX];
  const int written = snprintf(payload, sizeof(payload),
           "{"
           "\"deviceId\":\"%s\","
           "\"ph\":%.2f,"
           "\"phRaw\":%d,"
           "\"tempC\":%.1f,"
           "\"cover\":{\"position\":%.3f,\"motion\":\"%s\",\"estimated\":true},"
           "\"pump\":{\"on\":%s,\"runMinutes\":%lu},"
           "\"heater\":{\"on\":%s,\"auto\":%s,\"setpointC\":%.1f},"
           "\"filterAlert\":%s,"
           "\"uptimeS\":%lu"
           "}",
           DEVICE_ID,
           phValue,
           phRaw,
           waterTempC,
           coverPosition,
           coverMotionLabel(),
           pumpOn ? "true" : "false",
           (unsigned long)pumpRunMinutes,
           heaterOn ? "true" : "false",
           heaterAuto ? "true" : "false",
           heaterSetpointC,
           filterAlert ? "true" : "false",
           millis() / 1000UL);

  if (written < 0 || (size_t)written >= sizeof(payload)) {
    Serial.printf("Trame de télémétrie trop longue (%d octets), non publiée\n",
                  written);
    return;
  }

  // Retenu par le broker : une application qui se connecte reçoit
  // immédiatement le dernier état connu, sans attendre 2 s.
  // La rétention est réservée aux topics d'ÉTAT ; les topics de
  // commande ne doivent jamais être retenus (voir
  // clearRetainedCommands).
  mqtt.publish(topicTelemetry, payload, true);
}
