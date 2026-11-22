import CoreGraphics
import Foundation

struct ModelTouchMovement {
    enum Change: Equatable {
        case orbit(CGVector)
        case transform(translation: CGVector, scale: CGFloat)
        case separation(scale: CGFloat)
    }

    private let threshold: CGFloat = 6
    private var highestContactCount = 0
    private var center: CGPoint?
    private var span: CGFloat?
    private var isDragging = false
    private var isScaling = false

    mutating func contactsChanged(_ points: [CGPoint]) {
        highestContactCount = points.isEmpty ? 0 : max(highestContactCount, points.count)
        isDragging = false
        isScaling = false
        guard points.count == highestContactCount, (1...3).contains(points.count) else {
            center = nil
            span = nil
            return
        }
        let geometry = geometry(of: points)
        center = geometry.center
        span = geometry.span
    }

    mutating func move(_ points: [CGPoint]) -> Change? {
        // Lifting a finger must not turn a three-finger split into a two-finger zoom.
        guard points.count == highestContactCount, let center, let span else { return nil }
        let geometry = geometry(of: points)
        let translation = CGVector(dx: geometry.center.x - center.x, dy: geometry.center.y - center.y)
        let spanChange = geometry.span - span

        if points.count == 3 {
            guard spanChange != 0, isScaling || abs(spanChange) >= threshold else { return nil }
            isScaling = true
            self.span = geometry.span
            return .separation(scale: geometry.span / span)
        }

        isDragging = isDragging || hypot(translation.dx, translation.dy) >= threshold
        if isDragging { self.center = geometry.center }
        if points.count == 1 { return isDragging ? .orbit(translation) : nil }

        isScaling = isScaling || abs(spanChange) >= threshold
        if isScaling { self.span = geometry.span }
        guard isDragging || isScaling else { return nil }
        return .transform(translation: isDragging ? translation : .zero,
                          scale: isScaling ? geometry.span / span : 1)
    }

    private func geometry(of points: [CGPoint]) -> (center: CGPoint, span: CGFloat) {
        let count = CGFloat(points.count)
        let total = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let center = CGPoint(x: total.x / count, y: total.y / count)
        let sumSquared = points.reduce(CGFloat.zero) { total, point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            return total + dx * dx + dy * dy
        }
        return (center, max(12, 2 * sqrt(sumSquared / count)))
    }
}
