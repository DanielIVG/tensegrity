/*
  Balanza con celda de carga de 10 kg + HX711 + servidor HTTP
  Placas: ESP8266 (NodeMCU / Wemos D1) o ESP32
  Libreria: "HX711 Arduino Library" de Bogdan Necula

  Tambien lee un sensor de humedad de suelo YL-38 (salida analogica) y
  muestra la humedad en porcentaje junto al peso.

  Muestra por el monitor serie el valor CRUDO (cuentas del HX711) y su
  conversion a gramos. El peso es APROXIMADO: la celda tiene ruido y deriva,
  asi que el valor se filtra (mediana + promedio movil), se redondea y se
  informa el ruido estimado.

  Servidor (puerto 80):
    GET /data  -> JSON con crudo, filtrado, gramos, kg y ruido
    GET /tare  -> pone la balanza en cero (con la balanza VACIA)

  Calibracion (con tus mediciones):
    sin peso : promedio -298 496 cuentas
    con 1 kg : promedio  -97 693 cuentas
    diferencia = 200 802 cuentas por 1000 g  ->  ~201 cuentas/gramo
*/

#include "HX711.h"

#if defined(ESP32)
  #include <WiFi.h>
  #include <WebServer.h>
  WebServer servidor(80);
#elif defined(ESP8266)
  #include <ESP8266WiFi.h>
  #include <ESP8266WebServer.h>
  ESP8266WebServer servidor(80);
#else
  #error "Se necesita una placa con WiFi: ESP8266 o ESP32"
#endif

// ---------------- Configuracion ----------------
const char* WIFI_SSID = "";      // <-- CAMBIAR
const char* WIFI_PASS = "TU_CLAVE_WIFI";    // <-- CAMBIAR

// Si no logra conectarse al WiFi, crea su propia red (IP 192.168.4.1)
const char* AP_SSID = "Tensegridad-Balanza";
const char* AP_PASS = "12345678";

const int PIN_DOUT = 4;   // DT del HX711
const int PIN_SCK  = 5;   // SCK del HX711

// Sensor de humedad de suelo YL-38 (pin AO a la entrada analogica)
#if defined(ESP32)
const int PIN_HUMEDAD = 34;   // ESP32: ADC de 12 bits -> hay que recalibrar los valores
#else
const int PIN_HUMEDAD = A0;   // ESP8266: ADC de 10 bits (0-1023)
#endif
const int VALOR_SECO   = 1024;  // lectura en seco (calibracion medida)
const int VALOR_MOJADO = 495;   // lectura en mojado (calibracion medida)

const float CUENTAS_POR_GRAMO = 201.0f;  // calibracion (ver arriba)
const float CAPACIDAD_G       = 10000.0f; // celda de 10 kg
const float ZONA_MUERTA_G     = 3.0f;    // |peso| menor a esto se muestra como 0
const float PASO_G            = 5.0f;    // el peso se redondea a multiplos de 5 g
const float ALFA              = 0.15f;   // filtro: menor = mas suave y mas lento
// ------------------------------------------------

const int N_MEDIANA = 5;
const int N_RUIDO   = 20;

HX711 celda;

long   ventana[N_MEDIANA];
int    nVentana = 0;
float  filtrado = 0;
bool   hayFiltrado = false;
long   crudo = 0;
double offset = 0;

long   histRuido[N_RUIDO];
int    nRuido = 0, idxRuido = 0;

int humedadCruda = 0;
int humedadPct   = 0;

unsigned long tUltimoSerial = 0;
unsigned long tUltimaHumedad = 0;

long medianaVentana() {
  long a[N_MEDIANA];
  for (int i = 0; i < nVentana; i++) a[i] = ventana[i];
  for (int i = 1; i < nVentana; i++) {          // ordenamiento por insercion
    long v = a[i]; int j = i - 1;
    while (j >= 0 && a[j] > v) { a[j + 1] = a[j]; j--; }
    a[j + 1] = v;
  }
  return a[nVentana / 2];
}

void reiniciarFiltros() {
  nVentana = 0; nRuido = 0; idxRuido = 0; hayFiltrado = false;
}

void leerSensor() {
  if (!celda.is_ready()) return;          // el HX711 entrega ~10 lecturas/s
  crudo = celda.read();

  // 1) mediana de las ultimas 5 lecturas (quita picos)
  if (nVentana < N_MEDIANA) {
    ventana[nVentana++] = crudo;
  } else {
    for (int i = 1; i < N_MEDIANA; i++) ventana[i - 1] = ventana[i];
    ventana[N_MEDIANA - 1] = crudo;
  }
  long med = medianaVentana();

  // 2) promedio movil exponencial (suaviza el ruido)
  if (!hayFiltrado) { filtrado = med; hayFiltrado = true; }
  else              { filtrado += ALFA * (med - filtrado); }

  // 3) historial para estimar el ruido
  histRuido[idxRuido] = crudo;
  idxRuido = (idxRuido + 1) % N_RUIDO;
  if (nRuido < N_RUIDO) nRuido++;
}

float gramosSinRedondear() {
  return (float)((filtrado - offset) / CUENTAS_POR_GRAMO);
}

float gramosMostrados() {
  float g = gramosSinRedondear();
  if (fabsf(g) < ZONA_MUERTA_G) return 0.0f;
  return roundf(g / PASO_G) * PASO_G;
}

// Humedad del suelo: promedio de 8 lecturas y conversion a porcentaje
void leerHumedad() {
  long suma = 0;
  for (int i = 0; i < 8; i++) { suma += analogRead(PIN_HUMEDAD); delay(2); }
  humedadCruda = suma / 8;
  humedadPct = constrain(map(humedadCruda, VALOR_SECO, VALOR_MOJADO, 0, 100), 0, 100);
}

// Desviacion estandar de las ultimas lecturas, en gramos
float ruidoGramos() {
  if (nRuido < 5) return 0.0f;
  double suma = 0;
  for (int i = 0; i < nRuido; i++) suma += histRuido[i];
  double media = suma / nRuido, var = 0;
  for (int i = 0; i < nRuido; i++) { double d = histRuido[i] - media; var += d * d; }
  return (float)(sqrt(var / nRuido) / CUENTAS_POR_GRAMO);
}

// Pone el cero con la balanza vacia: promedio de 20 lecturas
void tararBalanza() {
  double suma = 0; int n = 0;
  unsigned long t0 = millis();
  while (n < 20 && millis() - t0 < 5000) {
    if (celda.is_ready()) { suma += celda.read(); n++; }
    delay(1);
  }
  if (n > 0) {
    offset = suma / n;
    reiniciarFiltros();
    Serial.print("Tara hecha. Cero (crudo) = ");
    Serial.println((long)offset);
  } else {
    Serial.println("Tara fallida: el HX711 no responde");
  }
}

void enviarDatos() {
  float g = gramosMostrados();
  char buf[400];
  snprintf(buf, sizeof(buf),
    "{\"raw\":%ld,\"raw_filtrado\":%ld,\"offset\":%ld,\"gramos\":%.1f,"
    "\"kg\":%.3f,\"ruido_g\":%.1f,\"sobrecarga\":%s,\"aproximado\":true,"
    "\"humedad_raw\":%d,\"humedad_pct\":%d}",
    crudo, (long)filtrado, (long)offset, g, g / 1000.0f, ruidoGramos(),
    (gramosSinRedondear() > CAPACIDAD_G) ? "true" : "false",
    humedadCruda, humedadPct);
  servidor.sendHeader("Cache-Control", "no-cache");
  servidor.send(200, "application/json", buf);
}

void conectarWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Conectando a WiFi");
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) {
    delay(500); Serial.print(".");
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("IP de la balanza: ");
    Serial.println(WiFi.localIP());
  } else {
    WiFi.mode(WIFI_AP);
    WiFi.softAP(AP_SSID, AP_PASS);
    Serial.print("Sin WiFi. Red propia '");
    Serial.print(AP_SSID);
    Serial.print("'. IP de la balanza: ");
    Serial.println(WiFi.softAPIP());
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\nBalanza HX711 - celda de 10 kg");

  celda.begin(PIN_DOUT, PIN_SCK);

  conectarWiFi();

  servidor.on("/data", enviarDatos);
  servidor.on("/tare", []() {
    tararBalanza();
    servidor.send(200, "text/plain", "ok");
  });
  servidor.on("/", []() {
    servidor.send(200, "text/plain", "Balanza HX711. Usa /data o /tare");
  });
  servidor.begin();

  leerHumedad();
  Serial.println("Dejando la balanza VACIA para la tara...");
  delay(1500);
  tararBalanza();
}

void loop() {
  servidor.handleClient();
  leerSensor();

  // La humedad cambia lento: se lee cada 2 s
  if (millis() - tUltimaHumedad >= 2000) {
    tUltimaHumedad = millis();
    leerHumedad();
  }

  if (millis() - tUltimoSerial >= 500) {
    tUltimoSerial = millis();
    Serial.print("Crudo: ");
    Serial.print(crudo);
    Serial.print(" | Filtrado: ");
    Serial.print((long)filtrado);
    Serial.print(" | Peso aprox.: ");
    Serial.print(gramosMostrados(), 0);
    Serial.print(" g (+/- ");
    Serial.print(ruidoGramos(), 1);
    Serial.print(" g de ruido) | Humedad tierra: ");
    Serial.print(humedadPct);
    Serial.print("% (crudo ");
    Serial.print(humedadCruda);
    Serial.println(")");
    if (gramosSinRedondear() > CAPACIDAD_G) Serial.println("AVISO: sobrecarga de la celda (> 10 kg)");
  }
}
