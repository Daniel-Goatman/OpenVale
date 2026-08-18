import Foundation

enum RotationMode: String {
    case daily
    case manual
}

enum WallpaperSchedule {
    static func dailyIndex(
        for date: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> Int {
        guard count > 0 else { return 0 }

        let start = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let current = calendar.startOfDay(for: date)
        let elapsedDays = calendar.dateComponents([.day], from: start, to: current).day ?? 0
        return ((elapsedDays % count) + count) % count
    }

    static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? date.addingTimeInterval(86_400)
    }
}
