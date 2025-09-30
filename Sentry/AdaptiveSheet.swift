//
//  AdaptiveSheet.swift
//  Sentry
//
//  Created by Adon Omeri on 30/9/2025.
//

import SwiftUI

extension View {
	public func adaptiveSheet<Content: View>(
		isPresented: Binding<Bool>,
		@ViewBuilder content: @escaping () -> Content
	) -> some View {
		modifier(AdaptiveSheet(isPresented: isPresented, sheetContent: content))
	}
}

struct AdaptiveSheet<SheetContent: View>: ViewModifier {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Binding var isPresented: Bool

	@State private var sheetPosition: CustomBottomSheet<SheetContent>.SheetPosition = .collapsed

	let sheetContent: () -> SheetContent

	func body(content: Content) -> some View {
		ZStack {
				//your own stuff will go in here!
			content

			CustomBottomSheet(
				sheetPosition: $sheetPosition,
				content: sheetContent
			)
		}
		.onChange(of: horizontalSizeClass) { old, new in
			handleSizeClassChange(from: old, to: new)
		}
		.onAppear {
			if horizontalSizeClass == .regular {
				isPresented = false
			}
		}
	}

		//device orientation change? fret not :D
	private func handleSizeClassChange(from old: UserInterfaceSizeClass?, to new: UserInterfaceSizeClass?) {
		if old == .regular && new == .compact {
			isPresented = (sheetPosition == .fullyExpanded)
		}

		if old == .compact && new == .regular {
			sheetPosition = isPresented ? .fullyExpanded : .collapsed
			isPresented = false
		}
	}
}


private struct CustomBottomSheet<Content: View>: View {
	enum SheetPosition {
		case collapsed, fullyExpanded
	}

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Binding var sheetPosition: SheetPosition

		//we use a dragOffset to apply real-time movement,
		//and update the final position when the drag ends.
	@State private var dragOffset: CGFloat = 0

	let content: () -> Content

	var body: some View {
		GeometryReader { geometry in
			VStack {
					//See 4. for the Handle design :)
				DragHandle { value in
					dragOffset = value
				} onDragEnded: { value in
					handleDragEnd(translation: value, height: geometry.size.height)
				}

				content()
			}
			.frame(
				width: horizontalSizeClass == .compact ? geometry.size.width : 350,
				height: geometry.size.height,
				alignment: .top
			)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
			.shadow(radius: 4)
			.offset(
				x: horizontalSizeClass == .compact ? 0 : geometry.size.width * 0.05,
				y: calculatedOffset(for: sheetPosition, height: geometry.size.height) + dragOffset
			)
			.animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: dragOffset)
		}
		.edgesIgnoringSafeArea(.bottom)
	}

		//the drag logic checks if you're dragging up or down,
	private func handleDragEnd(translation: CGFloat, height: CGFloat) {
		let threshold: CGFloat = 100
		let collapsedY = calculatedOffset(for: .collapsed, height: height)
		let expandedY = calculatedOffset(for: .fullyExpanded, height: height)
		let currentY = collapsedY + dragOffset

			//and chooses the closest snap point:
		let newPosition: SheetPosition = {
			if translation > threshold { return .collapsed }
			if translation < -threshold { return .fullyExpanded }
			let midpoint = (collapsedY + expandedY) / 2
			return currentY > midpoint ? .collapsed : .fullyExpanded
		}()

			//a springy feedback
		withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8)) {
			sheetPosition = newPosition
			dragOffset = 0
		}
	}

		//my magic numbers, but feel free to adjust :)
		//offset here basically means distance from top on both states
	private func calculatedOffset(for position: SheetPosition, height: CGFloat) -> CGFloat {
		let compactOffsetPosition: CGFloat = 180
		let regularOffsetPosition: CGFloat = 80
		let expandedOffsetPositionMultiplier: CGFloat = 0.075

		switch position {
			case .collapsed:
				return height - (horizontalSizeClass == .compact ? compactOffsetPosition : regularOffsetPosition)
			case .fullyExpanded:
				return height * expandedOffsetPositionMultiplier
		}
	}
}


private struct DragHandle: View {
	let onDragChanged: (CGFloat) -> Void
	let onDragEnded: (CGFloat) -> Void

	var body: some View {
			//where the design goes
		Capsule()
			.frame(width: 40, height: 6)
			.foregroundColor(.gray)
			.padding(10)
			.contentShape(Rectangle())
			.gesture(
				//actual gesture handling
				DragGesture()
					.onChanged { value in onDragChanged(value.translation.height) }
					.onEnded { value in onDragEnded(value.translation.height) }
			)
	}
}
