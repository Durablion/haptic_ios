import Foundation
import CoreBluetooth

// MARK: - Discovered device model

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID            // peripheral.identifier
    var name: String
    var rssi: Int
    var isConnected: Bool
}

// MARK: - Side selector

enum HapticSide: UInt8, CaseIterable, Identifiable {
    case left  = 0x01
    case right = 0x02
    case both  = 0x03

    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .left:  return "L"
        case .right: return "R"
        case .both:  return "Both"
        }
    }
}

// MARK: - BLEManager

final class BLEManager: NSObject, ObservableObject {

    /// Matches both haptic_ble_tapp.ino and rtk_haptics_bridge_v2.ino.
    static let hapticServiceUUID        = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    static let hapticCharacteristicUUID = CBUUID(string: "abcd1234-ab12-ab12-ab12-abcdef123456")

    // Published state for the UI
    @Published var statusText: String = "Tap the antenna icon to scan"
    @Published var isConnected: Bool = false
    @Published var connectedName: String = ""
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

    /// Send a haptic command to the firmware.
    /// Protocol (matches rtk_haptics_bridge_v2.ino):
    ///   Byte 0: motor  (0x01=left, 0x02=right, 0x03=both)
    ///   Byte 1: effect (DRV2605 effect 1..123)
    ///   Byte 2: count  (repetitions)
    ///   Byte 3: interval (×10 ms between pulses)
    func send(side: HapticSide, effect: UInt8, count: UInt8 = 1, intervalMs: Int = 100) {
        guard let peripheral = peripheral, let ch = writeChar else {
            statusText = "Not connected"
            return
        }
        let intv10 = UInt8(clamping: max(1, intervalMs / 10))
        let payload: [UInt8] = [side.rawValue, max(1, min(123, effect)), max(1, count), intv10]
        let data = Data(payload)
        let type: CBCharacteristicWriteType =
            ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: ch, type: type)
    }

    /// Start a wide scan that surfaces every named peripheral (scanner UI).
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

    /// Connect to a peripheral chosen from the scanner list.
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
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:    statusText = "Tap the antenna icon to scan"
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
        guard isDiscovering else { return }

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
        discoveredDevices.sort { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            return lhs.rssi > rhs.rssi
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusText = "Discovering services…"
        peripheral.discoverServices([Self.hapticServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        isConnected = false
        connectedName = ""
        statusText = "Failed to connect"
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        writeChar = nil
        connectedName = ""
        statusText = manuallyDisconnected ? "Disconnected" : "Lost connection"
        manuallyDisconnected = false
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            statusText = "No services on this device"
            return
        }
        var found = false
        for svc in services where svc.uuid == Self.hapticServiceUUID {
            found = true
            peripheral.discoverCharacteristics([Self.hapticCharacteristicUUID], for: svc)
        }
        if !found {
            statusText = "Selected device has no haptic service"
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == Self.hapticCharacteristicUUID {
            writeChar = c
            isConnected = true
            connectedName = peripheral.name ?? "Unknown"
            statusText = "Connected to \(connectedName)"
        }
    }
}
