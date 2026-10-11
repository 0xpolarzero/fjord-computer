import Foundation
import Testing
@testable import Lookout

/// The bar's sections: every inbox starts with GitHub's holding every category; a category in none, or in one deleted, is
/// in the first; the bar and the shown order go section by section.
@MainActor @Suite struct CategorySections {
    /// A store that never saves (a test must not reach the saved state).
    private func quiet() -> Store {
        let store = Store()
        store.persists = false
        return store
    }

    private func category(_ name: String, section: UUID? = nil, hidden: Bool = false) -> InboxCategory {
        var c = InboxCategory(name: name, symbol: "tray", color: .blue)
        c.section = section
        c.hidden = hidden
        return c
    }

    @Test func everyInboxStartsWithGitHubsSectionHoldingEveryCategory() {
        let store = quiet()
        store.categories = [category("Mine"), category("Reviews")]
        #expect(store.categorySections == [.github])
        #expect(store.barSections.map(\.section) == [.github])
        #expect(store.barSections.first?.categories.map(\.name) == ["Mine", "Reviews"])
    }

    @Test func theBarAndTheShownOrderGoSectionBySection() {
        let store = quiet()
        let work = store.createSection(name: "Work")
        store.categories = [category("CI", section: work.id), category("Mine"), category("Hidden", section: work.id, hidden: true),
                            category("Reviews")]
        #expect(store.barSections.map(\.section?.name) == ["GitHub", "Work"])
        #expect(store.shownCategories.map(\.name) == ["Mine", "Reviews", "CI"])
        // The order things are matched in is the categories' own.
        #expect(store.categories.map(\.name) == ["CI", "Mine", "Hidden", "Reviews"])
    }

    @Test func aSectionWithNothingShownHasNoWell() {
        let store = quiet()
        _ = store.createSection(name: "Empty")
        store.categories = [category("Mine")]
        #expect(store.barSections.map(\.section?.name) == ["GitHub"])
    }

    @Test func deletingASectionMovesItsCategoriesToTheFirstLeft() {
        let store = quiet()
        let work = store.createSection(name: "Work")
        store.categories = [category("Mine"), category("CI", section: work.id)]
        store.deleteSection(work.id)
        #expect(store.barSections.map(\.section?.name) == ["GitHub"])
        #expect(store.barSections.first?.categories.map(\.name) == ["Mine", "CI"])
        // The last one gone: the categories alone, no well.
        store.deleteSection(CategorySection.github.id)
        #expect(store.barSections.count == 1 && store.barSections[0].section == nil)
        #expect(store.barSections[0].categories.map(\.name) == ["Mine", "CI"])
    }

    @Test func reorderingSectionsKeepsEachCategoryWhereItWas() {
        let store = quiet()
        let work = store.createSection(name: "Work")
        store.categories = [category("Mine"), category("CI", section: work.id)]
        store.moveSection(work.id, by: -1)
        #expect(store.barSections.map(\.section?.name) == ["Work", "GitHub"])
        #expect(store.barSections.map { $0.categories.map(\.name) } == [["CI"], ["Mine"]])
    }

    @Test func draggingACategoryOntoAnotherTakesItsPlaceInItsSection() {
        let store = quiet()
        let work = store.createSection(name: "Work")
        store.categories = [category("Mine"), category("Reviews"), category("CI", section: work.id), category("Deps", section: work.id)]
        // Onto Deps, in Work: Mine takes its place there; the list reads as the tree, top to bottom.
        store.moveCategory(store.categories[0].id, onto: store.categories[3].id)
        #expect(store.barSections.map { $0.categories.map(\.name) } == [["Reviews"], ["CI", "Deps", "Mine"]])
        #expect(store.categories.map(\.name) == ["Reviews", "CI", "Deps", "Mine"])
        // Onto a section's header: its top.
        let deps = store.categories.first { $0.name == "Deps" }!.id
        store.moveCategory(deps, toTopOf: CategorySection.github.id)
        #expect(store.categories.map(\.name) == ["Deps", "Reviews", "CI", "Mine"])
    }

    @Test func draggingASectionMovesItsCategoriesWithIt() {
        let store = quiet()
        let work = store.createSection(name: "Work")
        store.categories = [category("Mine"), category("CI", section: work.id)]
        store.moveSection(work.id, onto: CategorySection.github.id)
        #expect(store.categorySections.map(\.name) == ["Work", "GitHub"])
        #expect(store.categories.map(\.name) == ["CI", "Mine"])
    }

    @Test func aFoldedSectionAddsUpItsCategoriesCounts() {
        let store = quiet()
        store.categories = [category("Mine"), category("Reviews")]
        let part = store.barSections[0]
        #expect(store.sectionBadge(part) == nil)
        store.toggleCollapsed(CategorySection.github.id)
        #expect(store.categorySections[0].isCollapsed)
        store.toggleCollapsed(CategorySection.github.id)
        #expect(!store.categorySections[0].isCollapsed)
        // On the demo's inbox: every category's count, added up, in the first one's colour that has any.
        let demo = quiet()
        Demo.populate(demo)
        let all = demo.barSections[0]
        let badged = all.categories.filter { demo.badge($0) > 0 }
        #expect(demo.sectionBadge(all)?.count == badged.map(demo.badge).reduce(0, +))
        #expect(demo.sectionBadge(all)?.fill == badged.first?.color.swatch)
    }

    @Test func aSectionsIconComesFromItsName() {
        #expect(SectionIcon.local(name: "My GitHub") == CategorySection.githubMark)
        #expect(SectionIcon.local(name: "Reviews") == "eye")
        #expect(quiet().createSection(name: "Builds").symbol == "hammer")
    }

    /// A chooser that takes the first option, after `during` ran (what happens while Jev is being asked).
    private func choosing(during: @escaping @MainActor () -> Void) -> Claude.Chooser {
        { options, _, _, _ in
            await MainActor.run { during() }
            return JevClient.Choice(choice: options[0], confidence: 1, probabilities: [options[0]: 1])
        }
    }

    @Test func anAutomaticIconNeverOverwritesOneChosenOrANameChangedWhileAsking() async {
        let store = quiet()
        let section = store.createSection(name: "Builds")
        let id = section.id
        let start = store.categorySections.first { $0.id == id }?.symbol
        // Chosen by hand while Jev is being asked: his pick is dropped.
        await store.autoPickSectionIcon(id, name: "Builds", choose: choosing {
            if let i = store.categorySections.firstIndex(where: { $0.id == id }) {
                store.categorySections[i].symbol = "star"
                store.categorySections[i].iconChosen = true
            }
        })
        #expect(store.categorySections.first { $0.id == id }?.symbol == "star")
        // Renamed while asked: the pick was for the old name.
        if let i = store.categorySections.firstIndex(where: { $0.id == id }) {
            store.categorySections[i].iconChosen = nil
            store.categorySections[i].symbol = "tray"
        }
        await store.autoPickSectionIcon(id, name: "Builds", choose: choosing {
            if let i = store.categorySections.firstIndex(where: { $0.id == id }) { store.categorySections[i].name = "Other" }
        })
        #expect(store.categorySections.first { $0.id == id }?.symbol == "tray")
        // Left alone, the pick is applied.
        await store.autoPickSectionIcon(id, name: "Other", choose: choosing {})
        #expect(store.categorySections.first { $0.id == id }?.symbol != "tray")
        _ = start
    }

    @Test func aFileFromBeforeSectionsLoadsWithGitHubsAlone() throws {
        let old = try JSONEncoder().encode(PersistedState(settings: AppSettings(), categories: [category("Mine")]))
        let state = try JSONDecoder().decode(PersistedState.self, from: old)
        #expect(state.categorySections == nil)
        #expect(state.categories?.first?.section == nil)
        let work = CategorySection(name: "Work", symbol: "briefcase", iconChosen: true)
        let saved = try JSONEncoder().encode(PersistedState(settings: AppSettings(), categorySections: [.github, work]))
        #expect(try JSONDecoder().decode(PersistedState.self, from: saved).categorySections == [.github, work])
    }

    @Test func movingACategoryToASectionIsOneUndoStep() {
        let store = quiet()
        let work = store.createSection(name: "Work")
        store.categories = [category("Mine")]
        let history = CategoryHistory(store: store)
        store.moveCategory(store.categories[0].id, toSection: work.id)
        history.observe(store)
        #expect(store.barSections.map(\.section?.name) == ["Work"])
        history.undo(store)
        #expect(store.barSections.map(\.section?.name) == ["GitHub"])
    }
}
