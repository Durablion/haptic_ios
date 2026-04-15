/*
 * RTK-GNSS Bridge + Dual Haptics — ESP32-S3-N16R8
 * 
 * Kombinerer:
 *  1) NMEA-bridge fra LG290P → BLE (Nordic UART Service)
 *  2) Haptikk-kontroll av to DRV2605 via BLE
 *
 * Pin-plan:
 *   UART2 RX (LG290P TXD2) = GPIO 18
 *   UART2 TX (LG290P RXD2) = GPIO 17
 *   Wire  (I2C0): SDA=8,  SCL=9   → venstre DRV2605
 *   Wire1 (I2C1): SDA=38, SCL=39  → høyre DRV2605
 *
 * BLE Services:
 *   NUS  6E400001-... → NMEA TX (notify) + RTCM RX (write)
 *   HAP  12345678-... → Haptics kommando (write)
 */

#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "Adafruit_DRV2605.h"

// ──────────────── Maskinvare-pinner ────────────────
static constexpr int UART2_RX_PIN = 18;
static constexpr int UART2_TX_PIN = 17;
static constexpr long UART2_BAUD  = 460800;

static constexpr int SDA0_PIN = 8;   // Wire  — venstre DRV
static constexpr int SCL0_PIN = 9;
static constexpr int SDA1_PIN = 38;  // Wire1 — høyre DRV
static constexpr int SCL1_PIN = 39;

// ──────────────── BLE UUIDs ────────────────
// Nordic UART Service (NUS) — NMEA/RTCM
#define NUS_SERVICE_UUID    "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_TX_UUID         "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // Notify: NMEA → mobil
#define NUS_RX_UUID         "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // Write:  RTCM ← mobil

// Haptics Service
#define HAP_SERVICE_UUID    "12345678-1234-1234-1234-123456789abc"
#define HAP_CHAR_UUID       "abcd1234-ab12-ab12-ab12-abcdef123456"  // Write: kommandoer

// ──────────────── Globale objekter ────────────────
Adafruit_DRV2605 drvLeft;
Adafruit_DRV2605 drvRight;

BLECharacteristic *pNusTxChar = nullptr;
bool deviceConnected = false;

char nmeaLine[256];
size_t nmeaLen = 0;

// ──────────────── Haptikk-repetisjon (asynkron) ────────────────
struct HapRepeat {
  uint8_t  motor;         // 0=idle, 0x01=L, 0x02=R, 0x03=begge
  uint8_t  effect;        // DRV2605 effekt-nummer
  uint8_t  remaining;     // gjenværende repetisjoner
  uint16_t intervalMs;    // ms mellom hver puls
  unsigned long nextFire; // millis()-tidspunkt for neste puls
};

static HapRepeat hapState = {0, 0, 0, 0, 0};

// Trigger én haptisk puls på valgte motor(er)
void fireHaptic(uint8_t motor, uint8_t effect) {
  if (motor & 0x01) {
    drvLeft.setWaveform(0, effect);
    drvLeft.setWaveform(1, 0);
    drvLeft.go();
  }
  if (motor & 0x02) {
    drvRight.setWaveform(0, effect);
    drvRight.setWaveform(1, 0);
    drvRight.go();
  }
}

// ──────────────── BLE Callbacks ────────────────

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    Serial.println(">>> Mobil tilkoblet via BLE!");
  }
  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    Serial.println(">>> Mobil frakoblet — annonserer på nytt...");
    delay(100);
    pServer->getAdvertising()->start();
  }
};

// RTCM-data fra mobil → LG290P
class NusRxCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String val = pChar->getValue();
    if (val.length() > 0) {
      Serial2.write((uint8_t*)val.c_str(), val.length());
    }
  }
};

// Haptikk-kommandoer fra mobil
//   Byte 0: motor  — 0x01=venstre, 0x02=høyre, 0x03=begge
//   Byte 1: effekt — DRV2605 effekt 1–123 (default 1 = Strong Click)
//   Byte 2: antall — repetisjoner (default 1 = én enkelt puls)
//   Byte 3: intervall — pause mellom pulser i ×10 ms (default 10 = 100 ms)
class HapticsCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String val = pChar->getValue();
    if (val.length() < 1) return;

    uint8_t motor    = val[0];
    uint8_t effect   = (val.length() > 1) ? val[1] : 1;
    uint8_t count    = (val.length() > 2) ? val[2] : 1;
    uint8_t intv10ms = (val.length() > 3) ? val[3] : 10;

    if (count == 0) count = 1;
    if (motor < 0x01 || motor > 0x03) return;

    // Fyr av første puls umiddelbart
    fireHaptic(motor, effect);
    Serial.printf("HAP: motor=0x%02X effekt=%d count=%d intervall=%dms\n",
                  motor, effect, count, intv10ms * 10);

    // Hvis flere repetisjoner, sett opp asynkron tilstand
    if (count > 1) {
      hapState.motor      = motor;
      hapState.effect     = effect;
      hapState.remaining  = count - 1;  // første er allerede fyrt
      hapState.intervalMs = (uint16_t)intv10ms * 10;
      hapState.nextFire   = millis() + hapState.intervalMs;
    }
  }
};

// ──────────────── Setup ────────────────

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== RTK-Bridge + Haptics (ESP32-S3) ===");

  // ── UART mot LG290P ──
  Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX_PIN, UART2_TX_PIN);

  delay(2000);  // Vent på LG290P boot
  Serial.println("Konfigurerer LG290P...");
  Serial2.print("$PQTMCFGMSGRATE,W,GST,1*0B\r\n");
  delay(200);
  Serial2.print("$PQTMSAVEPAR*5A\r\n");
  delay(200);
  Serial.println("LG290P konfigurasjon fullført.");

  // ── I2C + DRV2605 ──
  Wire.begin(SDA0_PIN, SCL0_PIN);
  if (!drvLeft.begin(&Wire)) {
    Serial.println("FEIL: DRV2605 venstre (Wire) ikke funnet!");
    // Fortsetter uten — appen virker fremdeles for NMEA
  } else {
    drvLeft.selectLibrary(1);
    drvLeft.setMode(DRV2605_MODE_INTTRIG);
    Serial.println("DRV2605 venstre OK");
  }

  Wire1.begin(SDA1_PIN, SCL1_PIN);
  if (!drvRight.begin(&Wire1)) {
    Serial.println("FEIL: DRV2605 høyre (Wire1) ikke funnet!");
  } else {
    drvRight.selectLibrary(1);
    drvRight.setMode(DRV2605_MODE_INTTRIG);
    Serial.println("DRV2605 høyre OK");
  }

  // ── BLE ──
  BLEDevice::init("TellTrack RTK");
  BLEDevice::setMTU(517);

  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // --- NUS (NMEA/RTCM) Service ---
  BLEService *pNusService = pServer->createService(NUS_SERVICE_UUID);

  pNusTxChar = pNusService->createCharacteristic(
    NUS_TX_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pNusTxChar->addDescriptor(new BLE2902());

  BLECharacteristic *pNusRxChar = pNusService->createCharacteristic(
    NUS_RX_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pNusRxChar->setCallbacks(new NusRxCallback());

  pNusService->start();

  // --- Haptics Service ---
  BLEService *pHapService = pServer->createService(HAP_SERVICE_UUID);

  BLECharacteristic *pHapChar = pHapService->createCharacteristic(
    HAP_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pHapChar->setCallbacks(new HapticsCallback());
  pHapChar->addDescriptor(new BLE2902());

  pHapService->start();

  // --- Annonsering ---
  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(NUS_SERVICE_UUID);
  pAdv->addServiceUUID(HAP_SERVICE_UUID);
  pAdv->setScanResponse(true);

  BLEDevice::startAdvertising();
  Serial.println("BLE klar — venter på tilkobling...");
}

// ──────────────── Loop ────────────────

void loop() {
  // Les NMEA fra LG290P og videresend relevante setninger over BLE
  while (Serial2.available()) {
    char c = (char)Serial2.read();

    if (c == '$') nmeaLen = 0;  // Ny setning

    if (nmeaLen < sizeof(nmeaLine) - 1) {
      nmeaLine[nmeaLen++] = c;

      if (c == '\n') {
        nmeaLine[nmeaLen] = '\0';

        // Filtrer: send kun relevante NMEA-typer
        if (strstr(nmeaLine, "GGA") ||
            strstr(nmeaLine, "GST") ||
            strstr(nmeaLine, "GSA") ||
            strstr(nmeaLine, "GSV") ||
            strstr(nmeaLine, "RMC")) {

          if (deviceConnected) {
            pNusTxChar->setValue((uint8_t*)nmeaLine, (size_t)nmeaLen);
            pNusTxChar->notify();
          }
        }
        nmeaLen = 0;
      }
    } else {
      nmeaLen = 0;  // Overflow-beskyttelse
    }
  }

  // ── Haptikk-repetisjon (asynkron) ──
  if (hapState.remaining > 0 && millis() >= hapState.nextFire) {
    fireHaptic(hapState.motor, hapState.effect);
    hapState.remaining--;
    hapState.nextFire = millis() + hapState.intervalMs;
    if (hapState.remaining == 0) {
      Serial.println("HAP: sekvens ferdig");
    }
  }
}
