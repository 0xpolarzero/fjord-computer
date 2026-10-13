import Foundation
import Testing
@testable import FjordComputer

@Suite struct RouterCardEqualityTests {
    private func card() -> RouterCard {
        RouterCard(id: "s#t1", sessionID: "s", kind: .done, title: "Build", folder: "/code/app",
                   text: String(repeating: "A long turn. ", count: 1000), createdAt: Date(timeIntervalSince1970: 100))
    }

    @Test func copiesAndDecodedCardsKeepValueEqualityAndHashing() throws {
        let original = card(), copy = original
        let decoded = try JSONDecoder().decode(RouterCard.self, from: JSONEncoder().encode(original))
        #expect(original == copy && original == decoded)
        #expect(Set([original, copy, decoded]).count == 1)
        var changed = copy
        changed.text += " Another result."
        #expect(changed != original && copy == original)
        changed.text = original.text
        #expect(changed == original && Set([original, changed]).count == 1)
    }

    @Test func nestedEditsAndHistoryChangesInvalidateACopiedCard() {
        var original = card()
        original.asks = [RouterAsk(question: "Ship?")]
        original.triage = RouterTriage(state: .done, urgency: 2)
        var changed = original
        changed.asks?[0].question = "Ship today?"
        #expect(changed != original)
        changed = original
        changed.triage?.urgency = 4
        #expect(changed != original)
        changed = original
        changed.createdAt = original.createdAt.addingTimeInterval(1)
        #expect(changed != original)
        changed = original
        changed.addressedAt = original.createdAt
        #expect(changed != original && original.isOpen)
    }
}
