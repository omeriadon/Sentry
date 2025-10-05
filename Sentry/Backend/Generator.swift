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

public struct Coord: Hashable, Codable {
	public let lat: Double
	public let lon: Double
	public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

public struct NDVILSTRecord: Codable {
	public let coordinate: Coord
	public let ndvi: Double
	public let lstC: Double
	public let burnedProb: Double
	public let burned: Bool
	public let dateISO: String
}

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
	let latBits = lat.bitPattern
	let lonBits = lon.bitPattern

	var h = latBits &+ lonBits
	h = h &* 0x9E37_79B9_7F4A_7C15 &+ 0x0123_4567_89AB_CDEF

	let frac = Double((h >> 10) & 0xFFFF) / Double(0xFFFF)

	return (frac - 0.5) * 0.16
}

public func synthesizePoint(coord: Coord, options: SyntheticOptions = SyntheticOptions()) -> NDVILSTRecord {
	let latBits = coord.lat.bitPattern
	let lonBits = coord.lon.bitPattern

	let mixA = latBits &* 0x9E37_79B9_7F4A_7C15
	let mixB = (lonBits &<< 13) ^ (lonBits &>> 7)
	let coordMix = mixA ^ mixB

	let seed = options.seed &+ coordMix

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

public func synthesizeRecords(for coords: [Coord], options: SyntheticOptions = SyntheticOptions()) -> [NDVILSTRecord] {
	if coords.isEmpty { return [] }
	var out: [NDVILSTRecord] = []

	for c in coords {
		var opt = options

		let latBits = c.lat.bitPattern
		let lonBits = c.lon.bitPattern

		let mixA = latBits &* 0x9E37_79B9_7F4A_7C15
		let mixB = (lonBits &<< 13) ^ (lonBits &>> 7)
		let coordMix = mixA ^ mixB

		opt.seed = opt.seed &+ coordMix

		out.append(synthesizePoint(coord: c, options: opt))
	}
	return out
}

public func synthesizeRecordsAsync(for coords: [Coord], options: SyntheticOptions = SyntheticOptions()) async -> [NDVILSTRecord] {
	if coords.isEmpty { return [] }

	let batchSize = 200
	let slices = stride(from: 0, to: coords.count, by: batchSize).enumerated().map { index, start -> (Int, [Coord]) in
		let end = min(start + batchSize, coords.count)
		return (index, Array(coords[start ..< end]))
	}

	var partial = Array(repeating: [NDVILSTRecord](), count: slices.count)

	await withTaskGroup(of: (Int, [NDVILSTRecord]).self) { group in
		for (index, batch) in slices {
			group.addTask {
				(index, synthesizeRecords(for: batch, options: options))
			}
		}

		for await (index, chunk) in group {
			partial[index] = chunk
		}
	}

	return partial.flatMap { $0 }
}

public enum FirePredictionError: Error {
	case modelNotFound
	case modelFailed(Error)
}

public func predictFireProbability(for record: NDVILSTRecord) throws -> Double {
	if let modelURL = Bundle.main.url(forResource: "wildifre_predicter", withExtension: "mlmodelc") {
		do {
			let model = try MLModel(contentsOf: modelURL)
			let provider = try MLDictionaryFeatureProvider(dictionary: [
				"NDVI": NSNumber(value: record.ndvi),
				"LST": NSNumber(value: record.lstC),
				"BURNED_AREA": NSNumber(value: record.burnedProb),
			])
			let output = try model.prediction(from: provider)

			if let value = output.featureValue(for: "CLASSProbability")?.doubleValue { return value }
			if let value = output.featureValue(for: "classProbability")?.doubleValue { return value }
			if let value = output.featureValue(for: "probability")?.doubleValue { return value }

			var fallback: Double?
			for name in output.featureNames {
				if let v = output.featureValue(for: name)?.doubleValue, fallback == nil || v > fallback! {
					fallback = v
				}
			}
			if let fallback { return fallback }
		} catch {
			throw FirePredictionError.modelFailed(error)
		}
	}

	let ndviFactor = clamp((0.5 - record.ndvi) / 0.5, min: 0.0, max: 1.0)
	let lstFactor = clamp((record.lstC - 25.0) / 30.0, min: 0.0, max: 1.0)
	return clamp(0.5 * record.burnedProb + 0.35 * ndviFactor + 0.15 * lstFactor, min: 0.0, max: 1.0)
}

public func predictFireProbabilitySafe(for record: NDVILSTRecord) -> Double {
	do {
		return try predictFireProbability(for: record)
	} catch {
		let ndviFactor = clamp((0.5 - record.ndvi) / 0.5, min: 0.0, max: 1.0)
		let lstFactor = clamp((record.lstC - 25.0) / 30.0, min: 0.0, max: 1.0)
		return clamp(0.5 * record.burnedProb + 0.35 * ndviFactor + 0.15 * lstFactor, min: 0.0, max: 1.0)
	}
}

public func predictFireProbabilitiesAsync(for records: [NDVILSTRecord]) async -> [Double] {
	if records.isEmpty { return [] }

	let batchSize = 500
	let slices = stride(from: 0, to: records.count, by: batchSize).enumerated().map { index, start -> (Int, ArraySlice<NDVILSTRecord>) in
		let end = min(start + batchSize, records.count)
		return (index, records[start ..< end])
	}

	var partial = Array(repeating: [Double](), count: slices.count)

	await withTaskGroup(of: (Int, [Double]).self) { group in
		for (index, batch) in slices {
			group.addTask {
				(index, batch.map { predictFireProbabilitySafe(for: $0) })
			}
		}

		for await (index, chunk) in group {
			partial[index] = chunk
		}
	}

	return partial.flatMap { $0 }
}

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

public func synthesizeRecordsFromBBox(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, spacingMeters: Double = 500, options: SyntheticOptions = SyntheticOptions()) -> [NDVILSTRecord] {
	let grid = generateGrid(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, spacingMeters: spacingMeters)
	return synthesizeRecords(for: grid, options: options)
}

public func synthesizeRecordsFromBBoxAsync(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, spacingMeters: Double = 500, options: SyntheticOptions = SyntheticOptions()) async -> [NDVILSTRecord] {
	let grid = generateGrid(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, spacingMeters: spacingMeters)
	return await synthesizeRecordsAsync(for: grid, options: options)
}
