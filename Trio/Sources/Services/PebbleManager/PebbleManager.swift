import Combine
import Foundation
import Swinject

protocol PebbleManager {
    func sendState(_ state: WatchState)
    var isEnabled: Bool { get set }
    var isRunning: Bool { get }
    func start()
    func stop()
}

final class BasePebbleManager: PebbleManager, Injectable {
    private let dataBridge = PebbleDataBridge()
    private let commandManager = PebbleCommandManager()
    private var apiServer: PebbleLocalAPIServer?

    @Persisted(key: "BasePebbleManager.isEnabled") var isEnabled: Bool = false {
        didSet {
            if isEnabled { start() } else { stop() }
        }
    }

    @Persisted(key: "BasePebbleManager.port") private var port: UInt16 = 8080

    private(set) var isRunning = false

    init(resolver: Resolver) {
        injectServices(resolver)
        if isEnabled { start() }
    }

    func start() {
        guard !isRunning else { return }
        let server = PebbleLocalAPIServer(dataBridge: dataBridge, commandManager: commandManager, port: port)
        apiServer = server
        server.start()
        isRunning = true
        debug(.service, "Pebble: integration started on port \(port)")
    }

    func stop() {
        apiServer?.stop()
        apiServer = nil
        isRunning = false
        debug(.service, "Pebble: integration stopped")
    }

    func sendState(_ state: WatchState) {
        guard isEnabled else { return }
        dataBridge.updateFromWatchState(state)
    }

    func getCommandManager() -> PebbleCommandManager {
        commandManager
    }

    func getCurrentPort() -> UInt16 {
        port
    }

    func setPort(_ newPort: UInt16) {
        guard newPort >= 1024, newPort <= 65535 else { return }
        port = newPort
        if isRunning { stop(); start() }
    }
}
