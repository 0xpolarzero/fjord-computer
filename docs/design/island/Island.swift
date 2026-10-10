// Lookout, v5: a sibling of Claude's Code tab. Every token below is read from the Claude desktop app's own bundle
// (@ant/cds, dark mode): greys, roles, radii, control heights, type scale, shadows. Fonts are Claude's own
// Anthropic Sans / Serif, loaded from the app at runtime. Nothing here is invented that Claude doesn't already do.
//   swiftc -O -parse-as-library Island.swift -o /tmp/island && /tmp/island shots
import AppKit
import CoreText
import SwiftUI

// MARK: - CDS tokens (dark)

enum K {
    // gray ramp
    static let g900 = hex(0x0B0B0B), g850 = hex(0x151515), g830 = hex(0x1A1A19), g800 = hex(0x20201F), g750 = hex(0x2C2C2A)
    static let g50 = hex(0xF0EFEC), g200 = hex(0xC3C2B7), g400 = hex(0x898781), g500 = hex(0x6D6B67)
    // surfaces
    static let page = g900, surface1 = g850, panel = g830, popover = g800
    // text
    static let text = g50, text2 = g200, muted = g400
    // alpha of neutral-900 (white in dark)
    static func alpha(_ a: Double) -> Color { Color.white.opacity(a) }
    static let border = alpha(0.10), hover = alpha(0.075), selected = alpha(0.15), field = alpha(0.05), secondary = alpha(0.10)
    // roles
    static let clay = hex(0xD97757)
    static let accent = hex(0x3987E5)     // blue-400: the sidebar's unread dot
    static let accentText = hex(0x6DA7EC) // blue-300
    static let warning = hex(0xFAB219)    // yellow-200: needs you
    static let danger = hex(0xEC7E7E)     // red-300
    static let success = hex(0x55BF50)    // green-300
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Type: Anthropic Sans, the CDS scale

enum Fnt {
    static func sans(_ size: CGFloat, _ w: String = "Regular", display: Bool = false) -> Font {
        .custom("AnthropicSansVariable-\(display ? "Display" : "Text")\(w)", size: size)
    }
    static let caption = sans(11)               // 11/17
    static let footnote = sans(12)              // 12/15
    static let body = sans(13)                  // 13/19
    static let bodyM = sans(13, "Medium")
    static let prose = sans(14)                 // 14/20: what Claude and the sessions say
    static let heading = sans(14, "Medium")
    static let title = sans(20, "Medium", display: true)
    static let mono = Font.system(size: 12, design: .monospaced)
}

extension Text { func k(_ f: Font, _ c: Color) -> Text { font(f).foregroundColor(c) } }

// MARK: - Claude's own pieces

/// The sidebar's status dot: amber needs you, blue done and unread, a ring when quiet.
struct Dot: View {
    enum S { case ask, done, working, quiet, stuck }
    let s: S
    var body: some View {
        ZStack {
            switch s {
            case .ask: Circle().fill(K.warning).frame(width: 6, height: 6)
            case .done: Circle().fill(K.accent).frame(width: 6, height: 6)
            case .stuck: Circle().fill(K.danger).frame(width: 6, height: 6)
            case .quiet: Circle().strokeBorder(K.g500, lineWidth: 1).frame(width: 7, height: 7)
            case .working: Working()
            }
        }
        .frame(width: 12, height: 12)
    }
}

/// Claude's "···" while it works, in clay.
struct Working: View {
    var body: some View {
        HStack(spacing: 1.5) {
            Circle().fill(K.clay).frame(width: 2.5, height: 2.5)
            Circle().fill(K.clay.opacity(0.7)).frame(width: 2.5, height: 2.5)
            Circle().fill(K.clay.opacity(0.4)).frame(width: 2.5, height: 2.5)
        }
    }
}

struct Chip: View {
    let s: String
    var body: some View {
        Text(s).k(Fnt.footnote, K.text2)
            .padding(.horizontal, 6).frame(height: 20)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(K.border, lineWidth: 1))
    }
}

struct Btn: View {
    enum Kind { case primary, secondary, ghost }
    let s: String; var kind: Kind = .secondary
    var body: some View {
        Text(s).font(Fnt.sans(13, "Medium"))
            .foregroundColor(kind == .primary ? K.g900 : kind == .ghost ? K.text2 : K.text)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(kind == .primary ? K.text : kind == .secondary ? K.secondary : .clear))
    }
}

/// A quiet line for something done on your behalf, as the Code tab shows "Ran 2 commands ›".
struct Quiet: View {
    let s: String
    var body: some View {
        HStack(spacing: 4) {
            Text(s).k(Fnt.body, K.muted)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(K.muted)
        }
    }
}

/// The Code tab's composer: a context strip above, the field, a quiet footer.
struct Composer: View {
    var target: String; var project: String
    var placeholder = "Reply, or tell the Router"
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(target).k(Fnt.mono, K.muted)
                Text(project).k(Fnt.mono, K.muted)
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10).fill(K.field))
            HStack {
                Text(placeholder).k(Fnt.prose, K.muted)
                Spacer()
                Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundColor(K.muted)
                    .frame(width: 24, height: 24).background(Circle().fill(K.secondary))
            }
            .padding(.leading, 14).padding(.trailing, 8).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(K.field))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(K.border, lineWidth: 1))
            HStack(spacing: 14) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                Text("@ project").font(Fnt.footnote)
                Spacer()
                Text("Router").font(Fnt.footnote)
            }
            .foregroundColor(K.muted).padding(.horizontal, 8).padding(.top, 2)
        }
    }
}

// MARK: - Content (the app's demo data)

struct Item: Identifiable {
    let id: String; let dot: Dot.S; let title: String; let project: String; let ago: String; let line: String
}
let needs: [Item] = [
    .init(id: "lcu", dot: .ask, title: "LCU update notifications", project: "lcu", ago: "2m", line: "Should updates install silently, or ask first each time?"),
    .init(id: "linux", dot: .ask, title: "LCU JavaScript sandbox on Linux", project: "microsandbox", ago: "9m", line: "Plan ready"),
    .init(id: "calc", dot: .stuck, title: "Calculator display reading", project: "lcu-research", ago: "6m", line: "Can't reach the staging database: the VPN is down."),
]
let done: [Item] = [
    .init(id: "ci", dot: .done, title: "CI failure diagnosis", project: "microsandbox", ago: "4m", line: "Fixed the flaky sandbox test; CI is green on the branch."),
]
let working: [Item] = [
    .init(id: "agent", dot: .working, title: "Agent completion notifications", project: "lookout", ago: "", line: "Running swift test"),
]
let earlier: [Item] = [
    .init(id: "transfer", dot: .quiet, title: "Repository ownership transfer setup", project: "microsandbox", ago: "12m", line: ""),
    .init(id: "games", dot: .quiet, title: "Game recommendations", project: "", ago: "30m", line: ""),
]

// MARK: - The island: black, it's the notch

enum Notch { static let w: CGFloat = 188; static let h: CGFloat = 32 }

struct IslandShape: Shape {
    var r: CGFloat; var flare: CGFloat = 6
    func path(in b: CGRect) -> Path {
        let w = b.width, h = b.height, f = flare, R = min(r, h / 2)
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: f, y: f), control: CGPoint(x: f, y: 0))
        p.addLine(to: CGPoint(x: f, y: h - R))
        p.addArc(tangent1End: CGPoint(x: f, y: h), tangent2End: CGPoint(x: f + R, y: h), radius: R)
        p.addLine(to: CGPoint(x: w - f - R, y: h))
        p.addArc(tangent1End: CGPoint(x: w - f, y: h), tangent2End: CGPoint(x: w - f, y: h - R), radius: R)
        p.addLine(to: CGPoint(x: w - f, y: f))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - f, y: 0))
        p.closeSubpath(); return p
    }
}

struct Ears: View {
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) { Dot(s: .ask); Text("3").k(Fnt.bodyM, K.text) }.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: Notch.w)
            HStack(spacing: 6) { Working(); Text("2").k(Fnt.bodyM, K.text2) }.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14).frame(height: Notch.h)
    }
}

struct Island<Inner: View>: View {
    var width: CGFloat
    @ViewBuilder var inner: Inner
    var body: some View {
        VStack(spacing: 0) { Ears(); inner.frame(maxWidth: .infinity, alignment: .topLeading) }
            .frame(width: width).padding(.horizontal, 6)
            .background(IslandShape(r: 14).fill(.black))
            .shadow(color: .black.opacity(0.32), radius: 24, y: 8)
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

/// A row as in Claude's sidebar: dot, title, quiet project on the right.
struct SRow: View {
    let i: Item; var on = false; var showProject = true
    var body: some View {
        HStack(spacing: 8) {
            Dot(s: i.dot)
            Text(i.title).k(Fnt.body, i.dot == .quiet ? K.text2 : K.text).lineLimit(1)
            Spacer(minLength: 8)
            if showProject { Text(i.project).k(Fnt.footnote, K.muted).lineLimit(1) }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? K.hover : .clear))
    }
}

// MARK: - Desktop

struct Desk<Content: View>: View {
    var h: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .top) {
            if let img = NSImage(contentsOfFile: "/tmp/island-proto/wall.png") {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 1512, height: 982, alignment: .top).frame(height: h, alignment: .top).clipped()
            }
            HStack(spacing: 20) {
                Image(systemName: "apple.logo").font(.system(size: 14))
                Text("Claude").font(.system(size: 13, weight: .bold))
                ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { Text($0).font(.system(size: 13)) }
                Spacer()
                Image(systemName: "wifi").font(.system(size: 13))
                Image(systemName: "battery.75percent").font(.system(size: 15))
                Text("Thu 9 Oct  14:32").font(.system(size: 13))
            }
            .foregroundColor(.white.opacity(0.9)).padding(.horizontal, 18).frame(height: Notch.h)
            .overlay { IslandShape(r: 8, flare: 0).fill(.black).frame(width: Notch.w, height: Notch.h) }
            content
        }
        .frame(width: 1512, height: h, alignment: .top).clipped()
    }
}

// MARK: - Island states

struct Rest: View {
    var body: some View { Desk(h: 120) { Ears().frame(width: Notch.w + 96).background(IslandShape(r: 10).fill(.black)) } }
}

struct Arrives: View {
    var body: some View {
        Desk(h: 260) {
            Island(width: 420) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text("LCU update notifications").k(Fnt.footnote, K.muted)
                        Spacer()
                        Text("now").k(Fnt.footnote, K.muted)
                    }
                    Text("Should updates install silently, or ask first each time?").k(Fnt.prose, K.text)
                        .lineSpacing(3).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Btn(s: "Install silently"); Btn(s: "Ask first")
                        Spacer()
                        Btn(s: "Reply", kind: .ghost)
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 14)
            }
        }
    }
}

struct Glance: View {
    var body: some View {
        Desk(h: 320) {
            Island(width: 420) {
                VStack(spacing: 0) {
                    SRow(i: needs[0], on: true); SRow(i: needs[1]); SRow(i: needs[2]); SRow(i: done[0])
                    HStack(spacing: 8) {
                        Dot(s: .working)
                        Text("Agent completion notifications").k(Fnt.body, K.text2).lineLimit(1)
                        Spacer()
                        Text("Running swift test").k(Fnt.footnote, K.muted)
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                }
                .padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 8)
            }
        }
    }
}

struct Hub: View {
    let rows: [(String, String, String, String)] = [
        ("andrewrk", "std.Io: add vectored reads to File", "zig#21877", "3m"),
        ("allevato", "Respect trailing comma config in collection literals", "swift-format#1042", "18m"),
        ("mattt", "Pill overlaps the Dock when it's on the right", "lookout#12", "42m"),
        ("ahoppen", "Add --lines option to format a range", "swift-format#1051", "1h"),
        ("kylef", "Add GitHub Enterprise host setting", "lookout#15", "1h"),
    ]
    var body: some View {
        Desk(h: 520) {
            Island(width: 480) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        tab("Needs you", true); tab("Bots", false); tab("Done", false)
                        Spacer()
                        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(K.muted).padding(.trailing, 6)
                    }
                    .padding(.top, 4).padding(.bottom, 6)
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        if i == 0 { expanded(r) } else { row(r) }
                    }
                    HStack(spacing: 14) {
                        ci(K.danger, "swift-format"); ci(K.clay, "zig"); ci(K.success, "lookout"); ci(K.success, "lcu")
                        Spacer()
                    }
                    .padding(.horizontal, 8).frame(height: 36).padding(.top, 4)
                }
                .padding(.horizontal, 6).padding(.bottom, 8)
            }
        }
    }
    func tab(_ s: String, _ on: Bool) -> some View {
        Text(s).k(Fnt.bodyM, on ? K.text : K.muted).padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? K.hover : .clear))
    }
    func avatar(_ u: String) -> some View {
        ZStack { if let i = NSImage(contentsOfFile: "/tmp/island-proto/avatars/\(u).png") { Image(nsImage: i).resizable() } }
            .frame(width: 16, height: 16).clipShape(Circle())
    }
    func row(_ r: (String, String, String, String)) -> some View {
        HStack(spacing: 8) {
            avatar(r.0)
            Text(r.1).k(Fnt.body, K.text).lineLimit(1)
            Spacer(minLength: 10)
            Text(r.2).k(Fnt.footnote, K.muted)
        }
        .padding(.horizontal, 8).frame(height: 30)
    }
    func expanded(_ r: (String, String, String, String)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(r)
            VStack(alignment: .leading, spacing: 10) {
                Text("This should take the buffer by slice instead, otherwise we copy twice on the hot path.")
                    .k(Fnt.prose, K.text2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) { Btn(s: "Open", kind: .primary); Btn(s: "Mark read"); Btn(s: "Done", kind: .ghost) }
            }
            .padding(.leading, 32).padding(.trailing, 10).padding(.bottom, 12)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(K.hover))
    }
    func ci(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 6) { Circle().fill(c).frame(width: 6, height: 6); Text(s).k(Fnt.footnote, K.muted) }
    }
}

// MARK: - The Router window: a sibling of the Code tab

enum Focus { case question, plan, done, chat }

struct RouterWindow: View {
    var focus: Focus
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 268).background(K.surface1)
            VStack(spacing: 0) {
                topbar
                main.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(K.panel)
        }
        .frame(width: 1140, height: 740)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(K.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(K.hex(0xFF5F57)).frame(width: 12, height: 12)
                Circle().fill(K.hex(0xFEBC2E)).frame(width: 12, height: 12)
                Circle().fill(K.hex(0x28C840)).frame(width: 12, height: 12)
            }
            .padding(.leading, 16).frame(height: 48)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(K.muted)
                    Text("Search").k(Fnt.body, K.muted)
                    Spacer()
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(K.field))
                .padding(.bottom, 8)
                nav("bubble.left", "Router", on: focus == .chat)
                nav("plus", "New session")
                label("Needs you")
                ForEach(needs) { SRow(i: $0, on: sel($0), showProject: false) }
                label("Done")
                ForEach(done) { SRow(i: $0, on: sel($0), showProject: false) }
                label("Working")
                ForEach(working) { SRow(i: $0, showProject: false) }
                label("Earlier")
                ForEach(earlier) { SRow(i: $0, showProject: false) }
                Spacer()
            }
            .padding(.horizontal, 10)
        }
    }
    func sel(_ i: Item) -> Bool {
        switch focus { case .question: i.id == "lcu"; case .plan: i.id == "linux"; case .done: i.id == "ci"; case .chat: false }
    }
    func nav(_ icon: String, _ s: String, on: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(K.text2).frame(width: 12)
            Text(s).k(Fnt.body, K.text)
            Spacer()
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? K.hover : .clear))
    }
    func label(_ s: String) -> some View {
        Text(s).k(Fnt.footnote, K.muted).padding(.horizontal, 8).padding(.top, 18).padding(.bottom, 4)
    }

    var current: Item? {
        switch focus { case .question: needs[0]; case .plan: needs[1]; case .done: done[0]; case .chat: nil }
    }

    var topbar: some View {
        HStack(spacing: 8) {
            Text(current?.title ?? "Router").k(Fnt.bodyM, K.text)
            if let c = current { Chip(s: c.project) }
            Spacer()
            if current != nil {
                icon("checkmark.circle"); icon("arrow.up.right.square")
            }
        }
        .padding(.horizontal, 16).frame(height: 48)
    }

    func icon(_ n: String) -> some View {
        Image(systemName: n).font(.system(size: 13)).foregroundColor(K.muted).frame(width: 28, height: 28)
    }

    @ViewBuilder var main: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                switch focus {
                case .question: question
                case .plan: plan
                case .done: doneView
                case .chat: chat
                }
            }
            .frame(width: 640, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 20)
            Composer(target: current.map { "→ " + $0.title } ?? "→ Router", project: current?.project ?? "",
                     placeholder: current == nil ? "Ask, or tell it what to pass on" : "Reply, or tell the Router")
                .frame(width: 640).padding(.bottom, 16)
        }
    }

    var question: some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Updates").k(Fnt.footnote, K.muted)
                    Spacer()
                    Text("1 of 1").k(Fnt.footnote, K.muted)
                }
                .padding(.horizontal, 14).padding(.top, 12)
                Text("Should updates install silently, or ask first each time?").k(Fnt.heading, K.text)
                    .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
                option(1, "Install silently", "Download and install in the background")
                option(2, "Ask first", "Show a prompt before each update", on: true)
                option(3, "Other", "Write your own answer", muted: true)
                HStack { Spacer(); Btn(s: "Skip", kind: .ghost); Btn(s: "Send answer", kind: .primary) }
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(K.surface1))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(K.border, lineWidth: 1))
        }
    }
    func option(_ n: Int, _ s: String, _ d: String, on: Bool = false, muted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").k(Fnt.body, K.muted).frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(s).k(Fnt.bodyM, muted ? K.text2 : K.text)
                Text(d).k(Fnt.footnote, K.muted)
            }
            Spacer()
            if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundColor(K.text) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? K.hover : .clear))
        .padding(.horizontal, 4)
    }

    var plan: some View {
        Group {
            Text("Here's the plan. macOS stays as it is; Linux gets a Firecracker microVM.")
                .k(Fnt.prose, K.text).lineSpacing(4)
            VStack(alignment: .leading, spacing: 10) {
                Text("Run the JavaScript sandbox in a Firecracker microVM on Linux").k(Fnt.heading, K.text)
                VStack(alignment: .leading, spacing: 6) {
                    step("Boot a minimal microVM from the sandbox image (cold start about 120 ms)")
                    step("Mount the workspace read-only over virtio-fs")
                    step("Bridge stdio and the LCU JS calls over vsock")
                    step("Leave macOS on Virtualization.framework")
                }
                HStack(spacing: 6) { Btn(s: "Approve", kind: .primary); Btn(s: "Keep planning") }.padding(.top, 6)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(K.surface1))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(K.border, lineWidth: 1))
        }
    }
    func step(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").k(Fnt.prose, K.muted)
            Text(s).k(Fnt.prose, K.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    var doneView: some View {
        Group {
            Text("Fixed the flaky sandbox test; CI is green on the branch.").k(Fnt.prose, K.text).lineSpacing(4)
            VStack(alignment: .leading, spacing: 10) {
                running("Review the sandbox changes", "Reading sandbox.rs")
                running("Check the other CI jobs", "Thinking")
                running("Run the full test suite", "swift test · 6m")
            }
        }
    }
    func running(_ t: String, _ what: String) -> some View {
        HStack(spacing: 8) { Working(); Text(t).k(Fnt.body, K.text2); Text(what).k(Fnt.body, K.muted) }
    }

    var chat: some View {
        Group {
            you("what needs me?")
            Text("Three need you. LCU update notifications asks how updates should install, the Linux sandbox has a plan to approve, and Calculator display reading is stuck on the VPN. CI failure diagnosis is done.")
                .k(Fnt.prose, K.text).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            you("transfer: remove the old remote")
            Quiet(s: "Sent to Repository ownership transfer setup")
            VStack(alignment: .leading, spacing: 6) {
                Text("Repository ownership transfer setup").k(Fnt.footnote, K.muted)
                Text("Removed old-origin; only the new org's remote is left. Two open PRs still target the old fork; I left them alone.")
                    .k(Fnt.prose, K.text).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(K.surface1))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(K.border, lineWidth: 1))
            you("start a session in @lookout to bump the version")
            Text("Couldn't reach Game recommendations: it isn't open in Claude.").k(Fnt.body, K.danger)
        }
    }
    func you(_ s: String) -> some View {
        HStack { Spacer(); Text(s).k(Fnt.prose, K.text).padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(K.alpha(0.07))) }
    }
}

struct WindowShot: View {
    var focus: Focus
    var body: some View {
        Desk(h: 900) {
            Ears().frame(width: Notch.w + 96).background(IslandShape(r: 10).fill(.black))
            RouterWindow(focus: focus).padding(.top, 110)
        }
    }
}

// MARK: - Render

@main
struct Render {
    @MainActor static func main() {
        for f in (try? FileManager.default.contentsOfDirectory(atPath: "/tmp/island-proto/fonts")) ?? [] {
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "/tmp/island-proto/fonts/\(f)") as CFURL, .process, nil)
        }
        let dir = CommandLine.arguments.dropFirst().first ?? "shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func mid(_ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: (1512 - w) / 2, y: 0, width: w, height: h) }
        save(WindowShot(focus: .question), "1-router-question", dir, mid(1240, 880))
        save(WindowShot(focus: .chat), "2-router-chat", dir, mid(1240, 880))
        save(WindowShot(focus: .plan), "3-router-plan", dir, mid(1240, 880))
        save(WindowShot(focus: .done), "4-router-done", dir, mid(1240, 880))
        save(Rest(), "5-island-rest", dir, mid(720, 100))
        save(Arrives(), "6-island-question", dir, mid(720, 200))
        save(Glance(), "7-island-hover", dir, mid(720, 260))
        save(Hub(), "8-island-kept-open", dir, mid(760, 440))
    }

    @MainActor static func save<V: View>(_ v: V, _ name: String, _ dir: String, _ crop: CGRect?) {
        let r = ImageRenderer(content: v.environment(\.colorScheme, .dark))
        r.scale = 2
        guard var cg = r.cgImage else { print("failed \(name)"); return }
        if let crop, let c = cg.cropping(to: CGRect(x: crop.minX * 2, y: crop.minY * 2, width: crop.width * 2, height: crop.height * 2)) { cg = c }
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        print("\(dir)/\(name).png")
    }
}
