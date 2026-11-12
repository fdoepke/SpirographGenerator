import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Exporter {

    // MARK: SVG

    static func svg(model: SpirographModel, geometry g: SpirographGeometry) -> String {
        let size = model.outputSize
        let half = size / 2
        let scale = g.extent > 0 ? half / g.extent : 1

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<!-- Spirograph Generator: \(model.curveType.rawValue), R=\(model.intFixed) r=\(model.intRolling) d=\(num(model.penOffset)) -->\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(num(size))mm\" height=\"\(num(size))mm\" viewBox=\"0 0 \(num(size)) \(num(size))\">\n"
        if model.svgIncludeBackground {
            out += "  <rect width=\"100%\" height=\"100%\" fill=\"\(hex(model.backgroundColor))\"/>\n"
        }

        let count = g.curves.count
        for (i, curve) in g.curves.enumerated() {
            guard !curve.isEmpty else { continue }
            var d = ""
            d.reserveCapacity(curve.count * 18)
            for (j, p) in curve.enumerated() {
                d += j == 0 ? "M" : (j == 1 ? " L" : " ")
                d += "\(num(half + Double(p.x) * scale)) \(num(half - Double(p.y) * scale))"
            }
            let stroke = hex(model.color(forCopy: i, of: count))
            out += "  <path d=\"\(d)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(num(model.svgStroke))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
        }
        out += "</svg>\n"
        return out
    }

    // MARK: G-code

    static func gcode(model: SpirographModel, geometry g: SpirographGeometry) -> String {
        switch model.gcodeFlavor {
        case .plain: return plainGCode(model, g)
        case .cnc: return cncGCode(model, g)
        case .prusa: return prusaGCode(model, g)
        }
    }

    /// Converts the curves into machine coordinates (mm), dropping points closer than `minSegment`.
    private static func toolpaths(_ model: SpirographModel, _ g: SpirographGeometry,
                                  originX: Double, originY: Double,
                                  minSegment: Double = 0.02) -> [[CGPoint]] {
        let scale = g.extent > 0 ? (model.outputSize / 2) / g.extent : 1
        return g.curves.compactMap { curve -> [CGPoint]? in
            guard !curve.isEmpty else { return nil }
            var out: [CGPoint] = []
            out.reserveCapacity(curve.count)
            var pending: CGPoint? = nil
            for p in curve {
                let q = CGPoint(x: originX + Double(p.x) * scale, y: originY + Double(p.y) * scale)
                if let last = out.last, Double(hypot(q.x - last.x, q.y - last.y)) < minSegment {
                    pending = q
                    continue
                }
                out.append(q)
                pending = nil
            }
            if let q = pending { out.append(q) }
            return out
        }
    }

    private static func xy(_ p: CGPoint) -> String { "X\(num(Double(p.x))) Y\(num(Double(p.y)))" }

    private static func descriptionLines(_ model: SpirographModel, _ g: SpirographGeometry) -> [String] {
        [
            "Spirograph Generator",
            "\(model.curveType.rawValue) R=\(model.intFixed) r=\(model.intRolling) d=\(num(model.penOffset))",
            "Copies: \(g.curves.count) Turns: \(num(g.turns))",
            "Drawing size: \(num(model.outputSize)) x \(num(model.outputSize)) mm",
        ]
    }

    // MARK: Plain

    private static func plainGCode(_ model: SpirographModel, _ g: SpirographGeometry) -> String {
        let origin = model.originCentered ? 0 : model.outputSize / 2
        let paths = toolpaths(model, g, originX: origin, originY: origin)

        func penUp() -> [String] {
            switch model.penMode {
            case .zAxis: return ["G0 Z\(num(model.penUpZ)) ; pen up"]
            case .custom: return commandLines(model.penUpCommands)
            }
        }
        func penDown() -> [String] {
            switch model.penMode {
            case .zAxis: return ["G1 Z\(num(model.penDownZ)) F\(num(model.plungeRate)) ; pen down"]
            case .custom: return commandLines(model.penDownCommands)
            }
        }

        var lines = descriptionLines(model, g).map { "; " + $0 }
        lines.append("; Origin " + (model.originCentered ? "at centre" : "at bottom-left"))
        lines += ["G21 ; units: millimetres", "G90 ; absolute positioning"]
        lines += penUp()
        for path in paths {
            guard let start = path.first else { continue }
            lines.append("G0 \(xy(start)) F\(num(model.travelRate))")
            lines += penDown()
            for (i, p) in path.dropFirst().enumerated() {
                lines.append("G1 \(xy(p))" + (i == 0 ? " F\(num(model.feedRate))" : ""))
            }
            lines += penUp()
        }
        lines.append("G0 X\(num(origin)) Y\(num(origin)) F\(num(model.travelRate)) ; return to origin")
        lines.append("M2 ; end of program")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: CNC

    /// RS-274 style for GRBL / LinuxCNC / Mach3: % delimiters, (comments), modal setup line,
    /// safe-Z retracts, optional N line numbers and M30 program end.
    private static func cncGCode(_ model: SpirographModel, _ g: SpirographGeometry) -> String {
        let origin = model.originCentered ? 0 : model.outputSize / 2
        let paths = toolpaths(model, g, originX: origin, originY: origin)
        let safeZ = num(model.penUpZ), workZ = num(model.penDownZ)

        var body: [String] = []
        func comment(_ s: String) -> String {
            "(" + s.replacingOccurrences(of: "(", with: "[").replacingOccurrences(of: ")", with: "]") + ")"
        }

        body += descriptionLines(model, g).map(comment)
        body.append(comment("Origin " + (model.originCentered ? "at centre" : "at bottom-left") + ", safe Z \(safeZ), work Z \(workZ)"))
        body.append("G17 G21 G90 G94 " + comment("XY plane, mm, absolute, feed per minute"))
        body.append("G0 Z\(safeZ)")
        for (n, path) in paths.enumerated() {
            guard let start = path.first else { continue }
            body.append(comment("Path \(n + 1) of \(paths.count)"))
            body.append("G0 \(xy(start))")
            body.append("G1 Z\(workZ) F\(num(model.plungeRate))")
            for (i, p) in path.dropFirst().enumerated() {
                body.append("G1 \(xy(p))" + (i == 0 ? " F\(num(model.feedRate))" : ""))
            }
            body.append("G0 Z\(safeZ)")
        }
        body.append("G0 X\(num(origin)) Y\(num(origin))")
        body.append("M30 " + comment("program end"))

        if model.cncLineNumbers {
            body = body.enumerated().map { i, line in
                line.hasPrefix("(") ? line : "N\((i + 1) * 10) \(line)"
            }
        }
        return (["%"] + body + ["%"]).joined(separator: "\n") + "\n"
    }

    // MARK: Prusa

    /// Prints the spirograph line as a thin wall on a Prusa printer: PrusaSlicer-style metadata,
    /// per-printer start/end G-code, relative extrusion (M83), retraction + Z-hop on travels,
    /// ;LAYER_CHANGE / ;TYPE / ;WIDTH / ;HEIGHT annotations for the PrusaSlicer G-code viewer,
    /// M73 progress / remaining time, and – on MMU printers – one filament slot per copy with
    /// ramming, tool change and purging on a wipe tower.
    private static func prusaGCode(_ model: SpirographModel, _ g: SpirographGeometry) -> String {
        let printer = model.prusaPrinter
        let bed = printer.bedSize
        let layout = model.prusaLayout()
        let multi = model.mmuMultiColorActive

        // Paths in bed coordinates, each tagged with its filament slot.
        let rawPaths = toolpaths(model, g, originX: layout.centerX, originY: layout.centerY, minSegment: 0.05)
        let jobs: [(path: [CGPoint], slot: Int)] = rawPaths.enumerated()
            .map { (path: $0.element, slot: model.slot(forCopy: $0.offset)) }
            .filter { $0.path.count > 1 }
        let tools = model.mmuToolsUsed.filter { t in jobs.contains { $0.slot == t } }
        let firstTool = tools.first ?? model.mmuSlot

        // Bounding box of the print incl. tower (for M555 / probing area).
        var minX = layout.centerX, minY = layout.centerY, maxX = layout.centerX, maxY = layout.centerY
        if let first = jobs.first?.path.first {
            minX = Double(first.x); maxX = minX; minY = Double(first.y); maxY = minY
        }
        for job in jobs {
            for p in job.path {
                minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
                minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
            }
        }
        if multi, let t = layout.tower {
            minX = min(minX, Double(t.minX)); maxX = max(maxX, Double(t.maxX))
            minY = min(minY, Double(t.minY)); maxY = max(maxY, Double(t.maxY))
        }

        let plan = model.extrusionPlan
        let w = plan.passWidth                                 // single-pass width (also used on the wipe tower)
        let halfLine = model.printLineWidth / 2
        let reach = halfLine + model.skirtExtent
        minX -= reach; maxX += reach; minY -= reach; maxY += reach
        let filamentArea = Double.pi * 0.875 * 0.875          // 1.75 mm filament
        let flow = model.extrusionMultiplier / 100
        let zFeed = printer.maxZFeed
        let travelSpeed = max(model.printTravelSpeed, 1)
        let retractSpeed = max(model.retractSpeed, 1)
        let maxVolumetric = model.filament.maxVolumetricSpeed
        let toolChangeSeconds = 30.0                          // MMU unload + load, rough estimate

        struct Layer { let z: Double; let height: Double; let speed: Double }
        var layers: [Layer] = []
        var z = 0.0
        for i in 0..<model.layerCountInt {
            let h = i == 0 ? model.firstLayerHeight : model.layerHeight
            z += h
            let wanted = i == 0 ? model.firstLayerSpeed : model.printSpeed
            let lw = plan.width(forLayerHeight: h)
            layers.append(Layer(z: z, height: h, speed: max(1, min(wanted, maxVolumetric / max(lw * h, 0.001)))))
        }
        let topZ = layers.last?.z ?? model.firstLayerHeight

        // MARK: body
        var body: [String] = []
        var progressMarks: [Int: Double] = [:]   // line index -> elapsed seconds
        var elapsed = 0.0
        var filamentUsed = 0.0
        var pos = CGPoint(x: 0, y: 0)
        var retracted = false
        var toolChanges = 0

        func mark() {
            progressMarks[body.count] = elapsed
            body.append("")
        }

        func crossSection(_ h: Double, _ width: Double) -> Double { max((width - h) * h + Double.pi * h * h / 4, 0) }

        /// Retract, hop, travel, lower, unretract. Short hops between neighbouring passes are plain moves.
        func travel(to p: CGPoint, z: Double, allowShortMove: Bool = false) {
            if allowShortMove && Double(hypot(p.x - pos.x, p.y - pos.y)) < 2 {
                body.append("G1 \(xy(p)) F\(num(travelSpeed * 60))")
                elapsed += Double(hypot(p.x - pos.x, p.y - pos.y)) / travelSpeed
                pos = p
                return
            }
            if model.retractLength > 0 && !retracted {
                body.append("G1 E-\(num(model.retractLength)) F\(num(retractSpeed * 60)) ; retract")
                elapsed += model.retractLength / retractSpeed
                retracted = true
            }
            body.append("G1 Z\(num(z + model.zHop)) F\(num(zFeed))")
            body.append("G1 \(xy(p)) F\(num(travelSpeed * 60)) ; travel")
            body.append("G1 Z\(num(z)) F\(num(zFeed))")
            elapsed += Double(hypot(p.x - pos.x, p.y - pos.y)) / travelSpeed
            elapsed += 2 * (model.zHop + 0.2) / (zFeed / 60)
            pos = p
            if retracted {
                body.append("G1 E\(num(model.retractLength)) F\(num(retractSpeed * 60)) ; unretract")
                elapsed += model.retractLength / retractSpeed
                retracted = false
            }
        }

        /// Extrudes along a polyline starting at the current position.
        func extrude<S: Sequence>(_ points: S, height: Double, speed: Double, width: Double? = nil,
                                  markEvery: Int = 400) where S.Element == CGPoint {
            let cs = crossSection(height, width ?? w)
            for (i, p) in points.enumerated() {
                let length = Double(hypot(p.x - pos.x, p.y - pos.y))
                let e = cs * length / filamentArea * flow
                filamentUsed += e
                body.append("G1 \(xy(p)) E\(numE(e))" + (i == 0 ? " F\(num(speed * 60))" : ""))
                elapsed += length / speed
                pos = p
                if (i + 1) % markEvery == 0 { mark() }
            }
        }

        /// Ramming (old filament), tool change and purge (new filament) on the wipe tower.
        func toolChange(to tool: Int, layer: Layer, index: Int) {
            guard let tower = layout.tower else { body.append("T\(tool - 1)"); return }
            let baseLine = index * layout.linesPerChange
            func lineEnds(_ j: Int) -> (CGPoint, CGPoint) {
                let x = Double(tower.minX) + (Double(baseLine + j) + 0.5) * w
                let a = CGPoint(x: x, y: Double(tower.minY)), b = CGPoint(x: x, y: Double(tower.maxY))
                return j % 2 == 0 ? (a, b) : (b, a)
            }
            let isFirstLayer = layer.z <= model.firstLayerHeight + 0.001
            let towerSpeed = isFirstLayer ? min(layer.speed, 20) : min(layer.speed, 40)

            body.append("; CP TOOLCHANGE START")
            body.append(";TYPE:Wipe tower")
            body.append(";WIDTH:\(num(w))")
            let (start, _) = lineEnds(0)
            travel(to: start, z: layer.z)

            // Ramming: push the old filament out fast to shape its tip for a clean unload.
            let cs = max(crossSection(layer.height, w), 0.001)
            for j in 0..<layout.rammingLines {
                let (a, b) = lineEnds(j)
                if j > 0 { extrude([a], height: layer.height, speed: towerSpeed) }
                let rammingVolumetric = min(maxVolumetric, 6 + Double(j) * 2)
                extrude([b], height: layer.height, speed: max(5, rammingVolumetric / cs))
            }

            body.append("T\(tool - 1) ; MMU3: switch to slot \(tool)")
            elapsed += toolChangeSeconds
            toolChanges += 1

            // Purge the new filament.
            for j in layout.rammingLines..<layout.linesPerChange {
                let (a, b) = lineEnds(j)
                extrude([a, b], height: layer.height, speed: towerSpeed)
            }
            body.append("; CP TOOLCHANGE END")
        }

        // Offset copies of each path, one per extrusion pass (computed once, reused on every layer).
        let offsetPaths: [[[CGPoint]]] = jobs.map { job in
            plan.offsets.map { offsetPolyline(job.path, by: $0) }
        }

        // Crossing detection: split every pass into runs that extrude or skip over already printed lines.
        // The result depends on the print order, which alternates per layer with multiple tools – cache per order.
        var crossingsSkipped = 0
        let skirtBead = w
        let crossingThreshold: Double = {
            let t = model.crossingClearance / 100 * w
            return plan.passes > 1 ? min(t, plan.spacing * 0.9) : t
        }()

        // Skirt: loops around the OUTER contour of the whole drawing only, at a distance (outermost first).
        let skirtLoops: [[CGPoint]] = model.skirtEnabled
            ? OutlineLoops.loops(paths: jobs.map { $0.path }, lineWidth: model.printLineWidth,
                                 gap: model.skirtDistance, bead: skirtBead, spacing: model.skirtSpacing,
                                 count: model.skirtLoopCount)
            : []

        var runCache: [[Int]: [Int: [PrintRun]]] = [:]
        func runs(forToolOrder order: [Int]) -> [Int: [PrintRun]] {
            if let cached = runCache[order] { return cached }
            var sequence: [(key: Int, points: [CGPoint])] = []
            for tool in order {
                for (jobIndex, job) in jobs.enumerated() where job.slot == tool {
                    for k in plan.offsets.indices {
                        var pts = offsetPaths[jobIndex][k]
                        if k % 2 == 1 { pts.reverse() }
                        sequence.append((key: jobIndex * 1000 + k, points: pts))
                    }
                }
            }
            let result: [Int: [PrintRun]]
            if model.crossingMode == .extrude {
                result = Dictionary(uniqueKeysWithValues: sequence.map { ($0.key, [PrintRun(points: $0.points, extrude: true)]) })
            } else {
                result = crossingRuns(sequence, threshold: crossingThreshold,
                                      window: max(4 * crossingThreshold, 2 * w) + 0.5)
            }
            runCache[order] = result
            return result
        }

        /// Emits one pass made of extrude / skip runs.
        func emitRuns(_ passRuns: [PrintRun], type: String, width: Double, layer: Layer,
                      allowShortMove: Bool, crossingMode: CrossingMode) {
            guard let first = passRuns.first?.points.first else { return }
            travel(to: first, z: layer.z, allowShortMove: allowShortMove)
            body.append(type)
            body.append(";WIDTH:\(num(width))")
            for run in passRuns {
                if run.extrude {
                    extrude(run.points.dropFirst(), height: layer.height, speed: layer.speed, width: width)
                    continue
                }
                // Crossing an already printed line.
                crossingsSkipped += 1
                let retractAtCrossing = crossingMode == .retract && model.retractLength > 0
                if retractAtCrossing {
                    body.append("G1 E-\(num(model.retractLength)) F\(num(retractSpeed * 60)) ; crossing: retract")
                    elapsed += model.retractLength / retractSpeed
                    if model.zHop > 0 { body.append("G1 Z\(num(layer.z + model.zHop)) F\(num(zFeed))") }
                }
                let feed = retractAtCrossing ? travelSpeed : layer.speed
                for (i, p) in run.points.dropFirst().enumerated() {
                    body.append("G1 \(xy(p))" + (i == 0 ? " F\(num(feed * 60)) ; crossing: no extrusion" : ""))
                    elapsed += Double(hypot(p.x - pos.x, p.y - pos.y)) / feed
                    pos = p
                }
                if retractAtCrossing {
                    if model.zHop > 0 { body.append("G1 Z\(num(layer.z)) F\(num(zFeed))") }
                    body.append("G1 E\(num(model.retractLength)) F\(num(retractSpeed * 60)) ; unretract")
                    elapsed += model.retractLength / retractSpeed
                }
                body.append(type)
            }
        }
        var currentTool = firstTool
        for (li, layer) in layers.enumerated() {
            body.append(";LAYER_CHANGE")
            body.append(";Z:\(num(layer.z))")
            body.append(";HEIGHT:\(num(layer.height))")
            mark()
            if li == 0 {
                body.append("M107 ; part fan off for first layer")
            } else if li == 1 {
                body.append("M106 S\(Int((model.fanPercent / 100 * 255).rounded())) ; part fan")
            }

            // Alternate tool order each layer so the loaded filament is used first.
            let order: [Int] = li % 2 == 0 ? tools : Array(tools.reversed())
            let printSkirt = li < model.skirtLayerCount
            let layerRuns = runs(forToolOrder: order)

            if printSkirt {
                // Skirt around the outside of the drawing (separate from it).
                for (n, loop) in skirtLoops.enumerated() where loop.count > 1 {
                    emitRuns([PrintRun(points: loop, extrude: true)], type: ";TYPE:Skirt/Brim", width: skirtBead,
                             layer: layer, allowShortMove: n > 0, crossingMode: .extrude)
                }
            }

            var changeIndex = 0
            for tool in order {
                if tool != currentTool {
                    toolChange(to: tool, layer: layer, index: changeIndex)
                    changeIndex += 1
                    currentTool = tool
                }
                let beadWidth = plan.width(forLayerHeight: layer.height)
                for (jobIndex, job) in jobs.enumerated() where job.slot == tool {
                    for k in plan.offsets.indices {
                        guard let passRuns = layerRuns[jobIndex * 1000 + k] else { continue }
                        let outer = k == 0 || k == plan.passes - 1
                        emitRuns(passRuns, type: outer ? ";TYPE:External perimeter" : ";TYPE:Perimeter",
                                 width: beadWidth, layer: layer, allowShortMove: k > 0,
                                 crossingMode: model.crossingMode)
                    }
                }
            }
        }
        if model.retractLength > 0 && !retracted {
            body.append("G1 E-\(num(model.retractLength)) F\(num(retractSpeed * 60)) ; retract")
        }

        // Fill in progress lines now that the total time is known.
        let total = max(elapsed, 1)
        for (index, t) in progressMarks {
            let percent = min(max(Int((t / total * 100).rounded(.down)), 0), 99)
            let remaining = max(Int(((total - t) / 60).rounded(.up)), 0)
            body[index] = "M73 P\(percent) R\(remaining)"
        }

        // MARK: assemble
        let values: [String: String] = [
            "printer_model": printer.rawValue,
            "nozzle_diameter": num(model.nozzleDiameter),
            "nozzle_temp": num(model.nozzleTemp.rounded()),
            "bed_temp": num(model.bedTemp.rounded()),
            "filament_type": model.filament.typeCode,
            "area_x": num(max(floor(minX), 0)),
            "area_y": num(max(floor(minY), 0)),
            "area_w": num(ceil(maxX - minX) + 1),
            "area_h": num(ceil(maxY - minY) + 1),
            "end_z": num(min(topZ + 10, printer.maxZ)),
            "tool": "T\(min(max(firstTool, 1), 5) - 1)",
        ]
        func fill(_ template: String) -> [String] {
            var t = template
            for (key, value) in values { t = t.replacingOccurrences(of: "{\(key)}", with: value) }
            return t.components(separatedBy: .newlines)
        }

        let startTemplate = model.customStartEnd && !model.prusaStartGCode.isEmpty ? model.prusaStartGCode : printer.defaultStartGCode
        let endTemplate = model.customStartEnd && !model.prusaEndGCode.isEmpty ? model.prusaEndGCode : printer.defaultEndGCode

        let filamentCm3 = filamentUsed * filamentArea / 1000
        let grams = filamentCm3 * model.filament.density
        let timeString = formatMinutes(total / 60)
        let posix = Locale(identifier: "en_US_POSIX")

        var lines: [String] = ["; generated by Spirograph Generator 1.0"]
        lines += descriptionLines(model, g).map { "; " + $0 }
        lines += [
            "; printer_model = \(printer.rawValue)",
            "; filament_type = \(model.filament.typeCode)",
        ]
        if printer.hasMMU {
            lines.append("; mmu_slots = " + tools.map { String($0) }.joined(separator: ","))
            if multi, let t = layout.tower {
                lines.append("; wipe_tower = X\(num(Double(t.minX))) Y\(num(Double(t.minY))) W\(num(Double(t.width))) D\(num(Double(t.height)))")
                lines.append("; purge_volume = \(num(model.mmuPurgeVolume)) mm3, total_toolchanges = \(toolChanges)")
            }
        }
        if model.skirtEnabled {
            lines.append("; skirt = \(model.skirtLoopCount) loops, distance \(num(model.skirtDistance)) mm, height \(model.skirtLayerCount) layers")
        }
        lines.append("; crossings = \(model.crossingMode.rawValue), skipped \(crossingsSkipped) (clearance \(num(crossingThreshold)) mm)")
        lines += [
            "; nozzle_diameter = \(num(model.nozzleDiameter))",
            "; filament_diameter = 1.75",
            "; temperature = \(num(model.nozzleTemp.rounded()))",
            "; bed_temperature = \(num(model.bedTemp.rounded()))",
            "; first_layer_height = \(num(model.firstLayerHeight))",
            "; layer_height = \(num(model.layerHeight))",
            "; layers = \(layers.count), height = \(num(topZ)) mm",
            "; line_width = \(num(model.printLineWidth)) mm (\(plan.passes) pass\(plan.passes == 1 ? "" : "es") x \(num(w)) mm, spacing \(num(plan.spacing)) mm)",
            "; extrusion_width = \(num(w))",
            "; bed_shape = 0x0,\(num(bed.width))x0,\(num(bed.width))x\(num(bed.depth)),0x\(num(bed.depth))",
            "; estimated printing time (normal mode) = \(timeString)",
        ]
        if model.exceedsPrusaBed {
            lines.append("; WARNING: drawing does not fit on the bed")
        }
        lines.append("")
        lines += fill(startTemplate)
        lines.append("M73 P0 R\(Int((total / 60).rounded(.up)))")
        lines.append("M221 S100 ; flow 100%")
        lines.append("G21 ; millimetres")
        lines.append("G90 ; absolute XYZ")
        lines.append("M83 ; relative extrusion")
        lines.append("")
        lines += body
        lines.append("")
        lines.append(";TYPE:Custom")
        lines += fill(endTemplate)
        lines += [
            "M73 P100 R0",
            "",
            "; filament used [mm] = \(String(format: "%.2f", locale: posix, filamentUsed))",
            "; filament used [cm3] = \(String(format: "%.2f", locale: posix, filamentCm3))",
            "; filament used [g] = \(String(format: "%.2f", locale: posix, grams))",
            "; total filament used [g] = \(String(format: "%.2f", locale: posix, grams))",
            "; total toolchanges = \(toolChanges)",
            "; estimated printing time (normal mode) = \(timeString)",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    struct PrintRun {
        var points: [CGPoint]
        var extrude: Bool
    }

    /// Splits each polyline (in print order) into runs, marking the parts that pass over lines printed
    /// earlier on the same layer. A point counts as "over" a line when it is closer than `threshold` to an
    /// earlier printed sample; samples printed within the last `window` mm of the same continuous line are
    /// ignored so a line never collides with itself right behind the nozzle.
    static func crossingRuns(_ sequence: [(key: Int, points: [CGPoint])],
                             threshold: Double, window: Double,
                             detect: Set<Int>? = nil) -> [Int: [PrintRun]] {
        let cell = max(threshold, 0.05)
        let step = cell / 2
        let t2 = threshold * threshold
        var grid: [Int64: [(x: Double, y: Double, s: Double)]] = [:]
        func key(_ cx: Int64, _ cy: Int64) -> Int64 { (cx << 32) ^ (cy & 0xFFFF_FFFF) }
        func cellOf(_ v: Double) -> Int64 { Int64((v / cell).rounded(.down)) }

        var s = 0.0                       // arc length counter for the whole layer
        var result: [Int: [PrintRun]] = [:]

        for (seqKey, pts) in sequence {
            s += 10_000                   // a new line: never "recent" to the previous one
            guard let start = pts.first else { result[seqKey] = []; continue }
            let detecting = detect?.contains(seqKey) ?? true   // non-detecting lines still block later ones

            func isCovered(_ x: Double, _ y: Double) -> Bool {
                let cx = cellOf(x), cy = cellOf(y)
                for dx in -1...1 {
                    for dy in -1...1 {
                        guard let bucket = grid[key(cx + Int64(dx), cy + Int64(dy))] else { continue }
                        for q in bucket where s - q.s > window {
                            let ddx = q.x - x, ddy = q.y - y
                            if ddx * ddx + ddy * ddy < t2 { return true }
                        }
                    }
                }
                return false
            }
            func insert(_ x: Double, _ y: Double) {
                grid[key(cellOf(x), cellOf(y)), default: []].append((x: x, y: y, s: s))
            }

            var runs: [PrintRun] = []
            var current = PrintRun(points: [start], extrude: !(detecting && isCovered(Double(start.x), Double(start.y))))
            if current.extrude { insert(Double(start.x), Double(start.y)) }
            var prev = start

            for p in pts.dropFirst() {
                let dx = Double(p.x - prev.x), dy = Double(p.y - prev.y)
                let len = (dx * dx + dy * dy).squareRoot()
                let n = max(1, Int((len / step).rounded(.up)))
                for i in 1...n {
                    let f = Double(i) / Double(n)
                    let x = Double(prev.x) + dx * f, y = Double(prev.y) + dy * f
                    s += len / Double(n)
                    let covered = detecting && isCovered(x, y)
                    let q = CGPoint(x: x, y: y)
                    if covered == current.extrude {
                        // State change: close the current run here and start a new one.
                        current.points.append(q)
                        runs.append(current)
                        current = PrintRun(points: [q], extrude: !covered)
                    } else if i == n {
                        current.points.append(q)   // keep only original vertices inside a run
                    }
                    if !covered { insert(x, y) }
                }
                prev = p
            }
            if current.points.count > 1 || runs.isEmpty { runs.append(current) }

            // Ignore tiny gaps (< 0.3 mm) – merge them back into extrusion.
            var merged: [PrintRun] = []
            for run in runs {
                var r = run
                if !r.extrude && polylineLength(r.points) < 0.3 { r.extrude = true }
                if var last = merged.last, last.extrude == r.extrude {
                    last.points.append(contentsOf: r.points.dropFirst())
                    merged[merged.count - 1] = last
                } else {
                    merged.append(r)
                }
            }
            result[seqKey] = merged
        }
        return result
    }

    static func polylineLength(_ pts: [CGPoint]) -> Double {
        zip(pts, pts.dropFirst()).reduce(0.0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }
    }

    /// Offsets a polyline sideways by `d` mm using mitred vertex normals (miter limited to 2×).
    static func offsetPolyline(_ pts: [CGPoint], by d: Double) -> [CGPoint] {
        guard abs(d) > 1e-9, pts.count > 1 else { return pts }
        let n = pts.count
        let closed = Double(hypot(pts[0].x - pts[n - 1].x, pts[0].y - pts[n - 1].y)) < 1e-6

        // Unit left-normals of each segment; degenerate segments inherit the previous normal.
        var normals: [(x: Double, y: Double)] = []
        normals.reserveCapacity(n - 1)
        var last: (x: Double, y: Double) = (0, 1)
        for i in 0..<(n - 1) {
            let dx = Double(pts[i + 1].x - pts[i].x), dy = Double(pts[i + 1].y - pts[i].y)
            let len = (dx * dx + dy * dy).squareRoot()
            if len > 1e-9 { last = (-dy / len, dx / len) }
            normals.append(last)
        }

        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let prev = i > 0 ? normals[i - 1] : (closed ? normals[n - 2] : normals[0])
            let next = i < n - 1 ? normals[i] : (closed ? normals[0] : normals[n - 2])
            var bx = prev.x + next.x, by = prev.y + next.y
            let blen = (bx * bx + by * by).squareRoot()
            var scale = 1.0
            if blen < 1e-6 {
                bx = next.x; by = next.y          // direction reversal (cusp)
            } else {
                bx /= blen; by /= blen
                let cosHalf = bx * next.x + by * next.y
                scale = 1 / max(cosHalf, 0.5)
            }
            out.append(CGPoint(x: Double(pts[i].x) + bx * d * scale, y: Double(pts[i].y) + by * d * scale))
        }
        return out
    }

    /// Extrusion amounts need more precision than coordinates.
    private static func numE(_ v: Double) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    private static func formatMinutes(_ m: Double) -> String {
        let total = Int((m * 60).rounded())
        let h = total / 3600, min = (total % 3600) / 60, s = total % 60
        return h > 0 ? "\(h)h \(min)m \(s)s" : "\(min)m \(s)s"
    }

    private static func commandLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Helpers

    /// Compact number formatting: up to 3 decimals, no trailing zeros, "." as separator.
    static func num(_ v: Double) -> String {
        var s = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        if s == "-0" { s = "0" }
        return s
    }

    static func hex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(ns.redComponent), c(ns.greenComponent), c(ns.blueComponent))
    }

    // MARK: Saving

    @MainActor
    static func save(_ text: String, suggestedName: String, fileExtension ext: String) {
        let panel = NSSavePanel()
        let type: UTType = ext == "svg" ? .svg : (UTType(filenameExtension: ext, conformingTo: .plainText) ?? .plainText)
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "\(suggestedName).\(ext)"
        panel.canCreateDirectories = true
        panel.title = ext == "svg" ? "Export SVG" : "Export G-code"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Outline loops (skirt)

/// Builds evenly spaced loops around the outer contour of a drawing (used for the skirt).
///
/// The drawing (centre-line paths printed `lineWidth` wide) is rasterised, a Euclidean distance
/// transform gives every grid point its distance to the nearest line, a flood fill from the border
/// finds the area *outside* the drawing, and marching squares traces iso-distance contours there.
/// Contours of one distance field never cross each other or the drawing, so loops are evenly spaced
/// and nothing is printed inside the spirograph.
enum OutlineLoops {

    /// Returns closed loops, outermost first.
    static func loops(paths: [[CGPoint]], lineWidth: Double, gap: Double, bead: Double,
                      spacing: Double, count: Int, maxGrid: Int = 1600) -> [[CGPoint]] {
        guard count > 0, paths.contains(where: { $0.count > 1 }) else { return [] }
        let half = lineWidth / 2
        let levels = (0..<count).map { gap + bead / 2 + Double($0) * spacing }   // distance from line edge
        let reach = half + (levels.last ?? 0) + bead

        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for path in paths {
            for p in path {
                minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
                minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
            }
        }
        let span = max(maxX - minX, maxY - minY) + 2 * reach
        let res = max(min(bead / 4, 0.1), span / Double(maxGrid))  // grid spacing in mm
        minX -= reach + 2 * res; minY -= reach + 2 * res
        maxX += reach + 2 * res; maxY += reach + 2 * res
        let nx = Int(((maxX - minX) / res).rounded(.up)) + 1
        let ny = Int(((maxY - minY) / res).rounded(.up)) + 1

        // 1. Seed grid points on the centre lines.
        let inf = 1e20
        var d2 = [Double](repeating: inf, count: nx * ny)
        for path in paths {
            for (a, b) in zip(path, path.dropFirst()) {
                let ax = Double(a.x), ay = Double(a.y), dx = Double(b.x) - ax, dy = Double(b.y) - ay
                let n = max(1, Int(((dx * dx + dy * dy).squareRoot() / (res * 0.5)).rounded(.up)))
                for k in 0...n {
                    let f = Double(k) / Double(n)
                    let i = Int(((ax + dx * f - minX) / res).rounded())
                    let j = Int(((ay + dy * f - minY) / res).rounded())
                    if i >= 0, j >= 0, i < nx, j < ny { d2[j * nx + i] = 0 }
                }
            }
        }

        // 2. Squared Euclidean distance transform (Felzenszwalb & Huttenlocher), rows then columns.
        var f = [Double](repeating: 0, count: max(nx, ny))
        var out = [Double](repeating: 0, count: max(nx, ny))
        var v = [Int](repeating: 0, count: max(nx, ny))
        var z = [Double](repeating: 0, count: max(nx, ny) + 1)
        func edt1d(_ n: Int) {
            var k = 0
            v[0] = 0; z[0] = -inf; z[1] = inf
            if n > 1 {
                for q in 1..<n {
                    var sv = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                    while sv <= z[k] {
                        k -= 1
                        sv = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                    }
                    k += 1
                    v[k] = q; z[k] = sv; z[k + 1] = inf
                }
            }
            k = 0
            for q in 0..<n {
                while z[k + 1] < Double(q) { k += 1 }
                let dq = Double(q - v[k])
                out[q] = dq * dq + f[v[k]]
            }
        }
        for j in 0..<ny {
            for i in 0..<nx { f[i] = d2[j * nx + i] }
            edt1d(nx)
            for i in 0..<nx { d2[j * nx + i] = out[i] }
        }
        for i in 0..<nx {
            for j in 0..<ny { f[j] = d2[j * nx + i] }
            edt1d(ny)
            for j in 0..<ny { d2[j * nx + i] = out[j] }
        }

        // 3. Distance from the line edge, and the outside region via flood fill from the border.
        var field = [Double](repeating: 0, count: nx * ny)
        for idx in 0..<(nx * ny) { field[idx] = d2[idx].squareRoot() * res - half }
        var outside = [Bool](repeating: false, count: nx * ny)
        var stack: [Int] = []
        func push(_ i: Int, _ j: Int) {
            let idx = j * nx + i
            if !outside[idx] && field[idx] > 0 { outside[idx] = true; stack.append(idx) }
        }
        for i in 0..<nx { push(i, 0); push(i, ny - 1) }
        for j in 0..<ny { push(0, j); push(nx - 1, j) }
        while let idx = stack.popLast() {
            let i = idx % nx, j = idx / nx
            if i > 0 { push(i - 1, j) }
            if i < nx - 1 { push(i + 1, j) }
            if j > 0 { push(i, j - 1) }
            if j < ny - 1 { push(i, j + 1) }
        }
        // Holes inside the drawing count as "inside" so no loop is traced there.
        for idx in 0..<(nx * ny) where !outside[idx] { field[idx] = -1 }

        // 4. Marching squares for each level, outermost first.
        var result: [[CGPoint]] = []
        for level in levels.reversed() {
            for loop in contours(field, nx: nx, ny: ny, level: level, originX: minX, originY: minY, res: res) {
                result.append(simplify(loop, tolerance: min(0.02, res / 4)))
            }
        }
        return result
    }

    private static func contours(_ field: [Double], nx: Int, ny: Int, level: Double,
                                 originX: Double, originY: Double, res: Double) -> [[CGPoint]] {
        // Edge ids: horizontal edge from (i,j) to (i+1,j) = 2*(j*nx+i); vertical (i,j)-(i,j+1) = 2*(j*nx+i)+1.
        func point(_ edge: Int) -> CGPoint {
            let idx = edge / 2, i = idx % nx, j = idx / nx
            let (i2, j2) = edge % 2 == 0 ? (i + 1, j) : (i, j + 1)
            let va = field[j * nx + i], vb = field[j2 * nx + i2]
            let t = abs(vb - va) < 1e-12 ? 0.5 : min(max((level - va) / (vb - va), 0), 1)
            return CGPoint(x: originX + (Double(i) + Double(i2 - i) * t) * res,
                           y: originY + (Double(j) + Double(j2 - j) * t) * res)
        }

        var segments: [(Int, Int)] = []
        var byEdge: [Int: [Int]] = [:]
        func add(_ a: Int, _ b: Int) {
            byEdge[a, default: []].append(segments.count)
            byEdge[b, default: []].append(segments.count)
            segments.append((a, b))
        }
        for j in 0..<(ny - 1) {
            for i in 0..<(nx - 1) {
                let v0 = field[j * nx + i], v1 = field[j * nx + i + 1]
                let v2 = field[(j + 1) * nx + i + 1], v3 = field[(j + 1) * nx + i]
                let c = (v0 >= level ? 1 : 0) | (v1 >= level ? 2 : 0) | (v2 >= level ? 4 : 0) | (v3 >= level ? 8 : 0)
                if c == 0 || c == 15 { continue }
                let e0 = 2 * (j * nx + i)             // bottom
                let e1 = 2 * (j * nx + i + 1) + 1     // right
                let e2 = 2 * ((j + 1) * nx + i)       // top
                let e3 = 2 * (j * nx + i) + 1         // left
                let centreHigh = (v0 + v1 + v2 + v3) / 4 >= level
                switch c {
                case 1, 14: add(e3, e0)
                case 2, 13: add(e0, e1)
                case 3, 12: add(e3, e1)
                case 4, 11: add(e1, e2)
                case 6, 9: add(e0, e2)
                case 7, 8: add(e3, e2)
                case 5:
                    if centreHigh { add(e0, e1); add(e2, e3) } else { add(e3, e0); add(e1, e2) }
                case 10:
                    if centreHigh { add(e3, e0); add(e1, e2) } else { add(e0, e1); add(e2, e3) }
                default: break
                }
            }
        }

        // Chain segments into closed loops.
        var used = [Bool](repeating: false, count: segments.count)
        var loops: [[CGPoint]] = []
        for start in segments.indices where !used[start] {
            used[start] = true
            let firstEdge = segments[start].0
            var edges = [firstEdge, segments[start].1]
            var current = segments[start].1
            while current != firstEdge {
                guard let next = byEdge[current]?.first(where: { !used[$0] }) else { break }
                used[next] = true
                current = segments[next].0 == current ? segments[next].1 : segments[next].0
                edges.append(current)
            }
            if edges.count > 3 { loops.append(edges.map(point)) }
        }
        return loops
    }

    /// Ramer–Douglas–Peucker simplification (keeps the closing point).
    private static func simplify(_ pts: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard pts.count > 3 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let ax = Double(pts[a].x), ay = Double(pts[a].y)
            let dx = Double(pts[b].x) - ax, dy = Double(pts[b].y) - ay
            let len = (dx * dx + dy * dy).squareRoot()
            var maxD = -1.0, maxI = a
            for i in (a + 1)..<b {
                let px = Double(pts[i].x) - ax, py = Double(pts[i].y) - ay
                // For a closed span (start == end) measure the distance to the start point instead.
                let d = len < 1e-9 ? (px * px + py * py).squareRoot() : abs(px * dy - py * dx) / len
                if d > maxD { maxD = d; maxI = i }
            }
            if maxD > tolerance {
                keep[maxI] = true
                stack.append((a, maxI)); stack.append((maxI, b))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }
}
