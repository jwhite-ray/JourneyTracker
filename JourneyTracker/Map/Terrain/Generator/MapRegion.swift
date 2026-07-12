//
//  MapRegion.swift
//  JourneyTracker
//
//  The AUTHORING model for the faceted map (KAN-19, P2 of epic KAN-16). A map is
//  authored as a short list of REGION records plus a deterministic seed — never
//  as hand-placed glyphs (App Concept doc, "a map is authored as a short list of
//  REGION records plus a deterministic seed"). `MapGenerator` expands these into
//  the hundreds of `TerrainGlyph`/`TerrainBlob`/… values `TerrainRenderer` draws.
//
//  Everything is a value type and `Codable`, so a finished map can ship as bundled
//  JSON later (P4) with only this small authoring input travelling between a user's
//  iCloud devices — each device regenerates the identical glyph set from it.
//
//  Codable-DEFAULTS TRAP (for the future bundled-JSON path): Swift's synthesized
//  decoder does NOT apply a property's default when the key is simply absent — a
//  missing key throws `keyNotFound`, it does not fall back to `= 1`. So the
//  in-code defaults below (jitter, feather, sourceWidth, `major`, …) are authoring
//  conveniences, not a lenient-JSON contract. When maps start shipping as JSON,
//  either emit every key or add explicit `init(from:)` fallbacks — do not assume a
//  hand-trimmed JSON with omitted keys will decode.
//
//  Sizes/positions are authored in MAP UNITS (the journey's own logical space).
//  Region real-world extents are validated in real miles via the journey's
//  miles-per-map-unit scale (App Concept doc's bounds table) — see `MapValidator`.
//

import CoreGraphics

// MARK: - Scatter tuning

/// Per-region scatter parameters (§07.4). Defaults are chosen so authors rarely
/// set these — a bare region gets a sensible mass. The generator multiplies these
/// by the harness's global knobs at generation time.
struct ScatterParams: Codable, Equatable {
    /// Glyphs per map-unit² of region area. `nil` → the generator's per-kind
    /// default, so region SIZE drives glyph count and masses scale naturally.
    var density: Double?
    /// Intensity of per-glyph position + size jitter (1 = the P1-proven look).
    var jitter: Double = 1
    /// Rim-cull strength: higher fades the mass out more softly toward its edge.
    var feather: Double = 0.45

    init(density: Double? = nil, jitter: Double = 1, feather: Double = 0.45) {
        self.density = density
        self.jitter = jitter
        self.feather = feather
    }
}

// MARK: - Waypoint

struct MapWaypoint: Codable, Identifiable, Equatable {
    enum State: String, Codable { case reached, next, upcoming }
    var id: String
    /// Position in map units. Must lie ON the trek path (validated).
    var position: CGPoint
    var name: String
    /// Real MILES from the journey start — the anchor a waypoint pins along the
    /// path. Named unit-explicitly on purpose: at P4 this sits beside SwiftData's
    /// `Waypoint.distanceFromStart`, which is in METERS. Keeping `miles` in the
    /// name prevents the map-authoring miles-vs-meters collision.
    var milesFromStart: Double
    /// A design-token name (`journey.theme` accent), never a literal color.
    var accentToken: String
    var state: State
    var isDestination: Bool = false
}

// MARK: - Region record

/// One authored region. An unordered bag of these (plus a seed) is a whole map;
/// `TerrainRenderer` imposes the §07.6 back-to-front order, so records carry no
/// z-index. Each `id` is STABLE and unique — it keys the region's RNG substream,
/// so editing one region never reshuffles the others.
enum MapRegion: Codable, Identifiable {
    case range(Range)
    case forest(Forest)
    case river(River)
    case lake(Lake)
    case coast(Coast)
    case groundCover(GroundCover)
    case settlement(Settlement)
    case road(Road)
    case trekPath(TrekPath)

    var id: String {
        switch self {
        case .range(let r): return r.id
        case .forest(let f): return f.id
        case .river(let r): return r.id
        case .lake(let l): return l.id
        case .coast(let c): return c.id
        case .groundCover(let g): return g.id
        case .settlement(let s): return s.id
        case .road(let r): return r.id
        case .trekPath(let t): return t.id
        }
    }

    // MARK: Shapes

    /// A mountain range: an oriented band (§07.5 "ranges run off-map"). `halfLength`
    /// runs along `axisAngle`; `halfWidth` is perpendicular. Validated as a range
    /// 75–300 mi long, ≤10 mi wide, on TOTAL authored size (may run off `bounds`).
    struct Range: Codable {
        var id: String
        var center: CGPoint
        var axisAngle: CGFloat = 0
        var halfLength: CGFloat
        var halfWidth: CGFloat
        /// How many of the tallest peaks get a snow cap (§07.3.1). `nil` → a few.
        var snowCaps: Int?
        var scatter: ScatterParams?
    }

    /// A forest: a soft elliptical mass of conifers (§07.3.2). Validated 0.5–300 sq mi.
    struct Forest: Codable {
        var id: String
        var center: CGPoint
        var rx: CGFloat
        var ry: CGFloat
        var autumn: Bool = false
        var scatter: ScatterParams?
    }

    /// A river: a source→mouth polyline HINT the generator meanders (§07.5). The
    /// mouth kind (inland/freshwater/sea) is DERIVED from what it terminates in.
    /// Validated ≥2 mi long; must start off-map or in a range and end in a lake or
    /// at the coast.
    struct River: Codable {
        var id: String
        var hint: [CGPoint]
        var meanderAmplitude: CGFloat = 8
        var sourceWidth: CGFloat = 5
        var mouthWidth: CGFloat = 12
    }

    /// A lake: an asymmetric water blob ring (§07.3.4). Validated 0.3–30 sq mi.
    struct Lake: Codable {
        var id: String
        var ring: [CGPoint]
    }

    /// Ocean / coastline (§07.3.5). No size restriction. `seaward` points from land
    /// toward open water; `seaCorners` close the depth bands off the scene edge.
    struct Coast: Codable {
        var id: String
        var coastline: [CGPoint]
        var seaward: CGVector
        var seaCorners: [CGPoint]
    }

    /// Ground cover — plains, dunes, or marsh (§07.3.6). `ring` is the region area.
    struct GroundCover: Codable {
        enum Kind: String, Codable { case plains, dunes, marsh }
        var id: String
        var kind: Kind
        var ring: [CGPoint]
        var scatter: ScatterParams?
    }

    /// A settlement: a tight cluster of 3–5 homes by water (§07.3.8, §07.5).
    struct Settlement: Codable {
        var id: String
        var site: CGPoint
        var name: String?
        /// Homes in the cluster. `nil` → the generator picks 3–5 deterministically.
        var homeCount: Int?
    }

    /// A road (§07.3.7). Solid ink; `major` draws the twin-stroke variant.
    struct Road: Codable {
        var id: String
        var points: [CGPoint]
        var major: Bool = false
    }

    /// The trek path (§07.3.7): the dot-dash spine every waypoint sits on. Its
    /// `points` include each waypoint position as a control point (App Concept doc:
    /// "waypoints ARE control points"), so the smoothed curve passes through them.
    struct TrekPath: Codable {
        var id: String
        var points: [CGPoint]
    }
}

// MARK: - The authored map

/// A whole authored map: bounds, seed, the real-mileage anchor, its regions, and
/// its waypoints. The generator is a pure function of this value.
struct MapAuthoring: Codable {
    var name: String
    /// The journey's logical map-unit space. Regions may be authored partly
    /// outside it; the renderer clips (`Canvas` culling is free).
    var bounds: CGRect
    var seed: UInt64
    /// The real-distance anchor: the journey's total distance in miles. Combined
    /// with the trek path's map-unit arc length it defines miles-per-map-unit.
    var journeyMiles: Double
    var regions: [MapRegion]
    var waypoints: [MapWaypoint]

    /// The first trek-path region, if any (a map should have exactly one).
    var trekPath: MapRegion.TrekPath? {
        for region in regions { if case .trekPath(let t) = region { return t } }
        return nil
    }

    /// The trek path's SMOOTHED arc length in map units — the scale's denominator.
    var trekArcLengthMapUnits: CGFloat {
        guard let trek = trekPath else { return 0 }
        return MapGeometry.smoothedLength(trek.points)
    }

    /// Miles per map unit, anchored by trek-path arc length ↔ `journeyMiles`
    /// (App Concept doc). Region real-mile extents convert through this. Returns 0
    /// if there's no measurable trek path (an authoring error the validator flags).
    var milesPerMapUnit: Double {
        let arc = Double(trekArcLengthMapUnits)
        guard arc > 0 else { return 0 }
        return journeyMiles / arc
    }

    /// Square miles per square map unit.
    var squareMilesPerSquareUnit: Double { milesPerMapUnit * milesPerMapUnit }

    // Convenience accessors used by the generator and validators.
    var lakes: [MapRegion.Lake] { regions.compactMap { if case .lake(let l) = $0 { return l }; return nil } }
    var rivers: [MapRegion.River] { regions.compactMap { if case .river(let r) = $0 { return r }; return nil } }
    var coast: MapRegion.Coast? { for r in regions { if case .coast(let c) = r { return c } }; return nil }
}
