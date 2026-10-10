import Foundation
import Testing
@testable import Lookout

/// The bar's sections: every inbox starts with GitHub's holding every category; a category in none, or in one deleted, is
/// in the first; the bar and the shown order go section by section.
@MainActor @Suite struct CategorySections {
    private func category(_ name: String, section: UUID? = nil, hidden: Bool = false) -> InboxCategory {
        var c = InboxCategory(name: name, symbol: "tray", color: .blue)
        c.section = section
        c.hidden = hidden
        return c
    }

    @Test func everyInboxStartsWithGitHubsSectionHoldingEveryCategory() {
        let store = Store()
        store.categories = [category("Mine"), category("Reviews")]
        #expect(store.categorySections == [.github])
        #expect(store.barSections.map(\.section) == [.github])
        #expect(store.barSections.first?.categories.map(\.name) == ["Mine", "Reviews"])
    }

    @Test func theBarAndTheShownOrderGoSectionBySection() {
        let store = Store()
        let work = store.createSection(name: "Work")
        store.categories = [category("CI", section: work.id), category("Mine"), category("Hidden", section: work.id, hidden: true),
                            category("Reviews")]
        #expect(store.barSections.map(\.section?.name) == ["GitHub", "Work"])
        #expect(store.shownCategories.map(\.name) == ["Mine", "Reviews", "CI"])
        // The order things are matched in is the categories' own.
        #expect(store.categories.map(\.name) == ["CI", "Mine", "Hidden", "Reviews"])
    }

    @Test func aSectionWithNothingShownHasNoWell() {
        let store = Store()
        _ = store.createSection(name: "Empty")
        store.categories = [category("Mine")]
        #expect(store.barSections.map(\.section?.name) == ["GitHub"])
    }

    @Test func deletingASectionMovesItsCategoriesToTheFirstLeft() {
        let store = Store()
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
        let store = Store()
        let work = store.createSection(name: "Work")
        store.categories = [category("Mine"), category("CI", section: work.id)]
        store.moveSection(work.id, by: -1)
        #expect(store.barSections.map(\.section?.name) == ["Work", "GitHub"])
        #expect(store.barSections.map { $0.categories.map(\.name) } == [["CI"], ["Mine"]])
    }

    @Test func aSectionsIconComesFromItsName() {
        #expect(SectionIcon.local(name: "My GitHub") == CategorySection.githubMark)
        #expect(SectionIcon.local(name: "Reviews") == "eye")
        #expect(Store().createSection(name: "Builds").symbol == "hammer")
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
        let store = Store()
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
