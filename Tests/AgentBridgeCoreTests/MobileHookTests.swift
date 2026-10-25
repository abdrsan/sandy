import AgentBridgeCore
import Foundation
import Testing

@Suite struct MobileHookTests {
    @Test func mobileInstallerPreservesPassiveAndForeignHooks() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let file=dir.appendingPathComponent("settings.json")
        try Data(#"{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"other-helper"}]}]}}"#.utf8).write(to:file)
        let exe="/tmp/it's Sandy.app/Contents/Helpers/sandy-agent"
        _ = try ClaudeSettingsInstaller.install(settingsURL:file,executable:exe)
        let original=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
        _ = try ClaudeSettingsInstaller.mobileApprovals(settingsURL:file,executable:exe,install:true)
        let once=try Data(contentsOf:file)
        let again=try ClaudeSettingsInstaller.mobileApprovals(settingsURL:file,executable:exe,install:true)
        #expect(!again.changed)
        #expect(try Data(contentsOf:file)==once)
        #expect(String(data:once,encoding:.utf8)!.contains("mobile-approval"))
        _ = try ClaudeSettingsInstaller.mobileApprovals(settingsURL:file,executable:exe,install:false)
        let restored=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! NSDictionary
        #expect(restored.isEqual(to:original))
    }
    @Test func mobileInstallerPreservesMalformedSettings() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let raw=Data("broken".utf8);try raw.write(to:file);defer {try? FileManager.default.removeItem(at:file)}
        #expect(throws:(any Error).self) { try ClaudeSettingsInstaller.mobileApprovals(settingsURL:file,executable:"/tmp/sandy-agent",install:true) }
        #expect(try Data(contentsOf:file)==raw)
    }
    @Test func approvalHookFallsBackWithoutAnEnabledMac() throws {
        let result=try runHook(enabled:false)
        #expect(result.isEmpty)
    }
    @Test func approvalHookEmitsOnlyMatchingSingleUseDecision() throws {
        let result=try runHook(enabled:true)
        let object=try JSONSerialization.jsonObject(with:result) as! [String:Any]
        let hook=object["hookSpecificOutput"] as! [String:Any]
        #expect(hook["hookEventName"] as? String == "PermissionRequest")
        let decision=hook["decision"] as! [String:String]
        #expect(decision==["behavior":"deny"])
    }
    private func runHook(enabled:Bool) throws -> Data {
        var bin=URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<6 { if FileManager.default.isExecutableFile(atPath:bin.appendingPathComponent("sandy-agent").path) { break };bin.deleteLastPathComponent() }
        let helper=bin.appendingPathComponent("sandy-agent")
        #expect(FileManager.default.isExecutableFile(atPath:helper.path))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        if enabled {try Data(String(Date().timeIntervalSince1970).utf8).write(to:root.appendingPathComponent("enabled"))}
        let child=Process();child.executableURL=helper;child.arguments=["mobile-approval"]
        var env=ProcessInfo.processInfo.environment;env["SANDY_MOBILE_DIR"]=root.path;child.environment=env
        let input=Pipe(),output=Pipe();child.standardInput=input;child.standardOutput=output;child.standardError=FileHandle.nullDevice
        try child.run();defer {if child.isRunning {child.terminate()}}
        try input.fileHandleForWriting.write(contentsOf:Data(#"{"hook_event_name":"PermissionRequest","session_id":"test","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"printf test"}}"#.utf8))
        try input.fileHandleForWriting.close()
        if enabled {
            let deadline=Date().addingTimeInterval(4);var file:URL?
            while Date()<deadline && file==nil {
                file=(try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("requests"),includingPropertiesForKeys:nil))?.first{$0.pathExtension=="json"}
                if file==nil {Thread.sleep(forTimeInterval:0.03)}
            }
            let requestFile=try #require(file)
            let request=try JSONSerialization.jsonObject(with:Data(contentsOf:requestFile)) as! [String:Any]
            #expect((request["context"] as! String).contains("printf test"))
            let response=["id":request["id"] as! String,"digest":request["digest"] as! String,"action":"deny"]
            try JSONSerialization.data(withJSONObject:response).write(to:requestFile.deletingPathExtension().appendingPathExtension("response"),options:.atomic)
        }
        let end=Date().addingTimeInterval(3)
        while child.isRunning && Date()<end {Thread.sleep(forTimeInterval:0.03)}
        if child.isRunning {child.terminate()}
        child.waitUntilExit();#expect(child.terminationStatus==0)
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}
