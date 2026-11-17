import Foundation

enum TetherlineError: LocalizedError, Equatable {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
