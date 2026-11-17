import CryptoKit
import Foundation

// Anker Prime BLE protocol, ported from SolixBLE (MIT, github.com/flip-dots/SolixBLE).
// Packet: ff09 <len LE 2B> <pattern 3B> <cmd 2B> <payload> <xor checksum 1B>.

extension Data {
    init(hex: String) {
        var d = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            d.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        self = d
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

struct Packet {
    let pattern: Data
    let cmd: Data
    let payload: Data

    var patternHex: String { pattern.hex }
    var cmdHex: String { cmd.hex }

    static func checksum(_ d: Data) -> UInt8 { d.reduce(0, ^) }

    static func parse(_ raw: Data) -> Packet? {
        let b = [UInt8](raw)
        guard b.count >= 10, b[0] == 0xff, b[1] == 0x09,
              Int(b[2]) | Int(b[3]) << 8 == b.count,
              checksum(Data(b[..<(b.count - 1)])) == b[b.count - 1]
        else { return nil }
        return Packet(pattern: Data(b[4..<7]), cmd: Data(b[7..<9]), payload: Data(b[9..<(b.count - 1)]))
    }

    static func build(pattern: Data, cmd: Data, payload: Data) -> Data {
        let length = 2 + 2 + 3 + 2 + payload.count + 1
        var d = Data([0xff, 0x09, UInt8(length & 0xff), UInt8(length >> 8)])
        d.append(pattern)
        d.append(cmd)
        d.append(payload)
        d.append(checksum(d))
        return d
    }
}

/// Payload parameters: <id 1B> <len 1B> <data>, an optional leading 00 is skipped.
func parseTLV(_ payload: Data) -> [String: Data] {
    var b = [UInt8](payload)
    if b.first == 0 { b.removeFirst() }
    var out: [String: Data] = [:]
    var i = 0
    while i < b.count {
        let id = String(format: "%02x", b[i])
        guard i + 1 < b.count else { out[id] = Data(); break }
        let len = Int(b[i + 1])
        guard i + 2 + len <= b.count else { break }
        out[id] = Data(b[(i + 2)..<(i + 2 + len)])
        i += 2 + len
    }
    return out
}

enum AnkerCrypto {
    static let negotiationKey = SymmetricKey(data: Data(hex: "b8ff7422955d4eb6d554a2c470280559"))
    static let negotiationNonce = Data(hex: "6ba3e3f2f3a60f2971ce5d1f")
    static let aad = Data(hex: "3322110077665544bbaa9988ffeeddcc")
    // Fixed client key from SolixBLE: the device accepts any key, the session secret comes from ECDH.
    static let privateKey = try! P256.KeyAgreement.PrivateKey(
        rawRepresentation: Data(hex: "754744d72984c378bc4fa77d7fcdf6bbb6d9df119fa9be4948eb8a3b4cd6071f"))

    static func decrypt(_ payload: Data, key: SymmetricKey, nonce: Data) -> Data? {
        guard payload.count >= 16,
              let n = try? AES.GCM.Nonce(data: nonce),
              let box = try? AES.GCM.SealedBox(nonce: n, ciphertext: payload.dropLast(16), tag: payload.suffix(16))
        else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: aad)
    }

    static func encrypt(_ payload: Data, key: SymmetricKey, nonce: Data) -> Data {
        let box = try! AES.GCM.seal(payload, using: key, nonce: AES.GCM.Nonce(data: nonce), authenticating: aad)
        return box.ciphertext + box.tag
    }

    /// Raw ECDH secret: bytes 0..<16 are the AES key, 16..<28 the nonce.
    static func sharedSecret(devicePublicKey xy: Data) -> Data? {
        guard let pub = try? P256.KeyAgreement.PublicKey(x963Representation: Data([0x04]) + xy),
              let s = try? privateKey.sharedSecretFromKeyAgreement(with: pub)
        else { return nil }
        return s.withUnsafeBytes { Data($0) }
    }
}

struct DeviceInfoPacket {
    let name, firmware, serial: String

    init?(_ p: [String: Data]) {
        guard let fw = p["a3"], fw.first == UInt8(ascii: "v"),
              let s = p["a4"], s.count >= 8,
              let fws = String(data: fw, encoding: .ascii) else { return nil }
        name = String(decoding: p["a2"] ?? Data(), as: UTF8.self)
        firmware = fws
        serial = String(decoding: s, as: UTF8.self)
    }
}

/// Handshake and telemetry for the Prime 3-in-1 charger. Feed it notifications,
/// send whatever it returns to the command characteristic.
final class AnkerSession {
    private enum Neg {
        static let pattern = Data(hex: "030001")
        static let sessionPattern = Data(hex: "03000f")
        static let start = Data(hex: "ff09200003000140010a82d0ab535303e3aa9f0c2f9c868465bc8476f556fb7d")
        static let replies: [String: Data] = [
            "4801": Data(hex: "ff09270003000140030a82d0ab53538ab3de100ac9bb87a0b8e36c1dd8167a9c25a9839d9a14d5"),
            "4803": Data(hex: "ff09200003000140290a82d0ab535303e3aa9f0c2f9c868465bc8476f556fb55"),
            "4829": Data(hex: "ff092d0003000140050a82d0ab53538ab3de100ae04aca6791257881a90164eac7460450e0c82f2c03de4f9604"),
            "4805": Data(hex: "ff095c0003000140210ac6ea31e4300bb2877d6ddeb628b0d7be8d768333f00ceab5454d20fbd97e091457b1f3b6efb6511eb9e98ac2b2c46eee211ae359ad246e1ae9886b4a29e41eddd5a5064d8b9ffdbfb43eb6b8e307fcde9de7"),
        ]
        static let stage5 = (cmd: Data(hex: "4022"), payload: Data(hex: "a104f079b569a30400000000a518474d54304253542c4d332e352e302f312c4d31302e352e30"))
        static let stage6 = (cmd: Data(hex: "4027"), payload: Data(hex: "a104f079b569a22437396562656433352d646339632d343930342d623430632d373263346538363361613130"))
        static let stage7a = (cmd: Data(hex: "4200"), payload: Data(hex: "a10121fe04f079b569"))
        static let stage7b = (cmd: Data(hex: "420a"), payload: Data(hex: "a10121a203044742a3250437396562656433352d646339632d343930342d623430632d373263346538363361613130a5020101fe04f079b569"))
        static let baseTimestamp: UInt32 = 0x69b5_79ef
    }

    private(set) var info: DeviceInfoPacket?
    private(set) var telemetry: [String: Data]?
    private var secret: Data?
    private var negotiatedAt: Date?

    var isNegotiated: Bool { secret != nil }

    func start() -> [Data] {
        secret = nil
        negotiatedAt = nil
        return [Neg.start]
    }

    /// Returns packets to write. Sets `telemetry` when a report arrives.
    func handle(_ raw: Data) -> (writes: [Data], telemetryUpdated: Bool) {
        guard let p = Packet.parse(raw) else { return ([], false) }
        switch p.patternHex {
        case "030001":
            return (negotiate(p), false)
        case "03010f", "030111":
            guard p.cmdHex == "4300", let plain = decrypt(p.payload) else { return ([], false) }
            telemetry = parseTLV(plain)
            return ([], true)
        default:
            return ([], false)
        }
    }

    func subscribe() -> Data? { command(Data(hex: "4200"), Data(hex: "a10121")) }

    private func negotiate(_ p: Packet) -> [Data] {
        if info == nil, let plain = decrypt(p.payload) { info = DeviceInfoPacket(parseTLV(plain)) }
        if let reply = Neg.replies[p.cmdHex] { return [reply] }
        switch p.cmdHex {
        case "4821":
            guard let plain = decrypt(p.payload), let xy = parseTLV(plain)["a1"],
                  let s = AnkerCrypto.sharedSecret(devicePublicKey: xy) else { return Neg.start.asArray }
            secret = s
            negotiatedAt = Date()
            return [sealed(Neg.pattern, Neg.stage5.cmd, Neg.stage5.payload)]
        case "4822":
            return [sealed(Neg.pattern, Neg.stage6.cmd, Neg.stage6.payload)]
        case "4827":
            var out = [sealed(Neg.sessionPattern, Neg.stage7a.cmd, Neg.stage7a.payload),
                       sealed(Neg.sessionPattern, Neg.stage7b.cmd, Neg.stage7b.payload)]
            if let sub = subscribe() { out.append(sub) }
            return out
        default:
            return []
        }
    }

    private func command(_ cmd: Data, _ payload: Data) -> Data? {
        guard let at = negotiatedAt else { return nil }
        var ts = Neg.baseTimestamp &+ UInt32(max(0, Date().timeIntervalSince(at)))
        let tsBytes = withUnsafeBytes(of: &ts) { Data($0) }  // little-endian on Apple silicon and Intel
        return sealed(Neg.sessionPattern, cmd, payload + Data(hex: "fe04") + tsBytes)
    }

    private func sealed(_ pattern: Data, _ cmd: Data, _ payload: Data) -> Data {
        let s = secret!
        let enc = AnkerCrypto.encrypt(payload, key: SymmetricKey(data: s.prefix(16)), nonce: s.subdata(in: 16..<28))
        return Packet.build(pattern: pattern, cmd: cmd, payload: enc)
    }

    private func decrypt(_ payload: Data) -> Data? {
        if let s = secret {
            return AnkerCrypto.decrypt(payload, key: SymmetricKey(data: s.prefix(16)), nonce: s.subdata(in: 16..<28))
        }
        return AnkerCrypto.decrypt(payload, key: AnkerCrypto.negotiationKey, nonce: AnkerCrypto.negotiationNonce)
    }
}

private extension Data {
    var asArray: [Data] { [self] }
}

/// Pad record: 04 <status> <volts 0.01 V> <amps 0.01 A> <watts 0.01 W>, little-endian.
func decodePads(_ t: [String: Data]) -> [Pad] {
    ["a2", "a3", "a4"].enumerated().map { i, key in
        let b = [UInt8](t[key] ?? Data())
        func u16(_ at: Int) -> Double { b.count >= at + 2 ? Double(Int(b[at]) | Int(b[at + 1]) << 8) / 100 : 0 }
        let status = b.count >= 2 ? (b[1] == 1 ? "output" : b[1] == 0 ? "not_connected" : "unknown") : "unknown"
        return Pad(id: i + 1, status: status, watts: u16(6), volts: u16(2), amps: u16(4),
                   raw: Data(b).hex, kind: PadKind.forPad(i + 1))
    }
}
