import AppKit
import Foundation
import Testing
@testable import Lookout

/// The composer's inline @project pills: what the text view holds, what the model and the Router get.
@MainActor
@Suite struct RouterMentionFieldTests {
    private let known = [(name: "lookout", folder: "/code/lookout"), (name: "lcu", folder: "/code/lcu")]

    private func view() -> MentionTextView {
        let (font, base) = MentionField.attributes()
        let view = MentionTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        view.base = base
        view.font = font
        view.known = { known }
        view.name = { folder in known.first { $0.folder == folder }?.name ?? folder }
        view.makePill = { folder in MentionAttachment(folder: folder, name: view.name(folder), color: nil, font: font) }
        return view
    }

    @Test func pastedAtNamesOfKnownProjectsBecomePillsAndSerializeBack() {
        let v = view()
        v.insertPlain("ask @lookout and @lcu, not @nobody or me@lcu", replacing: NSRange(location: 0, length: 0))
        let (draft, tokens) = MentionText.serialize(v.attributedString())
        #expect(tokens == ["/code/lookout", "/code/lcu"])
        #expect(draft == "ask \(MentionText.markString) and \(MentionText.markString), not @nobody or me@lcu")
        let sent = MentionText.plain(draft, tokens: tokens) { name in known.first { $0.folder == name }!.name }
        #expect(sent == "ask @lookout and @lcu, not @nobody or me@lcu")
        // Selecting and copying gives "@name".
        #expect(v.plain(NSRange(location: 0, length: 5)) == "ask @lookout")
    }

    @Test func aPillIsOneCharacterAndOneBackspaceRemovesIt() {
        let v = view()
        v.insertPlain("hi @lcu there", replacing: NSRange(location: 0, length: 0))
        #expect(v.string.count == "hi ".count + 1 + " there".count)
        v.setSelectedRange(NSRange(location: 4, length: 0))
        v.deleteBackward(nil)
        #expect(v.string == "hi  there" && MentionText.serialize(v.attributedString()).tokens.isEmpty)
    }

    @Test func textTypedAfterAPillIsPlainText() {
        let v = view()
        v.insertPlain("@lcu", replacing: NSRange(location: 0, length: 0))
        v.insertPlain(" x", replacing: v.selectedRange())
        #expect(MentionText.serialize(v.attributedString()).tokens.count == 1)
        #expect(v.attributedString().attribute(.attachment, at: 2, effectiveRange: nil) == nil)
    }

    @Test func pickingAMentionPutsAPillWhereTheWordWasAndASpaceAfterIt() {
        let model = RouterModel()
        model.tokens = ["/code/lcu"]
        model.draft = "\(MentionText.markString) then @lo"
        model.caret = nil
        model.pickMention("/code/lookout")
        #expect(model.tokens == ["/code/lcu", "/code/lookout"])
        #expect(model.draft == "\(MentionText.markString) then \(MentionText.markString) " && model.caretRequest == 9)
        // Earlier in the text: the pill takes its place in the order.
        model.tokens = ["/code/lcu"]
        model.draft = "ab @lo \(MentionText.markString)"
        model.caret = 6
        model.pickMention("/code/lookout")
        #expect(model.tokens == ["/code/lookout", "/code/lcu"] && model.projects == ["/code/lookout", "/code/lcu"])
    }
}
