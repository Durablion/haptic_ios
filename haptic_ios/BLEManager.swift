import Foundation
import CoreBluetooth

// MARK: - Discovered device model

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID            // peripheral.identifier
    var name: String
    var rssi: Int
    var isConnected: Bool
}

// MARK: - BLEManager

final class BLEManager: NSObject, ObservableObject {

    // Service / characteristic UUIDs must match haptic_ble_tapp.ino on the ESP32
    static let serviceUUID        = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    static let characteristicUUID = CBUUID(string: "abcd1234-ab12-ab12-ab12-abcdef123456")
    static let preferredName      = "Haptics-ESP32"

    // Published state for the UI
    @Published var statusText: String = "Starting…"
    @Published var isConnected: Bool = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isDiscovering: Bool = false

    // Internal state
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var discoveryMap: [UUID: CBPeripheral] = [:]
    private var manuallyDisconnected = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func sendLeft()  { write(byte: 0x01) }
    func sendRight() { write(byte: 0x02) }

    /// Begin a wide scan that surfaces all named peripherals (for the scanner UI).
    func startDiscoveryScan() {
        guard central.state == .poweredOn else {
            statusText = "Bluetooth is not on"
            return
        }
        central.stopScan()
        discoveredDevices.removeAll()
        discoveryMap.removeAll()
        isDiscovering = true
        statusText = "Scanning…"
        central.scanForPeripherals(withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopDiscoveryScan() {
        guard isDiscovering else { return }
        isDiscovering = false
        central.stopScan()
        if !isConnected { statusText = "Idle" }
    }

    /// Connect to a specific peripheral chosen from the scanner list.
    func connect(to id: UUID) {
        guard let target = discoveryMap[id] else { return }
        stopDiscoveryScan()
        manuallyDisconnected = false
        if let existing = peripheral { central.cancelPeripheralConnection(existing) }
        peripheral = target
        target.delegate = self
        statusText = "Connecting to \(target.name ?? "device")…"
        central.connect(target)
    }

    func disconnect() {
        manuallyDisconnected = true
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    // MARK: - Internals

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

    private func startAutoScan() {
        guard central.state == .poweredOn else { return }
        statusText = "Searching for \(Self.preferredName)…"
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:    startAutoScan()
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

        // Discovery scan: surface every named device for the scanner UI.
        if isDiscovering {
            let id = peripheral.identifier
            let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = advName ?? peripheral.name ?? ""
            guard !name.isEmpty else { return }
            discoveryMap[id] = peripheral
            let rssi = RSSI.intValue
            let connected = isConnected && self.peripheral?.identifier == id
            if let idx = discoveredDevices.firstIndex(where: { $0.id == id }) {
                discoveredDevices[idx].rssi = rssi
                discoveredDevices[idx].name = name
                discoveredDevices[idx].isConnected = connected
            } else {
                discoveredDevices.append(
                    DiscoveredDevice(id: id, name: name, rssi: rssi, isConnected: connected)
                )
            }
            // Connected first, then strongest signal
            discoveredDevices.sort { lhs, rhs in
                if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
                return lhs.rssi > rhs.rssi
            }
            return
        }

        // Auto-scan: connect to the first matching ESP32.
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
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        isConnected = false
        statusText = "Failed to connect"
        startAutoScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        writeChar = nil
        if manuallyDisconnected {
            statusText = "Disconnected"
            manuallyDisconnected = false
        } else {
            statusText = "Disconnected — searching…"
            startAutoScan()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            statusText = "Service \(Self.serviceUUID) not found on this device"
            return
        }
        var found = false
        for svc in services where svc.uuid == Self.serviceUUID {
            found = true
            peripheral.discoverCharacteristics([Self.characteristicUUID], for: svc)
        }
        if !found {
            statusText = "Selected device has no haptic service"
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == Self.characteristicUUID {
            writeChar = c
            isConnected = true
            statusText = "Connected to \(peripheral.name ?? Self.preferredName)"
        }
    }
}
