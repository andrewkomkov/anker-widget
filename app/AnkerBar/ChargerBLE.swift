import CoreBluetooth
import Foundation

/// Finds the charger, runs the handshake and reports telemetry. Callbacks come on the main queue.
final class ChargerBLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Status: Equatable {
        case bluetoothOff, unauthorized, scanning, connecting, negotiating, live
    }

    static let advertisedService = CBUUID(string: "FF09")
    static let service = CBUUID(string: "8C850001-0302-41C5-B46E-CF057C562025")
    static let commandChar = CBUUID(string: "8C850002-0302-41C5-B46E-CF057C562025")
    static let telemetryChar = CBUUID(string: "8C850003-0302-41C5-B46E-CF057C562025")

    var onStatus: ((Status) -> Void)?
    var onTelemetry: ((_ telemetry: [String: Data], _ info: DeviceInfoPacket?, _ name: String?) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var session = AnkerSession()
    private var watchdog: Timer?
    private var lastPacket = Date.distantPast
    private(set) var status: Status = .scanning { didSet { if status != oldValue { onStatus?(status) } } }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func reconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        startScan()
    }

    private func startScan() {
        guard central.state == .poweredOn else { return }
        status = .scanning
        central.scanForPeripherals(withServices: [Self.advertisedService])
    }

    // MARK: central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: startScan()
        case .unauthorized: status = .unauthorized
        default: status = .bluetoothOff
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral == nil else { return }
        c.stopScan()
        peripheral = p
        p.delegate = self
        status = .connecting
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = .negotiating
        p.discoverServices([Self.service])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        retryLater()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        retryLater()
    }

    private func retryLater() {
        watchdog?.invalidate()
        peripheral = nil
        command = nil
        status = .scanning
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.peripheral == nil { self?.startScan() }
        }
    }

    // MARK: peripheral

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { return reconnect() }
        p.discoverCharacteristics([Self.commandChar, Self.telemetryChar], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        command = s.characteristics?.first { $0.uuid == Self.commandChar }
        guard command != nil, let t = s.characteristics?.first(where: { $0.uuid == Self.telemetryChar })
        else { return reconnect() }
        p.setNotifyValue(true, for: t)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard c.isNotifying else { return reconnect() }
        session = AnkerSession()
        lastPacket = Date()
        send(session.start())
        startWatchdog()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let value = c.value else { return }
        lastPacket = Date()
        let (writes, updated) = session.handle(value)
        send(writes)
        if updated, let t = session.telemetry {
            status = .live
            onTelemetry?(t, session.info, p.name)
        }
    }

    private func send(_ packets: [Data]) {
        guard let p = peripheral, let c = command else { return }
        for d in packets { p.writeValue(d, for: c, type: .withResponse) }
    }

    /// Restart the handshake if the charger goes quiet, reconnect if that does not help.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let quiet = Date().timeIntervalSince(self.lastPacket)
            if !self.session.isNegotiated, quiet > 15 {
                self.lastPacket = Date()
                self.send(self.session.start())
            } else if quiet > 60 {
                self.reconnect()
            }
        }
    }
}
