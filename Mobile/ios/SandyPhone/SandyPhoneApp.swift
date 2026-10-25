import SwiftUI
import UserNotifications
import SandyMobileCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,didRegisterForRemoteNotificationsWithDeviceToken deviceToken:Data) {
        Task { @MainActor in PhoneStore.shared.registerPush(deviceToken) }
    }
}
@main struct SandyPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store=PhoneStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var scanner=false
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section {
                        Label(store.status,systemImage:store.connected ? "lock.shield.fill":"wifi.slash")
                        if !store.fingerprint.isEmpty { Text(store.fingerprint).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    if store.room == nil {
                        Section("Pair with your Mac") {
                            TextEditor(text:$store.pairingText).frame(minHeight:100).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Scan QR code") { scanner=true }
                            Button("Connect",action:store.pair)
                        }
                    } else {
                        Section("Requests for your approval") {
                            if store.approvals.isEmpty { Text("No pending actions") }
                            ForEach(store.approvals) { approval in
                                VStack(alignment:.leading,spacing:10) {
                                    Text("\(approval.source) · \(approval.tool)").font(.headline)
                                    Text(approval.context).font(.caption.monospaced()).textSelection(.enabled)
                                    Text(Date(timeIntervalSince1970:Double(approval.expiresAt)/1000),style:.relative).font(.caption)
                                    HStack {
                                        Button("Allow once") { store.decide(approval,action:"allow") }.buttonStyle(.borderedProminent)
                                        Button("Deny",role:.destructive) { store.decide(approval,action:"deny") }.buttonStyle(.bordered)
                                    }.disabled(store.busy)
                                }
                            }
                        }
                        Section("Agent activity") {
                            ForEach(store.activities.reversed()) { activity in
                                VStack(alignment:.leading,spacing:4) {
                                    Text("\(activity.source) · \(activity.project)").font(.headline)
                                    Text(activity.operation.isEmpty ? activity.state : activity.operation)
                                    Text("\(activity.state) · \(Date(timeIntervalSince1970:Double(activity.timestamp)/1000).formatted(date:.omitted,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Section {
                            Button("Enable notifications",action:store.enableNotifications)
                            Button("Show on Lock Screen") { store.startLiveStatus() }
                            Button("Unpair",role:.destructive,action:store.unpair)
                        }
                    }
                }.navigationTitle("Sandy").sheet(isPresented:$scanner) { PairingScanner { store.pairingText=$0; scanner=false; store.pair() } }
            }.onAppear { store.resume() }.onChange(of:scenePhase) { _, phase in phase == .active ? store.resume() : store.pause() }
        }
    }
}
