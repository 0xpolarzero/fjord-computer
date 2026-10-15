import Foundation
import Testing
@testable import Fjord

/// Debug and E2E builds have plugin, marketplace, hook-script and sshConfigs names of their own, so they never re-point
/// what the installed app registered in Claude Code.
@Suite struct DevPluginNamesTests {
    @Test func installedAndDevelopmentNamesNeverCollide() {
        #expect(ClaudePlugin.pluginName(development: false) == "fjord")
        #expect(ClaudePlugin.pluginName(development: true) == "fjord-dev")
        #expect(ClaudePlugin.guestPluginName(development: false) == "fjord-guest")
        #expect(ClaudePlugin.guestPluginName(development: true) == "fjord-guest-dev")
        #expect(FormHookInstaller.scriptName(development: false) == "fjord-form.sh")
        #expect(FormHookInstaller.scriptName(development: true) == "fjord-dev-form.sh")
        #expect(ClaudeSSHSettings.entryID(deviceId: nil, computerId: "c", development: false) == "fjord-local-c")
        #expect(ClaudeSSHSettings.entryID(deviceId: nil, computerId: "c", development: true) == "fjord-dev-local-c")
    }

    @Test func marketplacesCarryTheirBuildsNames() {
        #expect(ClaudePlugin.marketplaceJSON(development: false) == ClaudePlugin.marketplaceTemplate)
        let dev = ClaudePlugin.marketplaceJSON(development: true)
        #expect(dev.contains("\"name\": \"fjord-dev\"") && !dev.contains("\"name\": \"fjord\""))
        let guest = ClaudePlugin.guestMarketplaceJSON(development: true)
        #expect(guest.contains("\"name\": \"fjord-guest-dev\"") && !guest.contains("\"name\": \"fjord\""))
        #expect(ClaudePlugin.guestMarketplaceJSON(development: false).contains("\"name\": \"fjord-guest\""))
    }

    @Test func thisTestBuildIsDevelopment() {
        #expect(AppIdentity.isDevelopment())
        #expect(ClaudePlugin.id == "fjord-dev@fjord-dev" && ClaudePlugin.guestID == "fjord-guest-dev@fjord-guest-dev")
        let paths = try? GuestRouterPaths(home: "/home/a")
        #expect(paths?.hook.hasSuffix("/fjord-dev-form.sh") == true && paths?.plugin.hasSuffix("/plugin-dev") == true)
    }
}
