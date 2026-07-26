import SwiftUI

@MainActor
struct AutomationSurfaceView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview
        case loops
        case lanes
        case vibes
        case skills

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: AppStrings.Automation.overview
            case .loops: AppStrings.Loops.title
            case .lanes: AppStrings.VibeLanes.lanes
            case .vibes: AppStrings.VibeLanes.vibes
            case .skills: AppStrings.Skills.title
            }
        }

        var symbolName: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .loops: "clock.arrow.circlepath"
            case .lanes: "point.3.connected.trianglepath.dotted"
            case .vibes: "sparkles.rectangle.stack"
            case .skills: "books.vertical"
            }
        }
    }

    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var loopManager: VibeLoopManager
    @ObservedObject var laneNavigation: VibeLaneSurfaceNavigationViewModel
    @ObservedObject var skillStore: VibeLaneSkillStore
    let projectOptions: [VibeLoopProjectOption]
    let acpProjects: [AnyProjectSession]
    let resolveACPSession: (VibeLaneACPChatTarget) -> ACPStandaloneSessionStore?
    let onOpenFileTarget: ((TerminalFileSystemTarget) -> Void)?

    @State private var selectedSection = Section.overview

    var body: some View {
        VStack(spacing: 0) {
            sectionBar
            ZStack {
                AutomationOverviewView(
                    isActive: selectedSection == .overview,
                    onOpenSkills: { select(.skills) },
                    onOpenVibes: { select(.vibes) },
                    onOpenLanes: { select(.lanes) },
                    onOpenLoops: { select(.loops) }
                )
                .automationLayer(isActive: selectedSection == .overview)

                VibeLoopsSurfaceView(
                    manager: loopManager,
                    projectOptions: projectOptions,
                    acpProjects: acpProjects,
                    resolveACPSession: resolveACPSession,
                    onOpenLane: openLane,
                    onOpenVibes: { select(.vibes) }
                )
                .automationLayer(isActive: selectedSection == .loops)

                VibeLaneSurfaceView(
                    rootScreen: selectedSection == .vibes ? .vibes : .lanes,
                    onOpenACPSession: { _ in },
                    onOpenFileTarget: onOpenFileTarget
                )
                .automationLayer(isActive: selectedSection == .lanes || selectedSection == .vibes)

                SkillLibraryView(
                    store: skillStore,
                    manager: loopManager.laneManager
                )
                .automationLayer(isActive: selectedSection == .skills)
            }
        }
        .background(palette.canvasBackgroundColor)
    }

    private var sectionBar: some View {
        HStack(spacing: uiScale.spacing(18)) {
            Label(AppStrings.Automation.title, systemImage: "gearshape.2")
                .font(.system(size: uiScale.textSize(15), weight: .semibold))

            Picker(
                AppStrings.Automation.title,
                selection: Binding(
                    get: { selectedSection },
                    set: { section in select(section) }
                )
            ) {
                ForEach(Section.allCases) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: uiScale.chromeSize(650))

            Spacer()
        }
        .padding(.horizontal, uiScale.spacing(18))
        .padding(.vertical, uiScale.spacing(10))
        .background(palette.canvasBackgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderColorValue.opacity(0.5))
                .frame(height: uiScale.chromeSize(1))
        }
    }

    private func select(_ section: Section) {
        selectedSection = section
        switch section {
        case .overview:
            break
        case .loops:
            break
        case .lanes:
            laneNavigation.showLanes()
        case .vibes:
            laneNavigation.showVibes()
        case .skills:
            skillStore.reload()
        }
    }

    private func openLane(_ id: UUID?) {
        selectedSection = .lanes
        if let id {
            laneNavigation.showLaneEditor(id: id)
        } else {
            laneNavigation.showLanes()
        }
    }
}

private extension View {
    func automationLayer(isActive: Bool) -> some View {
        self
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}
