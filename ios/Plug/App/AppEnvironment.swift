import Foundation

struct AppEnvironment {
    let baseURL: URL?

    /// The Phase 2 preview stays off unless explicitly enabled for the matching backend.
    var requestsEnabled: Bool {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "PlugRequestsV2Enabled") as? String
        #if DEBUG
        let value = ProcessInfo.processInfo.environment["PLUG_REQUESTS_V2_ENABLED"] ?? bundled
        #else
        let value = bundled
        #endif
        return ["YES", "TRUE", "1"].contains(value?.uppercased() ?? "")
    }

    static let local = AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8080"))

    static var configured: AppEnvironment {
        let runtime = ProcessInfo.processInfo.environment["PLUG_API_URL"]
        let bundled = Bundle.main.object(forInfoDictionaryKey: "PlugAPIURL") as? String
        #if DEBUG && !targetEnvironment(simulator)
        // A phone launched from the home screen has no scheme environment. A current
        // embedded development address also supersedes a stale open Xcode scheme.
        let development = Bundle.main.object(forInfoDictionaryKey: "PlugDevelopmentAPIURL") as? String
        #else
        let development: String? = nil
        #endif
        let setting = preferredAPISetting(development: development, runtime: runtime, bundled: bundled)
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

    static func preferredAPISetting(development: String?, runtime: String?, bundled: String?) -> String? {
        [development, runtime, bundled].compactMap { value -> String? in
            guard let value, !value.isEmpty, !value.contains("$(") else { return nil }
            return value
        }.first
    }
}
