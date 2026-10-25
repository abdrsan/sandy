import CryptoKit
import Foundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct RelayBatch: Codable, Sendable { public var cursor: Int; public var messages: [MobileEnvelope] }
public struct RelayLiveState: Codable, Sendable {
    public var working: Int; public var waiting: Int
    public init(working: Int, waiting: Int) { self.working=working; self.waiting=waiting }
}
public struct MobilePairing: Codable, Sendable {
    public var version = 1
    public var relay: String
    public var room: String
    public var token: String
    public var macKey: String
    public init(relay: String, room: String, token: String, macKey: String) {
        self.relay = relay; self.room = room; self.token = token; self.macKey = macKey
    }
    public var text: String { (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "" }
    public static func parse(_ text: String) throws -> Self {
        guard text.utf8.count < 4096 else { throw MobileFailure.invalid }
        let pairing = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        _ = try MobileRelayClient.baseURL(pairing.relay)
        guard pairing.version == 1, pairing.room.utf8.count >= 22, pairing.room.utf8.count <= 64,
              pairing.room.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              pairing.token.utf8.count >= 43, pairing.token.utf8.count <= 128,
              let key = Data(base64Encoded: pairing.macKey), key.count == 65 else { throw MobileFailure.invalid }
        _ = try P256.KeyAgreement.PublicKey(x963Representation: key)
        return pairing
    }
}
public actor MobileRelayClient {
    let base: URL
    let room: String
    let token: String
    let role: String
    private let session: URLSession
    public init(relay: String, room: String, token: String, role: String) throws {
        base = try Self.baseURL(relay); self.room = room; self.token = token; self.role = role
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        config.urlCache = nil; config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public static func baseURL(_ text: String) throws -> URL {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { throw MobileFailure.invalid }
        return url
    }
    private func request(_ suffix: String, method: String = "GET", body: Data? = nil, admin: String? = nil) async throws -> Data {
        let path = admin != nil ? "/v1/rooms" : "/v1/rooms/\(room)\(suffix)"
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else { throw MobileFailure.invalid }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(admin ?? token)", forHTTPHeaderField: "Authorization")
        request.setValue(role, forHTTPHeaderField: "X-Sandy-Role")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 2_500_000 else { throw MobileFailure.invalid }
        return data
    }
    public func create(admin: String, phoneToken: String) async throws {
        let hash: (String) -> String = { MobileCrypto.fingerprint(Data($0.utf8)) }
        let body = try JSONEncoder().encode(["room": room, "macHash": hash(token), "phoneHash": hash(phoneToken)])
        _ = try await request("", method: "POST", body: body, admin: admin)
    }
    public func send(_ envelope: MobileEnvelope, notify: Bool = false, live: RelayLiveState? = nil) async throws {
        struct Send: Encodable { var envelope: MobileEnvelope; var notify: Bool; var live: RelayLiveState? }
        _ = try await request("/messages", method: "POST", body: JSONEncoder().encode(Send(envelope: envelope, notify: notify, live: live)))
    }
    public func poll(after: Int) async throws -> RelayBatch {
        try JSONDecoder().decode(RelayBatch.self, from: await request("/messages?after=\(after)"))
    }
    public func setPush(platform: String, token: String) async throws -> Bool {
        let data = try await request("/push", method: "POST", body: JSONEncoder().encode(["platform":platform,"token":token]))
        return (try? JSONDecoder().decode([String: Bool].self, from: data)["configured"]) == true
    }
    public func revoke() async throws { _ = try await request("", method: "DELETE") }
}
