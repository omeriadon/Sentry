//
//  ContentView.swift
//  Sentry
//
//  Created by Adon Omeri on 30/9/2025.
//

import CoreML
import MapKit
import SwiftUI

struct Location: Identifiable {
	let id = UUID()
	var name: String
	var coordinate: CLLocationCoordinate2D
}

private struct Coordinate: Hashable {
	let lat: Double
	let lon: Double
}

private struct TileSeed {
	let center: CLLocationCoordinate2D
	let coordinate: Coordinate
	let polygon: [CLLocationCoordinate2D]
}

struct ContentView: View {
	@Environment(\.horizontalSizeClass) private var hSize
	@Environment(\.verticalSizeClass) private var vSize

	var useNavSplitView: Bool {
		#if os(macOS) || os(visionOS)
			return true
		#else
			switch UIDevice.current.userInterfaceIdiom {
			case .pad:
				return hSize == .regular
			case .phone:
				return false
			default:
				return false
			}
		#endif
	}

	@State var isSheetPresented = true
	@State var position: MapCameraPosition = .userLocation(fallback: .automatic)
	@Namespace var mapScope
	@State var locations: [Location] = []

	// Rectangle corners
	@State var selectedCorners: (topLeft: CLLocationCoordinate2D?, bottomRight: CLLocationCoordinate2D?) = (nil, nil)
	@State var addPins = false
	@State private var currentDetent: PresentationDetent = .height(80)

	// ---------- NEW: records and spacing used by the synthetic generator ----------
	@State private var records: [NDVILSTRecord] = []
	private let spacingMeters: Double = 500.0
	// ---------------------------------------------------------------------------

	var normalizedCorners: (topLeft: CLLocationCoordinate2D, bottomRight: CLLocationCoordinate2D)? {
		guard let tl = selectedCorners.topLeft, let br = selectedCorners.bottomRight else {
			return nil
		}
		let top = max(tl.latitude, br.latitude)
		let bottom = min(tl.latitude, br.latitude)
		let left = min(tl.longitude, br.longitude)
		let right = max(tl.longitude, br.longitude)

		return (
			topLeft: CLLocationCoordinate2D(latitude: top, longitude: left),
			bottomRight: CLLocationCoordinate2D(latitude: bottom, longitude: right)
		)
	}

	@State var firePrediction: String = "Unknown"

	@State private var generationTask: Task<Void, Never>? = nil
	@State private var isRunning: Bool = false

	var body: some View {
		Group {
			if useNavSplitView {
				NavigationSplitView {
					sideView
						.navigationSplitViewColumnWidth(min: 230, ideal: 350, max: 500)
				} detail: {
					mapView
				}

			} else {
				mapView
					.sheet(isPresented: $isSheetPresented) {
						sideView
							.padding()
							.presentationDetents(
								[.height(80), .fraction(0.35), .medium],
								selection: $currentDetent
							)
							.presentationBackgroundInteraction(.enabled)
							.presentationDragIndicator(.visible)
							.interactiveDismissDisabled()
					}
			}
		}
	}

	var mapView: some View {
		NavigationStack {
			MapReader { proxy in
				Map(
					position: $position,
					interactionModes: [.pan, .zoom],
					scope: mapScope
				) {
					UserAnnotation()

					ForEach(records, id: \.coordinate) { rec in
						let center = CLLocationCoordinate2D(latitude: rec.coordinate.lat, longitude: rec.coordinate.lon)
							// Instead of recomputing:
							// let polygonCoords = tilePolygonCoordinates(center: center, spacingMeters: spacingMeters)
							// Use the polygon from the seed:
						let polygonCoords = tilePolygonCoordinates(center: center, spacingMeters: spacingMeters)

						MapPolygon(coordinates: polygonCoords)
							.foregroundStyle(Color(hue: 0.33 * Double((rec.ndvi + 1.0) / 2.0), saturation: 0.8, brightness: 0.9).opacity(0.5))
							.stroke(Color.black.opacity(0.25), lineWidth: 1)

						Annotation(String(format: "NDVI %.2f\nP: %.2f", rec.ndvi, predictFireProbabilitySafe(for: rec)), coordinate: center) {
							VStack {
								Text(String(format: "%.2f", rec.ndvi))
									.font(.caption2)
									.fontWeight(.semibold)							}
						}
						.annotationTitles(.hidden)
					}

					// ---------- changed: only draw the orange selection rectangle when NOT showing predicted pixels ----------
					if let corners = normalizedCorners, records.isEmpty {
						let path: [CLLocationCoordinate2D] = [
							corners.topLeft,
							CLLocationCoordinate2D(latitude: corners.topLeft.latitude, longitude: corners.bottomRight.longitude),
							corners.bottomRight,
							CLLocationCoordinate2D(latitude: corners.bottomRight.latitude, longitude: corners.topLeft.longitude),
						]

						MapPolygon(coordinates: path)
							.foregroundStyle(.orange.opacity(0.2))
							.stroke(Color.white, lineWidth: 2)
							.strokeStyle(style: .init(lineCap: .round, lineJoin: .round))

						// Draw annotations using normalized positions
						let cornerAnnotations: [(CLLocationCoordinate2D, String, Double)] = [
							(corners.topLeft, "Top Left", -45),
							(CLLocationCoordinate2D(latitude: corners.topLeft.latitude, longitude: corners.bottomRight.longitude), "Top Right", 45),
							(corners.bottomRight, "Bottom Right", 135),
							(CLLocationCoordinate2D(latitude: corners.bottomRight.latitude, longitude: corners.topLeft.longitude), "Bottom Left", -135),
						]

						ForEach(cornerAnnotations, id: \.1) { coord, name, rotation in
							Annotation(name, coordinate: coord) {
								Image(systemName: "chevron.up")
									.imageScale(.large)
									.padding(7)
									.rotationEffect(Angle(degrees: rotation))
									.glassEffect(.regular.tint(.orange), in: .circle)
							}
							.annotationTitles(.hidden)
						}
					} else {
						// show corner hint pins when selection present but rectangle hidden (e.g. records displayed)
						if let topLeft = selectedCorners.topLeft {
							Annotation("Top Left?", coordinate: topLeft) {
								Image(systemName: "chevron.up")
									.imageScale(.large)
									.padding(7)
									.rotationEffect(Angle(degrees: -45))
									.glassEffect(.regular.tint(.orange), in: .circle)
							}
							.annotationTitles(.hidden)
						}
						if let bottomRight = selectedCorners.bottomRight {
							Annotation("Bottom Right?", coordinate: bottomRight) {
								Image(systemName: "chevron.up")
									.imageScale(.large)
									.padding(7)
									.rotationEffect(Angle(degrees: 135))
									.glassEffect(.regular.tint(.orange), in: .circle)
							}
							.annotationTitles(.hidden)
						}
					}
				}
				.onTapGesture(coordinateSpace: .local) { location in
					if addPins, let coordinate = proxy.convert(
						location,
						from: .local
					) {
						if selectedCorners.topLeft == nil {
							selectedCorners.topLeft = coordinate
						} else if selectedCorners.bottomRight == nil {
							selectedCorners.bottomRight = coordinate
						} else {
							selectedCorners = (coordinate, nil)
						}
					}
				}
			}
			.animation(.easeInOut(duration: 0.3), value: addPins)
			.toolbarBackground(.clear)
			.navigationTitle("")
			.toolbar {
				ToolbarItem(placement: .navigation) {
					Button {} label: {
						Label("Settings", systemImage: "gear")
					}
				}

				ToolbarSpacer(.fixed)
				ToolbarItem(placement: .primaryAction) {
					Button {
						withAnimation {
							addPins.toggle()
						}
					} label: {
						Label(addPins ? "Done" : "Add Pins", systemImage: addPins ? "checkmark" : "plus")
							.contentTransition(.numericText())
					}
				}
			}
			.mapControlVisibility(.visible)
			.mapStyle(
				.hybrid(
					elevation: .realistic,
					pointsOfInterest: .including([]),
					showsTraffic: false
				)
			)
			.mapControls {
				Spacer()

				MapUserLocationButton()
				MapCompass()
				MapScaleView()

				#if os(macOS)
					MapZoomStepper()
				#endif
			}
		}
		.onChange(
			of: CornerPair(
				topLeft: selectedCorners.topLeft,
				bottomRight: selectedCorners.bottomRight
			)
		) {
			firePrediction = ""
			// Keep existing records when changing corners only if you want, otherwise clear:
			// records.removeAll()
		}
	}

	var sideView: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				// Instruction area
				Group {
					if selectedCorners.topLeft == nil {
						Label("Tap the first corner of the rectangle", systemImage: "circle.grid.cross.left.filled")
					} else if selectedCorners.bottomRight == nil {
						Label("Tap the opposite corner of the rectangle", systemImage: "circle.grid.cross.right.filled")
					} else {
						Label("Rectangle defined. Run to synthesize NDVI and predict fire.", systemImage: "checkmark.circle")
					}
				}
				.font(.callout)

				Button {
					if isRunning { cancelGeneration() } else {
						withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { isRunning = true }
						generateValuesAsync(seed: 42, date: Date(), batchSize: 128, gapFraction: 0.985)
					}
				} label: {
					HStack {
						if isRunning { ProgressView().progressViewStyle(.circular) }
						Text(isRunning ? "Cancel" : "Run Synthetic NDVI & Predict Fire").fontWeight(.semibold)
					}
					.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)

				// Quick stats and controls
				HStack {
					Text("Points:")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("\(records.count)")
						.font(.headline)
				}

				if !firePrediction.isEmpty {
					Text(firePrediction)
						.font(.body)
						.padding(8)
						.background(.thinMaterial)
						.clipShape(RoundedRectangle(cornerRadius: 10))
				}

				// Optional: show first few records for debugging
				if !records.isEmpty {
					GroupBox("Sample points") {
						VStack(alignment: .leading, spacing: 8) {
							ForEach(Array(records.prefix(6)), id: \.coordinate) { r in
								Text(String(format: "NDVI %.3f  LST %.1f°C  BurnProb %.2f", r.ndvi, r.lstC, r.burnedProb))
									.font(.caption2)
									.monospacedDigit()
							}
						}
						.padding(.vertical, 6)
					}
				}

				Spacer()
			}
			.padding()
		}
	}


	private func generateTileSeeds(
		minLat: Double,
		maxLat: Double,
		minLon: Double,
		maxLon: Double,
		baseSpacingMeters: Double,
		gapFraction: Double = 0.985,
		maxTiles: Int = 25
	) -> [TileSeed] {
		let top = maxLat
		let bottom = minLat
		let left = minLon
		let right = maxLon

		let latDiff = max(top - bottom, 0.000_001)
		let lonDiff = max(right - left, 0.000_001)

			// Start with provided spacing
		var spacingMeters = baseSpacingMeters

			// Compute spacing to ensure counts do not exceed maxTiles
		let metersPerDegreeLat = 111_320.0
		let midLat = (top + bottom) / 2.0
		let metersPerDegreeLon = 111_320.0 * cos(midLat * .pi / 180.0)

		var latCount = Int(ceil(latDiff * metersPerDegreeLat / spacingMeters))
		var lonCount = Int(ceil(lonDiff * metersPerDegreeLon / spacingMeters))

			// Increase spacing if too many tiles
		if latCount > maxTiles || lonCount > maxTiles {
			let scale = max(Double(latCount) / Double(maxTiles), Double(lonCount) / Double(maxTiles))
			spacingMeters *= scale
			latCount = Int(ceil(latDiff * metersPerDegreeLat / spacingMeters))
			lonCount = Int(ceil(lonDiff * metersPerDegreeLon / spacingMeters))
		}

			// Compute actual step size in degrees to **fill the bbox**
		let actualLatStep = latDiff / Double(latCount)
		let actualLonStep = lonDiff / Double(lonCount)
		let latHalf = (actualLatStep / 2.0) * gapFraction
		let lonHalf = (actualLonStep / 2.0) * gapFraction

		var seeds: [TileSeed] = []
		for latIndex in 0..<latCount {
			let centerLat = bottom + (Double(latIndex) * actualLatStep) + (actualLatStep / 2.0)
			for lonIndex in 0..<lonCount {
				let centerLon = left + (Double(lonIndex) * actualLonStep) + (actualLonStep / 2.0)
				let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
				let polygon = [
					CLLocationCoordinate2D(latitude: centerLat + latHalf, longitude: centerLon - lonHalf),
					CLLocationCoordinate2D(latitude: centerLat + latHalf, longitude: centerLon + lonHalf),
					CLLocationCoordinate2D(latitude: centerLat - latHalf, longitude: centerLon + lonHalf),
					CLLocationCoordinate2D(latitude: centerLat - latHalf, longitude: centerLon - lonHalf),
				]
				let coord = Coordinate(lat: centerLat, lon: centerLon)
				seeds.append(TileSeed(center: center, coordinate: coord, polygon: polygon))
			}
		}
		return seeds
	}








		// tile polygon helper (keeps render consistent with gapFraction)
	private func tilePolygonCoordinates(center: CLLocationCoordinate2D, spacingMeters: Double, gapFraction: Double = 0.985) -> [CLLocationCoordinate2D] {
		let latHalfDeg = (spacingMeters / 111_320.0) / 2.0 * gapFraction
		let metersPerDegLon = 111_320.0 * cos(center.latitude * .pi / 180.0)
		let lonHalfDeg = (spacingMeters / max(metersPerDegLon, 0.000_001)) / 2.0 * gapFraction

		return [
			CLLocationCoordinate2D(latitude: center.latitude + latHalfDeg, longitude: center.longitude - lonHalfDeg),
			CLLocationCoordinate2D(latitude: center.latitude + latHalfDeg, longitude: center.longitude + lonHalfDeg),
			CLLocationCoordinate2D(latitude: center.latitude - latHalfDeg, longitude: center.longitude + lonHalfDeg),
			CLLocationCoordinate2D(latitude: center.latitude - latHalfDeg, longitude: center.longitude - lonHalfDeg),
		]
	}

		// Async batch generator. Precomputes coords & options, then performs background batches.
		// Uses synthesizeRecords(for:options:) synchronously on a background thread.
	func generateValuesAsync(seed: UInt64 = 42, date: Date = Date(), batchSize: Int = 128, gapFraction: Double = 0.985) {
			// cancel any running work
		generationTask?.cancel()

			// Build options (copy) used by the generator
		var opts = SyntheticOptions()
		opts.seed = seed
		opts.date = date

			// prepare coords (compute seeds now so we don't capture self inside heavy work)
		let coordsList: [Coordinate]
		if let c = normalizedCorners {
			let seeds = generateTileSeeds(
				minLat: c.bottomRight.latitude,
				maxLat: c.topLeft.latitude,
				minLon: c.topLeft.longitude,
				maxLon: c.bottomRight.longitude,
				baseSpacingMeters: spacingMeters,
				gapFraction: gapFraction
			)
			coordsList = seeds.map { $0.coordinate }
		} else {
				// fallback small sample area
			let bboxMinLat = 37.33
			let bboxMaxLat = 37.34
			let bboxMinLon = -122.04
			let bboxMaxLon = -122.02
			let seeds = generateTileSeeds(
				minLat: bboxMinLat,
				maxLat: bboxMaxLat,
				minLon: bboxMinLon,
				maxLon: bboxMaxLon,
				baseSpacingMeters: spacingMeters,
				gapFraction: gapFraction
			)
			coordsList = seeds.map { $0.coordinate }
		}

			// clear old records and mark running
		records.removeAll()
		isRunning = true

			// Start detached worker; it will periodically marshal results to the main actor.
		generationTask = Task.detached(priority: .userInitiated) {
			let total = coordsList.count
			let strideSize = batchSize
			for i in stride(from: 0, to: total, by: strideSize) {
				if Task.isCancelled { break }
				let batch = Array(coordsList[i..<min(i+strideSize, total)])

					// Offload to background queue
				let batchResult = await withCheckedContinuation { cont in
					DispatchQueue.global(qos: .userInitiated).async {
						let result = synthesizeRecords(for: batch.map { Coord(lat: $0.lat, lon: $0.lon) }, options: opts)
						cont.resume(returning: result)
					}
				}

				await MainActor.run { records.append(contentsOf: batchResult) }
				await Task.yield()
			}
			await MainActor.run {
				isRunning = false
				generationTask = nil
			}
		}

	}

		// Cancel an in-progress generation
	func cancelGeneration() {
		generationTask?.cancel()
		generationTask = nil
		isRunning = false
	}


	// ---------- EXISTING functions (unchanged apart from using records/isRunning where needed) ----------
	// generateValues(seed:date:) and calculateFire() are expected to exist in this file scope as provided earlier.
	// The implementations referenced must be present (synthesizeRecordsFromBBox, predictFireProbabilitySafe, etc.).
	func generateValues(seed: UInt64 = 42, date: Date = Date()) {
		// Build options by mutating the default initializer (SyntheticOptions has no parameterized init).
		var opts = SyntheticOptions()
		opts.seed = seed
		opts.date = date

		if let c = normalizedCorners {
			records = synthesizeRecordsFromBBox(
				minLat: c.bottomRight.latitude,
				maxLat: c.topLeft.latitude,
				minLon: c.topLeft.longitude,
				maxLon: c.bottomRight.longitude,
				spacingMeters: spacingMeters,
				options: opts
			)
		} else {
			// default fallback bbox (small sample)
			let bboxMinLat = 37.33
			let bboxMaxLat = 37.34
			let bboxMinLon = -122.04
			let bboxMaxLon = -122.02
			records = synthesizeRecordsFromBBox(
				minLat: bboxMinLat,
				maxLat: bboxMaxLat,
				minLon: bboxMinLon,
				maxLon: bboxMaxLon,
				spacingMeters: spacingMeters,
				options: opts
			)
		}
	}

	func calculateFire() {
		// Ensure values exist
		if records.isEmpty {
			generateValues()
		}

		// compute probabilities (predictFireProbabilitySafe uses CoreML if available, else heuristic)
		Task.detached { @MainActor in
			let probs = records.map { predictFireProbabilitySafe(for: $0) }
			let count = Double(max(1, probs.count))
			let avg = probs.reduce(0, +) / count
			let maxP = probs.max() ?? 0.0
			let pStr = String(format: "%.2f", avg)
			let maxStr = String(format: "%.2f", maxP)
			firePrediction = "Avg fire prob: \(pStr)  •  Max: \(maxStr)  •  Points: \(Int(count))"

			// clear prediction after brief delay
			DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
				firePrediction = ""
			}
		}
	}
}

#Preview {
	ContentView()
}

struct CornerPair: Equatable {
	let topLeft: CLLocationCoordinate2D?
	let bottomRight: CLLocationCoordinate2D?

	static func == (lhs: CornerPair, rhs: CornerPair) -> Bool {
		lhs.topLeft?.latitude == rhs.topLeft?.latitude &&
			lhs.topLeft?.longitude == rhs.topLeft?.longitude &&
			lhs.bottomRight?.latitude == rhs.bottomRight?.latitude &&
			lhs.bottomRight?.longitude == rhs.bottomRight?.longitude
	}
}
