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

					// Draw rectangle polygon if both corners exist
					if let topLeft = selectedCorners.topLeft, let bottomRight = selectedCorners.bottomRight {
						let minLat = min(topLeft.latitude, bottomRight.latitude)
						let maxLat = max(topLeft.latitude, bottomRight.latitude)
						let minLon = min(topLeft.longitude, bottomRight.longitude)
						let maxLon = max(topLeft.longitude, bottomRight.longitude)

						let path: [CLLocationCoordinate2D] = [
							CLLocationCoordinate2D(latitude: maxLat, longitude: minLon), // top-left
							CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon), // top-right
							CLLocationCoordinate2D(latitude: minLat, longitude: maxLon), // bottom-right
							CLLocationCoordinate2D(latitude: minLat, longitude: minLon), // bottom-left
						]

						if let topLeft = selectedCorners.0 {
							Annotation(
								"Top Left",
								coordinate: topLeft
							) {
								Image(systemName: "chevron.up")
									.imageScale(.large)
									.padding(7)
									.rotationEffect(Angle(degrees: -45))
									.glassEffect(.regular.tint(.orange), in: .circle)
							}
							.annotationTitles(.hidden)
						}

						if let bottomRight = selectedCorners.1 {
							Annotation(
								"Bottom Right",
								coordinate: bottomRight
							) {
								Image(systemName: "chevron.up")
									.imageScale(.large)
									.padding(7)
									.rotationEffect(Angle(degrees: 135))
									.glassEffect(.regular.tint(.orange), in: .circle)
							}
							.annotationTitles(.hidden)
						}

						MapPolygon(coordinates: path)
							.foregroundStyle(.orange.opacity(0.2))
							.stroke(Color.white, lineWidth: 2)
							.strokeStyle(
								style: .init(
									lineCap: .round,
									lineJoin: .round
								)
							)
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
