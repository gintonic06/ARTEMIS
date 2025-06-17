#include <ESP8266WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <Ticker.h>
#include <queue>
#include <WiFiManager.h>

// ---------- Configuración ----------
const int   SEND_INTERVAL_MS      = 20;        // 50 Hz
bool                shouldSaveConfig = false;
WebSocketsClient    webSocket;
Ticker              dataTicker;
std::queue<String>  dataQueue;
volatile bool       dataReady = false;

// ---------- Callbacks ----------
void saveConfigCallback() { shouldSaveConfig = true; }

// Lee del Nano por Serial y genera JSON
void generateData() {
  if (!Serial.available()) return;

  String raw = Serial.readStringUntil('\n');
  raw.trim();

  // Esperamos línea tipo "512,623"
  int separador = raw.indexOf(',');
  if (separador == -1) return;

  int braquial = raw.substring(0, separador).toInt();
  int tibial   = raw.substring(separador + 1).toInt();

  float vBraquial = (braquial / 1023.0) * 3.3;
  float vTibial   = (tibial   / 1023.0) * 3.3;

  StaticJsonDocument<128> doc;
  doc["t"] = millis();
  doc["braquial"] = vBraquial;
  doc["tibial"] = vTibial;

  String json;
  serializeJson(doc, json);

  dataQueue.push(json);
  dataReady = true;
}

void onWebSocketMessage(WStype_t type, uint8_t * payload, size_t length) {
  if (type == WStype_TEXT) {
    String msg = String((char*)payload);
    Serial.println("Mensaje recibido: " + msg);

    if (msg == "start") {
      Serial.println("Iniciando lectura desde Nano...");
      dataTicker.attach_ms(SEND_INTERVAL_MS, generateData);
    } 
    else if (msg == "stop") {
      Serial.println("Deteniendo lectura...");
      dataTicker.detach();
    }
  }
}

// ---------- Setup ----------
void setup() {
  Serial.begin(115200); // Serial con el Nano
  Serial.println("Iniciando ESP8266...");

  WiFiManager wifiManager;
  wifiManager.setSaveConfigCallback(saveConfigCallback);
  wifiManager.setConfigPortalTimeout(180);
  if (!wifiManager.autoConnect("Artemis_AP")) {
    Serial.println("Fallo al conectar, reiniciando…");
    delay(3000);
    ESP.reset();
    delay(5000);
  }

  Serial.println("Conectado. IP: " + WiFi.localIP().toString());

  webSocket.begin("172.20.10.6", 8765, "/ws/arduino"); // Cambia la IP si es necesario
  webSocket.setReconnectInterval(2000);
  webSocket.onEvent(onWebSocketMessage);
}

// ---------- Loop principal ----------
void loop() {
  webSocket.loop();

  // Enviar datos si hay conexión
  if (dataReady && webSocket.isConnected()) {
    static unsigned long lastSend = 0;

    while (!dataQueue.empty()) {
      webSocket.sendTXT(dataQueue.front());
      dataQueue.pop();
      while (millis() - lastSend < 5) delay(1);
      lastSend = millis();
    }
    dataReady = false;
  }

  // Limpieza si el socket está desconectado
  static unsigned long lastClean = millis();
  if (!webSocket.isConnected() && millis() - lastClean > 1000) {
    while (!dataQueue.empty()) dataQueue.pop();
    lastClean = millis();
  }
}

