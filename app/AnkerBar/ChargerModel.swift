import Foundation
import SwiftUI
import WidgetKit

/// Runs the Python daemon, decodes its JSON lines and feeds the menu and the widget.
@MainActor
final class ChargerModel: ObservableObject {
    @Published private(set) var state: ChargerState?
    @Published private(set) var statusText = "Подключаюсь к зарядке…"

    private var process: Process?
    private var buffer = Data()
    private var lastWidgetReload = Date.distantPast
    private var lastWidgetKey = ""

    /// Widget reloads are budgeted by the system; reload at once when a pad
    /// starts or stops, otherwise at most this often.
    private let widgetMinInterval: TimeInterval = 60

    init() {
        state = SharedStore.load()
        startDaemon()
    }

    // MARK: daemon

    private var projectDir: URL {
        let path = Bundle.main.object(forInfoDictionaryKey: "AnkerProjectDir") as? String ?? ""
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    func restartDaemon() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        statusText = "Подключаюсь к зарядке…"
        startDaemon()
    }

    private func startDaemon() {
        let python = projectDir.appendingPathComponent(".venv/bin/python")
        let script = projectDir.appendingPathComponent("daemon/ankerd.py")
        guard FileManager.default.fileExists(atPath: python.path) else {
            statusText = "Нет \(python.path)"
            return
        }
        let p = Process()
        p.executableURL = python
        p.arguments = ["-u", script.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.statusText = "Демон остановился, перезапуск…"
                try? await Task.sleep(for: .seconds(5))
                if self?.process?.isRunning == false { self?.startDaemon() }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            statusText = "Не запустить демон: \(error.localizedDescription)"
        }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let s = try? JSONDecoder().decode(ChargerState.self, from: Data(line)) {
                apply(s, forceWidget: false)
            }
        }
    }

    private func apply(_ incoming: ChargerState, forceWidget: Bool) {
        var s = incoming
        if s.device?.firmware == nil, let old = state?.device { s.device = old }
        s.pads = s.pads.map { var p = $0; p.kind = PadKind.forPad(p.id); return p }
        state = s
        statusText = s.connected ? "" : (s.error.map { "Зарядка: \($0)" } ?? "Нет связи с зарядкой")
        SharedStore.save(s)

        let key = "\(s.connected)|" + s.pads.map { "\($0.status)\($0.kind?.rawValue ?? "")" }.joined(separator: ",")
        let due = Date().timeIntervalSince(lastWidgetReload) >= widgetMinInterval
        if forceWidget || key != lastWidgetKey || due {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetReload = Date()
            lastWidgetKey = key
        }
    }
}
