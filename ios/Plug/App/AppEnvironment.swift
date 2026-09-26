import Foundation

struct AppEnvironment {
    let baseURL: URL?
    /// Where the public Terms and Privacy Policy pages live. Person Two owns those routes
    /// in /web; the host is configured rather than compiled in, because there is no
    /// production domain yet and a placeholder would read like a decision.
    var webBaseURL: URL?

    static let local = AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8080"),
                                      webBaseURL: URL(string: "http://localhost:3000"))

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
        guard let setting, !setting.isEmpty else { return AppEnvironment(baseURL: nil, webBaseURL: nil) }
        #endif
        guard let url = URL(string: setting), let scheme = url.scheme, url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return AppEnvironment(baseURL: nil, webBaseURL: nil) }
        #if DEBUG
        guard ["http", "https"].contains(scheme) else { return AppEnvironment(baseURL: nil, webBaseURL: nil) }
        #else
        guard scheme == "https" else { return AppEnvironment(baseURL: nil, webBaseURL: nil) }
        #endif
        return AppEnvironment(baseURL: url, webBaseURL: configuredWebURL())
    }

    static func preferredAPISetting(development: String?, runtime: String?, bundled: String?) -> String? {
        [development, runtime, bundled].compactMap { value -> String? in
            guard let value, !value.isEmpty, !value.contains("$(") else { return nil }
            return value
        }.first
    }

    /// Held to the same rules as the API URL: no credentials, no query, no fragment, and
    /// https outside a debug build. A consent link is the one place the app sends someone
    /// away from itself, so it must not be pointable at anything by configuration alone.
    private static func configuredWebURL() -> URL? {
        let setting = ProcessInfo.processInfo.environment["PLUG_WEB_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "PlugWebURL") as? String
        guard let setting, !setting.isEmpty, let url = URL(string: setting), let scheme = url.scheme,
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        #if DEBUG
        return ["http", "https"].contains(scheme) ? url : nil
        #else
        return scheme == "https" ? url : nil
        #endif
    }
}
