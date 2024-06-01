import Foundation
import JavaScriptCore

final class JavaScriptWorker {
    private let processQueue = DispatchQueue(label: "DispatchQueue.JavaScriptWorker", attributes: .concurrent)
    private let virtualMachine: JSVirtualMachine
    private var contextPool: [JSContext] = []
    private let contextPoolLock = NSLock()

    init(poolSize: Int = 5) {
        virtualMachine = JSVirtualMachine()!
        // Pre-create a pool of JSContext instances
        for _ in 0 ..< poolSize {
            contextPool.append(createContext())
        }
    }

    private func createContext() -> JSContext {
        let context = JSContext(virtualMachine: virtualMachine)!
        context.exceptionHandler = { _, exception in
            if let error = exception?.toString() {
                warning(.openAPS, "JavaScript Error: \(error)")
            }
        }
        let consoleLog: @convention(block) (String) -> Void = { message in
            debug(.openAPS, "JavaScript log: \(message)")
        }
        context.setObject(consoleLog, forKeyedSubscript: "_consoleLog" as NSString)
        return context
    }

    private func getContext() -> JSContext {
        contextPoolLock.lock()
        let context = contextPool.popLast() ?? createContext()
        contextPoolLock.unlock()
        return context
    }

    private func returnContext(_ context: JSContext) {
        contextPoolLock.lock()
        contextPool.append(context)
        contextPoolLock.unlock()
    }

    @discardableResult func evaluate(script: Script) -> JSValue! {
        evaluate(string: script.body)
    }

    private func evaluate(string: String) -> JSValue! {
        let context = getContext()
        defer { returnContext(context) }
        return context.evaluateScript(string)
    }

    private func json(for string: String) -> RawJSON {
        evaluate(string: "JSON.stringify(\(string), null, 4);")!.toString()!
    }

    func call(function: String, with arguments: [JSON]) -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")
        return json(for: "\(function)(\(joined))")
    }

    func inCommonContext<Value>(execute: (JavaScriptWorker) -> Value) -> Value {
        let context = getContext()
        defer { returnContext(context) }
        return execute(self)
    }

    func evaluateBatch(scripts: [Script]) {
        let ctx = getContext()
        defer { returnContext(ctx) } // Ensure the context is returned to the pool
        scripts.forEach { script in
            ctx.evaluateScript(script.body)
        }
    }
}
