import SwiftUI
import CoreImage.CIFilterBuiltins
import SandyMobileCore

struct MobileSettingsPane: View {
    @ObservedObject private var store = MobileLinkStore.shared
    @ObservedObject var agents: AgentMonitorStore
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Label(localized("Phone Access"),systemImage:"iphone.and.arrow.forward").font(.system(size:11,weight:.semibold))
            TextField(localized("HTTPS relay URL"),text:$store.relayURL).disabled(store.enabled)
            SecureField(localized("Relay access key"),text:$store.adminToken).disabled(store.enabled)
            HStack {
                Button(localized(store.enabled ? "Disconnect Phone Link" : "Connect Phone Link")) { store.enabled ? store.stop() : store.start() }
                if store.enabled { Button(localized("Pair Phone")) { store.pair() } }
            }
            if !store.status.isEmpty { Text(store.status).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true) }
            if !store.pairingText.isEmpty {
                if let image=qr(store.pairingText) { Image(nsImage:image).interpolation(.none).resizable().frame(width:150,height:150).background(.white) }
                Button(localized("Copy Pairing Code")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.pairingText,forType:.string) }
                Text(localized("Pairing expires in two minutes. Keep this code private.")).foregroundStyle(Theme.tertiary).fixedSize(horizontal:false,vertical:true)
            }
            if let peer=store.pendingPeer {
                Text(peer.name).fontWeight(.semibold)
                if let data=peer.key.flatMap({Data(base64Encoded:$0)}) { Text(MobileCrypto.fingerprint(data)).textSelection(.enabled).lineLimit(3) }
                Text(localized("Compare the fingerprint on your phone before allowing it.")).fixedSize(horizontal:false,vertical:true)
                Button(localized("Trust This Phone")) { store.approvePair() }
            }
            ForEach(store.peers.filter(\.approved)) { peer in
                HStack { Text(peer.name); Spacer(); Button(localized("Revoke Phone")) { store.revoke(peer) } }
            }
            if store.peers.contains(where: { $0.approved }) {
                Button(localized("Install Mobile Approvals")) { agents.installMobileApprovals() }
            }
            Button(localized("Remove Mobile Approvals")) { agents.uninstallMobileApprovals() }
        }.font(.system(size:11)).padding(8).background(RoundedRectangle(cornerRadius:10).fill(Theme.surface))
    }
    private func qr(_ text: String) -> NSImage? {
        let filter=CIFilter.qrCodeGenerator(); filter.message=Data(text.utf8)
        guard let image=filter.outputImage?.transformed(by:CGAffineTransform(scaleX:5,y:5)),
              let cg=CIContext().createCGImage(image,from:image.extent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
    }
}
