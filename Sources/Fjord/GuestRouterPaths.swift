import Foundation

/// Guest-owned Router paths. These are built from guest.account.home as strings; host path APIs never touch them.
struct GuestRouterPaths: Equatable, Sendable {
    let home: String
    let root: String
    let forms: String
    let plugin: String
    let key: String
    let presence: String
    let inbox: String
    let claudeDir: String
    let registry: String
    let projects: String
    let settings: String
    let hook: String
    let formModule: String

    init(home: String) throws {
        guard home.hasPrefix("/"), !home.contains("\0") else { throw GuestClientFailure.invalidPath(home) }
        self.home = home
        root = Self.join(home, ".local/share/fjord/router")
        forms = Self.join(root, "forms")
        plugin = Self.join(root, AppIdentity.isDevelopment() ? "plugin-dev" : "plugin")
        key = Self.join(root, "relay.key")
        presence = Self.join(root, "presence")
        inbox = Self.join(root, "relay")
        claudeDir = Self.join(home, ".claude")
        registry = Self.join(claudeDir, "sessions")
        projects = Self.join(claudeDir, "projects")
        settings = Self.join(claudeDir, "settings.json")
        hook = Self.join(root, FormHookInstaller.scriptName(development: AppIdentity.isDevelopment()))
        formModule = Self.join(root, "form-hook.mjs")
    }

    static func join(_ root: String, _ child: String) -> String {
        root == "/" ? "/" + child : root.hasSuffix("/") ? root + child : root + "/" + child
    }
}
