//
//  ContentView.swift
//  Sentry
//
//  Created by Adon Omeri on 30/9/2025.
//

import MapKit
import SwiftUI

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

	// Rectangle corners
	@State var selectedCorners: (topLeft: CLLocationCoordinate2D?, bottomRight: CLLocationCoordinate2D?) = (nil, nil)
	@State var addPins = false
	@State private var currentDetent: PresentationDetent = .height(80)

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

	var body: some View {
		Group {
			if useNavSplitView {
				NavigationSplitView {
					sideView
						.navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
				} detail: {
					mapView
				}

			} else {
				ZStack {
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
	}

	var mapView: some View {
		NavigationStack {
			MapReader { proxy in
				Map(
					position: $position,
					interactionModes: [.pan, .rotate, .zoom],
					scope: mapScope
				) {
					UserAnnotation()

					if let topLeft = selectedCorners.topLeft {
						Annotation("Top Left", coordinate: topLeft) {
							Image(systemName: "chevron.up")
								.imageScale(.large)
								.padding(7)
								.rotationEffect(Angle(degrees: -45))
								.glassEffect(.regular.tint(.orange), in: .circle)
						}
						.annotationTitles(.hidden)
					}

					if let bottomRight = selectedCorners.bottomRight {
						Annotation("Bottom Right", coordinate: bottomRight) {
							Image(systemName: "chevron.up")
								.imageScale(.large)
								.padding(7)
								.rotationEffect(Angle(degrees: 135))
								.glassEffect(.regular.tint(.orange), in: .circle)
						}
						.annotationTitles(.hidden)
					}

					if let corners = normalizedCorners {
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
					}
				}
				.onTapGesture { position in
					if addPins, let coordinate = proxy.convert(position, from: .local) {
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
			#if os(iOS)
				.navigationBarTitleDisplayMode(.inline)
			#endif
				.navigationTitle("Sentry")
				.toolbar {
					ToolbarItem {
						Button {} label: {
							Label("Settings", systemImage: "gear")
						}
					}

					ToolbarSpacer(.fixed)
					ToolbarItem {
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
						elevation: .flat,
						pointsOfInterest: .including([]),
						showsTraffic: false
					)
				)
				.mapControls {
					MapUserLocationButton()
					MapCompass()
					MapScaleView()

					#if os(macOS)
						MapZoomStepper()
					#endif
				}
		}
	}

	var sideView: some View {
		Group {
			if selectedCorners.topLeft == nil {
				Label("Tap top-left corner of the rectangle",
				      systemImage: "square.grid.3x3.topleft.filled")
					.transition(.blurReplace)

			} else if selectedCorners.bottomRight == nil {
				Label("Tap bottom-right corner of the rectangle",
				      systemImage: "square.grid.3x3.bottomright.filled")
					.transition(.blurReplace)

			} else {
				Label(
					"Rectangle defined, you can adjust corners by tapping again",
					systemImage: "checkmark.circle"
				)
				.transition(.blurReplace)
			}
		}
		.animation(
			.easeInOut,
			value: CornerPair(topLeft: selectedCorners.topLeft, bottomRight: selectedCorners.bottomRight)
		)
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
