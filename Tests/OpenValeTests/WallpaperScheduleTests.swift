import Foundation
import XCTest
@testable import OpenVale

final class WallpaperScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDailyIndexAdvancesOncePerCalendarDay() throws {
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)))
        let secondDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDate))

        let firstIndex = WallpaperSchedule.dailyIndex(for: firstDate, count: 6, calendar: calendar)
        let secondIndex = WallpaperSchedule.dailyIndex(for: secondDate, count: 6, calendar: calendar)

        XCTAssertEqual(secondIndex, (firstIndex + 1) % 6)
    }

    func testDailyIndexWrapsAcrossLibrary() throws {
        let startDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)))
        let wrappedDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: startDate))

        XCTAssertEqual(
            WallpaperSchedule.dailyIndex(for: startDate, count: 6, calendar: calendar),
            WallpaperSchedule.dailyIndex(for: wrappedDate, count: 6, calendar: calendar)
        )
    }

    func testNextRefreshUsesLocalCalendarBoundary() throws {
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 23, minute: 59))
        )
        let nextMidnight = WallpaperSchedule.nextMidnight(after: date, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextMidnight)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
    }

    func testEmptyLibraryReturnsSafeIndex() {
        XCTAssertEqual(WallpaperSchedule.dailyIndex(for: Date(), count: 0), 0)
    }
}
