import AppKit
import SwiftUI
import MeterCore

/// Documentation scene built from the app's real status icon and popover content.
/// It uses a generated backdrop and synthetic data, never a user's desktop.
struct DemoSceneView: View {
    @ObservedObject var store: MeterStore
    let statusIcon: (UsageAnalysis) -> NSImage
    let statusTitle: () -> String
    let showDashboard: () -> Void
    let showSettings: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.19, green: 0.48, blue: 0.65),
                                    Color(red: 0.49, green: 0.74, blue: 0.78),
                                    Color(red: 0.84, green: 0.78, blue: 0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Ellipse().fill(Color.white.opacity(0.13))
                .frame(width: 1250, height: 430).rotationEffect(.degrees(-18))
                .offset(x: 220, y: 390).blur(radius: 60)

            VStack(spacing: 0) {
                ZStack {
                    Color.white.opacity(0.06)
                    HStack(spacing: 7) {
                        if let analysis = store.currentAnalysis {
                            Image(nsImage: statusIcon(analysis)).frame(width: 21, height: 21)
                            Text(statusTitle().trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                }.frame(height: 32)

                Spacer().frame(height: 14)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Palette.background)
                        .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 8)
                    PopoverView(store: store, showDashboard: showDashboard, showSettings: showSettings)
                        .frame(width: 396, height: 648)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    PopoverPointer().fill(Palette.background)
                        .frame(width: 26, height: 12).offset(y: -11)
                }.frame(width: 396, height: 648)
            }
        }.frame(width: 880, height: 730).clipped()
    }
}

private struct PopoverPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - 3, y: 3))
            path.addQuadCurve(to: CGPoint(x: rect.midX + 3, y: 3), control: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
