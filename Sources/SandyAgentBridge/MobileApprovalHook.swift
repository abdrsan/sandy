import Darwin
import Foundation
import SandyMobileCore

/// Separate from passive hooks. No output on failure/timeout: Claude retains its
/// normal permission prompt. Never emits permanent allow rules or rewritten input.
func runMobileApproval() {
    signal(SIGALRM) { _ in _exit(0) }; alarm(3)
    var input=Data()
    while let data=try? FileHandle.standardInput.read(upToCount:32768), !data.isEmpty {
        guard input.count+data.count<=1_000_000 else { return }; input.append(data)
    }
    alarm(0)
    guard let payload=(try? JSONSerialization.jsonObject(with:input)) as? [String:Any],
          payload["hook_event_name"] as? String == "PermissionRequest",
          let tool=payload["tool_name"] as? String, let session=payload["session_id"] as? String,
          let arguments=payload["tool_input"] as? [String:Any] else { return }
    let root=ProcessInfo.processInfo.environment["SANDY_MOBILE_DIR"].map{URL(fileURLWithPath:$0)} ??
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sandy/Mobile")
    guard let heartbeat=try? String(contentsOf:root.appendingPathComponent("enabled"),encoding:.utf8),
          let time=Double(heartbeat), abs(Date().timeIntervalSince1970-time)<8 else { return }
    let context: [String:Any] = ["tool":tool,"input":arguments,"cwd":payload["cwd"] as? String ?? "","session":session]
    guard let data=try? JSONSerialization.data(withJSONObject:context,options:[.sortedKeys,.withoutEscapingSlashes]),
          data.count<24000, let text=String(data:data,encoding:.utf8) else { return }
    let approval=MobileApproval(source:"claude",session:session,tool:tool,context:text)
    let folder=root.appendingPathComponent("requests")
    let file=folder.appendingPathComponent(approval.id+".json")
    let response=folder.appendingPathComponent(approval.id+".response")
    do {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        // No .withoutOverwriting: combined with .atomic it is a fatal error on
        // this Foundation — and the id is a UUID, so there is nothing to lose.
        try JSONEncoder().encode(approval).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    } catch { return }
    defer { try? FileManager.default.removeItem(at:file); try? FileManager.default.removeItem(at:response) }
    let deadline=ContinuousClock.now.advanced(by:.seconds(90))
    while ContinuousClock.now < deadline {
        if let data=try? Data(contentsOf:response), data.count<1024,
           let decision=(try? JSONSerialization.jsonObject(with:data)) as? [String:String],
           decision["id"]==approval.id, decision["digest"]==approval.digest,
           let action=decision["action"], ["allow","deny"].contains(action) {
            let result: [String:Any] = ["hookSpecificOutput":["hookEventName":"PermissionRequest","decision":["behavior":action]]]
            if let output=try? JSONSerialization.data(withJSONObject:result) { FileHandle.standardOutput.write(output+Data([10])) }
            return
        }
        guard let value=try? String(contentsOf:root.appendingPathComponent("enabled"),encoding:.utf8),
              let refreshed=Double(value), abs(Date().timeIntervalSince1970-refreshed)<8 else { return }
        Thread.sleep(forTimeInterval:0.2)
    }
}
