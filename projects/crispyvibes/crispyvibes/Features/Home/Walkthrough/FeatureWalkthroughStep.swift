import CoreGraphics
import Foundation

struct FeatureWalkthroughStep: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let heroImageName: String
    let annotations: [FeatureWalkthroughAnnotation]
    let shortcutHint: String?
}

struct FeatureWalkthroughAnnotation: Identifiable, Equatable {
    enum Placement: String, Equatable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing

        var offset: CGSize {
            switch self {
            case .topLeading:
                return CGSize(width: 140, height: 66)
            case .topTrailing:
                return CGSize(width: -140, height: 66)
            case .bottomLeading:
                return CGSize(width: 140, height: -66)
            case .bottomTrailing:
                return CGSize(width: -140, height: -66)
            }
        }
    }

    let id: String
    let title: String
    let detail: String
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let placement: Placement
}

protocol FeatureWalkthroughStepProviding {
    var steps: [FeatureWalkthroughStep] { get }
}

struct DefaultFeatureWalkthroughStepProvider: FeatureWalkthroughStepProviding {
    let steps: [FeatureWalkthroughStep] = [
        FeatureWalkthroughStep(
            id: "welcome",
            title: "Welcome to Crispy",
            message: "A vibespace-first IDE where files, terminals, and controls stay in one flow.",
            heroImageName: "WalkthroughWelcome",
            annotations: [
                FeatureWalkthroughAnnotation(
                    id: "welcome-toolbar",
                    title: "Action Toolbar",
                    detail: "Global controls and vibespace actions are always within reach.",
                    normalizedX: 0.16,
                    normalizedY: 0.19,
                    placement: .topLeading
                ),
                FeatureWalkthroughAnnotation(
                    id: "welcome-explorer",
                    title: "Explorer Rail",
                    detail: "Browse files and switch context fast without leaving the canvas.",
                    normalizedX: 0.24,
                    normalizedY: 0.45,
                    placement: .topLeading
                )
            ],
            shortcutHint: "Cmd+Shift+N to create a vibespace"
        ),
        FeatureWalkthroughStep(
            id: "vibespace-dashboard",
            title: "VibeSpace Dashboard",
            message: "Use the dashboard to manage vibespace health and project inventory.",
            heroImageName: "WalkthroughDashboard",
            annotations: [
                FeatureWalkthroughAnnotation(
                    id: "dashboard-summary",
                    title: "VibeSpace Summary",
                    detail: "Quickly review project counts and missing paths.",
                    normalizedX: 0.30,
                    normalizedY: 0.28,
                    placement: .bottomLeading
                ),
                FeatureWalkthroughAnnotation(
                    id: "dashboard-actions",
                    title: "One-Click Actions",
                    detail: "Add projects, open settings, and remove stale vibespaces.",
                    normalizedX: 0.54,
                    normalizedY: 0.44,
                    placement: .topTrailing
                )
            ],
            shortcutHint: "Toolbar: VibeSpace Dashboard"
        ),
        FeatureWalkthroughStep(
            id: "views-and-layout",
            title: "Views and Layout",
            message: "Switch layouts depending on task depth and terminal board intensity.",
            heroImageName: "WalkthroughViewsLayout",
            annotations: [
                FeatureWalkthroughAnnotation(
                    id: "layout-terminal-only",
                    title: "Terminal Board",
                    detail: "Arrange independent terminals in a drag-and-resize 4x4 board.",
                    normalizedX: 0.56,
                    normalizedY: 0.55,
                    placement: .topTrailing
                ),
                FeatureWalkthroughAnnotation(
                    id: "layout-rail",
                    title: "Project Rail",
                    detail: "Keep fast context switching available while running multiple terminals.",
                    normalizedX: 0.16,
                    normalizedY: 0.60,
                    placement: .topLeading
                )
            ],
            shortcutHint: "Cmd+D (Detailed), Cmd+T (Terminal Board)"
        ),
        FeatureWalkthroughStep(
            id: "project-shortcuts",
            title: "Project Navigation",
            message: "Jump to active projects instantly and keep momentum.",
            heroImageName: "WalkthroughProjectNavigation",
            annotations: [
                FeatureWalkthroughAnnotation(
                    id: "project-list",
                    title: "Shortcut-Ready Project List",
                    detail: "Map frequently used projects to number shortcuts in vibespace settings.",
                    normalizedX: 0.20,
                    normalizedY: 0.58,
                    placement: .topLeading
                ),
                FeatureWalkthroughAnnotation(
                    id: "project-focus",
                    title: "Focused Work Area",
                    detail: "The central canvas updates immediately as you switch projects.",
                    normalizedX: 0.66,
                    normalizedY: 0.44,
                    placement: .bottomTrailing
                )
            ],
            shortcutHint: "Cmd+1 ... Cmd+9 to focus mapped projects"
        ),
        FeatureWalkthroughStep(
            id: "terminal-workflow",
            title: "Terminal View Enhancements",
            message: "Create independent terminals, assign project roots, and arrange them freely.",
            heroImageName: "WalkthroughTerminalWorkflow",
            annotations: [
                FeatureWalkthroughAnnotation(
                    id: "terminal-tabs",
                    title: "Grid Tiles",
                    detail: "Drag terminals between slots and resize spans to match your workflow.",
                    normalizedX: 0.37,
                    normalizedY: 0.68,
                    placement: .bottomLeading
                ),
                FeatureWalkthroughAnnotation(
                    id: "preset-modes",
                    title: "Project + Directory Picker",
                    detail: "Create each terminal from a project root, home directory, or subfolder.",
                    normalizedX: 0.74,
                    normalizedY: 0.68,
                    placement: .bottomTrailing
                )
            ],
            shortcutHint: "Use New Terminal in Terminal Board view"
        ),
        FeatureWalkthroughStep(
            id: "complete",
            title: "You Are Ready",
            message: "Fine-tune appearance and defaults, then reopen this guide anytime.",
            heroImageName: "WalkthroughReady",
            annotations: [
                FeatureWalkthroughAnnotation(
                    id: "ready-settings",
                    title: "App Settings",
                    detail: "Customize appearance, typography, and global behavior.",
                    normalizedX: 0.31,
                    normalizedY: 0.49,
                    placement: .bottomLeading
                ),
                FeatureWalkthroughAnnotation(
                    id: "ready-theme",
                    title: "Theme Builder",
                    detail: "Adjust tokens quickly for a personalized UI palette.",
                    normalizedX: 0.74,
                    normalizedY: 0.49,
                    placement: .bottomTrailing
                )
            ],
            shortcutHint: "Toolbar: Walkthrough"
        )
    ]
}
