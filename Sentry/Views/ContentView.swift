//
//  ContentView.swift
//  Sentry
//
//  Created by Adon Omeri on 30/9/2025.
//

import CoreML
import MapKit
import SwiftUI

actor DataGenerationActor {
	private var isCancelled = false

	func cancelGeneration() {
		isCancelled = true
	}

	func resetCancellation() {
		isCancelled = false
	}

	func generateRecords(
		coordinates: [Coord],
		options: SyntheticOptions,
		progressCallback: @MainActor @Sendable (Double) -> Void
	) async -> [NDVILSTRecord] {
		await resetCancellation()

		let batchSize = 800
		let total = coordinates.count
		var allRecords: [NDVILSTRecord] = []
		allRecords.reserveCapacity(total)

		for i in stride(from: 0, to: total, by: batchSize) {
			if isCancelled { break }

			let endIndex = min(i + batchSize, total)
			let batch = Array(coordinates[i ..< endIndex])

			let batchRecords = await synthesizeRecordsAsync(for: batch, options: options)

			if isCancelled { break }
			allRecords.append(contentsOf: batchRecords)

			if i % (batchSize * 10) == 0 || endIndex == total {
				let progress = Double(endIndex) / Double(total)
				await progressCallback(progress)
			}
		}

		return isCancelled ? [] : allRecords
	}

	func calculateFireProbabilities(for records: [NDVILSTRecord]) async -> (avg: Double, max: Double, count: Int) {
		let probs = await predictFireProbabilitiesAsync(for: records)
		let count = max(1, probs.count)
		let avg = probs.reduce(0, +) / Double(count)
		let maxP = probs.max() ?? 0.0

		return (avg: avg, max: maxP, count: count)
	}
}

struct Location: Identifiable {
	let id = UUID()
	var name: String
	var coordinate: CLLocationCoordinate2D
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

	@State var selectedCorners: (topLeft: CLLocationCoordinate2D?, bottomRight: CLLocationCoordinate2D?) = (nil, nil)
	@State private var currentDetent: PresentationDetent = .height(100)

	@State private var records: [NDVILSTRecord] = []
	private let spacingMeters: Double = 500.0
	@State private var generationProgress: Double = 0.0
	@State private var totalRecordsToGenerate: Int = 0

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

	@State var firePrediction = ""

	@State private var dataGenerator = DataGenerationActor()
	@State private var generationTask: Task<Void, Never>? = nil
	@State private var isRunning: Bool = false

	@State private var estimatedCellCount = 0
	private let maxAllowedCells = 500
	private let maxRenderableRecords = 200

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
							.presentationDetents([
								.height(100),
								.fraction(0.2),
								.fraction(0.35),
								.medium,
							], selection: $currentDetent)
							.presentationBackgroundInteraction(.enabled)
							.presentationDragIndicator(.visible)
					}
					.onChange(of: isSheetPresented) { presented in
						if !presented {
							DispatchQueue.main.async {
								isSheetPresented = true
							}
						}
					}
			}
		}
	}

	private var mapView: some View {
		MapReader { proxy in
			Map(
				position: $position,
				interactionModes: [.pan, .zoom],
				scope: mapScope
			) {
				UserAnnotation()

				ForEach(records.prefix(maxRenderableRecords), id: \.coordinate) { rec in
					let normalizedNDVI = max(0.0, min(1.0, (rec.ndvi + 1.0) * 0.5))
					let hue = min(1.0, 0.33 * normalizedNDVI)

					let center = CLLocationCoordinate2D(latitude: rec.coordinate.lat, longitude: rec.coordinate.lon)
					let polygonCoords = tilePolygonCoordinates(center: center, spacingMeters: spacingMeters)

					MapPolygon(coordinates: polygonCoords)
						.foregroundStyle(Color(hue: hue, saturation: 0.8, brightness: 0.9).opacity(0.6))

					if records.count <= 100 {
						Annotation("", coordinate: center) {
							Text(String(format: "%.2f", rec.ndvi))
								.font(.caption2)
								.fontWeight(.medium)
								.padding(1)
								.background(.thinMaterial)
								.clipShape(RoundedRectangle(cornerRadius: 3))
						}
						.annotationTitles(.hidden)
					}
				}

				if let corners = normalizedCorners, records.isEmpty {
					let path: [CLLocationCoordinate2D] = [
						corners.topLeft,
						CLLocationCoordinate2D(latitude: corners.topLeft.latitude, longitude: corners.bottomRight.longitude),
						corners.bottomRight,
						CLLocationCoordinate2D(latitude: corners.bottomRight.latitude, longitude: corners.topLeft.longitude),
					]

					MapPolygon(coordinates: path)
						.foregroundStyle(.orange.opacity(0.2))
				}

				if let topLeft = selectedCorners.topLeft {
					Annotation("Top Left", coordinate: topLeft) {
						Image(systemName: "mappin.circle.fill")
							.foregroundStyle(.orange)
							.background(.white, in: .circle)
					}
					.annotationTitles(.hidden)
				}
				if let bottomRight = selectedCorners.bottomRight {
					Annotation("Bottom Right", coordinate: bottomRight) {
						Image(systemName: "mappin.circle.fill")
							.foregroundStyle(.orange)
							.background(.white, in: .circle)
					}
					.annotationTitles(.hidden)
				}
			}
			.onTapGesture(coordinateSpace: .local) { location in
				if let coordinate = proxy.convert(location, from: .local) {
					if selectedCorners.topLeft == nil {
						selectedCorners.topLeft = coordinate
					} else if selectedCorners.bottomRight == nil {
						selectedCorners.bottomRight = coordinate
						estimatedCellCount = estimateCellCount()
					} else {
						selectedCorners = (coordinate, nil)
					}
				}
			}
		}
		.toolbarBackground(.clear)
		.navigationTitle("")
		.mapControlVisibility(.visible)
		.mapStyle(
						.hybrid(
				elevation: .realistic,
				pointsOfInterest: .all,
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

	var sideView: some View {
		List {
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
			.listRowBackground(Color.clear)
			.listRowSeparator(.hidden)

			Button {
				if isRunning {
					cancelGeneration()
				} else {
					estimatedCellCount = estimateCellCount()
					if estimatedCellCount > maxAllowedCells {
						resizeSelectionToFitLimit()
						estimatedCellCount = estimateCellCount()
					}
					withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { isRunning = true }
					generateValuesOnThread(seed: 42, date: Date())
				}
			} label: {
				if isRunning { ProgressView().progressViewStyle(.circular) }
				Text(isRunning ? "Cancel" : "Run Prediction")
					.fontWeight(.semibold)
			}
			.buttonSizing(.flexible)
			.buttonStyle(.glassProminent)
			.listRowBackground(Color.clear)
			.listRowSeparator(.hidden)

			if let _ = normalizedCorners, !isRunning {
				HStack {
					Text("Estimated data points:")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("\(estimatedCellCount)")
						.font(.caption)
						.fontWeight(.medium)
						.foregroundStyle(estimatedCellCount > maxAllowedCells ? .red : .primary)
				}
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)

				if estimatedCellCount > maxAllowedCells {
					Text("Selection exceeds the \(maxAllowedCells) point limit")
						.font(.caption)
						.foregroundStyle(.red)
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
				}
			}

			if !isRunning {
				HStack {
					Text("Points:")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("\(records.count)")
						.font(.headline)
				}
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)

				if !firePrediction.isEmpty {
					Text(firePrediction)
						.font(.body)
						.padding(8)
						.transition(.opacity)
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
				}

				if !records.isEmpty {
					Section("Sample Data") {
						VStack(alignment: .leading, spacing: 6) {
							ForEach(Array(records.prefix(4)), id: \.coordinate) { r in
								Text(
									String(
										format: "NDVI %.3f          LST %.2f°C          BURNED AREA %.1f",
										r.ndvi,
										r.lstC,
										r.burnedProb
									)
								)
								.font(.caption2)
								.monospacedDigit()
							}
						}
						.padding(.vertical, 4)
					}
					.listRowBackground(Color.clear)
					.listRowSeparator(.hidden)
				}
			} else {
				Text("Processing in background...")
					.font(.caption)
					.foregroundStyle(.secondary)
					.listRowBackground(Color.clear)
					.listRowSeparator(.hidden)

				HStack {
					Text("Progress:")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("\(Int(generationProgress * 100))%")
						.font(.headline)
						.monospacedDigit()
				}
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)
			}
		}
		.scrollContentBackground(.hidden)
		.background(.clear)
		.listStyle(.sidebar)
	}

	private func estimateCellCount() -> Int {
		guard let corners = normalizedCorners else { return 0 }

		let latDiff = abs(corners.topLeft.latitude - corners.bottomRight.latitude)
		let lonDiff = abs(corners.topLeft.longitude - corners.bottomRight.longitude)

		let heightMeters = latDiff * 111_320
		let widthMeters = lonDiff * 111_320 * cos((corners.topLeft.latitude + corners.bottomRight.latitude) / 2 * .pi / 180.0)

		let cellsHeight = Int(ceil(heightMeters / spacingMeters))
		let cellsWidth = Int(ceil(widthMeters / spacingMeters))

		return cellsHeight * cellsWidth
	}

	private func resizeSelectionToFitLimit() {
		guard let corners = normalizedCorners, estimatedCellCount > maxAllowedCells else { return }

		let scaleFactor = sqrt(Double(maxAllowedCells) / Double(estimatedCellCount))

		let centerLat = (corners.topLeft.latitude + corners.bottomRight.latitude) / 2
		let centerLon = (corners.topLeft.longitude + corners.bottomRight.longitude) / 2

		let latSpan = corners.topLeft.latitude - corners.bottomRight.latitude
		let lonSpan = corners.bottomRight.longitude - corners.topLeft.longitude

		let newLatSpan = latSpan * scaleFactor
		let newLonSpan = lonSpan * scaleFactor

		let newTopLeft = CLLocationCoordinate2D(
			latitude: centerLat + (newLatSpan / 2),
			longitude: centerLon - (newLonSpan / 2)
		)

		let newBottomRight = CLLocationCoordinate2D(
			latitude: centerLat - (newLatSpan / 2),
			longitude: centerLon + (newLonSpan / 2)
		)

		selectedCorners = (newTopLeft, newBottomRight)

		estimatedCellCount = estimateCellCount()
	}

	private var cachedLatHalfDeg: Double?
	private var cachedLonHalfDegAtLat: [Double: Double] = [:]

	private func tilePolygonCoordinates(center: CLLocationCoordinate2D, spacingMeters: Double) -> [CLLocationCoordinate2D] {
		let latHalfDeg = (spacingMeters / 111_320.0) / 2.0
		let metersPerDegLon = 111_320.0 * cos(center.latitude * .pi / 180.0)
		let lonHalfDeg = (spacingMeters / max(metersPerDegLon, 0.000_001)) / 2.0

		return [
			CLLocationCoordinate2D(latitude: center.latitude + latHalfDeg, longitude: center.longitude - lonHalfDeg),
			CLLocationCoordinate2D(latitude: center.latitude + latHalfDeg, longitude: center.longitude + lonHalfDeg),
			CLLocationCoordinate2D(latitude: center.latitude - latHalfDeg, longitude: center.longitude + lonHalfDeg),
			CLLocationCoordinate2D(latitude: center.latitude - latHalfDeg, longitude: center.longitude - lonHalfDeg),
		]
	}

	func generateValuesOnThread(seed: UInt64 = 42, date: Date = Date()) {
		cancelGeneration()

		var opts = SyntheticOptions()
		opts.seed = seed
		opts.date = date

		let coordsList: [Coord]
		if let c = normalizedCorners {
			coordsList = generateGrid(
				minLat: c.bottomRight.latitude,
				maxLat: c.topLeft.latitude,
				minLon: c.topLeft.longitude,
				maxLon: c.bottomRight.longitude,
				spacingMeters: spacingMeters
			)
		} else {
			coordsList = generateGrid(
				minLat: 37.33,
				maxLat: 37.34,
				minLon: -122.04,
				maxLon: -122.02,
				spacingMeters: spacingMeters
			)
		}

		let limitedCoords = coordsList.count > maxAllowedCells
			? Array(coordsList.prefix(maxAllowedCells))
			: coordsList

		records.removeAll()
		totalRecordsToGenerate = limitedCoords.count
		generationProgress = 0.0

		generationTask = Task(priority: .userInitiated) {
			try? await Task.sleep(nanoseconds: 100_000_000)

			let generatedRecords = await dataGenerator.generateRecords(
				coordinates: limitedCoords,
				options: opts
			) { @MainActor progress in
				withAnimation(.linear(duration: 0.1)) {
					self.generationProgress = progress
				}
			}

			guard !Task.isCancelled else {
				await MainActor.run {
					self.isRunning = false
					self.generationTask = nil
					self.generationProgress = 0.0
				}
				return
			}

			await MainActor.run {
				if !generatedRecords.isEmpty {
					self.records = generatedRecords
					self.generationProgress = 1.0
				}
			}

			try? await Task.sleep(nanoseconds: 300_000_000)

			if !Task.isCancelled {
				await MainActor.run {
					self.isRunning = false
					self.generationTask = nil
				}

				if !generatedRecords.isEmpty {
					await MainActor.run {
						self.calculateFire()
					}
				}
			}
		}
	}

	func cancelGeneration() {
		generationTask?.cancel()
		Task {
			await dataGenerator.cancelGeneration()
		}
		isRunning = false
		generationTask = nil
		generationProgress = 0.0
		totalRecordsToGenerate = 0
	}

	func generateValuesAsync(seed: UInt64 = 42, date: Date = Date()) async -> [NDVILSTRecord] {
		var opts = SyntheticOptions()
		opts.seed = seed
		opts.date = date

		if let c = normalizedCorners {
			let raw = await synthesizeRecordsFromBBoxAsync(
				minLat: c.bottomRight.latitude,
				maxLat: c.topLeft.latitude,
				minLon: c.topLeft.longitude,
				maxLon: c.bottomRight.longitude,
				spacingMeters: spacingMeters,
				options: opts
			)
			return Array(raw.prefix(maxAllowedCells))
		} else {
			let raw = await synthesizeRecordsFromBBoxAsync(
				minLat: 37.33,
				maxLat: 37.34,
				minLon: -122.04,
				maxLon: -122.02,
				spacingMeters: spacingMeters,
				options: opts
			)
			return Array(raw.prefix(maxAllowedCells))
		}
	}

	func generateValues(seed: UInt64 = 42, date: Date = Date()) {
		Task {
			let newRecords = await generateValuesAsync(seed: seed, date: date)
			await MainActor.run {
				records = newRecords
			}
		}
	}

	func calculateFire() {
		guard !records.isEmpty else { return }

		Task(priority: .userInitiated) {
			let fireStats = await dataGenerator.calculateFireProbabilities(for: records)

			await MainActor.run {
				let pStr = String(format: "%.2f", fireStats.avg)
				let maxStr = String(format: "%.2f", fireStats.max)
				self.firePrediction = "Avg fire prob: \(pStr) • Max: \(maxStr) • Points: \(fireStats.count)"
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
