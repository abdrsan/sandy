import CryptoKit
import SandyMobileCore
import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class PhoneStore: ObservableObject {
    static let shared=PhoneStore()
    private struct Saved: Codable { var pairing: MobilePairing; var key: Data }
    @Published var pairingText=""
    @Published var activities: [MobileActivity]=[]
    @Published var approvals: [MobileApproval]=[]
    @Published var status="Paste or scan the pairing code from Sandy on your Mac."
    @Published var fingerprint=""
    @Published var connected=false
    @Published var busy=false
    private var saved: Saved?
    private var client: MobileRelayClient?
    private var task: Task<Void,Never>?
    private var replay=MobileReplayWindow()
    private var cursor=0
    var room: String? { saved?.pairing.room }

    init() {
        if let data=try? MobileKeychain.read("phone-setup"),let saved=try? JSONDecoder().decode(Saved.self,from:data) {
            self.saved=saved; fingerprint=MobileCrypto.fingerprint((try? P256.KeyAgreement.PrivateKey(rawRepresentation:saved.key).publicKey.x963Representation) ?? Data())
        }
    }
    func pair() {
        do {
            let pairing=try MobilePairing.parse(pairingText)
            let key=P256.KeyAgreement.PrivateKey()
            _ = try ApprovalKey.publicKey(room:pairing.room)
            let state=Saved(pairing:pairing,key:key.rawRepresentation)
            try MobileKeychain.write(JSONEncoder().encode(state),account:"phone-setup")
            saved=state; fingerprint=MobileCrypto.fingerprint(key.publicKey.x963Representation)
            pairingText=""; cursor=0; replay=MobileReplayWindow(); resume()
        } catch { status="Invalid pairing code, or a device screen lock is required." }
    }
    func resume() {
        guard task==nil,let saved else { return }
        do { client=try MobileRelayClient(relay:saved.pairing.relay,room:saved.pairing.room,token:saved.pairing.token,role:"phone") }
        catch { status="Invalid relay address"; return }
        task=Task {
            while !Task.isCancelled {
                do { try await sync(); connected=true }
                catch { connected=false; status="No connection to Mac. Last data may be out of date." }
                try? await Task.sleep(for:.seconds(2))
            }
        }
    }
    func pause() { task?.cancel(); task=nil; connected=false }
    func unpair() { pause(); saved=nil; client=nil; activities=[]; approvals=[]; MobileKeychain.remove("phone-setup"); status="Device unpaired" }
    private func send(_ message: MobileMessage) async throws {
        guard let saved,let client, let mac=Data(base64Encoded:saved.pairing.macKey) else { throw MobileFailure.invalid }
        let envelope=try MobileCrypto.seal(message,room:saved.pairing.room,sender:P256.KeyAgreement.PrivateKey(rawRepresentation:saved.key),recipient:mac)
        try await client.send(envelope)
    }
    private func sync() async throws {
        guard let saved,let client else { return }
        let batch=try await client.poll(after:cursor)
        guard !Task.isCancelled, self.saved?.pairing.room==saved.pairing.room else { return }
        for envelope in batch.messages {
            do {
                let message=try MobileCrypto.open(envelope,room:saved.pairing.room,recipient:P256.KeyAgreement.PrivateKey(rawRepresentation:saved.key),trustedSender:Data(base64Encoded:saved.pairing.macKey))
                try replay.claim(envelope)
                if message.type=="snapshot" {
                    activities=message.activities ?? []; approvals=(message.approvals ?? []).filter{$0.expiresAt>Int64(Date().timeIntervalSince1970*1000)}
                    status="Connected to Mac"; fingerprint=""
                    updateLiveStatus()
                } else if message.type=="result" {
                    approvals.removeAll{$0.id==message.requestID}; status=message.result=="allow" ? "Mac accepted the approval" : "Mac: \(message.result ?? "resolved")"
                }
            } catch { continue }
        }
        cursor=batch.cursor
        if !fingerprint.isEmpty {
            try await send(MobileMessage(type:"hello",name:UIDevice.current.name,
                approvalKey:ApprovalKey.publicKey(room:saved.pairing.room).base64EncodedString()))
            status="Compare the fingerprint below with Mac, then trust this phone on Mac."
        }
    }
    func decide(_ approval: MobileApproval, action: String) {
        guard !busy,let saved,approval.expiresAt>Int64(Date().timeIntervalSince1970*1000) else { return }
        busy=true
        Task {
            defer { busy=false }
            do {
                let signature=try ApprovalKey.sign(approval.signingData(room:saved.pairing.room,action:action),room:saved.pairing.room)
                let decision=MobileDecision(requestID:approval.id,digest:approval.digest,challenge:approval.challenge,action:action,signature:signature.base64EncodedString())
                status="Sending decision…"
                try await send(MobileMessage(type:"decision",decision:decision))
            } catch { status="Decision was not sent. Nothing was approved." }
        }
    }
    func enableNotifications() {
        Task {
            if (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])) == true {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    func registerLivePush(_ token: Data) async {
        try? await client?.setPush(platform:"apns-live",token:token.map{String(format:"%02x",$0)}.joined())
    }
    func registerPush(_ token: Data) {
        Task { if (try? await client?.setPush(platform:"apns",token:token.map{String(format:"%02x",$0)}.joined())) != true { status="Push sender is not configured on the relay yet." } }
    }
}
