//
//  DeviceEnvironment.swift
//  Sentry
//
//  Created by Adon Omeri on 1/10/2025.
//

import SwiftUI

extension EnvironmentValues {
	var useNavSplitView: Bool {
		#if os(macOS) || os(visionOS)
			return true
		#elseif os(iOS)
			switch UIDevice.current.userInterfaceIdiom {
			case .pad:
				if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
					let hSize = scene.traitCollection.horizontalSizeClass
					let vSize = scene.traitCollection.verticalSizeClass
					return hSize == .regular && vSize == .compact // horizontal
				}
				return false // vertical
			case .phone:
				return false

			default:
				return false
			}
		#else
			return false
		#endif
	}
}
