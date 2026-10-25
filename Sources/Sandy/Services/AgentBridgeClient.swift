import Foundation
import Darwin

@MainActor
protocol AgentBridgeRunning: AnyObject {
    var onData: ((Data) -> Void)? { get set }
    var onExit: ((Int32) -> Void)? { get set }
    func start(arguments: [String]) throws
    func stop()
}

/// The monitor owns its pipes. Read them off the UI thread, preserving stdout
/// order through EOF before reporting termination. Stale generations cannot
/// deliver bytes or an exit into a replacement connection.
@MainActor
final class AgentBridgeClient: AgentBridgeRunning {
    enum LaunchError: Error { case missingHelper }

    static var bundledExecutable: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sandy-agent")
    }

    var onData: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?
    private let executable: URL
    private var process: Process?
    private var generation = 0

    init(executable: URL = AgentBridgeClient.bundledExecutable) {
        self.executable = executable
    }

    func start(arguments: [String]) throws {
        stop()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw LaunchError.missingHelper
        }
        let child = Process()
        let output = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        // Diagnostics may include provider data. They never enter history or
        // the UI; the process exit is represented by a fixed localized notice.
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child
        let stamp = generation
        Task.detached(priority: .utility) { [weak self] in
            let handle = output.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                await self?.deliver(data, generation: stamp)
            }
            child.waitUntilExit()
            try? handle.close()
            await self?.exited(child.terminationStatus, generation: stamp)
        }
    }

    func stop() {
        generation += 1
        if let child = process, child.isRunning {
            child.terminate()
            // A wedged helper must not survive a disabled source or app exit.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil
    }

    private func deliver(_ data: Data, generation stamp: Int) {
        guard stamp == generation else { return }
        onData?(data)
    }

    private func exited(_ code: Int32, generation stamp: Int) {
        guard stamp == generation else { return }
        process = nil
        onExit?(code)
    }
}
