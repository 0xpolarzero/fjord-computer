import Foundation
import Testing
@testable import Lookout

@MainActor
@Suite struct AppNavigationTests {
    private let a = UUID(), b = UUID(), c = UUID()

    @Test func backAndForwardWalkTheHistory() {
        var h = NavigationHistory(.category(a))
        h.visit(.done)
        h.visit(.settings)
        #expect(h.current == .settings && h.canGoBack && !h.canGoForward)
        #expect(h.back() && h.current == .done)
        #expect(h.back() && h.current == .category(a))
        #expect(!h.back() && !h.canGoBack)
        #expect(h.forward() && h.forward() && h.current == .settings)
        let more = h.forward()
        #expect(!more)
    }

    @Test func goingSomewhereNewDropsTheForwardPlaces() {
        var h = NavigationHistory(.category(a))
        h.visit(.done)
        h.visit(.router)
        h.back()
        h.visit(.categories)
        #expect(!h.canGoForward)
        #expect(h.stack == [.category(a), .done, .categories])
    }

    @Test func visitingTheCurrentPlaceAddsNothing() {
        var h = NavigationHistory(.done)
        h.visit(.done)
        #expect(h.stack == [.done] && !h.canGoBack)
    }

    @Test func theNavigatorRemembersTheLastPlace() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppNavigationTests-\(UUID().uuidString)"))
        let first = AppNavigator(fallback: .router, defaults: defaults)
        #expect(first.selection == .router)
        first.go(.category(a))
        first.go(.settings)
        first.back()
        let second = AppNavigator(fallback: .done, defaults: defaults)
        #expect(second.selection == .category(a))
    }

    @Test func tokensRoundTrip() {
        for d in [AppDestination.category(a), .done, .router, .settings, .categories] {
            #expect(AppDestination(token: d.token) == d)
        }
        #expect(AppDestination(token: "category:nope") == nil)
        #expect(AppDestination(token: "?") == nil)
    }

    @Test func aPlaceThatIsGoneResolvesToTheFirstCategoryShown() {
        #expect(AppDestination.category(c).resolved(shown: [a, b], routerOn: true) == .category(a))
        #expect(AppDestination.category(b).resolved(shown: [a, b], routerOn: true) == .category(b))
        #expect(AppDestination.category(c).resolved(shown: [], routerOn: true) == .done)
        #expect(AppDestination.router.resolved(shown: [a], routerOn: false) == .category(a))
        #expect(AppDestination.settings.resolved(shown: [], routerOn: false) == .settings)
    }

    @Test func settlingReplacesGonePlacesInTheHistoryToo() throws {
        let nav = AppNavigator(start: .category(a), defaults: nil)
        nav.go(.category(c))
        nav.go(.settings)
        nav.go(.category(c))
        nav.settle(shown: [a, b], routerOn: true)
        #expect(nav.selection == .category(a))
        #expect(!nav.history.stack.contains(.category(c)))
        #expect(nav.history.stack == [.category(a), .settings, .category(a)])
    }

    @Test func theSidebarOrderIsCategoriesDoneRouterSettingsCategories() {
        #expect(AppDestination.all(shown: [a, b], routerOn: true) == [.category(a), .category(b), .done, .router, .settings, .categories])
        #expect(AppDestination.all(shown: [a], routerOn: false) == [.category(a), .done, .settings, .categories])
    }

    @Test func theGoMenuNumbersTheFirstNinePlaces() {
        let ids = (0..<8).map { _ in UUID() }
        let all = AppDestination.all(shown: ids, routerOn: true)   // 8 categories, Done, Router, Settings, Categories = 12
        let items = GoMenuModel.items(all) { $0.token }
        #expect(items.count == 12)
        #expect(items.prefix(9).map(\.key) == (1...9).map { String($0) })
        #expect(items.dropFirst(9).allSatisfy { $0.key == nil })
        #expect(GoMenuModel.destination(forShortcut: 1, in: all) == .category(ids[0]))
        #expect(GoMenuModel.destination(forShortcut: 9, in: all) == .done)
        #expect(GoMenuModel.destination(forShortcut: 0, in: all) == nil)
        #expect(GoMenuModel.destination(forShortcut: 10, in: all) == nil)
        #expect(GoMenuModel.destination(forShortcut: 3, in: [.done]) == nil)
    }

    @Test func theGoMenuItemsExistBeforeAnyWindow() throws {
        let item = GoMenu.shared.makeItem()
        let menu = try #require(item.submenu)
        let keys = menu.items.compactMap { $0.keyEquivalent.isEmpty ? nil : $0.keyEquivalent }
        #expect(keys == ["[", "]"] + (1...9).map { String($0) })
        let numbered = menu.items.filter { $0.tag > 0 }
        #expect(numbered.count == 9)
        #expect(numbered.allSatisfy { $0.isHidden })
    }
}
