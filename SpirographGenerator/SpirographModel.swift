import SwiftUI
import AppKit
import Observation

enum CurveType: String, CaseIterable, Identifiable, Codable {
    case hypotrochoid = "Wheel inside ring"
    case epitrochoid = "Wheel outside ring"
    var id: String { rawValue }
}

enum PenMode: String, CaseIterable, Identifiable, Codable {
    case zAxis = "Z axis"
    case custom = "Custom commands (servo/laser)"
    var id: String { rawValue }
}

enum GCodeFlavor: String, CaseIterable, Identifiable, Codable {
    case plain = "Plain"
    case cnc = "CNC (GRBL / LinuxCNC / Mach3)"
    case prusa = "Prusa 3D printer (PrusaSlicer)"
    var id: String { rawValue }
}

enum PrusaPrinter: String, CaseIterable, Identifiable, Codable {
    case mk4s = "MK4S"
    case mk4 = "MK4"
    case coreOne = "COREONE"
    case mk3s = "MK3S"
    case mk3sMMU3 = "MK3SMMU3"
    case mini = "MINI"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mk4s: "Original Prusa MK4S"
        case .mk4: "Original Prusa MK4"
        case .coreOne: "Prusa CORE One"
        case .mk3s: "Original Prusa MK3S/+"
        case .mk3sMMU3: "Original Prusa MK3S/+ with MMU3"
        case .mini: "Original Prusa MINI/+"
        }
    }

    /// Printable bed area in mm (width, depth).
    var bedSize: (width: Double, depth: Double) {
        switch self {
        case .mk4s, .mk4, .mk3s, .mk3sMMU3: (250, 210)
        case .coreOne: (250, 220)
        case .mini: (180, 180)
        }
    }

    var maxZ: Double {
        switch self {
        case .mk4s, .mk4: 220
        case .coreOne: 270
        case .mk3s, .mk3sMMU3: 210
        case .mini: 180
        }
    }

    /// True for printers fitted with a Multi Material Unit.
    var hasMMU: Bool { self == .mk3sMMU3 }

    /// Safe Z feed rate in mm/min.
    var maxZFeed: Double { 720 }

    /// Default retraction in mm (MINI is Bowden, the others direct drive).
    var defaultRetraction: Double {
        switch self {
        case .mini: 3.2
        case .mk3s, .mk3sMMU3: 0.8
        default: 0.7
        }
    }

    /// Start G-code template. Placeholders: {printer_model} {nozzle_diameter} {nozzle_temp}
    /// {bed_temp} {filament_type} {area_x} {area_y} {area_w} {area_h} {end_z} {tool} (MMU slot, e.g. T0)
    var defaultStartGCode: String {
        switch self {
        case .mk4s, .mk4, .coreOne:
            return """
            M17 ; enable steppers
            M862.1 P{nozzle_diameter} ; nozzle diameter check
            M862.3 P "{printer_model}" ; printer model check
            M555 X{area_x} Y{area_y} W{area_w} H{area_h} ; print area
            G90 ; absolute coordinates
            M83 ; relative extrusion
            M140 S{bed_temp} ; set bed temperature
            M104 S170 ; nozzle temperature for probing
            M109 R170 ; wait for probing temperature
            M84 E ; extruder motor off
            G28 ; home all axes
            M190 S{bed_temp} ; wait for bed temperature
            G29 P1 ; invalidate mesh & probe print area
            G29 P3.2 ; interpolate mesh
            G29 P3.13 ; extrapolate mesh outside probe area
            G29 A ; activate mesh bed levelling
            M104 S{nozzle_temp} ; set nozzle temperature
            G0 X10 Y3 Z15 F4800 ; move to purge position
            M109 S{nozzle_temp} ; wait for nozzle temperature
            G92 E0
            G1 Z0.3 F720
            G1 X80 E5.2 F1000 ; purge line
            G1 X100 E1.5 F1000 ; purge line
            G1 X105 F8000 ; wipe
            G1 Z1 F720
            G92 E0
            """
        case .mk3s:
            return """
            M862.3 P "{printer_model}" ; printer model check
            M862.1 P{nozzle_diameter} ; nozzle diameter check
            G90 ; absolute coordinates
            M83 ; relative extrusion
            M104 S{nozzle_temp} ; set nozzle temperature
            M140 S{bed_temp} ; set bed temperature
            M190 S{bed_temp} ; wait for bed temperature
            M109 S{nozzle_temp} ; wait for nozzle temperature
            G28 W ; home all axes without mesh bed levelling
            G80 ; mesh bed levelling
            G1 Z0.2 F720
            G1 Y-3 F1000 ; go outside print area
            G92 E0
            G1 X60 E9 F1000 ; intro line
            G1 X100 E12.5 F1000 ; intro line
            G92 E0
            """
        case .mk3sMMU3:
            return """
            M862.3 P "{printer_model}" ; printer model check
            M862.1 P{nozzle_diameter} ; nozzle diameter check
            G90 ; absolute coordinates
            M83 ; relative extrusion
            M104 S{nozzle_temp} ; set nozzle temperature
            M140 S{bed_temp} ; set bed temperature
            M190 S{bed_temp} ; wait for bed temperature
            M109 S{nozzle_temp} ; wait for nozzle temperature
            G28 W ; home all axes without mesh bed levelling
            G80 ; mesh bed levelling
            G1 Y-3 F1000 ; go outside print area
            G92 E0
            {tool} ; MMU3: load selected filament to the nozzle
            G1 Z0.4 F1000
            G1 X55 E29 F1073 ; purge line
            G1 X5 E29 F1800 ; purge line
            G1 X55 E8 F2000 ; purge line
            G1 Z0.3 F1000
            G92 E0
            G1 X240 E25 F2200 ; purge line
            G1 Y-2 F1000
            G1 X55 E25 F1400 ; purge line
            G1 Z0.2 F1000
            G1 X5 E4 F1000 ; purge line
            G92 E0
            """
        case .mini:
            return """
            M862.3 P "{printer_model}" ; printer model check
            M862.1 P{nozzle_diameter} ; nozzle diameter check
            G90 ; absolute coordinates
            M83 ; relative extrusion
            M104 S170 ; nozzle temperature for probing
            M140 S{bed_temp} ; set bed temperature
            M109 R170 ; wait for probing temperature
            G28 ; home all axes
            G29 ; mesh bed levelling
            M104 S{nozzle_temp} ; set nozzle temperature
            M190 S{bed_temp} ; wait for bed temperature
            M109 S{nozzle_temp} ; wait for nozzle temperature
            G1 Z0.2 F720
            G1 Y-2 F1000 ; go outside print area
            G92 E0
            G1 X60 E8 F700 ; intro line
            G1 X100 E12.5 F700 ; intro line
            G92 E0
            """
        }
    }

    var defaultEndGCode: String {
        let park: String
        switch self {
        case .mk4s, .mk4: park = "G1 X241 Y170 F3600 ; park"
        case .coreOne: park = "G1 X125 Y200 F3600 ; park"
        case .mk3s: park = "G1 X0 Y200 F3600 ; present bed"
        case .mk3sMMU3: park = "G1 X0 Y200 F3600 ; present bed"
        case .mini: park = "G1 X178 Y178 F4200 ; park"
        }
        let unload = hasMMU ? "\nM702 ; MMU3: unload filament" : ""
        return """
        G1 Z{end_z} F720 ; move print head up\(unload)
        M104 S0 ; nozzle off
        M140 S0 ; bed off
        M107 ; fan off
        \(park)
        G4 ; wait for moves to finish
        M84 X Y E ; disable motors
        """
    }
}

enum Filament: String, CaseIterable, Identifiable, Codable {
    case pla = "PLA"
    case petg = "PETG"
    case asa = "ASA"
    case abs = "ABS"
    case pc = "PC"
    case tpu = "Flex / TPU"
    var id: String { rawValue }

    var typeCode: String { self == .tpu ? "FLEX" : rawValue }

    var nozzleTemp: Double {
        switch self { case .pla: 215; case .petg: 240; case .asa: 260; case .abs: 255; case .pc: 275; case .tpu: 240 }
    }
    var bedTemp: Double {
        switch self { case .pla: 60; case .petg: 85; case .asa: 105; case .abs: 100; case .pc: 110; case .tpu: 50 }
    }
    var fanPercent: Double {
        switch self { case .pla: 100; case .petg: 30; case .asa: 15; case .abs: 15; case .pc: 10; case .tpu: 50 }
    }
    /// Max volumetric speed in mm³/s.
    var maxVolumetricSpeed: Double {
        switch self { case .pla: 15; case .petg: 10; case .asa: 12; case .abs: 11; case .pc: 8; case .tpu: 3.5 }
    }
    /// Density in g/cm³.
    var density: Double {
        switch self { case .pla: 1.24; case .petg: 1.27; case .asa: 1.07; case .abs: 1.04; case .pc: 1.20; case .tpu: 1.21 }
    }
}

enum CrossingMode: String, CaseIterable, Identifiable, Codable {
    case extrude = "Extrude over crossings"
    case stop = "Stop extrusion"
    case retract = "Retract & lift"
    var id: String { rawValue }
}

/// The computed curve, in "gear units", centred on the origin with y pointing up.
struct SpirographGeometry {
    var curves: [[CGPoint]]
    /// Largest distance of any point from the centre (used for scaling).
    var extent: Double
    var petals: Int
    var turns: Double
    var pointCount: Int
}

struct SpirographPreset: Identifiable {
    let id = UUID()
    let name: String
    let type: CurveType
    let fixed: Double
    let rolling: Double
    let offset: Double
    var copies: Double = 1
    var copyAngle: Double = 0

    static let all: [SpirographPreset] = [
        .init(name: "Classic Star", type: .hypotrochoid, fixed: 105, rolling: 63, offset: 45),
        .init(name: "Rose", type: .hypotrochoid, fixed: 96, rolling: 36, offset: 30),
        .init(name: "Lace", type: .hypotrochoid, fixed: 150, rolling: 64, offset: 58),
        .init(name: "Deltoid", type: .hypotrochoid, fixed: 90, rolling: 30, offset: 30),
        .init(name: "Astroid", type: .hypotrochoid, fixed: 100, rolling: 25, offset: 25),
        .init(name: "Flower (outside)", type: .epitrochoid, fixed: 60, rolling: 15, offset: 25),
        .init(name: "Cardioid", type: .epitrochoid, fixed: 50, rolling: 50, offset: 50),
        .init(name: "Mandala", type: .hypotrochoid, fixed: 100, rolling: 39, offset: 30, copies: 12, copyAngle: 30),
        .init(name: "Twisted Ribbon", type: .hypotrochoid, fixed: 120, rolling: 45, offset: 40, copies: 24, copyAngle: 2.5),
    ]
}

func gcd(_ a: Int, _ b: Int) -> Int {
    var a = abs(a), b = abs(b)
    while b != 0 { (a, b) = (b, a % b) }
    return max(a, 1)
}

@Observable
final class SpirographModel {
    // MARK: Gears
    var curveType: CurveType = .hypotrochoid
    var fixedRadius: Double = 105      // R – the fixed ring
    var rollingRadius: Double = 63     // r – the rolling wheel
    var penOffset: Double = 45         // d – pen hole distance from wheel centre

    // MARK: Loops
    var autoClose = true
    var manualTurns: Double = 5
    var resolution: Double = 360       // points per turn

    // MARK: Copies & rotation
    var copies: Double = 1
    var copyAngle: Double = 10
    var rotation: Double = 0

    // MARK: Appearance
    var lineColor: Color = Color(red: 0.13, green: 0.36, blue: 0.85)
    var backgroundColor: Color = .white
    var lineWidth: Double = 1.2
    var rainbow = false

    // MARK: Export
    var outputSize: Double = 150       // mm, width & height of drawing
    var svgStroke: Double = 0.3        // mm
    var svgIncludeBackground = false
    var originCentered = true

    // MARK: G-code
    var feedRate: Double = 1500
    var travelRate: Double = 3000
    var penMode: PenMode = .zAxis
    var penUpZ: Double = 5
    var penDownZ: Double = 0
    var plungeRate: Double = 500
    var penUpCommands = "M3 S90\nG4 P0.3"
    var penDownCommands = "M3 S30\nG4 P0.3"
    var gcodeFlavor: GCodeFlavor = .plain
    var cncLineNumbers = false
    var prusaPrinter: PrusaPrinter = .mk4s

    // MARK: Prusa 3D printing
    var filament: Filament = .pla
    var nozzleDiameter: Double = 0.4
    var nozzleTemp: Double = 215
    var bedTemp: Double = 60
    var fanPercent: Double = 100
    var firstLayerHeight: Double = 0.2
    var layerHeight: Double = 0.2
    var layerCount: Double = 3
    var extrusionWidth: Double = 0.45       // preferred width of a single pass
    var printLineWidth: Double = 0.45       // total printed line thickness (mm)
    var extrusionMultiplier: Double = 100   // %
    var printSpeed: Double = 40             // mm/s
    var firstLayerSpeed: Double = 20        // mm/s
    var printTravelSpeed: Double = 150      // mm/s
    var retractLength: Double = 0.7         // mm
    var retractSpeed: Double = 35           // mm/s
    var zHop: Double = 0.2                  // mm
    var crossingMode: CrossingMode = .stop
    var skirtEnabled = false
    @ObservationIgnored private var skirtPreviewCache: (key: String, loops: [[CGPoint]])?
    var skirtLoops: Double = 2              // number of loops
    var skirtDistance: Double = 3           // mm between drawing and skirt
    var skirtHeight: Double = 1             // layers
    var crossingClearance: Double = 75      // % of bead width
    var mmuSlot = 1                         // 1…5
    var mmuMultiColor = false
    var mmuColorCount = 3                   // slots 1…n are used
    var mmuPurgeVolume: Double = 70         // mm³ per tool change
    var mmuTowerDepth: Double = 60          // mm
    var mmuRamming = true
    var slotColors: [Color] = [
        Color(red: 0.98, green: 0.42, blue: 0.13),
        Color(red: 0.13, green: 0.36, blue: 0.85),
        Color(red: 0.18, green: 0.62, blue: 0.30),
        Color(red: 0.80, green: 0.20, blue: 0.60),
        Color(red: 0.25, green: 0.25, blue: 0.25),
    ]
    var customStartEnd = false
    var prusaStartGCode = ""
    var prusaEndGCode = ""

    static let nozzleSizes: [Double] = [0.25, 0.4, 0.6, 0.8]

    var layerCountInt: Int { max(1, Int(layerCount.rounded())) }
    var printHeight: Double { firstLayerHeight + layerHeight * Double(layerCountInt - 1) }
    /// Highest print speed (mm/s) the filament's max volumetric speed allows for normal layers.
    var volumetricSpeedLimit: Double { filament.maxVolumetricSpeed / max(extrusionPlan.passWidth * layerHeight, 0.001) }

    /// How the printed line is built from side-by-side extrusion passes.
    struct ExtrusionPlan {
        var passes: Int
        /// Width of one pass at the normal layer height.
        var passWidth: Double
        /// Centre-to-centre distance between passes (adjacent beads overlap slightly to fuse).
        var spacing: Double
        /// Perpendicular offsets of each pass from the curve centre line.
        var offsets: [Double] { (0..<passes).map { (Double($0) - Double(passes - 1) / 2) * spacing } }
        /// Bead width for a given layer height that keeps the same spacing.
        func width(forLayerHeight h: Double) -> Double {
            passes == 1 ? passWidth : spacing + h * (1 - Double.pi / 4)
        }
    }

    /// Skirt loop spacing (adjacent loops touch, like perimeters).
    var skirtSpacing: Double {
        max(extrusionPlan.passWidth - firstLayerHeight * (1 - Double.pi / 4), 0.05)
    }
    var skirtLoopCount: Int { skirtEnabled ? max(1, Int(skirtLoops.rounded())) : 0 }
    var skirtLayerCount: Int { skirtEnabled ? min(max(1, Int(skirtHeight.rounded())), layerCountInt) : 0 }
    /// How far the skirt reaches beyond the edge of the printed line.
    var skirtExtent: Double {
        skirtEnabled ? skirtDistance + Double(skirtLoopCount - 1) * skirtSpacing + extrusionPlan.passWidth : 0
    }

    /// True when the preview should show the skirt.
    var showsSkirtInPreview: Bool { gcodeFlavor == .prusa && skirtEnabled }

    /// Skirt loops for the preview, in the same units as `geometry` (coarser grid, cached).
    func previewSkirtLoops(for g: SpirographGeometry) -> [[CGPoint]] {
        guard showsSkirtInPreview, g.extent > 0 else { return [] }
        let bead = extrusionPlan.passWidth
        let key = [curveType.rawValue, "\(intFixed)", "\(intRolling)", "\(penOffset)", "\(g.turns)",
                   "\(resolution)", "\(copyCount)", "\(copyAngle)", "\(rotation)", "\(outputSize)",
                   "\(printLineWidth)", "\(skirtDistance)", "\(bead)", "\(skirtSpacing)", "\(skirtLoopCount)"]
            .joined(separator: "|")
        if let cache = skirtPreviewCache, cache.key == key { return cache.loops }
        let mmPerUnit = (outputSize / 2) / g.extent
        let paths = g.curves.map { $0.map { CGPoint(x: Double($0.x) * mmPerUnit, y: Double($0.y) * mmPerUnit) } }
        let loops = OutlineLoops.loops(paths: paths, lineWidth: printLineWidth, gap: skirtDistance, bead: bead,
                                       spacing: skirtSpacing, count: skirtLoopCount, maxGrid: 450)
            .map { $0.map { CGPoint(x: Double($0.x) / mmPerUnit, y: Double($0.y) / mmPerUnit) } }
        skirtPreviewCache = (key: key, loops: loops)
        return loops
    }

    var extrusionPlan: ExtrusionPlan {
        let total = max(printLineWidth, 0.05)
        let h = layerHeight
        let overlap = h * (1 - Double.pi / 4)          // PrusaSlicer-style bead overlap
        let minPass = nozzleDiameter * 0.9, maxPass = nozzleDiameter * 2
        func passWidth(_ n: Int) -> Double { (total + Double(n - 1) * overlap) / Double(n) }
        var n = max(1, Int((total / max(extrusionWidth, 0.05)).rounded()))
        while passWidth(n) > maxPass { n += 1 }
        while n > 1 && passWidth(n) < minPass { n -= 1 }
        let w = passWidth(n)
        return ExtrusionPlan(passes: n, passWidth: w, spacing: n > 1 ? w - overlap : 0)
    }

    func applyFilamentDefaults() {
        nozzleTemp = filament.nozzleTemp
        bedTemp = filament.bedTemp
        fanPercent = filament.fanPercent
        applyRetractionDefaults()
    }

    func applyRetractionDefaults() {
        retractLength = filament == .tpu ? min(0.4, prusaPrinter.defaultRetraction) : prusaPrinter.defaultRetraction
    }

    func applyNozzleDefaults() {
        extrusionWidth = (nozzleDiameter * 1.125 * 100).rounded() / 100
        layerHeight = (nozzleDiameter * 0.5 * 100).rounded() / 100
        firstLayerHeight = nozzleDiameter >= 0.6 ? layerHeight : 0.2
    }

    func resetPrusaTemplates() {
        prusaStartGCode = prusaPrinter.defaultStartGCode
        prusaEndGCode = prusaPrinter.defaultEndGCode
    }

    /// True when the drawing (plus wipe tower, if any) does not fit on the selected Prusa bed.
    var exceedsPrusaBed: Bool { !prusaLayout().fits }

    // MARK: MMU multi-colour

    /// Multi-colour printing is in effect (Prusa format, MMU printer, toggle on, >1 colour actually used).
    var mmuMultiColorActive: Bool {
        gcodeFlavor == .prusa && prusaPrinter.hasMMU && mmuMultiColor && min(mmuColorCount, copyCount) > 1
    }

    /// Filament slots (1-based) used by the print, in ascending order.
    var mmuToolsUsed: [Int] {
        mmuMultiColorActive ? Array(1...min(mmuColorCount, copyCount)) : [min(max(mmuSlot, 1), 5)]
    }

    /// Filament slot (1-based) for a copy of the curve.
    func slot(forCopy index: Int) -> Int {
        mmuMultiColorActive ? (index % max(mmuColorCount, 1)) + 1 : min(max(mmuSlot, 1), 5)
    }

    struct PrusaLayout {
        var centerX: Double
        var centerY: Double
        /// Wipe tower rectangle in bed coordinates (nil when not needed).
        var tower: CGRect?
        var rammingLines: Int
        var purgeLines: Int
        var changesPerLayer: Int
        var fits: Bool
        var linesPerChange: Int { rammingLines + purgeLines }
    }

    func prusaLayout() -> PrusaLayout {
        let bed = prusaPrinter.bedSize
        guard mmuMultiColorActive else {
            return PrusaLayout(centerX: bed.width / 2, centerY: bed.depth / 2, tower: nil,
                               rammingLines: 0, purgeLines: 0, changesPerLayer: 0,
                               fits: outputSize + printLineWidth + 2 * skirtExtent <= min(bed.width, bed.depth))
        }
        let w = extrusionPlan.passWidth, h = layerHeight
        let crossSection = max((w - h) * h + Double.pi * h * h / 4, 0.001)
        let lineVolume = crossSection * mmuTowerDepth
        let purgeLines = max(2, Int((mmuPurgeVolume / lineVolume).rounded(.up)))
        let rammingLines = mmuRamming ? max(1, Int((15 / lineVolume).rounded(.up))) : 0
        let changes = mmuToolsUsed.count - 1
        let towerWidth = Double(changes * (purgeLines + rammingLines) + 1) * w
        let margin = 6.0, gap = 6.0
        let towerX = bed.width - margin - towerWidth
        let towerY = (bed.depth - mmuTowerDepth) / 2
        let available = towerX - gap - margin
        let footprint = outputSize + printLineWidth + 2 * skirtExtent   // drawing incl. skirt
        let fits = footprint <= available && footprint <= bed.depth - 2 * margin && mmuTowerDepth <= bed.depth - 2 * margin
        return PrusaLayout(centerX: margin + available / 2, centerY: bed.depth / 2,
                           tower: CGRect(x: towerX, y: towerY, width: towerWidth, height: mmuTowerDepth),
                           rammingLines: rammingLines, purgeLines: purgeLines,
                           changesPerLayer: changes, fits: fits)
    }

    static let maxPoints = 300_000

    /// Export settings as shipped, captured before saved settings are loaded (for "Reset").
    @ObservationIgnored private(set) var defaultExportSettings = ExportSettings()

    init() {
        defaultExportSettings = exportSettings
        loadExportSettings()
    }

    var intFixed: Int { max(1, Int(fixedRadius.rounded())) }
    var intRolling: Int { max(1, Int(rollingRadius.rounded())) }
    var copyCount: Int { max(1, Int(copies.rounded())) }

    /// Number of cusps / petals of the closed curve.
    var petals: Int { intFixed / gcd(intFixed, intRolling) }
    /// Number of times the wheel travels around the ring before the curve closes.
    var closingTurns: Int { intRolling / gcd(intFixed, intRolling) }
    var turns: Double { autoClose ? Double(closingTurns) : max(0.1, manualTurns) }

    func generate() -> SpirographGeometry {
        let R = Double(intFixed), r = Double(intRolling), d = penOffset
        let totalT = 2 * Double.pi * turns
        let n = copyCount
        let steps = min(max(Int((turns * resolution).rounded(.up)), 8), Self.maxPoints / n)

        var base: [CGPoint] = []
        base.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = totalT * Double(i) / Double(steps)
            let x: Double, y: Double
            switch curveType {
            case .hypotrochoid:
                let k = (R - r) / r
                x = (R - r) * cos(t) + d * cos(k * t)
                y = (R - r) * sin(t) - d * sin(k * t)
            case .epitrochoid:
                let k = (R + r) / r
                x = (R + r) * cos(t) - d * cos(k * t)
                y = (R + r) * sin(t) - d * sin(k * t)
            }
            base.append(CGPoint(x: x, y: y))
        }

        // Radial extent is rotation-invariant, so scaling stays stable while rotating.
        let extent = base.reduce(0.0) { max($0, Double(hypot($1.x, $1.y))) }

        var curves: [[CGPoint]] = []
        curves.reserveCapacity(n)
        for c in 0..<n {
            let angle = (rotation + Double(c) * copyAngle) * .pi / 180
            let ca = cos(angle), sa = sin(angle)
            curves.append(base.map { p in
                let x = Double(p.x), y = Double(p.y)
                return CGPoint(x: x * ca - y * sa, y: x * sa + y * ca)
            })
        }

        return SpirographGeometry(curves: curves, extent: extent, petals: petals,
                                  turns: turns, pointCount: (steps + 1) * n)
    }

    /// Colour for a given copy; rainbow mode spreads hues over the copies.
    func color(forCopy index: Int, of count: Int) -> Color {
        if mmuMultiColorActive { return slotColors[(slot(forCopy: index) - 1) % slotColors.count] }
        guard rainbow, count > 1 else { return lineColor }
        return Color(hue: Double(index) / Double(count), saturation: 0.75, brightness: 0.85)
    }

    var suggestedFileName: String {
        "spirograph-R\(intFixed)-r\(intRolling)-d\(Int(penOffset.rounded()))"
    }

    // MARK: Actions

    func apply(_ preset: SpirographPreset) {
        curveType = preset.type
        fixedRadius = preset.fixed
        rollingRadius = preset.rolling
        penOffset = preset.offset
        copies = preset.copies
        copyAngle = preset.copyAngle
        autoClose = true
    }

    func randomize() {
        curveType = Double.random(in: 0...1) < 0.75 ? .hypotrochoid : .epitrochoid
        let R = Int.random(in: 60...160)
        let r = Int.random(in: 8...(R - 5))
        fixedRadius = Double(R)
        rollingRadius = Double(r)
        penOffset = Double.random(in: Double(r) * 0.3...Double(r) * 1.3).rounded()
        autoClose = true
    }

    @MainActor func exportSVG() {
        let text = Exporter.svg(model: self, geometry: generate())
        Exporter.save(text, suggestedName: suggestedFileName, fileExtension: "svg")
    }

    @MainActor func exportGCode() {
        let text = Exporter.gcode(model: self, geometry: generate())
        let suffix: String
        switch gcodeFlavor {
        case .plain: suffix = ""
        case .cnc: suffix = "-cnc"
        case .prusa: suffix = "-\(prusaPrinter.rawValue)"
        }
        Exporter.save(text, suggestedName: suggestedFileName + suffix, fileExtension: "gcode")
    }
}


// MARK: - Persisted export settings

/// Snapshot of all export settings. Every field is optional so settings saved by an older or newer
/// version of the app still load: missing or unknown values simply keep their defaults.
struct ExportSettings: Codable, Equatable {
    var outputSize: Double?
    var svgStroke: Double?
    var svgIncludeBackground: Bool?
    var originCentered: Bool?
    var feedRate: Double?
    var travelRate: Double?
    var penMode: PenMode?
    var penUpZ: Double?
    var penDownZ: Double?
    var plungeRate: Double?
    var penUpCommands: String?
    var penDownCommands: String?
    var gcodeFlavor: GCodeFlavor?
    var cncLineNumbers: Bool?
    var prusaPrinter: PrusaPrinter?
    var filament: Filament?
    var nozzleDiameter: Double?
    var nozzleTemp: Double?
    var bedTemp: Double?
    var fanPercent: Double?
    var firstLayerHeight: Double?
    var layerHeight: Double?
    var layerCount: Double?
    var extrusionWidth: Double?
    var printLineWidth: Double?
    var extrusionMultiplier: Double?
    var printSpeed: Double?
    var firstLayerSpeed: Double?
    var printTravelSpeed: Double?
    var retractLength: Double?
    var retractSpeed: Double?
    var zHop: Double?
    var crossingMode: CrossingMode?
    var crossingClearance: Double?
    var skirtEnabled: Bool?
    var skirtLoops: Double?
    var skirtDistance: Double?
    var skirtHeight: Double?
    var mmuSlot: Int?
    var mmuMultiColor: Bool?
    var mmuColorCount: Int?
    var mmuPurgeVolume: Double?
    var mmuTowerDepth: Double?
    var mmuRamming: Bool?
    var customStartEnd: Bool?
    var prusaStartGCode: String?
    var prusaEndGCode: String?
    var slotColors: [[Double]]?
}

extension SpirographModel {
    static let exportSettingsKey = "ExportSettings.v1"

    var exportSettings: ExportSettings {
        ExportSettings(
            outputSize: outputSize,
            svgStroke: svgStroke,
            svgIncludeBackground: svgIncludeBackground,
            originCentered: originCentered,
            feedRate: feedRate,
            travelRate: travelRate,
            penMode: penMode,
            penUpZ: penUpZ,
            penDownZ: penDownZ,
            plungeRate: plungeRate,
            penUpCommands: penUpCommands,
            penDownCommands: penDownCommands,
            gcodeFlavor: gcodeFlavor,
            cncLineNumbers: cncLineNumbers,
            prusaPrinter: prusaPrinter,
            filament: filament,
            nozzleDiameter: nozzleDiameter,
            nozzleTemp: nozzleTemp,
            bedTemp: bedTemp,
            fanPercent: fanPercent,
            firstLayerHeight: firstLayerHeight,
            layerHeight: layerHeight,
            layerCount: layerCount,
            extrusionWidth: extrusionWidth,
            printLineWidth: printLineWidth,
            extrusionMultiplier: extrusionMultiplier,
            printSpeed: printSpeed,
            firstLayerSpeed: firstLayerSpeed,
            printTravelSpeed: printTravelSpeed,
            retractLength: retractLength,
            retractSpeed: retractSpeed,
            zHop: zHop,
            crossingMode: crossingMode,
            crossingClearance: crossingClearance,
            skirtEnabled: skirtEnabled,
            skirtLoops: skirtLoops,
            skirtDistance: skirtDistance,
            skirtHeight: skirtHeight,
            mmuSlot: mmuSlot,
            mmuMultiColor: mmuMultiColor,
            mmuColorCount: mmuColorCount,
            mmuPurgeVolume: mmuPurgeVolume,
            mmuTowerDepth: mmuTowerDepth,
            mmuRamming: mmuRamming,
            customStartEnd: customStartEnd,
            prusaStartGCode: prusaStartGCode,
            prusaEndGCode: prusaEndGCode,
            slotColors: slotColors.map(Self.rgb)
        )
    }

    func apply(_ s: ExportSettings) {
        if let v = s.outputSize { outputSize = v }
        if let v = s.svgStroke { svgStroke = v }
        if let v = s.svgIncludeBackground { svgIncludeBackground = v }
        if let v = s.originCentered { originCentered = v }
        if let v = s.feedRate { feedRate = v }
        if let v = s.travelRate { travelRate = v }
        if let v = s.penMode { penMode = v }
        if let v = s.penUpZ { penUpZ = v }
        if let v = s.penDownZ { penDownZ = v }
        if let v = s.plungeRate { plungeRate = v }
        if let v = s.penUpCommands { penUpCommands = v }
        if let v = s.penDownCommands { penDownCommands = v }
        if let v = s.gcodeFlavor { gcodeFlavor = v }
        if let v = s.cncLineNumbers { cncLineNumbers = v }
        if let v = s.prusaPrinter { prusaPrinter = v }
        if let v = s.filament { filament = v }
        if let v = s.nozzleDiameter { nozzleDiameter = v }
        if let v = s.nozzleTemp { nozzleTemp = v }
        if let v = s.bedTemp { bedTemp = v }
        if let v = s.fanPercent { fanPercent = v }
        if let v = s.firstLayerHeight { firstLayerHeight = v }
        if let v = s.layerHeight { layerHeight = v }
        if let v = s.layerCount { layerCount = v }
        if let v = s.extrusionWidth { extrusionWidth = v }
        if let v = s.printLineWidth { printLineWidth = v }
        if let v = s.extrusionMultiplier { extrusionMultiplier = v }
        if let v = s.printSpeed { printSpeed = v }
        if let v = s.firstLayerSpeed { firstLayerSpeed = v }
        if let v = s.printTravelSpeed { printTravelSpeed = v }
        if let v = s.retractLength { retractLength = v }
        if let v = s.retractSpeed { retractSpeed = v }
        if let v = s.zHop { zHop = v }
        if let v = s.crossingMode { crossingMode = v }
        if let v = s.crossingClearance { crossingClearance = v }
        if let v = s.skirtEnabled { skirtEnabled = v }
        if let v = s.skirtLoops { skirtLoops = v }
        if let v = s.skirtDistance { skirtDistance = v }
        if let v = s.skirtHeight { skirtHeight = v }
        if let v = s.mmuSlot { mmuSlot = v }
        if let v = s.mmuMultiColor { mmuMultiColor = v }
        if let v = s.mmuColorCount { mmuColorCount = v }
        if let v = s.mmuPurgeVolume { mmuPurgeVolume = v }
        if let v = s.mmuTowerDepth { mmuTowerDepth = v }
        if let v = s.mmuRamming { mmuRamming = v }
        if let v = s.customStartEnd { customStartEnd = v }
        if let v = s.prusaStartGCode { prusaStartGCode = v }
        if let v = s.prusaEndGCode { prusaEndGCode = v }
        if let colors = s.slotColors {
            for (i, c) in colors.prefix(slotColors.count).enumerated() where c.count >= 3 {
                slotColors[i] = Color(.sRGB, red: c[0], green: c[1], blue: c[2])
            }
        }
    }

    func saveExportSettings() {
        guard let data = try? JSONEncoder().encode(exportSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.exportSettingsKey)
    }

    func loadExportSettings() {
        guard let data = UserDefaults.standard.data(forKey: Self.exportSettingsKey),
              let saved = try? JSONDecoder().decode(ExportSettings.self, from: data) else { return }
        apply(saved)
    }

    func resetExportSettings() {
        apply(defaultExportSettings)
        UserDefaults.standard.removeObject(forKey: Self.exportSettingsKey)
    }

    private static func rgb(_ color: Color) -> [Double] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return [Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent)]
    }
}
