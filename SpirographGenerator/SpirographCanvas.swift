import SwiftUI

struct SpirographCanvas: View {
    let geometry: SpirographGeometry
    let colors: [Color]
    let backgroundColor: Color
    let lineWidth: Double
    /// When set, the line is drawn at true scale: this width in mm on a drawing `outputSize` mm wide.
    var physicalWidth: (mm: Double, outputSize: Double)? = nil
    /// Auxiliary loops (skirt) in geometry units, drawn faintly underneath the drawing.
    var auxLoops: [[CGPoint]] = []
    var auxBeadMM: Double = 0.45
    var auxColor: Color = .gray
    /// Extent to fit into the view (geometry units); defaults to the drawing itself.
    var fitExtent: Double? = nil

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(backgroundColor))
            guard geometry.extent > 0 else { return }

            let margin: CGFloat = 28
            let half = max(1, min(size.width, size.height) / 2 - margin)
            let fit = CGFloat(max(fitExtent ?? geometry.extent, geometry.extent))
            let scale = half / fit
            let cx = size.width / 2, cy = size.height / 2
            func map(_ p: CGPoint) -> CGPoint { CGPoint(x: cx + p.x * scale, y: cy - p.y * scale) }

            // Pixels per millimetre (only meaningful when drawing at true scale).
            var pxPerMM: CGFloat? = nil
            if let physical = physicalWidth, physical.outputSize > 0 {
                pxPerMM = scale / CGFloat((physical.outputSize / 2) / geometry.extent)
            }

            // Skirt (auxiliary): one stroked path so touching loops form an even, light band.
            if !auxLoops.isEmpty {
                var aux = Path()
                for loop in auxLoops {
                    guard let first = loop.first else { continue }
                    aux.move(to: map(first))
                    for p in loop.dropFirst() { aux.addLine(to: map(p)) }
                }
                let width = max(0.5, CGFloat(auxBeadMM) * (pxPerMM ?? 1))
                ctx.stroke(aux, with: .color(auxColor.opacity(0.3)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            var strokeWidth = CGFloat(lineWidth)
            if let physical = physicalWidth, let pxPerMM {
                strokeWidth = max(0.5, CGFloat(physical.mm) * pxPerMM)
            }
            let style = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)

            for (i, curve) in geometry.curves.enumerated() {
                guard let first = curve.first else { continue }
                var path = Path()
                path.move(to: map(first))
                for p in curve.dropFirst() { path.addLine(to: map(p)) }
                ctx.stroke(path, with: .color(colors[i % max(colors.count, 1)]), style: style)
            }
        }
    }
}
