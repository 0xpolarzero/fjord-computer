import Observation
import Testing
@testable import FjordComputer

/// The navigation layer is glass only where the system draws it and no accessibility setting asks for opaque; the
/// `FJORD_GLASS` pin wins over the settings but never draws glass where it can't (docs/design/fjord/glass-plan.md §5.1).
@MainActor @Suite struct ChromeTests {
    private static let pins: [Bool?] = [nil, false, true]

    @Test func everyInputDecidesTheMode() {
        for available in [false, true] {
            for reduce in [false, true] {
                for contrast in [false, true] {
                    for pin in Self.pins {
                        let mode = Chrome.mode(glassAvailable: available, reduceTransparency: reduce,
                                               increaseContrast: contrast, pin: pin)
                        let glass = available && (pin ?? !(reduce || contrast))
                        #expect(mode == (glass ? Chrome.Mode.glass : .opaque),
                                "available \(available), reduce \(reduce), contrast \(contrast), pin \(String(describing: pin))")
                    }
                }
            }
        }
    }

    @Test func beforeMacOS26ItIsAlwaysOpaque() {
        for pin in Self.pins {
            #expect(Chrome.mode(glassAvailable: false, reduceTransparency: false, increaseContrast: false, pin: pin) == .opaque)
        }
    }

    @Test func eitherSettingTurnsGlassOpaqueUnlessPinned() {
        #expect(Chrome.mode(glassAvailable: true, reduceTransparency: false, increaseContrast: false, pin: nil) == .glass)
        #expect(Chrome.mode(glassAvailable: true, reduceTransparency: true, increaseContrast: false, pin: nil) == .opaque)
        #expect(Chrome.mode(glassAvailable: true, reduceTransparency: false, increaseContrast: true, pin: nil) == .opaque)
        #expect(Chrome.mode(glassAvailable: true, reduceTransparency: true, increaseContrast: true, pin: true) == .glass)
        #expect(Chrome.mode(glassAvailable: true, reduceTransparency: false, increaseContrast: false, pin: false) == .opaque)
    }

    @Test func aFixedChromeKeepsItsModeWhateverTheSettings() {
        for mode in [Chrome.Mode.glass, .opaque] {
            let chrome = Chrome(mode: mode)
            #expect(chrome.mode == mode)
            for reduce in [false, true] {
                for contrast in [false, true] {
                    chrome.update(reduceTransparency: reduce, increaseContrast: contrast)
                    #expect(chrome.mode == mode)
                }
            }
        }
    }

    @Test func aSettingChangeMovesTheModeAndTellsItsReaders() {
        let chrome = Chrome(glassAvailable: true)
        #expect(chrome.mode == .glass)
        var told = false
        withObservationTracking { _ = chrome.mode } onChange: { told = true }
        chrome.update(reduceTransparency: true, increaseContrast: false)
        #expect(chrome.mode == .opaque && told)
        chrome.update(reduceTransparency: false, increaseContrast: true)
        #expect(chrome.mode == .opaque)
        chrome.update(reduceTransparency: false, increaseContrast: false)
        #expect(chrome.mode == .glass)
    }

    @Test func aSameModeUpdateTellsNoOne() {
        let chrome = Chrome(glassAvailable: true, reduceTransparency: true)
        var told = false
        withObservationTracking { _ = chrome.mode } onChange: { told = true }
        chrome.update(reduceTransparency: false, increaseContrast: true)
        #expect(chrome.mode == .opaque && !told)
    }

    @Test func withoutGlassASettingChangesNothing() {
        let chrome = Chrome(glassAvailable: false)
        chrome.update(reduceTransparency: true, increaseContrast: true)
        chrome.update(reduceTransparency: false, increaseContrast: false)
        #expect(chrome.mode == .opaque)
    }

    @Test func aPinnedChromeIgnoresTheSettings() {
        let chrome = Chrome(glassAvailable: true, reduceTransparency: true, pin: true)
        #expect(chrome.mode == .glass)
        chrome.update(reduceTransparency: true, increaseContrast: true)
        #expect(chrome.mode == .glass)
    }
}
