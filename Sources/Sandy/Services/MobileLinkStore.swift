import AppKit
import CryptoKit
import SandyMobileCore

@MainActor
final class MobileLinkStore: ObservableObject {
    static let shared = MobileLinkStore()
    struct Peer: Codable, Identifiable {
        var id: String; var name: String; var token: String; var phoneToken: String
        var key: String?; var approvalKey: String?; var approved = false
    }
    private struct Saved: Codable { var relay: String; var admin: String; var key: String; var peers: [Peer] }
    @Published var relayURL = ""
    @Published var adminToken = ""
    @Published private(set) var enabled = false
    @Published private(set) var status = ""
    @Published private(set) var pairingText = ""
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var pendingPeer: Peer?
    @Published private(set) var approvalRequests: [MobileApproval] = []
    private var key = P256.KeyAgreement.PrivateKey()
    private var task: Task<Void, Never>?
    private var clients: [String: MobileRelayClient] = [:]
    private var cursors: [String: Int] = [:]
    private var replay: [String: MobileReplayWindow] = [:]
    private var activities: [MobileActivity] = []
    private var seenEvents = Set<String>()
    private var eventOrder: [String] = []
    private var notify = false
    private var forceSnapshot = false
    private var cycles = 0
    private var generation = 0
    private var enrollmentDeadline: Date?
    private var book = MobileApprovalBook()
    private var requests: [String: URL] = [:]
    private var modified = Set<String>()
    private let folder = Support.file("Mobile")

    init() {
        do {
            if let data = try MobileKeychain.read("mac-setup"), let saved = try? JSONDecoder().decode(Saved.self, from:data) {
                relayURL = saved.relay; adminToken = saved.admin; peers = saved.peers.filter(\.approved)
                if let raw = Data(base64Encoded:saved.key) { key = try P256.KeyAgreement.PrivateKey(rawRepresentation:raw) }
            }
        } catch { status = localized("Could not load mobile keys") }
    }
    private func save() throws {
        try MobileKeychain.write(JSONEncoder().encode(Saved(relay:relayURL,admin:adminToken,key:key.rawRepresentation.base64EncodedString(),peers:peers.filter(\.approved))),account:"mac-setup")
    }
    func start() {
        stop(); guard !adminToken.isEmpty else { status=localized("Enter relay URL and access key"); return }
        do { _ = try MobileRelayClient.baseURL(relayURL); try save() } catch { status=localized("Mobile setup is invalid"); return }
        enabled=true; let stamp=generation; status=localized("Connecting to mobile relay…")
        task=Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await self.cycle(stamp); guard stamp==generation else { return }; self.status=localized("Mobile link connected") }
                catch { guard stamp==generation else { return }; self.status=localized("Mobile link disconnected; retrying"); self.clients.removeAll(); self.cursors.removeAll() }
                try? await Task.sleep(for:.seconds(2))
            }
        }
    }
    func stop() {
        generation+=1; task?.cancel(); task=nil; enabled=false; clients.removeAll(); cursors.removeAll(); replay.removeAll()
        pairingText=""; pendingPeer=nil; peers.removeAll { !$0.approved }; enrollmentDeadline=nil
        requests.removeAll(); modified.removeAll()
        try? FileManager.default.removeItem(at:folder.appendingPathComponent("enabled"))
        book = MobileApprovalBook(); approvalRequests=[]
    }
    private func client(_ peer: Peer) async throws -> MobileRelayClient {
        if let existing=clients[peer.id] { return existing }
        let c=try MobileRelayClient(relay:relayURL,room:peer.id,token:peer.token,role:"mac")
        try await c.create(admin:adminToken,phoneToken:peer.phoneToken); clients[peer.id]=c; return c
    }
    func pair() {
        guard enabled else { return }
        let random: () -> String = { (0..<32).map { _ in UInt8.random(in:0...255) }.withUnsafeBytes { Data($0) }.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") }
        let peer=Peer(id:random(),name:"",token:random(),phoneToken:random())
        Task {
            do {
                _ = try await client(peer); peers.removeAll { !$0.approved }; peers.append(peer)
                enrollmentDeadline=Date().addingTimeInterval(120)
                pairingText=MobilePairing(relay:relayURL,room:peer.id,token:peer.phoneToken,macKey:key.publicKey.x963Representation.base64EncodedString()).text
            } catch { status=localized("Could not create pairing") }
        }
    }
    func approvePair() {
        guard let peer=pendingPeer, let index=peers.firstIndex(where:{$0.id==peer.id}),
              enrollmentDeadline.map({$0>Date()}) == true else { return }
        peers[index]=peer; peers[index].approved=true
        do { try save(); pendingPeer=nil; pairingText=""; enrollmentDeadline=nil; forceSnapshot=true }
        catch { peers[index].approved=false; status=localized("Could not save mobile keys") }
    }
    func revoke(_ peer: Peer) {
        let c=clients[peer.id]; peers.removeAll{$0.id==peer.id}; clients[peer.id]=nil
        try? save(); Task { try? await c?.revoke() }
    }
    func ingest(_ event: AgentEvent) {
        guard enabled, !seenEvents.contains(event.eventID), event.timestamp > Date().addingTimeInterval(-300) else { return }
        seenEvents.insert(event.eventID); eventOrder.append(event.eventID)
        if eventOrder.count>2000 { seenEvents.remove(eventOrder.removeFirst()) }
        let state: String
        switch event.kind {
        case .working: state="working"
        case .waiting: state="waiting"
        case .turnCompleted: state="finished"
        case .failed: state="error"
        case .disconnected: state="offline"
        case .sessionEnded: state="ended"
        default: state="idle"
        }
        activities.append(MobileActivity(id:event.eventID,session:event.sessionID,source:event.source.rawValue,state:state,
            operation:event.operation ?? "",project:event.projectPath.map{URL(fileURLWithPath:$0).lastPathComponent} ?? "",
            timestamp:Int64(event.timestamp.timeIntervalSince1970*1000)))
        activities=Array(activities.suffix(60)); forceSnapshot=true
        if ["waiting","finished","error"].contains(state) { notify=true }
    }
    private func send(_ message: MobileMessage, peer: Peer, notify: Bool=false) async throws {
        guard let publicKey=peer.key.flatMap({Data(base64Encoded:$0)}) else { throw MobileFailure.untrusted }
        let envelope=try MobileCrypto.seal(message,room:peer.id,sender:key,recipient:publicKey)
        let latest=Dictionary(activities.map { ($0.source+":"+$0.session,$0) },uniquingKeysWith: { $1 })
        let live=message.type=="snapshot" ? RelayLiveState(working:latest.values.filter { $0.state=="working" }.count,waiting:approvalRequests.count):nil
        try await client(peer).send(envelope,notify:notify,live:live)
    }
    private func cycle(_ stamp: Int) async throws {
        guard enabled, stamp==generation else { return }
        if let deadline=enrollmentDeadline, deadline<Date() {
            for peer in peers where !peer.approved { revoke(peer) }
            pairingText=""; pendingPeer=nil; enrollmentDeadline=nil
        }
        try await scanApprovals()
        cycles+=1
        let pending=await book.pending()
        approvalRequests=pending
        let snapshot=MobileMessage(type:"snapshot",activities:Array(activities.suffix(20)),approvals:Array(pending.prefix(1)))
        let shouldSend=forceSnapshot || cycles%10==0
        for peer in peers {
            let c=try await client(peer)
            let batch=try await c.poll(after:cursors[peer.id] ?? 0)
            guard enabled, stamp==generation, !Task.isCancelled else { throw MobileFailure.resolved }
            for envelope in batch.messages {
                do {
                    let message=try MobileCrypto.open(envelope,room:peer.id,recipient:key,trustedSender:peer.key.flatMap{Data(base64Encoded:$0)})
                    var window=replay[peer.id] ?? MobileReplayWindow(); try window.claim(envelope); replay[peer.id]=window
                    if !peer.approved, message.type=="hello", pendingPeer==nil, enrollmentDeadline.map({$0>Date()}) == true,
                       let name=message.name, name.utf8.count<=120,
                       let approvalKey=message.approvalKey, let raw=Data(base64Encoded:approvalKey), raw.count==65 {
                        _ = try P256.Signing.PublicKey(x963Representation:raw)
                        var proposed=peer; proposed.name=name; proposed.key=envelope.senderKey; proposed.approvalKey=approvalKey
                        pendingPeer=proposed
                    } else if peer.approved, message.type=="decision", let decision=message.decision,
                              let signingKey=peer.approvalKey.flatMap({Data(base64Encoded:$0)}) {
                        do {
                            let request=try await book.consume(decision,room:peer.id,publicKey:signingKey)
                            guard enabled, stamp==generation, peers.contains(where: { $0.id==peer.id && $0.approved && $0.key==peer.key }) else { throw MobileFailure.untrusted }
                            guard let file=requests.removeValue(forKey:request.id), FileManager.default.fileExists(atPath:file.path) else { throw MobileFailure.resolved }
                            let response=["id":request.id,"digest":request.digest,"action":decision.action]
                            let output=file.deletingPathExtension().appendingPathExtension("response")
                            try JSONEncoder().encode(response).write(to:output,options:.atomic)
                            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:output.path)
                            forceSnapshot=true
                            try await send(MobileMessage(type:"result",result:decision.action,requestID:request.id),peer:peer)
                        } catch { try? await send(MobileMessage(type:"result",result:"expired_or_resolved",requestID:decision.requestID),peer:peer) }
                    }
                } catch { continue } // Never log payloads or keys.
            }
            cursors[peer.id]=batch.cursor
            if peer.approved && shouldSend { try await send(snapshot,peer:peer,notify:notify) }
        }
        if shouldSend { forceSnapshot=false; notify=false }
    }
    private func scanApprovals() async throws {
        let manager=FileManager.default
        try manager.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        // Only a running, enabled app publishes this heartbeat. Hooks fail back to the terminal otherwise.
        if peers.contains(where: { $0.approved }) {
            try Data(String(Date().timeIntervalSince1970).utf8).write(to:folder.appendingPathComponent("enabled"),options:.atomic)
        } else { try? manager.removeItem(at:folder.appendingPathComponent("enabled")) }
        let requestFolder=folder.appendingPathComponent("requests")
        try manager.createDirectory(at:requestFolder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        for file in (try? manager.contentsOfDirectory(at:requestFolder,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])) ?? [] where file.pathExtension=="json" {
            let id=file.deletingPathExtension().lastPathComponent
            guard UUID(uuidString:id) != nil, !modified.contains(id) else { continue }
            let attrs=try file.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
            guard attrs.isRegularFile==true, attrs.isSymbolicLink != true, (attrs.fileSize ?? Int.max)<32000 else { continue }
            let request=try JSONDecoder().decode(MobileApproval.self,from:Data(contentsOf:file))
            guard request.id==id, request.expiresAt>Int64(Date().timeIntervalSince1970*1000),
                  request.digest==MobileCrypto.fingerprint(Data(request.context.utf8)) else { continue }
            try await book.insert(request); requests[id]=file; modified.insert(id); forceSnapshot=true; notify=true
        }
        let live=Set(await book.pending().map(\.id))
        for id in requests.keys where !live.contains(id) || !manager.fileExists(atPath:requests[id]!.path) { requests[id]=nil; await book.cancel(id); forceSnapshot=true }
        if modified.count>4096 { modified=Set(requests.keys) }
    }

    func decideLocally(_ approval: MobileApproval, action: String) {
        guard ["allow","deny"].contains(action), enabled else { return }
        let stamp=generation
        Task {
            do {
                let current=try await book.consumeLocally(approval.id)
                guard enabled, stamp==generation, let file=requests.removeValue(forKey:current.id) else { return }
                let output=file.deletingPathExtension().appendingPathExtension("response")
                try JSONEncoder().encode(["id":current.id,"digest":current.digest,"action":action]).write(to:output,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:output.path)
                approvalRequests.removeAll { $0.id==current.id }; forceSnapshot=true
            } catch { status=localized("Request expired or already resolved") }
        }
    }
}
