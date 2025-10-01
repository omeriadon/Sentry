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
				// Horizontal = regular width, compact height
				return hSize == .regular /* && vSize == .compact*/
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

	@State var selectedLocation: MKMapItem?

	@State var addPins = false

	@State private var currentDetent: PresentationDetent = .medium

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
				if addPins {
					Map(
						position: $position,
						interactionModes: [.pan, .rotate, .zoom],
						scope: mapScope
					) {
						UserAnnotation()

						ForEach(locations) { location in
							Marker(location.name, coordinate: location.coordinate)
								.tag(
									MKMapItem(
										location: CLLocation(
											latitude: location.coordinate.latitude,
											longitude: location.coordinate.longitude
										),
										address: nil
									)
								)
						}
						.annotationTitles(.hidden)
					}
					.onTapGesture { position in
						if addPins {
							if let coordinate = proxy.convert(position, from: .local) {
								let item = Location(
									name: coordinate.animatableData.first.description,
									coordinate: coordinate
								)

								locations.append(item)
							}
						}
					}
					.transition(.opacity)
				} else {
					Map(
						position: $position,
						interactionModes: [.pan, .rotate, .zoom],
						selection: $selectedLocation,
						scope: mapScope
					) {
						UserAnnotation()

						ForEach(locations) { location in
							Marker(location.name, coordinate: location.coordinate)
								.tag(
									MKMapItem(
										location: CLLocation(
											latitude: location.coordinate.latitude,
											longitude: location.coordinate.longitude
										),
										address: nil
									)
								)
						}
						.annotationTitles(.hidden)
					}
					.transition(.opacity)
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
		NavigationStack {
			List {
				if locations.isEmpty {
					Text("Add a location to get started.")
						.listRowBackground(Color.clear.background(.ultraThinMaterial))
				} else {
					ForEach(locations) { location in
						Button {
							withAnimation {
								selectedLocation =
									MKMapItem(
										location: CLLocation(
											latitude: location.coordinate.latitude,
											longitude: location.coordinate.longitude
										),
										address: nil
									)
							}
						} label: {
							Text(location.name)
						}
						.listRowBackground(Color.clear.background(.ultraThinMaterial))
					}
				}
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.background(.clear)
		}
	}
}

#Preview {
	ContentView()
}
