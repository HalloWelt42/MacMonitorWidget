import Foundation

// Kurzer Verlaufspuffer je Metrik für die Sparklines. Werte sind 0...1 normiert.
struct MetricHistory {
    private(set) var series: [Metric: [Double]] = [:]
    let capacity: Int = 60

    mutating func append(_ snapshot: SystemSnapshot) {
        for metric in Metric.allCases {
            let value = snapshot.fraction(for: metric) ?? 0
            push(metric, value)
        }
    }

    func values(for metric: Metric) -> [Double] {
        series[metric] ?? []
    }

    private mutating func push(_ metric: Metric, _ value: Double) {
        var arr = series[metric] ?? []
        arr.append(value)
        if arr.count > capacity {
            arr.removeFirst(arr.count - capacity)
        }
        series[metric] = arr
    }
}
