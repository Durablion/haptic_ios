import Foundation
import CoreBluetooth

final class BLEManager: NSObject, ObservableObject {
    // UUIDs must match haptic_ble_tapp.ino on the ESP32
    static let serviceUUID        = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    static let characteristicUUID = CBUUID(string: "abcd1234-ab12-ab12-ab12-abcdef123456")

    @Published var statusText: String = "Starting…"
    @Published var isConnected: Bool = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func sendLeft()  { write(byte: 0x01) }
    func sendRight() { write(byte: 0x02) }

    private func write(byte: UInt8) {
        guard let peripheral = peripheral, let ch = writeChar else {
            statusText = "Not connected"
            return
        }
        var b = byte
        let data = Data(bytes: &b, count: 1)
        let type: CBCharacteristicWriteType =
            ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: ch, type: type)
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusText = "Searching for Haptics-ESP32…"
            central.scanForPeripherals(withServices: [Self.serviceUUID])
        case .poweredOff:   statusText = "Bluetooth is off"
        case .unauthorized: statusText = "Bluetooth permission denied"
        case .unsupported:  statusText = "BLE not supported"
        default:            statusText = "Bluetooth: \(central.state.rawValue)"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        statusText = "Connecting…"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusText = "Discovering services…"
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        writeChar = nil
        statusText = "Disconnected — searching…"
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for svc in services where svc.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.characteristicUUID], for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == Self.characteristicUUID {
            writeChar = c
            isConnected = true
            statusText = "Connected to \(peripheral.name ?? "Haptics-ESP32")"
        }
    }
}
