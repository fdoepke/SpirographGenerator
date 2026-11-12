import SwiftUI

struct ControlsView: View {
    @Bindable var model: SpirographModel
    let geometry: SpirographGeometry

    var body: some View {
        Form {
            Section {
                HStack {
                    Menu("Presets") {
                        ForEach(SpirographPreset.all) { preset in
                            Button(preset.name) { model.apply(preset) }
                        }
                    }
                    Button("Randomize") { model.randomize() }
                }
            }

            Section("Gears") {
                Picker("Mode", selection: $model.curveType) {
                    ForEach(CurveType.allCases) { Text($0.rawValue).tag($0) }
                }
                ParameterSlider("Fixed ring radius (R)", value: $model.fixedRadius, range: 10...200)
                ParameterSlider("Rolling wheel radius (r)", value: $model.rollingRadius, range: 1...200)
                ParameterSlider("Pen offset (d)", value: $model.penOffset, range: 0...200, step: 0.5)
            }

            Section("Loops") {
                Toggle("Close curve automatically", isOn: $model.autoClose)
                if !model.autoClose {
                    ParameterSlider("Turns around the ring", value: $model.manualTurns, range: 0.5...100, step: 0.5)
                }
                LabeledContent("Petals", value: "\(geometry.petals)")
                LabeledContent("Turns to close", value: "\(model.closingTurns)")
                ParameterSlider("Smoothness (points per turn)", value: $model.resolution, range: 36...2000)
            }

            Section("Copies & rotation") {
                ParameterSlider("Copies", value: $model.copies, range: 1...72)
                ParameterSlider("Angle between copies (°)", value: $model.copyAngle, range: 0...180, step: 0.5)
                ParameterSlider("Rotation (°)", value: $model.rotation, range: 0...360)
            }

            Section("Appearance") {
                ColorPicker("Line colour", selection: $model.lineColor, supportsOpacity: false)
                ColorPicker("Background", selection: $model.backgroundColor, supportsOpacity: false)
                Toggle("Rainbow copies", isOn: $model.rainbow)
                if model.gcodeFlavor == .prusa {
                    ParameterSlider("Line width (mm, printed)", value: $model.printLineWidth, range: 0.2...20, step: 0.05)
                    Text("Printed as \(passesDescription). The preview shows the line at true scale for the \(Exporter.num(model.outputSize)) mm drawing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ParameterSlider("Preview line width (pt)", value: $model.lineWidth, range: 0.25...8, step: 0.25)
                }
            }

            Section("Export size") {
                ParameterSlider("Drawing size (mm)", value: $model.outputSize, range: 10...1000)
                ParameterSlider("SVG stroke width (mm)", value: $model.svgStroke, range: 0.05...3, step: 0.05)
                Toggle("Include background in SVG", isOn: $model.svgIncludeBackground)
                Toggle("Include skirt in SVG", isOn: $model.svgIncludeSkirt)
                if model.svgIncludeSkirt {
                    ColorPicker("Skirt colour", selection: $model.skirtColor, supportsOpacity: false)
                    ParameterSlider("Skirt loops", value: $model.skirtLoops, range: 1...10)
                    ParameterSlider("Skirt distance from drawing (mm)", value: $model.skirtDistance, range: 0.5...30, step: 0.5)
                    Text("The skirt is a separate group (id \"skirt\") around the outside of the drawing, drawn with the SVG stroke width. The SVG grows by \(Exporter.num((model.svgSkirtMargin * 10).rounded() / 10)) mm on each side to fit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("G-code") {
                Picker("Format", selection: $model.gcodeFlavor) {
                    ForEach(GCodeFlavor.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                switch model.gcodeFlavor {
                case .plain:
                    Toggle("Origin at centre (off = bottom-left)", isOn: $model.originCentered)
                    Picker("Pen control", selection: $model.penMode) {
                        ForEach(PenMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    switch model.penMode {
                    case .zAxis:
                        zControls(up: "Pen up Z (mm)", down: "Pen down Z (mm)")
                    case .custom:
                        CommandEditor(title: "Pen up commands", text: $model.penUpCommands)
                        CommandEditor(title: "Pen down commands", text: $model.penDownCommands)
                    }
                    feedControls

                case .cnc:
                    Toggle("Origin at centre (off = bottom-left)", isOn: $model.originCentered)
                    Toggle("Line numbers (N10, N20 …)", isOn: $model.cncLineNumbers)
                    zControls(up: "Safe Z height (mm)", down: "Work Z depth (mm)")
                    feedControls

                case .prusa:
                    Picker("Printer", selection: $model.prusaPrinter) {
                        ForEach(PrusaPrinter.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("The spirograph line is printed as a thin wall, centred on the \(Exporter.num(model.prusaPrinter.bedSize.width)) × \(Exporter.num(model.prusaPrinter.bedSize.depth)) mm bed. Size is set under Export size.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.exceedsPrusaBed {
                        Label(model.mmuMultiColorActive
                              ? "Drawing plus wipe tower does not fit on the bed – reduce the drawing size under Export size."
                              : "Drawing size is larger than the bed – reduce it under Export size.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if model.gcodeFlavor == .prusa {
                prusaSections
            }

            Section {
                HStack {
                    Button("Export SVG…") { model.exportSVG() }
                    Button("Export G-code…") { model.exportGCode() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.filament) { model.applyFilamentDefaults() }
        .onChange(of: model.nozzleDiameter) { model.applyNozzleDefaults() }
        .onChange(of: model.prusaPrinter) {
            model.applyRetractionDefaults()
            if model.customStartEnd { model.resetPrusaTemplates() }
        }
        .onChange(of: model.customStartEnd) {
            if model.customStartEnd && model.prusaStartGCode.isEmpty { model.resetPrusaTemplates() }
        }
    }

    private var passesDescription: String {
        let plan = model.extrusionPlan
        return "\(plan.passes) pass\(plan.passes == 1 ? "" : "es") × \(Exporter.num((plan.passWidth * 1000).rounded() / 1000)) mm"
    }

    @ViewBuilder
    private var feedControls: some View {
        ParameterSlider("Draw feed rate (mm/min)", value: $model.feedRate, range: 50...10000, step: 10)
        ParameterSlider("Travel rate (mm/min)", value: $model.travelRate, range: 50...20000, step: 10)
    }

    @ViewBuilder
    private var prusaSections: some View {
        Section("Printer & filament") {
            Picker("Nozzle diameter", selection: $model.nozzleDiameter) {
                ForEach(SpirographModel.nozzleSizes, id: \.self) { Text("\(Exporter.num($0)) mm").tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Filament", selection: $model.filament) {
                ForEach(Filament.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            ParameterSlider("Nozzle temperature (°C)", value: $model.nozzleTemp, range: 150...320)
            ParameterSlider("Bed temperature (°C)", value: $model.bedTemp, range: 0...120)
            ParameterSlider("Part cooling fan (%)", value: $model.fanPercent, range: 0...100)
        }

        if model.prusaPrinter.hasMMU {
            mmuSection
        }

        Section("Layers & extrusion") {
            ParameterSlider("First layer height (mm)", value: $model.firstLayerHeight, range: 0.05...1, step: 0.01)
            ParameterSlider("Layer height (mm)", value: $model.layerHeight, range: 0.05...1, step: 0.01)
            ParameterSlider("Number of layers", value: $model.layerCount, range: 1...500)
            LabeledContent("Wall height", value: "\(Exporter.num(model.printHeight)) mm")
            ParameterSlider("Line width (mm)", value: $model.printLineWidth, range: 0.2...20, step: 0.05)
            LabeledContent("Extrusion passes", value: passesDescription)
            ParameterSlider("Preferred single-pass width (mm)", value: $model.extrusionWidth, range: 0.1...2, step: 0.01)
            if model.extrusionPlan.passes == 1 && model.printLineWidth < model.nozzleDiameter * 0.9 {
                Text("A \(Exporter.num(model.printLineWidth)) mm line is thinner than a \(Exporter.num(model.nozzleDiameter)) mm nozzle prints reliably – use at least \(Exporter.num(model.nozzleDiameter * 0.9)) mm or a smaller nozzle.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ParameterSlider("Flow (%)", value: $model.extrusionMultiplier, range: 50...150)
        }

        Section("Speed & retraction") {
            ParameterSlider("Print speed (mm/s)", value: $model.printSpeed, range: 5...300)
            if model.printSpeed > model.volumetricSpeedLimit {
                Text("Limited to \(Int(model.volumetricSpeedLimit)) mm/s by the \(model.filament.rawValue) max volumetric speed (\(Exporter.num(model.filament.maxVolumetricSpeed)) mm³/s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ParameterSlider("First layer speed (mm/s)", value: $model.firstLayerSpeed, range: 5...100)
            ParameterSlider("Travel speed (mm/s)", value: $model.printTravelSpeed, range: 20...500)
            ParameterSlider("Retraction length (mm)", value: $model.retractLength, range: 0...8, step: 0.05)
            ParameterSlider("Retraction speed (mm/s)", value: $model.retractSpeed, range: 5...100)
            ParameterSlider("Z-hop on travel (mm)", value: $model.zHop, range: 0...2, step: 0.05)
        }

        Section("Skirt") {
            Toggle("Print a skirt around the drawing", isOn: $model.skirtEnabled)
            if model.skirtEnabled {
                ParameterSlider("Loops", value: $model.skirtLoops, range: 1...10)
                ParameterSlider("Distance from drawing (mm)", value: $model.skirtDistance, range: 0.5...30, step: 0.5)
                ParameterSlider("Skirt height (layers)", value: $model.skirtHeight, range: 1...20)
                Text("Separate loops around the outside of the drawing only – they prime the nozzle and show first-layer adhesion before the spirograph starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Line crossings") {
            Picker("Where the line crosses itself", selection: $model.crossingMode) {
                ForEach(CrossingMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            if model.crossingMode != .extrude {
                ParameterSlider("Crossing clearance (% of bead width)", value: $model.crossingClearance, range: 30...100)
                Text(model.crossingMode == .stop
                     ? "The nozzle keeps moving across lines already printed on the same layer without extruding, so crossings don't get double material."
                     : "Retracts and lifts by the Z-hop height to hop over lines already printed on the same layer, then unretracts. Cleaner, but slower with many crossings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Start / end G-code") {
            Toggle("Customize start & end G-code", isOn: $model.customStartEnd)
            if model.customStartEnd {
                CommandEditor(title: "Start G-code", text: $model.prusaStartGCode, height: 200)
                CommandEditor(title: "End G-code", text: $model.prusaEndGCode, height: 110)
                Text("Placeholders: {nozzle_temp} {bed_temp} {nozzle_diameter} {printer_model} {filament_type} {area_x} {area_y} {area_w} {area_h} {end_z} {tool}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to \(model.prusaPrinter.displayName) defaults") { model.resetPrusaTemplates() }
            } else {
                Text("Uses the standard \(model.prusaPrinter.displayName) sequence: heat, home, mesh bed levelling, purge line; then park and cool down.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var mmuSection: some View {
        Section("MMU3") {
            Toggle("Multi-colour (one filament slot per copy)", isOn: $model.mmuMultiColor)
            if model.mmuMultiColor {
                Picker("Colours", selection: $model.mmuColorCount) {
                    ForEach(2...5, id: \.self) { Text("\($0) – slots 1–\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                ForEach(0..<model.mmuColorCount, id: \.self) { i in
                    ColorPicker("Slot \(i + 1) filament colour", selection: $model.slotColors[i], supportsOpacity: false)
                }
                if model.copyCount < 2 {
                    Label("Increase Copies (under Copies & rotation) – each copy is printed in the next slot.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if model.copyCount < model.mmuColorCount {
                    Text("Only \(model.copyCount) copies, so only slots 1–\(model.copyCount) are used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ParameterSlider("Purge volume per change (mm³)", value: $model.mmuPurgeVolume, range: 15...300)
                ParameterSlider("Wipe tower depth (mm)", value: $model.mmuTowerDepth, range: 20...150)
                Toggle("Ramming before tool change", isOn: $model.mmuRamming)
                if model.mmuMultiColorActive {
                    let layout = model.prusaLayout()
                    if let tower = layout.tower {
                        Text("Wipe tower \(Exporter.num(Double(tower.width))) × \(Exporter.num(Double(tower.height))) mm at the right edge of the bed · \(layout.changesPerLayer) tool changes per layer, \(layout.changesPerLayer * model.layerCountInt) in total. All slots use the \(model.filament.rawValue) settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Picker("Filament slot", selection: $model.mmuSlot) {
                    ForEach(1...5, id: \.self) { Text("Slot \($0)").tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private func zControls(up: String, down: String) -> some View {
        ParameterSlider(up, value: $model.penUpZ, range: -10...50, step: 0.1)
        ParameterSlider(down, value: $model.penDownZ, range: -10...50, step: 0.1)
        ParameterSlider("Plunge rate (mm/min)", value: $model.plungeRate, range: 10...5000, step: 10)
    }
}

/// A labelled slider with an editable numeric field.
struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
            }
            Slider(value: Binding(
                get: { min(max(value, range.lowerBound), range.upperBound) },
                set: { value = ($0 / step).rounded() * step }
            ), in: range)
        }
    }
}

struct CommandEditor: View {
    let title: String
    @Binding var text: String
    var height: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
        }
    }
}
