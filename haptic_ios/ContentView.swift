import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(ble.statusText)
                    .font(.headline)
                    .foregroundColor(ble.isConnected ? .green : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                HStack(spacing: 16) {
                    BigButton(title: "LEFT", color: .blue) {
                        ble.sendLeft()
                    }
                    BigButton(title: "RIGHT", color: .orange) {
                        ble.sendRight()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Haptic Remote")
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

struct BigButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color)
                .cornerRadius(24)
        }
    }
}

#Preview {
    ContentView().environmentObject(BLEManager())
}
