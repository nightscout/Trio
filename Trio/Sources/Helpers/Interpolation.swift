import CoreGraphics

func pointInLine(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    var c: CGPoint = .zero
    c.x = a.x - ((a.x - b.x) * t)
    c.y = a.y - ((a.y - b.y) * t)
    return c
}

func pointInQuadCurve(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
    let a = pointInLine(p0, p1, t)
    let b = pointInLine(p1, p2, t)
    return pointInLine(a, b, t)
}

func pointInCubicCurve(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let a = pointInQuadCurve(p0, p1, p2, t)
    let b = pointInQuadCurve(p1, p2, p3, t)
    return pointInLine(a, b, t)
}

extension BinaryFloatingPoint {
    func inCubicCurve(_ p1: CGPoint, _ p2: CGPoint) -> Self {
        Self(pointInCubicCurve(.zero, p1, p2, CGPoint(x: 2, y: 1), CGFloat(self)).y)
    }

    func clamped(_ range: ClosedRange<Self> = 0 ... 1) -> Self {
        guard self < range.upperBound else { return range.upperBound }
        guard self > range.lowerBound else { return range.lowerBound }
        return self
    }
}
