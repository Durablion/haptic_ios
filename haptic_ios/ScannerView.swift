import SwiftUI

struct ScannerView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if ble.discoveredDevices.isEmpty {
                    HStack {
                        if ble.isDiscovering {
                            ProgressView()
                            Text("Scanning for BLE devices…")
                                .foregroundColor(.secondary)
                                .padding(.leading, 8)
                        } else {
                            Text("Tap Scan to look for devices")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    ForEach(ble.discoveredDevices) { device in
                        Button {
                            ble.connect(to: device.id)
                            dismiss()
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(ble.statusText)
            }
        }
        .navigationTitle("BLE Devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if ble.isDiscovering {
                    Button("Stop") { ble.stopDiscoveryScan() }
                } else {
                    Button("Scan") { ble.startDiscoveryScan() }
                }
            }
        }
        .onAppear { ble.startDiscoveryScan() }
        .onDisappear { ble.stopDiscoveryScan() }
    }
}

private struct DeviceRow: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if device.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    Text(device.name)
                        .font(.body)
                }
                Text(device.id.uuidString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: rssiIcon(device.rssi))
                    .foregroundColor(rssiColor(device.rssi))
                Text("\(device.rssi) dBm")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func rssiIcon(_ rssi: Int) -> String {
        switch rssi {
        case ..<(-85): return "wifi"
        case (-85)..<(-70): return "wifi"
        default: return "wifi"
        }
    }

    private func rssiColor(_ rssi: Int) -> Color {
        switch rssi {
        case ..<(-85): return .red
        case (-85)..<(-70): return .orange
        default: return .green
        }
    }
}

#Preview {
    NavigationStack {
        ScannerView().environmentObject(BLEManager())
    }
}
