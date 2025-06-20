#include <ESP8266WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <Ticker.h>
#include <queue>
#include <WiFiManager.h>

// Configuración
const int SEND_INTERVAL_MS = 20;  // 50 Hz
const int MAX_QUEUE_SIZE = 50;    // Tamaño máximo de cola para evitar sobrecarga
bool shouldSaveConfig = false;
WebSocketsClient webSocket;
Ticker dataTicker;
std::queue<String> dataQueue;
volatile bool dataReady = false;
unsigned long lastSendTime = 0;

// Callbacks
void saveConfigCallback() { shouldSaveConfig = true; }

void generateData() {
  static String buffer;
  
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') {
      buffer.trim();
      
      int separador = buffer.indexOf(',');
      if (separador != -1) {
        int braquial = buffer.substring(0, separador).toInt();
        int tibial = buffer.substring(separador + 1).toInt();

        float vBraquial = (braquial / 1023.0) * 3.3;
        float vTibial = (tibial / 1023.0) * 3.3;

        StaticJsonDocument<128> doc;
        doc["t"] = millis();
        doc["braquial"] = vBraquial;
        doc["tibial"] = vTibial;

        String json;
        serializeJson(doc, json);

        if (dataQueue.size() < MAX_QUEUE_SIZE) {
          dataQueue.push(json);
          dataReady = true;
        }
      }
      buffer = "";
    } else {
      buffer += c;
    }
  }
}

void onWebSocketMessage(WStype_t type, uint8_t* payload, size_t length) {
  if (type == WStype_TEXT) {
    String msg = String((char*)payload);
    Serial.println("Mensaje recibido: " + msg);

    if (msg == "start") {
      Serial.println("Iniciando lectura desde Nano...");
      dataTicker.attach_ms(SEND_INTERVAL_MS, generateData);
      lastSendTime = millis();
    } 
    else if (msg == "stop") {
      Serial.println("Deteniendo lectura...");
      dataTicker.detach();
    }
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(1);  // Reducir timeout para lectura serial
  Serial.println("Iniciando ESP8266...");

  WiFiManager wifiManager;
  wifiManager.setSaveConfigCallback(saveConfigCallback);
  wifiManager.setConfigPortalTimeout(180);
  if (!wifiManager.autoConnect("Artemis_AP")) {
    Serial.println("Fallo al conectar, reiniciando...");
    delay(3000);
    ESP.reset();
    delay(5000);
  }

  Serial.println("Conectado. IP: " + WiFi.localIP().toString());

  webSocket.begin("172.20.10.6", 8765, "/ws/arduino");
  webSocket.setReconnectInterval(2000);
  webSocket.onEvent(onWebSocketMessage);
}

void loop() {
  webSocket.loop();

  // Enviar datos si hay conexión y ha pasado el intervalo
  if (dataReady && webSocket.isConnected() && (millis() - lastSendTime >= SEND_INTERVAL_MS)) {
    if (!dataQueue.empty()) {
      webSocket.sendTXT(dataQueue.front());
      dataQueue.pop();
      lastSendTime = millis();
    }
    
    if (dataQueue.empty()) {
      dataReady = false;
    }
  }

  // Limpieza si el socket está desconectado
  if (!webSocket.isConnected() && !dataQueue.empty()) {
    while (!dataQueue.empty()) dataQueue.pop();
    dataReady = false;
  }
}
