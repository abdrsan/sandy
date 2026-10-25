import CryptoKit
import Foundation

public enum MobileFailure: Error { case invalid, stale, replay, expired, untrusted, signature, resolved }

public struct MobileEnvelope: Codable, Sendable {
    public var version = 1
    public var room: String
    public var id: String
    public var sentAt: Int64
    public var senderKey: String
    public var encapsulatedKey: String
    public var ciphertext: String
    var aad: Data { Data("sandy/mobile/1\n\(room)\n\(id)\n\(sentAt)\n\(senderKey)".utf8) }
}

public enum MobileCrypto {
    public static let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    static let info = Data("sandy/mobile/1/hpke-auth".utf8)
    public static func seal(_ message: MobileMessage, room: String, sender: P256.KeyAgreement.PrivateKey,
                            recipient: Data, now: Date = Date()) throws -> MobileEnvelope {
        var senderContext = try HPKE.Sender(recipientKey: P256.KeyAgreement.PublicKey(x963Representation: recipient),
                                            ciphersuite: suite, info: info, authenticatedBy: sender)
        var envelope = MobileEnvelope(room: room, id: UUID().uuidString.lowercased(),
                                      sentAt: Int64(now.timeIntervalSince1970 * 1000),
                                      senderKey: sender.publicKey.x963Representation.base64EncodedString(),
                                      encapsulatedKey: senderContext.encapsulatedKey.base64EncodedString(), ciphertext: "")
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= 48_000 else { throw MobileFailure.invalid }
        envelope.ciphertext = try senderContext.seal(payload, authenticating: envelope.aad).base64EncodedString()
        return envelope
    }
    public static func open(_ envelope: MobileEnvelope, room: String, recipient: P256.KeyAgreement.PrivateKey,
                            trustedSender: Data?, now: Date = Date()) throws -> MobileMessage {
        guard envelope.version == 1, envelope.room == room, UUID(uuidString: envelope.id) != nil,
              let key = Data(base64Encoded: envelope.senderKey), key.count == 65,
              let enc = Data(base64Encoded: envelope.encapsulatedKey), enc.count == 65,
              let cipher = Data(base64Encoded: envelope.ciphertext), cipher.count <= 49_000 else { throw MobileFailure.invalid }
        if let trustedSender, trustedSender != key { throw MobileFailure.untrusted }
        guard abs(now.timeIntervalSince1970 - Double(envelope.sentAt) / 1000) <= 120 else { throw MobileFailure.stale }
        var context = try HPKE.Recipient(privateKey: recipient, ciphersuite: suite, info: info,
                                         encapsulatedKey: enc, authenticatedBy: P256.KeyAgreement.PublicKey(x963Representation: key))
        return try JSONDecoder().decode(MobileMessage.self, from: context.open(cipher, authenticating: envelope.aad))
    }
    public static func fingerprint(_ key: Data) -> String { SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined() }
}

public struct MobileActivity: Codable, Sendable, Identifiable {
    public var id: String
    public var session: String
    public var source: String
    public var state: String
    public var operation: String
    public var project: String
    public var timestamp: Int64
    public init(id: String, session: String, source: String, state: String, operation: String, project: String, timestamp: Int64) {
        self.id = id; self.session = session; self.source = source; self.state = state
        self.operation = operation; self.project = project; self.timestamp = timestamp
    }
}
public struct MobileApproval: Codable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var session: String
    public var tool: String
    public var context: String
    public var digest: String
    public var challenge: String
    public var expiresAt: Int64
    public init(source: String, session: String, tool: String, context: String, now: Date = Date()) {
        id = UUID().uuidString.lowercased(); self.source = source; self.session = session
        self.tool = tool; self.context = context
        digest = MobileCrypto.fingerprint(Data(context.utf8))
        challenge = UUID().uuidString.lowercased() + UUID().uuidString.lowercased()
        expiresAt = Int64(now.addingTimeInterval(90).timeIntervalSince1970 * 1000)
    }
    public func signingData(room: String, action: String) -> Data {
        Data("sandy/decision/1\n\(room)\n\(id)\n\(digest)\n\(challenge)\n\(action)".utf8)
    }
}
public struct MobileDecision: Codable, Sendable {
    public var requestID: String
    public var digest: String
    public var challenge: String
    public var action: String
    public var signature: String
    public init(requestID: String, digest: String, challenge: String, action: String, signature: String) {
        self.requestID = requestID; self.digest = digest; self.challenge = challenge
        self.action = action; self.signature = signature
    }
}
public struct MobileMessage: Codable, Sendable {
    public var type: String
    public var name: String?
    public var approvalKey: String?
    public var activities: [MobileActivity]?
    public var approvals: [MobileApproval]?
    public var decision: MobileDecision?
    public var result: String?
    public var requestID: String?
    public init(type: String, name: String? = nil, approvalKey: String? = nil, activities: [MobileActivity]? = nil,
                approvals: [MobileApproval]? = nil, decision: MobileDecision? = nil, result: String? = nil, requestID: String? = nil) {
        self.type = type; self.name = name; self.approvalKey = approvalKey; self.activities = activities
        self.approvals = approvals; self.decision = decision; self.result = result; self.requestID = requestID
    }
}

/// Actor isolation makes claiming a request atomic across phones. Pending state
/// is intentionally not restored after restart. Expiry uses the Mac monotonic clock.
public actor MobileApprovalBook {
    private struct Entry { var request: MobileApproval; var deadline: ContinuousClock.Instant }
    private var entries: [String: Entry] = [:]
    public init() {}
    public func insert(_ request: MobileApproval) throws {
        guard request.context.utf8.count <= 24_000, entries.count < 32 else { throw MobileFailure.invalid }
        entries[request.id] = Entry(request: request, deadline: .now.advanced(by: .seconds(90)))
    }
    public func pending(now: Date = Date()) -> [MobileApproval] {
        entries = entries.filter { $0.value.deadline > .now && $0.value.request.expiresAt > Int64(now.timeIntervalSince1970 * 1000) }
        return entries.values.map(\.request).sorted { $0.expiresAt < $1.expiresAt }
    }
    public func cancel(_ id: String) { entries.removeValue(forKey: id) }
    public func cancelAll() { entries.removeAll() }
    public func consumeLocally(_ id: String, now: Date = Date()) throws -> MobileApproval {
        guard let entry = entries.removeValue(forKey: id) else { throw MobileFailure.resolved }
        guard entry.deadline > .now, entry.request.expiresAt > Int64(now.timeIntervalSince1970 * 1000) else { throw MobileFailure.expired }
        return entry.request
    }
    public func consume(_ decision: MobileDecision, room: String, publicKey: Data, now: Date = Date()) throws -> MobileApproval {
        guard let entry = entries[decision.requestID] else { throw MobileFailure.resolved }
        let request = entry.request
        guard entry.deadline > .now, request.expiresAt > Int64(now.timeIntervalSince1970 * 1000) else {
            entries.removeValue(forKey: request.id); throw MobileFailure.expired
        }
        guard ["allow", "deny"].contains(decision.action), request.digest == decision.digest,
              request.challenge == decision.challenge, let signature = Data(base64Encoded: decision.signature) else { throw MobileFailure.invalid }
        let key = try P256.Signing.PublicKey(x963Representation: publicKey)
        guard try key.isValidSignature(P256.Signing.ECDSASignature(derRepresentation: signature),
                                      for: request.signingData(room: room, action: decision.action)) else { throw MobileFailure.signature }
        entries.removeValue(forKey: request.id)
        return request
    }
}

public struct MobileReplayWindow: Sendable {
    private var seen: [String: Date] = [:]
    public init() {}
    public mutating func claim(_ envelope: MobileEnvelope, now: Date = Date()) throws {
        seen = seen.filter { $0.value > now.addingTimeInterval(-240) }
        guard seen.count < 4096, seen[envelope.id] == nil else { throw MobileFailure.replay }
        seen[envelope.id] = now
    }
}
