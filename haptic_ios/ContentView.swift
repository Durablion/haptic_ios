import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var showScanner = false

    // Settings for the next haptic fire
    @State private var side: HapticSide = .left
    @State private var count: Int = 1
    @State private var intervalMs: Double = 100

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status
                Text(ble.statusText)
                    .font(.subheadline)
                    .foregroundColor(ble.isConnected ? .green : .secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))

                // Controls
                VStack(spacing: 12) {
                    Picker("Side", selection: $side) {
                        ForEach(HapticSide.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Repetitions")
                        Spacer()
                        Stepper(value: $count, in: 1...10) {
                            Text("\(count)").monospacedDigit()
                        }
                        .labelsHidden()
                        Text("\(count)")
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }

                    HStack {
                        Text("Interval")
                        Slider(value: $intervalMs, in: 50...2550, step: 10)
                        Text("\(Int(intervalMs)) ms")
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Pattern list
                List(HapticPattern.all) { pattern in
                    Button {
                        ble.send(
                            side: side,
                            effect: pattern.id,
                            count: UInt8(count),
                            intervalMs: Int(intervalMs)
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pattern.name)
                                    .font(.body)
                                Text(pattern.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("#\(pattern.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(Capsule())
                            Image(systemName: "play.fill")
                                .foregroundColor(ble.isConnected ? .accentColor : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ble.isConnected)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Haptic Tester")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .accessibilityLabel("BLE Devices")
                }
            }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    ScannerView()
                        .environmentObject(ble)
                }
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(BLEManager())
}
