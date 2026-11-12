import SwiftUI

struct ContentView: View {
    @Bindable var model: SpirographModel

    var body: some View {
        let geometry = model.generate()
        let count = geometry.curves.count
        let colors = (0..<count).map { model.color(forCopy: $0, of: count) }
        let skirtLoops = model.previewSkirtLoops(for: geometry)
        // Zoom out so the skirt fits: extra mm beyond the drawing, converted to geometry units.
        let mmPerUnit = geometry.extent > 0 ? (model.outputSize / 2) / geometry.extent : 1
        let extraMM = model.showsSkirtInPreview ? model.printLineWidth / 2 + model.skirtExtent : 0
        let fitExtent = geometry.extent + extraMM / mmPerUnit

        HSplitView {
            ControlsView(model: model, geometry: geometry)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)

            ZStack(alignment: .bottom) {
                SpirographCanvas(geometry: geometry, colors: colors,
                                 backgroundColor: model.backgroundColor,
                                 lineWidth: model.lineWidth,
                                 physicalWidth: model.gcodeFlavor == .prusa
                                    ? (mm: model.printLineWidth, outputSize: model.outputSize) : nil,
                                 auxLoops: skirtLoops,
                                 auxBeadMM: model.extrusionPlan.passWidth,
                                 auxColor: colors.first ?? model.lineColor,
                                 fitExtent: fitExtent)
                Text("Petals \(geometry.petals)  ·  Turns \(Exporter.num(geometry.turns))  ·  Copies \(count)  ·  \(geometry.pointCount.formatted()) points  ·  \(Exporter.num(model.outputSize)) mm")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
            .frame(minWidth: 420, minHeight: 420)
        }
        .onChange(of: model.exportSettings) { model.saveExportSettings() }
        .toolbar {
            ToolbarItemGroup {
                Button { model.randomize() } label: { Label("Randomize", systemImage: "dice") }
                Button { model.exportSVG() } label: { Label("Export SVG", systemImage: "square.and.arrow.up") }
                Button { model.exportGCode() } label: { Label("Export G-code", systemImage: "pencil.and.outline") }
            }
        }
    }
}
