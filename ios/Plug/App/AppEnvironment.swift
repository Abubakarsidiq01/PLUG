import Foundation

struct AppEnvironment {
    let baseURL: URL?

    static let local = AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8080"))

    static var configured: AppEnvironment {
        let setting = ProcessInfo.processInfo.environment["PLUG_API_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "PlugAPIURL") as? String
        #if DEBUG
        guard let setting, !setting.isEmpty else { return .local }
        #else
        guard let setting, !setting.isEmpty else { return AppEnvironment(baseURL: nil) }
        #endif
        guard let url = URL(string: setting), let scheme = url.scheme, url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return AppEnvironment(baseURL: nil) }
        #if DEBUG
        guard ["http", "https"].contains(scheme) else { return AppEnvironment(baseURL: nil) }
        #else
        guard scheme == "https" else { return AppEnvironment(baseURL: nil) }
        #endif
        return AppEnvironment(baseURL: url)
    }
}
