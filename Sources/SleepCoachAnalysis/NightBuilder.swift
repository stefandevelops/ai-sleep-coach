import Foundation

/// Deterministic helpers for tests and sample nights.
public enum NightBuilder {
    public static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT")!
        return calendar
    }

    public static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return gmt.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public static func stages(
        start: Date,
        pattern: [(SleepStage, TimeInterval)],
        source: DataSource
    ) -> [SleepStageInterval] {
        var cursor = start
        return pattern.map { stage, duration in
            let interval = SleepStageInterval(
                start: cursor,
                end: cursor.addingTimeInterval(duration),
                stage: stage,
                source: source
            )
            cursor = interval.end
            return interval
        }
    }

    public static func series(
        from start: Date,
        every interval: TimeInterval,
        count: Int,
        value: (Int, Date) -> Double
    ) -> [TimedSample] {
        (0..<count).map { index in
            let date = start.addingTimeInterval(Double(index) * interval)
            return TimedSample(date: date, value: value(index, date))
        }
    }

    public static func motion(
        from start: Date,
        minutes: Int,
        magnitude: (Int) -> Double
    ) -> [MotionSample] {
        (0..<minutes).map { index in
            let mag = magnitude(index)
            return MotionSample(
                date: start.addingTimeInterval(Double(index) * 60),
                magnitude: mag,
                activeSeconds: mag >= 0.035 ? min(60, Int(mag * 400)) : 0
            )
        }
    }
}
