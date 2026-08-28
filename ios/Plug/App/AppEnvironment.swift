import Foundation

enum AppEnvironment {
    case local
    case localNetwork
    case staging

    var baseURL: URL {
        switch self {
        case .local:
            URL(string: "http://127.0.0.1:8080")!
        case .localNetwork:
            URL(string: "http://192.168.1.100:8080")!
        case .staging:
            URL(string: "https://staging-api.example.com")!
        }
    }
}
