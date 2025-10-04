//
//  Generator.swift
//  Sentry
//
//  Created by Adon Omeri on 4/10/2025.
//

import CoreLocation
import CoreML
import Foundation
import MapKit
import SwiftUI

/// ---------- Types (match earlier synthetic generator) ----------
public struct Coord: Hashable, Codable {
	public let lat: Double
	public let lon: Double
	public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

public struct NDVILSTRecord: Codable {
	public let coordinate: Coord
	public let ndvi: Double // -1..1
	public let lstC: Double // Celsius
	public let burnedProb: Double // 0..1
	public let burned: Bool
	public let dateISO: String
}

// ---------- Reusable helpers (from prior generator) ----------
private func metersPerDegreeLat() -> Double { 111_320.0 }
private func metersPerDegreeLon(atLat lat: Double) -> Double {
	111_320.0 * cos(lat * Double.pi / 180.0)
}

private func isoDate(_ d: Date) -> String {
	let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f.string(from: d)
}

private func clamp<T: Comparable>(_ v: T, min mn: T, max mx: T) -> T {
	return v < mn ? mn : (v > mx ? mx : v)
}

/// ---------- Small seeded RNG and gaussian helper ----------
private struct SeededRNG {
	private var state: UInt64
	init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
	mutating func nextDouble01() -> Double {
		state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
		let x = Double((state >> 11) & 0x1FFFFF) / Double(0x1FFFFF)
		return x
	}

	mutating func gaussian(mean: Double = 0, sigma: Double = 1) -> Double {
		let u1 = max(1e-12, nextDouble01())
		let u2 = nextDouble01()
		let z0 = sqrt(-2.0 * log(u1)) * cos(2 * Double.pi * u2)
		return z0 * sigma + mean
	}
}

/// ---------- Grid generator (returns center points) ----------
public func generateGrid(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, spacingMeters: Double) -> [Coord] {
	let top = max(minLat, maxLat)
	let bottom = min(minLat, maxLat)
	let left = min(minLon, maxLon)
	let right = max(minLon, maxLon)

	let midLat = (top + bottom) / 2.0
	let latStep = spacingMeters / metersPerDegreeLat()
	let lonStep = spacingMeters / max(metersPerDegreeLon(atLat: midLat), 1e-9)

	let latCount = max(1, Int(ceil((top - bottom) / latStep)))
	let lonCount = max(1, Int(ceil((right - left) / lonStep)))

	var out: [Coord] = []
	for i in 0 ..< latCount {
		let lat = bottom + (Double(i) + 0.5) * ((top - bottom) / Double(latCount))
		for j in 0 ..< lonCount {
			let lon = left + (Double(j) + 0.5) * ((right - left) / Double(lonCount))
			out.append(Coord(lat: lat, lon: lon))
		}
	}
	return out
}

/// ---------- Single-point synthesizer (deterministic via seed) ----------
public struct SyntheticOptions {
	public var seed: UInt64 = 12345
	public var date: Date = .init()
	public var seasonAmplitude: Double = 0.35
	public var baselineNDVI: Double = 0.2
	public var ndviNoiseSigma: Double = 0.04
	public var lstBaseC: Double = 15.0
	public var lstSeasonAmp: Double = 8.0
	public var lstNoiseSigma: Double = 1.8
	public var burnBaseProb: Double = 0.01
	public var burnSensitivityToNDVI: Double = 1.8
	public var burnSensitivityToLST: Double = 0.03
	public init() {}
}

private func spatialOffset(lat: Double, lon: Double) -> Double {
		// use unsigned-only mixing of bitPatterns (no Int64 casts)
	let latBits = lat.bitPattern   // UInt64
	let lonBits = lon.bitPattern   // UInt64

		// deterministic mixing: add, golden-ratio multiply, xor-shift, and add constant
	var h = latBits &+ lonBits
	h = h &* 0x9E3779B97F4A7C15 &+ 0x0123456789ABCDEF

		// extract a 16-bit pseudo-random fraction from the mixed value
	let frac = Double((h >> 10) & 0xFFFF) / Double(0xFFFF)

		// scale to small spatial offset
	return (frac - 0.5) * 0.16
}


public func synthesizePoint(coord: Coord, options: SyntheticOptions = SyntheticOptions()) -> NDVILSTRecord {
	// safe seed mixing using only UInt64 ops (no Int64 casts)
	let latBits = coord.lat.bitPattern // UInt64
	let lonBits = coord.lon.bitPattern // UInt64

	// deterministic mixing: golden-ratio multiply + shifts + xor
	let mixA = latBits &* 0x9E37_79B9_7F4A_7C15
	let mixB = (lonBits &<< 13) ^ (lonBits &>> 7)
	let coordMix = mixA ^ mixB

	let seed = options.seed &+ coordMix // wrapping add, stays UInt64

	var rng = SeededRNG(seed: seed)

	let calendar = Calendar(identifier: .iso8601)
	let doy = calendar.ordinality(of: .day, in: .year, for: options.date) ?? 1
	let phase = Double(doy) / Double(calendar.range(of: .day, in: .year, for: options.date)!.count)
	let seasonShift = 0.0

	let season = options.seasonAmplitude * cos(2.0 * Double.pi * (phase + seasonShift))
	let baseline = options.baselineNDVI + spatialOffset(lat: coord.lat, lon: coord.lon)
	let noise = rng.gaussian(mean: 0, sigma: options.ndviNoiseSigma)
	var ndvi = baseline + season + noise
	ndvi = clamp(ndvi, min: -1.0, max: 1.0)

	let lstSeason = options.lstSeasonAmp * cos(2.0 * Double.pi * (phase + 0.25))
	let ndviInfluence = (1.0 - clamp(ndvi, min: -1.0, max: 1.0)) * 6.0
	let lstNoise = rng.gaussian(mean: 0, sigma: options.lstNoiseSigma)
	var lstC = options.lstBaseC + lstSeason + ndviInfluence + lstNoise
	lstC = clamp(lstC, min: -50.0, max: 70.0)

	let ndviRisk = max(0.0, 0.5 - ndvi) * options.burnSensitivityToNDVI
	let lstRisk = max(0.0, lstC - options.lstBaseC) * options.burnSensitivityToLST
	var prob = options.burnBaseProb + ndviRisk + lstRisk
	prob = clamp(prob, min: 0.0, max: 1.0)

	let burned = rng.nextDouble01() < prob

	return NDVILSTRecord(coordinate: coord, ndvi: ndvi, lstC: lstC, burnedProb: prob, burned: burned, dateISO: isoDate(options.date))
}

/// ---------- Multi-point synthesizer (grid or list) ----------
public func synthesizeRecords(for coords: [Coord], options: SyntheticOptions = SyntheticOptions()) -> [NDVILSTRecord] {
	if coords.isEmpty { return [] }
	var out: [NDVILSTRecord] = []

	for c in coords {
		// start from the provided options and vary the seed per-point
		var opt = options

		// mix the two Double bitPatterns using only UInt64 ops (no signed conversions, no traps)
		let latBits = c.lat.bitPattern // UInt64
		let lonBits = c.lon.bitPattern // UInt64

		// deterministic mixing (golden-ratio multiply + xor/shift)
		let mixA = latBits &* 0x9E37_79B9_7F4A_7C15
		let mixB = (lonBits &<< 13) ^ (lonBits &>> 7)
		let coordMix = mixA ^ mixB

		// update the per-point seed on the mutable opt
		opt.seed = opt.seed &+ coordMix

		out.append(synthesizePoint(coord: c, options: opt))
	}
	return out
}

public func synthesizeRecordsFromBBox(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, spacingMeters: Double = 500, options: SyntheticOptions = SyntheticOptions()) -> [NDVILSTRecord] {
	let grid = generateGrid(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, spacingMeters: spacingMeters)
	return synthesizeRecords(for: grid, options: options)
}

/// ---------- Fire prediction using CoreML if available, heuristic fallback otherwise ----------
public enum FirePredictionError: Error {
	case modelNotFound
	case modelFailed(Error)
}

public func predictFireProbability(for record: NDVILSTRecord) throws -> Double {
	// Attempt to run a bundled CoreML model named "wildifre_predicter.mlmodelc" if it exists.
	// Input feature names expected: "NDVI", "LST", "BURNED_AREA".
	// Output expected to contain a probability value; function searches for likely keys.
	if let modelURL = Bundle.main.url(forResource: "wildifre_predicter", withExtension: "mlmodelc") {
		do {
			let mlmodel = try MLModel(contentsOf: modelURL)
			let inputDict: [String: Any] = [
				"NDVI": NSNumber(value: record.ndvi),
				"LST": NSNumber(value: record.lstC),
				"BURNED_AREA": NSNumber(value: record.burnedProb),
			]
			let provider = try MLDictionaryFeatureProvider(dictionary: inputDict as [String: Any])
			let out = try mlmodel.prediction(from: provider)
			// Common output keys: "CLASSProbability", "classProbability", "probability", or a numeric feature for the positive class.
			if let fv = out.featureValue(for: "CLASSProbability")?.doubleValue { return fv }
			if let fv = out.featureValue(for: "classProbability")?.doubleValue { return fv }
			if let fv = out.featureValue(for: "probability")?.doubleValue { return fv }
			// If none of the above, iterate and return the max numeric feature found
			var best: Double? = nil
			for name in out.featureNames {
				if let v = out.featureValue(for: name)?.doubleValue {
					if best == nil || v > best! { best = v }
				}
			}
			if let b = best { return b }
			// no numeric output found -> fallback to heuristic
		} catch {
			// if CoreML failed, gracefully fall back to heuristic below
			throw FirePredictionError.modelFailed(error)
		}
	}

	// Heuristic fallback: combine burnedProb, low NDVI and high LST into probability
	// deterministic formula that returns 0..1
	let ndviFactor = clamp((0.5 - record.ndvi) / 0.5, min: 0.0, max: 1.0) // 0 when ndvi >=0.5
	let lstFactor = clamp((record.lstC - 25.0) / 30.0, min: 0.0, max: 1.0) // scale above 25C
	let p = clamp(0.5 * record.burnedProb + 0.35 * ndviFactor + 0.15 * lstFactor, min: 0.0, max: 1.0)
	return p
}

/// Convenience wrapper for async UI use: attempts model; if model error thrown, returns heuristic
public func predictFireProbabilitySafe(for record: NDVILSTRecord) -> Double {
	do {
		return try predictFireProbability(for: record)
	} catch {
		// fall back to deterministic heuristic (same as above)
		let ndviFactor = clamp((0.5 - record.ndvi) / 0.5, min: 0.0, max: 1.0)
		let lstFactor = clamp((record.lstC - 25.0) / 30.0, min: 0.0, max: 1.0)
		let p = clamp(0.5 * record.burnedProb + 0.35 * ndviFactor + 0.15 * lstFactor, min: 0.0, max: 1.0)
		return p
	}
}

/// ---------- Map helper: construct square polygon around center given spacing (meters) ----------
public func tilePolygonCoordinates(center: CLLocationCoordinate2D, spacingMeters: Double) -> [CLLocationCoordinate2D] {
	let latStep = spacingMeters / metersPerDegreeLat()
	let lonStep = spacingMeters / max(metersPerDegreeLon(atLat: center.latitude), 1e-9)
	let halfLat = latStep / 2.0
	let halfLon = lonStep / 2.0

	return [
		CLLocationCoordinate2D(latitude: center.latitude + halfLat, longitude: center.longitude - halfLon),
		CLLocationCoordinate2D(latitude: center.latitude + halfLat, longitude: center.longitude + halfLon),
		CLLocationCoordinate2D(latitude: center.latitude - halfLat, longitude: center.longitude + halfLon),
		CLLocationCoordinate2D(latitude: center.latitude - halfLat, longitude: center.longitude - halfLon),
	]
}

// ---------- SwiftUI MapKit usage snippet (drop into your view) ----------
/*
 Replace `records` with your [NDVILSTRecord] and `spacingMeters` with the grid spacing you used.
 Then include this inside a Map content builder (iOS 17 / SwiftUI Map) or adapt to MKMapView.

 For SwiftUI Map (iOS 17+):

 ForEach(records, id: \.coordinate) { rec in
 let center = CLLocationCoordinate2D(latitude: rec.coordinate.lat, longitude: rec.coordinate.lon)
 let polygonCoords = tilePolygonCoordinates(center: center, spacingMeters: spacingMeters)

 MapPolygon(coordinates: polygonCoords)
 .foregroundStyle(Color(hue: 0.33 * Double((rec.ndvi + 1.0)/2.0), saturation: 0.8, brightness: 0.9).opacity(0.5))
 .stroke(Color.black.opacity(0.25), lineWidth: 1)

 Annotation(String(format: "NDVI %.2f\nP: %.2f", rec.ndvi, predictFireProbabilitySafe(for: rec)), coordinate: center) {
 VStack {
 Text(String(format: "%.2f", rec.ndvi))
 .font(.caption2)
 .fontWeight(.semibold)
 .padding(6)
 .background(.ultraThinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 8))
 }
 }
 .annotationTitles(.hidden)
 }

 Add the created overlays and annotations to your MKMapView instance.
 */

// ---------- Example quick usage (call from your controller) ----------
/*
 let bboxMinLat = 37.33
 let bboxMaxLat = 37.34
 let bboxMinLon = -122.04
 let bboxMaxLon = -122.02
 let spacing = 500.0

 var opts = SyntheticOptions()
 opts.seed = 42
 opts.date = ISO8601DateFormatter().date(from: "2025-10-02") ?? Date()

 let records = synthesizeRecordsFromBBox(minLat: bboxMinLat, maxLat: bboxMaxLat, minLon: bboxMinLon, maxLon: bboxMaxLon, spacingMeters: spacing, options: opts)

 // Predict single (synchronous safe wrapper)
 let sample = records.first!
 let prob = predictFireProbabilitySafe(for: sample)
 print("NDVI \(sample.ndvi) LST \(sample.lstC) BurnProb \(sample.burnedProb) -> fireProb \(prob)")

 // Use SwiftUI Map snippet above to render tiles and annotations.
 */
