# TellTrack RTK — Funksjonell spesifikasjon

## ESP32-S3 firmware: RTK-GNSS Bridge + Dual Haptics

**Versjon:** 0.1 (utkast)
**Dato:** 2026-04-15
**Maskinvare:** ESP32-S3-N16R8 DevKitC, Quectel LG290P, 2× DRV2605L

---

## 1. Formål

Firmwaren kombinerer to funksjoner på én ESP32-S3:

1. **RTK-GNSS bridge** — mottar NMEA-data fra en Quectel LG290P GNSS-mottaker over UART og videresender utvalgte setninger til en mobilapp via BLE. Mobilappen kan sende RTCM-korreksjonsdata tilbake.
2. **Haptisk feedback** — styrer to DRV2605L haptikk-drivere (venstre/høyre) basert på kommandoer mottatt fra mobilappen over BLE.

Sammen utgjør dette kjerneenheten i TellTrack: en GPS-brikke med retningsfeedback via vibrasjon, designet for sti-navigasjon.

---

## 2. Systemarkitektur

```
┌─────────────┐    UART 460800     ┌──────────────┐     BLE (NUS)      ┌────────────┐
│  Quectel    │  ────────────────▶  │              │  ────────────────▶  │            │
│  LG290P     │    NMEA-setninger   │  ESP32-S3    │    NMEA (notify)    │  Mobilapp  │
│  (RTK-GNSS) │  ◀────────────────  │  N16R8       │  ◀────────────────  │  (iOS)     │
│             │    RTCM-korreksjon  │              │    RTCM (write)     │            │
└─────────────┘                     │              │                     │            │
                                    │              │  ◀────────────────  │            │
                                    │              │    Haptikk (write)  │            │
                                    └──────┬───────┘     BLE (HAP)      └────────────┘
                                           │
                              I2C0 ────────┼──────── I2C1
                                           │
                                    ┌──────┴───────┐
                                    │              │
                              ┌─────┴─────┐  ┌────┴──────┐
                              │ DRV2605L  │  │ DRV2605L  │
                              │ (venstre) │  │ (høyre)   │
                              └─────┬─────┘  └─────┬─────┘
                                    │              │
                              ┌─────┴─────┐  ┌────┴──────┐
                              │  Motor L  │  │  Motor R  │
                              └───────────┘  └───────────┘
```

---

## 3. Maskinvare

### 3.1 Pin-allokering

| Funksjon | GPIO | Retning | Merknad |
|---|---|---|---|
| UART2 RX (LG290P TXD2) | 18 | Inn | 460800 baud, 8N1 |
| UART2 TX (LG290P RXD2) | 17 | Ut | 460800 baud, 8N1 |
| I2C0 SDA (Wire) | 8 | I/O | Venstre DRV2605L (adr. 0x5A) |
| I2C0 SCL (Wire) | 9 | I/O | Venstre DRV2605L |
| I2C1 SDA (Wire1) | 38 | I/O | Høyre DRV2605L (adr. 0x5A) |
| I2C1 SCL (Wire1) | 39 | I/O | Høyre DRV2605L |

### 3.2 Strøm

| Komponent | Typisk forbruk |
|---|---|
| ESP32-S3 (BLE aktiv) | ~100 mA |
| LG290P (RTK) | ~200 mA |
| DRV2605L × 2 (idle) | ~2 mA |
| DRV2605L (aktiv puls) | ~300 mA peak per motor |

Anbefalt forsyning: 5V / 1A minimum via USB-C.

---

## 4. BLE-grensesnitt

Enheten annonserer seg som **"TellTrack RTK"** med to BLE-services.

### 4.1 Nordic UART Service (NUS) — NMEA/RTCM

| Egenskap | Verdi |
|---|---|
| Service UUID | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX Characteristic | `6E400003-...` — Notify |
| RX Characteristic | `6E400002-...` — Write |
| MTU | 517 byte (forhandlet) |

**TX (ESP → mobil):** Filtrerte NMEA-setninger sendes som hele linjer (inkl. `\r\n`), én setning per notify. Setningstyper som videresendes:

| NMEA-type | Innhold | Bruk i appen |
|---|---|---|
| GGA | Posisjon, fix-kvalitet, antall satellitter, HDOP | Primær posisjonsdata |
| GST | Feilestimater (σ lat, σ lon, σ alt) | Nøyaktighetsvisning, RTK-kvalitet |
| RMC | Posisjon, hastighet, kurs, dato | Kurs og hastighet |
| GSA | DOP-verdier, aktive satellitter | Satellittstatus |
| GSV | Satellitter i synsfeltet | Himmelkart-visning |

**RX (mobil → ESP):** Binære RTCM3-rammer fra en NTRIP-klient i appen. Videresendes uendret til LG290P via UART.

### 4.2 Haptics Service (HAP)

| Egenskap | Verdi |
|---|---|
| Service UUID | `12345678-1234-1234-1234-123456789abc` |
| Characteristic | `abcd1234-ab12-ab12-ab12-abcdef123456` — Write |

**Kommandoformat (1–4 byte, bakover-kompatibelt):**

| Byte | Innhold | Obligatorisk | Default |
|---|---|---|---|
| 0 | Mål-motor (se tabell under) | Ja | — |
| 1 | DRV2605 effekt-nummer (1–123) | Nei | 1 (Strong Click) |
| 2 | Antall repetisjoner (1–255) | Nei | 1 (én enkelt puls) |
| 3 | Intervall mellom pulser, i ×10 ms (1–255 → 10–2550 ms) | Nei | 10 (= 100 ms) |

En kommando på kun 1 byte (f.eks. `[0x01]`) fungerer identisk med v0.1 — én Strong Click på venstre motor.

**Eksempler:**

| Byte-sekvens | Resultat |
|---|---|
| `[0x01]` | Venstre: 1× Strong Click |
| `[0x02, 7]` | Høyre: 1× Soft Bump |
| `[0x03, 1, 3, 15]` | Begge: 3× Strong Click, 150 ms mellom |
| `[0x01, 52, 5, 8]` | Venstre: 5× Pulsing Strong, 80 ms mellom |

**Oppførsel ved repetisjon:** Første puls fyres umiddelbart. Gjenværende pulser kjøres asynkront i firmware-loopen med `millis()`-basert timing, slik at NMEA-bridgen ikke blokkeres. En ny kommando avbryter en pågående sekvens.

**Mål-motor (byte 0):**

| Verdi | Effekt |
|---|---|
| `0x01` | Venstre motor |
| `0x02` | Høyre motor |
| `0x03` | Begge motorer samtidig |

**DRV2605 effekt-eksempler (byte 1):**

| Verdi | Navn | Egnet for |
|---|---|---|
| 1 | Strong Click 100% | Sving-varsling |
| 7 | Soft Bump 100% | Bekreftelse |
| 14 | Strong Buzz 100% | Feil / advarsel |
| 47 | Buzz 1 – 100% | Kontinuerlig blizzard-modus |
| 52 | Pulsing Strong 1 | Avviks-alarm |

---

## 5. GNSS-konfigurasjon

Ved oppstart sender firmwaren følgende kommandoer til LG290P:

| Kommando | Effekt |
|---|---|
| `$PQTMCFGMSGRATE,W,GST,1*0B` | Aktiverer GST-utdata (feilestimater) |
| `$PQTMSAVEPAR*5A` | Lagrer innstillinger permanent i flash |

Øvrig konfigurasjon (konstellasjoner, oppdateringsfrekvens, RTCM-input) forutsettes gjort på forhånd eller via appen.

---

## 6. Feilhåndtering

| Situasjon | Oppførsel |
|---|---|
| DRV2605L ikke funnet ved oppstart | Logger feilmelding til Serial. NMEA-bridge og BLE fungerer normalt. |
| BLE-frakobling | Annonsering restartes automatisk etter 100 ms. |
| NMEA-buffer overflow (>255 tegn) | Bufferen nullstilles, ufullstendig setning forkastes. |
| LG290P ikke koblet til | Ingen NMEA-data sendes. BLE og haptikk fungerer uavhengig. |

---

## 7. Begrensninger og kjente forutsetninger

- **Én BLE-klient om gangen.** ESP32 BLE-stakken støtter flere tilkoblinger, men firmwaren bruker en enkel `deviceConnected`-flagg og er ikke testet med flere klienter.
- **Ingen NMEA-sjekksum-validering.** Setninger videresendes som de er. Validering gjøres i mobilappen.
- **Ingen flyt-kontroll på UART.** Ved 460800 baud og mange konstellasjoner kan det teoretisk oppstå tap. Overvåk `Serial2.available()` ved debugging.
- **BLE-throughput.** Ved 10 Hz oppdatering med 5 NMEA-typer (~500 byte/sekund) er BLE-kapasiteten tilstrekkelig, men nær grensen ved mange GSV-setninger.
- **Haptikk-sekvens er preemptiv.** En ny haptikk-kommando avbryter en pågående repetisjon. Kun én sekvens kan kjøre om gangen.

---

## 8. Fremtidige utvidelser

- **Batteristatus-service** — egen BLE-characteristic for batterinivå (standard Battery Service UUID `0x180F`).
- **OTA-oppdatering** — ESP32-S3 støtter BLE OTA; kan legges til som egen service.
- **NTRIP-klient på ESP32** — flytte NTRIP-tilkoblingen fra mobilappen til ESP32 via WiFi, slik at enheten er selvforsynt med korreksjon.
- **Effektkjeder** — støtte for flere waveform-steg i én kommando (DRV2605 støtter opptil 8 sekvensielle effekter).
