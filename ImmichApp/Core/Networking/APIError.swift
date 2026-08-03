import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case unauthorized
    case decoding(Error)
    case server(status: Int, message: String?)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:      return String(localized: "Invalid server address.")
        case .notConnected:    return String(localized: "No internet connection.")
        case .unauthorized:    return String(localized: "Session expired, please sign in again.")
        case .decoding:        return String(localized: "Failed to read data from server.")
        case .server(_, let m):return m ?? String(localized: "A server error occurred.")
        case .unknown:         return String(localized: "An unknown error occurred.")
        }
    }
}
