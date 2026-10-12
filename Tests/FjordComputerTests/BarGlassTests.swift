import SwiftUI
import Testing
@testable import FjordComputer

/// The bar on glass (docs/design/fjord/glass-plan.md §5.5, §5.8): the fills' alpha steps, opaque mode keeping today's
/// tokens, and the drag's stretch with its Reduce Motion resolution.
@MainActor @Suite struct BarGlassTests {
    @Test func fillsAreInkStepsPerAppearance() {
        #expect(BarGlass.alpha(.hover, dark: true) == 0.06)
        #expect(BarGlass.alpha(.selected, dark: true) == 0.09)
        #expect(BarGlass.alpha(.selectedHover, dark: true) == 0.12)
        #expect(BarGlass.alpha(.hover, dark: false) == 0.06)
        #expect(BarGlass.alpha(.selected, dark: false) == 0.10)
        #expect(BarGlass.alpha(.selectedHover, dark: false) == 0.14)
        for dark in [true, false] {
            #expect(BarGlass.alpha(.hover, dark: dark) < BarGlass.alpha(.selected, dark: dark))
            #expect(BarGlass.alpha(.selected, dark: dark) < BarGlass.alpha(.selectedHover, dark: dark))
        }
    }

    @Test func opaqueKeepsTodaysTokens() {
        for step in [BarGlass.Step.hover, .selected, .selectedHover] {
            for scheme in [ColorScheme.dark, .light] {
                #expect(BarGlass.fill(step, glass: false, scheme: scheme, opaque: Theme.Fill.hover) == Theme.Fill.hover)
            }
        }
    }

    @Test func thePanelSharesTheBarsRadius() {
        #expect(BarGlass.panelRadius == BarGlass.barRadius)
        #expect(BarGlass.barRadius == 20)
    }

    @Test func aDragDrawsTheBarOutAlongItsMainAxis() {
        #expect(BarStretch.scale(CGVector(dx: 40, dy: 5), reduce: false) == CGSize(width: 1, height: BarStretch.across))
        #expect(BarStretch.scale(CGVector(dx: -40, dy: 5), reduce: false) == CGSize(width: 1, height: BarStretch.across))
        #expect(BarStretch.scale(CGVector(dx: 3, dy: -30), reduce: false) == CGSize(width: BarStretch.across, height: 1))
        // Narrower across, never larger: the carried window is exactly the bar's size.
        #expect(BarStretch.across < 1)
    }

    @Test func noStretchBeforeTheMotionHasADirection() {
        #expect(BarStretch.scale(.zero, reduce: false) == BarStretch.rest)
        #expect(BarStretch.scale(CGVector(dx: 3, dy: -4), reduce: false) == BarStretch.rest)
    }

    @Test func reduceMotionNeverStretches() {
        for motion in [CGVector(dx: 40, dy: 0), CGVector(dx: 0, dy: -40), CGVector(dx: 200, dy: 199)] {
            #expect(BarStretch.scale(motion, reduce: true) == BarStretch.rest)
        }
    }

    @Test func nothingIsMeasuredAtRest() {
        #expect(FjordHub.toMeasure(arriving: nil, peeking: nil, inBar: [.inbox, .router, .controls], measured: []).isEmpty)
        #expect(FjordHub.toMeasure(arriving: nil, peeking: nil, inBar: [.inbox], measured: [.inbox]).isEmpty)
    }

    @Test func aDwellMeasuresOnlyItsOwnSectionAfresh() {
        let all: Set<HubSection> = [.inbox, .router, .controls]
        // Its own section even when measured before (its content may have changed size), and nothing else: a sweep along
        // the bar measures one section at a time.
        #expect(FjordHub.toMeasure(arriving: .inbox, peeking: nil, inBar: all, measured: all) == [.inbox])
        #expect(FjordHub.toMeasure(arriving: .router, peeking: nil, inBar: all, measured: []) == [.router])
    }

    @Test func anOpenPanelMeasuresOnlyWhatIsNotMeasuredYet() {
        let all: Set<HubSection> = [.inbox, .router, .controls]
        // The open panel measures itself once shown; until then it is measured here too.
        #expect(FjordHub.toMeasure(arriving: nil, peeking: .inbox, inBar: all, measured: [.inbox]) == [.router, .controls])
        #expect(FjordHub.toMeasure(arriving: nil, peeking: .inbox, inBar: all, measured: []) == [.inbox, .router, .controls])
        #expect(FjordHub.toMeasure(arriving: nil, peeking: .inbox, inBar: all, measured: all).isEmpty)
    }

    @Test func sectionsNotInTheBarAreNotMeasured() {
        #expect(FjordHub.toMeasure(arriving: nil, peeking: .inbox, inBar: [.inbox, .controls], measured: [.inbox]) == [.controls])
    }
}
