import CryptoKit
import Foundation
import Testing
@testable import SandyMobileCore

@Suite struct MobileSecurityTests {
    @Test func authenticatedEncryptionRejectsTamperAndWrongPeer() throws {
        let mac = P256.KeyAgreement.PrivateKey(), phone = P256.KeyAgreement.PrivateKey(), stranger = P256.KeyAgreement.PrivateKey()
        var envelope = try MobileCrypto.seal(MobileMessage(type:"hello",name:"Phone"),room:"room",sender:phone,recipient:mac.publicKey.x963Representation)
        #expect(try MobileCrypto.open(envelope,room:"room",recipient:mac,trustedSender:phone.publicKey.x963Representation).name == "Phone")
        #expect(throws: (any Error).self) { try MobileCrypto.open(envelope,room:"other",recipient:mac,trustedSender:nil) }
        #expect(throws: (any Error).self) { try MobileCrypto.open(envelope,room:"room",recipient:mac,trustedSender:stranger.publicKey.x963Representation) }
        envelope.id = UUID().uuidString
        #expect(throws: (any Error).self) { try MobileCrypto.open(envelope,room:"room",recipient:mac,trustedSender:nil) }
    }
    @Test func staleAndDuplicateEnvelopesAreRefused() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let envelope = try MobileCrypto.seal(MobileMessage(type:"hello"),room:"r",sender:key,recipient:key.publicKey.x963Representation)
        var replay = MobileReplayWindow(); try replay.claim(envelope)
        #expect(throws: MobileFailure.self) { try replay.claim(envelope) }
        #expect(throws: (any Error).self) { try MobileCrypto.open(envelope,room:"r",recipient:key,trustedSender:nil,now:Date().addingTimeInterval(121)) }
    }
    @Test func oneDecisionCannotApproveTwoIdenticalCommands() async throws {
        let key = P256.Signing.PrivateKey(); let book = MobileApprovalBook()
        let first = MobileApproval(source:"claude",session:"s",tool:"Bash",context:"{\"command\":\"pwd\"}")
        let second = MobileApproval(source:"claude",session:"s",tool:"Bash",context:first.context)
        try await book.insert(first); try await book.insert(second)
        let signature = try key.signature(for:first.signingData(room:"r",action:"allow")).derRepresentation.base64EncodedString()
        let decision = MobileDecision(requestID:first.id,digest:first.digest,challenge:first.challenge,action:"allow",signature:signature)
        _ = try await book.consume(decision,room:"r",publicKey:key.publicKey.x963Representation)
        await #expect(throws: (any Error).self) { try await book.consume(decision,room:"r",publicKey:key.publicKey.x963Representation) }
        #expect(await book.pending().map(\.id) == [second.id])
    }
    @Test func wrongRoomExpiryAndChangedActionAreRefused() async throws {
        let key = P256.Signing.PrivateKey(); let book = MobileApprovalBook()
        let request = MobileApproval(source:"claude",session:"s",tool:"Bash",context:"pwd")
        try await book.insert(request)
        let signature = try key.signature(for:request.signingData(room:"r",action:"deny")).derRepresentation.base64EncodedString()
        var decision = MobileDecision(requestID:request.id,digest:request.digest,challenge:request.challenge,action:"allow",signature:signature)
        await #expect(throws: (any Error).self) { try await book.consume(decision,room:"r",publicKey:key.publicKey.x963Representation) }
        decision.action = "deny"
        await #expect(throws: (any Error).self) { try await book.consume(decision,room:"wrong",publicKey:key.publicKey.x963Representation) }
        await #expect(throws: (any Error).self) { try await book.consume(decision,room:"r",publicKey:key.publicKey.x963Representation,now:Date().addingTimeInterval(91)) }
    }
    @Test func pairingRejectsPlainHTTPAndMalformedKeys() {
        #expect(throws: (any Error).self) { try MobilePairing.parse("{}") }
        #expect(throws: (any Error).self) { try MobileRelayClient.baseURL("http://localhost:8787") }
        #expect(throws: (any Error).self) { try MobileRelayClient.baseURL("https://user:secret@example.com") }
    }
}
