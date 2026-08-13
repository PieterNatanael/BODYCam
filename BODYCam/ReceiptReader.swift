import Foundation

/// Locally parses the App Store receipt (ASN.1 DER) to check if the user
/// originally purchased the app before the freemium cutoff.
/// No server or shared secret required — Apple cryptographically signs the receipt.
struct ReceiptReader {

    // MARK: - Public API

    /// Returns true if the receipt's `original_purchase_date` (field 21) is before
    /// `cutoffDate` — meaning the user purchased the app before the freemium launch.
    static func isGrandfathered(receiptData: Data,
                                 cutoffDate: Date) -> Bool {
        guard let payload = extractPayload(from: receiptData) else { return false }

        var originalPurchaseDate: Date?

        iterateAttributes(in: payload) { type, value in
            if type == 21,   // original_purchase_date (IA5String inside OCTET STRING)
               let s = innerString(from: value) {
                originalPurchaseDate = parseDate(s)
            }
        }

        guard let date = originalPurchaseDate else { return false }
        return date < cutoffDate
    }

    // MARK: - PKCS7 payload extraction

    /// The receipt is a PKCS7 SignedData. Its payload is a DER-encoded SET of
    /// receipt attributes wrapped in an OCTET STRING. We walk the ASN.1 tree
    /// depth-first looking for that OCTET STRING (tag 0x04) whose content starts
    /// with a SET (tag 0x31).
    private static func extractPayload(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        return findPayload(in: bytes, from: 0, to: bytes.count)
    }

    private static func findPayload(in bytes: [UInt8], from start: Int, to end: Int) -> Data? {
        var i = start
        while i < end {
            guard i + 1 < end else { return nil }
            let tag = bytes[i]; i += 1
            let (length, next) = readLength(bytes, at: i); i = next
            let valueEnd = min(i + length, end)

            if tag == 0x04, i < valueEnd, bytes[i] == 0x31 {
                // Found the OCTET STRING wrapping our SET
                return Data(bytes[i..<valueEnd])
            }

            // Recurse into container tags (SEQUENCE, SET, context-specific)
            if tag == 0x30 || tag == 0x31 || (tag & 0xE0 == 0xA0) {
                if let found = findPayload(in: bytes, from: i, to: valueEnd) {
                    return found
                }
            }
            i = valueEnd
        }
        return nil
    }

    // MARK: - Attribute iteration

    /// Walks the SET OF ReceiptAttribute and calls `handler(type, valueOctetString)`.
    private static func iterateAttributes(in data: Data,
                                          handler: (Int, Data) -> Void) {
        var bytes = [UInt8](data)
        var i = 0

        // Skip outer SET tag + length
        guard i < bytes.count, bytes[i] == 0x31 else { return }
        i += 1
        let (_, setNext) = readLength(bytes, at: i); i = setNext

        while i < bytes.count {
            // Each attribute is a SEQUENCE { INTEGER type, INTEGER version, OCTET STRING value }
            guard i < bytes.count, bytes[i] == 0x30 else { i += 1; continue }
            i += 1
            let (seqLen, seqNext) = readLength(bytes, at: i); i = seqNext
            let seqEnd = i + seqLen

            // type INTEGER
            guard i < seqEnd, bytes[i] == 0x02 else { i = seqEnd; continue }
            i += 1
            let (tLen, tNext) = readLength(bytes, at: i); i = tNext
            let attrType = readInt(bytes, at: i, length: tLen); i += tLen

            // version INTEGER (skip)
            guard i < seqEnd, bytes[i] == 0x02 else { i = seqEnd; continue }
            i += 1
            let (vLen, vNext) = readLength(bytes, at: i); i = vNext + vLen

            // value OCTET STRING
            guard i < seqEnd, bytes[i] == 0x04 else { i = seqEnd; continue }
            i += 1
            let (valLen, valNext) = readLength(bytes, at: i); i = valNext
            let valEnd = min(i + valLen, seqEnd)
            let value = Data(bytes[i..<valEnd])

            handler(attrType, value)
            i = seqEnd
        }
    }

    // MARK: - ASN.1 helpers

    private static func readLength(_ bytes: [UInt8], at index: Int) -> (Int, Int) {
        guard index < bytes.count else { return (0, index) }
        let first = bytes[index]
        if first & 0x80 == 0 { return (Int(first), index + 1) }
        let numBytes = Int(first & 0x7F)
        var length = 0
        for j in 0..<numBytes {
            guard index + 1 + j < bytes.count else { break }
            length = (length << 8) | Int(bytes[index + 1 + j])
        }
        return (length, index + 1 + numBytes)
    }

    private static func readInt(_ bytes: [UInt8], at start: Int, length: Int) -> Int {
        var result = 0
        for j in 0..<length {
            guard start + j < bytes.count else { break }
            result = (result << 8) | Int(bytes[start + j])
        }
        return result
    }

    /// The attribute value is itself ASN.1-encoded (UTF8String or IA5String).
    /// Strip one TLV layer to get the raw string bytes.
    private static func innerString(from data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 1 else { return nil }
        var i = 1  // skip tag byte
        let (len, next) = readLength(bytes, at: i); i = next
        guard i + len <= bytes.count else { return nil }
        let raw = bytes[i..<(i + len)]
        return String(bytes: raw, encoding: .utf8) ?? String(bytes: raw, encoding: .ascii)
    }

    private static func parseDate(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }
}
