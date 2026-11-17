import ServiceManagement
import SwiftUI

@main
struct AnkerBarApp: App {
    @StateObject private var model = ChargerModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(systemName: model.state?.connected == true ? "bolt.fill" : "bolt.slash")
            if let s = model.state, s.connected, model.status == .live {
                Text(formatWatts(s.total))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: ChargerModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if let s = model.state, s.connected, model.status == .live {
                ForEach(s.pads) { pad in PadRow(pad: pad) }
                HStack {
                    Text("Total").bold()
                    Spacer()
                    Text(formatWatts(s.total)).bold().monospacedDigit()
                }
            } else {
                Text(model.statusText).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            HStack {
                Button("Reconnect") { model.reconnect() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Anker Prime").font(.headline)
            if let d = model.state?.device, let fw = d.firmware {
                Text("\(d.serial ?? "") · \(fw)").font(.caption).foregroundStyle(.secondary)
            }
            if let s = model.state {
                Text("updated \(s.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct PadRow: View {
    let pad: Pad
    var body: some View {
        let kind = pad.kind ?? .other
        HStack {
            Image(systemName: kind.symbol).frame(width: 22)
                .foregroundStyle(pad.isCharging ? .green : .secondary)
            Text(kind.title)
            Spacer()
            if pad.isCharging, let v = pad.volts, let a = pad.amps {
                Text("\(formatVolts(v)) · \(formatAmps(a))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(pad.isCharging ? formatWatts(pad.watts) : "—")
                .monospacedDigit()
                .foregroundStyle(pad.isCharging ? .primary : .secondary)
        }
    }
}
