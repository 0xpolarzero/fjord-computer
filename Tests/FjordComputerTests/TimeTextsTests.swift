import Foundation
import Testing
@testable import FjordComputer

@MainActor
struct TimeTextsTests {
    @Test func theDayEndsAtTheNextMidnightAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // 8 March 2026: clocks go forward at 2:00, the day is 23 hours long.
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let end = TimeTexts.dayEnd(after: noon, calendar: calendar)
        #expect(end == calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)))
        #expect(end.timeIntervalSince(calendar.startOfDay(for: noon)) == 23 * 3600)
    }

    @Test func aTimeIsFormattedOnceUntilSomethingItDependsOnChanges() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var made = 0
        let make = { (d: Date) -> String in made += 1; return "\(d.timeIntervalSinceReferenceDate)" }
        TimeTexts.invalidate()
        _ = TimeTexts.cached(date, .exact, make)
        _ = TimeTexts.cached(date, .exact, make)
        #expect(made == 1)
        // The time zone, the locale or the 12/24-hour preference changed.
        TimeTexts.invalidate()
        _ = TimeTexts.cached(date, .exact, make)
        #expect(made == 2)
    }
}
