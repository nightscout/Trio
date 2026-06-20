import Foundation

enum OrefFunctionResult {
    case success(RawJSON)
    case failure(Error)

    func returnOrThrow() throws -> RawJSON {
        switch self {
        case let .success(json): return json
        case let .failure(error): throw error
        }
    }
}
