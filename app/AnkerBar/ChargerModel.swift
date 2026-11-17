import Foundation
import SwiftUI
import WidgetKit

/// Owns the Bluetooth link, feeds the menu and shares the state with the widget.
@MainActor
final class ChargerModel: ObservableObject {
    @Published private(set) var state: ChargerState?
    @Published private(set) var status: ChargerBLE.Status = .scanning

    private let ble = ChargerBLE()
    private var lastWidgetReload = Date.distantPast
    private var lastWidgetKey = ""
    private var heartbeat: Timer?

    /// Widget reloads are budgeted by the system: reload at once when a pad
    /// starts or stops, otherwise at most this often.
    private let widgetMinInterval: TimeInterval = 60

    init() {
        state = SharedStore.load()
        ble.onStatus = { [weak self] s in
            MainActor.assumeIsolated { self?.statusChanged(s) }
        }
        ble.onTelemetry = { [weak self] t, info, name in
            MainActor.assumeIsolated { self?.telemetry(t, info: info, name: name) }
        }
        // Keep the shared timestamp fresh while the charger reports nothing new.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .live, var s = self.state else { return }
                s.ts = Date().timeIntervalSince1970
                self.publish(s, forceWidget: false)
            }
        }
    }

    var statusText: LocalizedStringKey {
        switch status {
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Allow Bluetooth for AnkerBar in System Settings"
        case .scanning: "Looking for the charger…"
        case .connecting, .negotiating: "Connecting to the charger…"
        case .live: ""
        }
    }

    func reconnect() { ble.reconnect() }

    private func statusChanged(_ s: ChargerBLE.Status) {
        status = s
        if s != .live, var st = state, st.connected {
            st.connected = false
            publish(st, forceWidget: true)
        }
    }

    private func telemetry(_ t: [String: Data], info: DeviceInfoPacket?, name: String?) {
        let pads = decodePads(t)
        var device = state?.device ?? DeviceInfo()
        if let info {
            device = DeviceInfo(name: info.name, firmware: info.firmware, serial: info.serial)
        }
        let s = ChargerState(
            ts: Date().timeIntervalSince1970, connected: true, device: device, pads: pads,
            total: (pads.reduce(0) { $0 + $1.watts } * 100).rounded() / 100, error: nil)
        publish(s, forceWidget: false)
    }

    private func publish(_ s: ChargerState, forceWidget: Bool) {
        let changed = s.pads.map(\.watts) != state?.pads.map(\.watts) || s.connected != state?.connected
        state = s
        SharedStore.save(s)
        let key = "\(s.connected)|" + s.pads.map(\.status).joined(separator: ",")
        let due = changed && Date().timeIntervalSince(lastWidgetReload) >= widgetMinInterval
        if forceWidget || key != lastWidgetKey || due {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetReload = Date()
            lastWidgetKey = key
        }
    }
}
