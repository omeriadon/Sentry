//
//  ContentView.swift
//  Sentry
//
//  Created by Adon Omeri on 30/9/2025.
//

import MapKit
import SwiftUI

struct Landmark: Identifiable {
	let id = UUID()
	let name: String
	let coordinate: CLLocationCoordinate2D
}

struct ContentView: View {
	@State private var mapType: MapKit.MapStyle = .standard
	@State private var cameraPosition: MapCameraPosition = .region(
		MKCoordinateRegion(
			center: CLLocationCoordinate2D(latitude: -31.95, longitude: 115.86),
			span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
		)
	)
	let landmarks = [
		Landmark(name: "Kings Park", coordinate: CLLocationCoordinate2D(latitude: -31.961, longitude: 115.843)),
	]

	@State var isSheetPresented = true

	var body: some View {
		NavigationStack {
			ZStack {
				Map(position: $cameraPosition) {
					ForEach(landmarks) { landmark in
						Marker(landmark.name, coordinate: landmark.coordinate)
					}
				}
				.mapStyle(mapType)
				.mapControlVisibility(.visible)
				.mapControls {
					MapUserLocationButton()
					MapCompass()
					MapScaleView()
				}
//				.sheet(isPresented: .constant(true)) {
//					HStack {
//						Text("search here")
//						Spacer()
//						Circle()
//					}
//					.padding()
//					.presentationDetents([.height(80), .medium, .large])
//					.presentationBackgroundInteraction(.enabled)
//				}
				.adaptiveSheet(isPresented: $isSheetPresented) {
					HStack {
						Text("search here")
						Spacer()
						Circle()
					}
				}

				#if !os(macOS) && !os(visionOS)
					VStack {
						Rectangle()
							.fill(.ultraThickMaterial)
							.mask(
								LinearGradient(
									colors: [
										.black,
										.black.opacity(0.8),
										.black.opacity(0.5),
										.black.opacity(0),
									], startPoint: .top,
									endPoint: .bottom
								)
							)
							.frame(height: 60)
							.ignoresSafeArea(edges: .top)

						Spacer()

						Rectangle()
							.fill(.ultraThickMaterial)
							.mask(
								LinearGradient(
									colors: [
										.black.opacity(0.0),
										.black.opacity(0.5),
										.black.opacity(0.8),
										.black,
									], startPoint: .top,
									endPoint: .bottom
								)
							)
							.frame(height: 60)
							.ignoresSafeArea(edges: .bottom)
					}
					.ignoresSafeArea()
					.allowsHitTesting(false)
				#endif // !os(macOS) || !os(visionOS)
			}
		}
	}
}

#Preview {
	ContentView()
}
