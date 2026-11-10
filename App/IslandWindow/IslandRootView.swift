import AnimationKit
import BuiltInProfiles
import IslandCore
import ProfileKit
import SwiftUI

/// T053 — SwiftUI root for the pill panel. Renders the primary + secondary
/// slots by dispatching to each occupant profile's `makeFullPillView` /
/// `makeHalfPillView`. Backgrounds are owned by `IslandCore.Theme` (S-5);
/// profiles draw only foreground.
struct IslandRootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let slotState = appState.slotState
        let bothOccupied = !slotState.primary.isEmpty && !slotState.secondary.isEmpty
        let totalWidth: CGFloat = bothOccupied ? Geometry.splitWidth : Geometry.expandedWidth

        HStack(spacing: Geometry.splitGap) {
            if !slotState.primary.isEmpty {
                view(for: slotState.primary)
                    .frame(width: slotWidth(for: slotState.primary))
                    .contentShape(RoundedRectangle(cornerRadius: Geometry.cornerRadius))
                    .onTapGesture { primaryTapped() }
            }
            if !slotState.secondary.isEmpty {
                view(for: slotState.secondary)
                    .frame(width: slotWidth(for: slotState.secondary))
                    .contentShape(RoundedRectangle(cornerRadius: Geometry.cornerRadius))
                    .onTapGesture { secondaryTapped() }
            }
        }
        .frame(width: totalWidth, height: Geometry.height)
        .background(pillBackground)
        .animation(.presentSpring, value: slotState.primary.profileID?.raw)
        .animation(.presentSpring, value: slotState.secondary.profileID?.raw)
    }

    // MARK: - Rendering dispatch

    @ViewBuilder
    private func view(for occupancy: SlotOccupancy) -> some View {
        switch occupancy {
        case .empty:
            EmptyView()
        case let .occupied(profileID, state, _, variant):
            if let anyView = appState.view(forProfileID: profileID, state: state, variant: variant) {
                anyView
            } else {
                EmptyView()
            }
        }
    }

    private func slotWidth(for occupancy: SlotOccupancy) -> CGFloat {
        guard case let .occupied(_, _, _, variant) = occupancy else { return 0 }
        switch variant {
        case .fullPill: return Geometry.expandedWidth
        case .halfPill: return Geometry.halfPillInnerWidth
        }
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: Geometry.cornerRadius, style: .continuous)
            // Opaque near-black base so the pill is visible on any desktop
            // background; `.regularMaterial` layered on top provides the
            // translucent Dynamic-Island-style look.
            .fill(Color.black.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: Geometry.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Geometry.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 2)
    }

    // MARK: - Interaction

    private func primaryTapped() {
        let id = appState.slotState.primary.profileID
        appState.performInteraction(for: id)
    }

    private func secondaryTapped() {
        let id = appState.slotState.secondary.profileID
        appState.performInteraction(for: id)
    }
}
