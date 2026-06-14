import Foundation
import CryptoTokenKit

/// Talks to a YubiKey's PIV applet over CryptoTokenKit (raw APDUs) to read a
/// slot's P-256 public key and sign a digest with it. P-256 == secp256r1 == R1,
/// so the resulting (r,s) feeds the existing `assemble_sig_r1` → SIG_R1 pipeline.
/// Hardware custody that's removable/portable (vs the device-bound Secure Enclave).
enum YubiKeyPIV {
    enum PIVError: LocalizedError {
        case noReader, noCard, selectFailed, metadataUnsupported, parse(String)
        case pinFailed(retriesLeft: Int?), pinBlocked, apdu(UInt16), notConnected

        var errorDescription: String? {
            switch self {
            case .noReader:            return "No smart-card reader found — is the YubiKey plugged in?"
            case .noCard:              return "Couldn't open the YubiKey. Re-insert it and try again."
            case .selectFailed:        return "Couldn't select the PIV applet on the YubiKey."
            case .metadataUnsupported: return "This YubiKey doesn't support PIV metadata (needs firmware 5.3+). Provision the slot with ykman."
            case .parse(let m):        return "YubiKey response parse error: \(m)"
            case .pinFailed(let r):    return "Wrong PIV PIN" + (r.map { " — \($0) tries left." } ?? ".")
            case .pinBlocked:          return "PIV PIN is blocked. Unblock it with your PUK (ykman)."
            case .apdu(let sw):        return String(format: "YubiKey error (SW=%04X).", sw)
            case .notConnected:        return "Lost connection to the YubiKey."
            }
        }
    }

    // Common PIV slots for digital signature / authentication.
    static let slots: [(UInt8, String)] = [(0x9a, "Authentication (9a)"),
                                           (0x9c, "Digital Signature (9c)"),
                                           (0x9d, "Key Management (9d)"),
                                           (0x9e, "Card Authentication (9e)")]

    private static let aid: [UInt8] = [0xA0, 0x00, 0x00, 0x03, 0x08, 0x00, 0x00, 0x10, 0x00, 0x01, 0x00]

    /// True if a YubiKey (or any PIV smart card) reader is present.
    static func isPresent() -> Bool {
        guard let mgr = TKSmartCardSlotManager.default else { return false }
        return !mgr.slotNames.isEmpty
    }

    /// Read the compressed (33-byte) P-256 public key from a PIV slot.
    static func publicKey(slot: UInt8) async throws -> Data {
        try await withCard { card in
            let meta = try await transmit(card, apdu: [0x00, 0xF7, 0x00, slot])
            guard let point = extractECPoint(fromMetadata: meta) else {
                throw PIVError.metadataUnsupported
            }
            return compress(point)
        }
    }

    /// Verify the PIV PIN then sign a 32-byte digest with the slot key → (r‖s), 64 bytes.
    static func sign(digest: Data, slot: UInt8, pin: String) async throws -> Data {
        guard digest.count == 32 else { throw PIVError.parse("digest must be 32 bytes") }
        return try await withCard { card in
            try await verifyPIN(card, pin: pin)
            // GENERAL AUTHENTICATE: 7C L 82 00 81 20 <digest>
            var data: [UInt8] = [0x7C, 0x24, 0x82, 0x00, 0x81, 0x20]
            data.append(contentsOf: digest)
            let resp = try await transmit(card, apdu: [0x00, 0x87, 0x11, slot] + lc(data) + data + [0x00])
            guard let der = tlvValue(0x82, in: tlvValue(0x7C, in: resp) ?? resp) else {
                throw PIVError.parse("no signature in response")
            }
            return try derToRS(der)
        }
    }

    // MARK: APDU plumbing

    private static func withCard<T>(_ body: (TKSmartCard) async throws -> T) async throws -> T {
        guard let mgr = TKSmartCardSlotManager.default, !mgr.slotNames.isEmpty else { throw PIVError.noReader }
        // Prefer a slot whose name mentions YubiKey; else the first reader.
        let name = mgr.slotNames.first { $0.localizedCaseInsensitiveContains("yubikey") } ?? mgr.slotNames[0]
        guard let slot = await mgr.getSlot(withName: name), let card = slot.makeSmartCard() else {
            throw PIVError.noCard
        }
        guard try await card.beginSession() else { throw PIVError.noCard }
        defer { card.endSession() }
        // SELECT the PIV applet.
        let sel = try await transmit(card, apdu: [0x00, 0xA4, 0x04, 0x00] + lc(aid) + aid, expectOK: false)
        guard sw(sel) == 0x9000 else { throw PIVError.selectFailed }
        return try await body(card)
    }

    private static func verifyPIN(_ card: TKSmartCard, pin: String) async throws {
        var bytes = Array(pin.utf8)
        guard bytes.count <= 8 else { throw PIVError.parse("PIN too long") }
        while bytes.count < 8 { bytes.append(0xFF) }   // PIV pads PIN to 8 with 0xFF
        let resp = try await transmit(card, apdu: [0x00, 0x20, 0x00, 0x80, 0x08] + bytes, expectOK: false)
        let status = sw(resp)
        if status == 0x9000 { return }
        if status == 0x6983 { throw PIVError.pinBlocked }
        if status & 0xFFF0 == 0x63C0 { throw PIVError.pinFailed(retriesLeft: Int(status & 0x000F)) }
        throw PIVError.apdu(status)
    }

    /// Send an APDU; transparently handles 61xx (GET RESPONSE) chaining.
    /// Returns the response data WITHOUT the trailing SW when expectOK, else with SW.
    @discardableResult
    private static func transmit(_ card: TKSmartCard, apdu: [UInt8], expectOK: Bool = true) async throws -> Data {
        var resp = try await card.transmit(Data(apdu))
        var acc = Data()
        while resp.count >= 2 {
            let s = sw(resp)
            acc.append(resp.prefix(resp.count - 2))
            if (s & 0xFF00) == 0x6100 {                       // more data available
                let le = UInt8(s & 0x00FF)
                resp = try await card.transmit(Data([0x00, 0xC0, 0x00, 0x00, le]))
                continue
            }
            if s == 0x9000 || !expectOK {
                return expectOK ? acc : (acc + resp.suffix(2))
            }
            throw PIVError.apdu(s)
        }
        throw PIVError.notConnected
    }

    // MARK: encoding helpers

    private static func sw(_ d: Data) -> UInt16 {
        guard d.count >= 2 else { return 0 }
        return (UInt16(d[d.count - 2]) << 8) | UInt16(d[d.count - 1])
    }

    /// Lc field (short form only — our APDUs are well under 255 bytes).
    private static func lc(_ data: [UInt8]) -> [UInt8] { [UInt8(data.count)] }

    /// Find a BER-TLV tag's value within `data` (single-byte tag, short/long length).
    private static func tlvValue(_ tag: UInt8, in data: Data?) -> Data? {
        guard let data else { return nil }
        var i = data.startIndex
        while i < data.endIndex {
            let t = data[i]; i = data.index(after: i)
            guard i < data.endIndex else { return nil }
            var len = Int(data[i]); i = data.index(after: i)
            if len & 0x80 != 0 {                              // long-form length
                let n = len & 0x7F
                len = 0
                for _ in 0..<n { guard i < data.endIndex else { return nil }; len = (len << 8) | Int(data[i]); i = data.index(after: i) }
            }
            let end = data.index(i, offsetBy: len, limitedBy: data.endIndex) ?? data.endIndex
            if t == tag { return data[i..<end] }
            i = end
        }
        return nil
    }

    /// Pull the 65-byte uncompressed EC point (04‖X‖Y) out of a PIV metadata response.
    private static func extractECPoint(fromMetadata meta: Data) -> Data? {
        // metadata tag 0x04 = public; its value holds 86 41 04 X Y (point template).
        let pub = tlvValue(0x04, in: meta) ?? meta
        let bytes = [UInt8](pub)
        // Find an uncompressed point: 0x04 followed by 64 bytes.
        var i = 0
        while i + 65 <= bytes.count {
            if bytes[i] == 0x04 && (i == 0 || bytes[i - 1] == 0x41) {
                return Data(bytes[i..<i + 65])
            }
            i += 1
        }
        // Fallback: value is exactly the 65-byte point.
        if bytes.count == 65 && bytes[0] == 0x04 { return Data(bytes) }
        return nil
    }

    /// Compress an uncompressed EC point (04‖X‖Y, 65 bytes) → 33 bytes (02/03‖X).
    private static func compress(_ point: Data) -> Data {
        let b = [UInt8](point)
        let x = Array(b[1..<33]), y = b[64]
        return Data([(y & 1) == 0 ? 0x02 : 0x03] + x)
    }

    /// DER ECDSA signature → fixed 64-byte r‖s.
    private static func derToRS(_ der: Data) throws -> Data {
        let b = [UInt8](der)
        var i = 0
        func readInt() throws -> [UInt8] {
            guard i < b.count, b[i] == 0x02 else { throw PIVError.parse("bad INTEGER") }
            i += 1
            guard i < b.count else { throw PIVError.parse("truncated") }
            let len = Int(b[i]); i += 1
            guard i + len <= b.count else { throw PIVError.parse("truncated int") }
            var v = Array(b[i..<i + len]); i += len
            while v.first == 0x00 { v.removeFirst() }          // strip sign padding
            while v.count < 32 { v.insert(0, at: 0) }          // left-pad to 32
            if v.count > 32 { throw PIVError.parse("integer too long") }
            return v
        }
        guard !b.isEmpty, b[0] == 0x30 else { throw PIVError.parse("bad SEQUENCE") }
        i = 2
        if b.count > 1 && (b[1] & 0x80) != 0 { i = 2 + Int(b[1] & 0x7F) }  // long-form seq len
        let r = try readInt(); let s = try readInt()
        return Data(r + s)
    }
}
