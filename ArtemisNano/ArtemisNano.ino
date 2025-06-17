void setup() {
  Serial.begin(115200);  // Velocidad serial para comunicarse con el ESP8266
}

void loop() {
  int braquial = analogRead(A0);
  int tibial   = analogRead(A1);

  // Enviar los datos separados por coma y con salto de línea
  Serial.print(braquial);
  Serial.print(",");
  Serial.println(tibial);

  delay(20);  // 50 Hz
}
