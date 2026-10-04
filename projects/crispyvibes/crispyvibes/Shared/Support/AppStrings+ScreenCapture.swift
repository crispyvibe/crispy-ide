import Foundation

extension AppStrings {
    /// User-facing strings for Screen Capture & Screenshot Studio (F062).
    enum ScreenCapture {
        static let cancel = String(localized: "screenCapture.action.cancel", defaultValue: "Cancel")
        static let captureFailedTitle = String(localized: "screenCapture.error.title", defaultValue: "Screen Capture Failed")
        static let commitSelection = String(localized: "screenCapture.selection.commit", defaultValue: "Capture Selection")
        static let delay = String(localized: "screenCapture.option.delay", defaultValue: "Delay")
        static let delayNone = String(localized: "screenCapture.option.delay.none", defaultValue: "None")
        static let dimensionsUnavailable = String(localized: "screenCapture.selection.dimensionsUnavailable", defaultValue: "Dimensions unavailable")
        static let display = String(localized: "screenCapture.mode.display", defaultValue: "Display")
        static let includePointer = String(localized: "screenCapture.option.includePointer", defaultValue: "Include pointer")
        static let mode = String(localized: "screenCapture.option.mode", defaultValue: "Mode")
        static let newCapture = String(localized: "screenCapture.action.newCapture", defaultValue: "New Capture")
        static let nextRegionEdge = String(localized: "screenCapture.selection.nextEdge", defaultValue: "Select Next Region Edge")
        static let openSystemSettings = String(localized: "screenCapture.permission.openSettings", defaultValue: "Open System Settings")
        static let permissionTitle = String(localized: "screenCapture.permission.title", defaultValue: "Screen Recording Permission")
        static let pointerExcluded = String(localized: "screenCapture.option.pointerExcluded", defaultValue: "Pointer excluded")
        static let pointerIncluded = String(localized: "screenCapture.option.pointerIncluded", defaultValue: "Pointer included")
        static let pointerMagnifier = String(localized: "screenCapture.selection.pointerMagnifier", defaultValue: "Pointer magnifier")
        static let recheck = String(localized: "screenCapture.permission.recheck", defaultValue: "Recheck")
        static let region = String(localized: "screenCapture.mode.region", defaultValue: "Region")
        static let regionKeyboardHint = String(localized: "screenCapture.selection.regionKeyboardHint", defaultValue: "Use Tab to choose an edge, arrow keys to adjust, and Return to capture.")
        static let regionLimitedToDisplay = String(localized: "screenCapture.selection.regionLimited", defaultValue: "Region limited to this display.")
        static let relaunchCrispy = String(localized: "screenCapture.permission.relaunch", defaultValue: "Relaunch Crispy")
        static let selectionCanvas = String(localized: "screenCapture.selection.canvas", defaultValue: "Screen capture selection")
        static let tryAgain = String(localized: "screenCapture.action.tryAgain", defaultValue: "Try Again")
        static let window = String(localized: "screenCapture.mode.window", defaultValue: "Window")

        static let captureScreenshot = String(localized: "screenCapture.command.captureScreen", defaultValue: "Capture Screenshot…")
        static let captureScreenshotHelp = String(localized: "screenCapture.toolbar.capture.help", defaultValue: "Capture a screenshot and open Screenshot Studio")
        static let settingsTitle = String(localized: "screenCapture.settings.title", defaultValue: "Screen Capture")
        static let settingsSubtitle = String(localized: "screenCapture.settings.subtitle", defaultValue: "Screenshot shortcut, options, permission, and local history")
        static let settingsCaptureTitle = String(localized: "screenCapture.settings.capture.title", defaultValue: "Capture Options")
        static let settingsCaptureDescription = String(localized: "screenCapture.settings.capture.description", defaultValue: "Choose the remembered mode, delay, and pointer behavior.")
        static let rememberedMode = String(localized: "screenCapture.settings.rememberedMode", defaultValue: "Remembered mode")
        static let globalShortcut = String(localized: "screenCapture.settings.globalShortcut", defaultValue: "Screenshot Shortcut")
        static let globalShortcutsDescription = String(localized: "screenCapture.settings.globalShortcuts.description", defaultValue: "The configurable system-wide shortcut works while Crispy is running and does not require Accessibility permission.")
        static let editShortcuts = String(localized: "screenCapture.settings.editShortcuts", defaultValue: "Edit Keyboard Shortcut")
        static let shortcutRegistered = String(localized: "screenCapture.shortcut.registered", defaultValue: "Registered")
        static let shortcutDisabled = String(localized: "screenCapture.shortcut.disabled", defaultValue: "Disabled")
        static let shortcutConflict = String(localized: "screenCapture.shortcut.conflict", defaultValue: "Unavailable — shortcut conflict")
        static let shortcutFailed = String(localized: "screenCapture.shortcut.failed", defaultValue: "Registration failed")
        static let historySettingsTitle = String(localized: "screenCapture.settings.history.title", defaultValue: "Screenshot History")
        static let historySettingsDescription = String(localized: "screenCapture.settings.history.description", defaultValue: "Flattened screenshots stay on this Mac for up to 30 days, with at most 50 items.")
        static let clearScreenshotHistory = String(localized: "screenCapture.settings.history.clear", defaultValue: "Clear Screenshot History")
        static let historyClearFailed = String(localized: "screenCapture.settings.history.clearFailed", defaultValue: "History could not be updated.")

        static let studioTitle = String(localized: "screenCapture.studio.title", defaultValue: "Screenshot Studio")
        static let studioCopy = String(localized: "screenCapture.studio.copy", defaultValue: "Copy")
        static let studioCopyAndDismiss = String(localized: "screenCapture.studio.copyAndDismiss", defaultValue: "Copy & Dismiss")
        static let studioRetryCopy = String(localized: "screenCapture.studio.retryCopy", defaultValue: "Retry Copy")
        static let studioRefresh = String(localized: "screenCapture.studio.refresh", defaultValue: "Refresh")
        static let studioDeleteCurrent = String(localized: "screenCapture.studio.deleteCurrent", defaultValue: "Delete Current")
        static let studioDeleteItem = String(localized: "screenCapture.studio.deleteItem", defaultValue: "Delete")
        static let studioClearHistory = String(localized: "screenCapture.studio.clearHistory", defaultValue: "Clear History")
        static let studioClearConfirmationTitle = String(localized: "screenCapture.studio.clearConfirmation.title", defaultValue: "Clear all screenshot history?")
        static let studioClose = String(localized: "screenCapture.studio.close", defaultValue: "Close")
        static let studioCancel = String(localized: "screenCapture.studio.cancel", defaultValue: "Cancel")
        static let studioNoCapture = String(localized: "screenCapture.studio.empty.title", defaultValue: "No Screenshot")
        static let studioNoCaptureDescription = String(localized: "screenCapture.studio.empty.description", defaultValue: "Take a screenshot to begin marking it up.")
        static let studioHistory = String(localized: "screenCapture.studio.history", defaultValue: "History")
        static let studioCurrent = String(localized: "screenCapture.studio.current", defaultValue: "Current")
        static let studioLoading = String(localized: "screenCapture.studio.loading", defaultValue: "Loading…")
        static let studioUnavailableThumbnail = String(localized: "screenCapture.studio.thumbnailUnavailable", defaultValue: "Preview unavailable")
        static let studioOutputFailed = String(localized: "screenCapture.studio.failure.output", defaultValue: "The latest image is still open, but delivery did not finish.")
        static let studioHistoryFailed = String(localized: "screenCapture.studio.failure.history", defaultValue: "The image is still open, but screenshot history could not be updated.")

        static func dimensions(_ width: Int, _ height: Int) -> String {
            String(localized: "screenCapture.selection.dimensions", defaultValue: "\(width) × \(height) px")
        }

        static func modeChanged(_ mode: CaptureMode) -> String {
            String(localized: "screenCapture.announcement.modeChanged", defaultValue: "\(modeTitle(mode)) mode")
        }

        static func delayChanged(_ seconds: Int) -> String {
            seconds == 0 ? delayNone : String(localized: "screenCapture.announcement.delayChanged", defaultValue: "Delay \(seconds) seconds")
        }

        static func regionEdge(_ edge: CaptureRegionEdge) -> String {
            let edgeName: String
            switch edge {
            case .left:
                edgeName = String(localized: "screenCapture.selection.regionEdge.left", defaultValue: "Left")
            case .top:
                edgeName = String(localized: "screenCapture.selection.regionEdge.top", defaultValue: "Top")
            case .right:
                edgeName = String(localized: "screenCapture.selection.regionEdge.right", defaultValue: "Right")
            case .bottom:
                edgeName = String(localized: "screenCapture.selection.regionEdge.bottom", defaultValue: "Bottom")
            }
            return String(localized: "screenCapture.selection.regionEdge", defaultValue: "Region edge: \(edgeName)")
        }

        static func windowTarget(_ index: Int, _ count: Int) -> String {
            String(localized: "screenCapture.selection.windowTarget", defaultValue: "Window \(index) of \(count)")
        }

        static func displayTarget(_ index: Int, _ count: Int) -> String {
            String(localized: "screenCapture.selection.displayTarget", defaultValue: "Display \(index) of \(count)")
        }

        static func countdown(_ seconds: Int) -> String {
            String(localized: "screenCapture.selection.countdown", defaultValue: "Capturing in \(seconds)")
        }

        static func selectionCanvasHint(_ mode: CaptureMode) -> String {
            switch mode {
            case .region:
                return String(localized: "screenCapture.selection.hint.region", defaultValue: "Drag a region, or use the keyboard controls.")
            case .window:
                return String(localized: "screenCapture.selection.hint.window", defaultValue: "Choose a window and click or press Return.")
            case .display:
                return String(localized: "screenCapture.selection.hint.display", defaultValue: "Choose a display and click or press Return.")
            }
        }

        static func delaySeconds(_ seconds: Int) -> String {
            String(localized: "screenCapture.option.delay.seconds", defaultValue: "\(seconds) seconds")
        }

        static func historyItemCount(_ count: Int) -> String {
            String(localized: "screenCapture.settings.history.count", defaultValue: "\(count) saved screenshots")
        }

        static func studioFailureMessage(_ failure: ScreenshotStudioFailure) -> String {
            switch failure.stage {
            case .render, .encode, .clipboard: return studioOutputFailed
            default: return studioHistoryFailed
            }
        }

        static func permissionMessage(_ state: ScreenCaptureAuthorizationState) -> String {
            switch state {
            case .undetermined:
                return String(localized: "screenCapture.permission.message.undetermined", defaultValue: "Crispy requests Screen Recording access only after you start a capture.")
            case .deniedOrRestricted:
                return String(localized: "screenCapture.permission.message.denied", defaultValue: "Screen Recording access is denied or restricted. Enable Crispy in System Settings, then recheck.")
            case .revoked:
                return String(localized: "screenCapture.permission.message.revoked", defaultValue: "Screen Recording access was revoked. Restore it in System Settings, then recheck.")
            case .grantedRelaunchRequired:
                return String(localized: "screenCapture.permission.message.relaunch", defaultValue: "Permission was granted, but Crispy must be relaunched before capturing.")
            case .granted:
                return String(localized: "screenCapture.permission.message.granted", defaultValue: "Screen Recording access is available.")
            }
        }

        static func authorizationStatus(_ state: ScreenCaptureAuthorizationState) -> String {
            switch state {
            case .undetermined: return String(localized: "screenCapture.permission.status.undetermined", defaultValue: "Not requested")
            case .deniedOrRestricted: return String(localized: "screenCapture.permission.status.denied", defaultValue: "Denied or restricted")
            case .revoked: return String(localized: "screenCapture.permission.status.revoked", defaultValue: "Revoked")
            case .grantedRelaunchRequired: return String(localized: "screenCapture.permission.status.relaunch", defaultValue: "Relaunch required")
            case .granted: return String(localized: "screenCapture.permission.status.granted", defaultValue: "Authorized")
            }
        }

        static func errorMessage(_ error: ScreenCaptureError) -> String {
            switch error {
            case .authorization(let state): return permissionMessage(state)
            case .catalogUnavailable: return String(localized: "screenCapture.error.catalog", defaultValue: "Displays and windows are currently unavailable.")
            case .targetUnavailable: return String(localized: "screenCapture.error.target", defaultValue: "The selected target is no longer available.")
            case .topologyChanged: return String(localized: "screenCapture.error.topology", defaultValue: "The display arrangement changed. Start a new capture.")
            case .protectedOrUnavailableContent: return String(localized: "screenCapture.error.protected", defaultValue: "The selected content cannot be captured.")
            case .invalidGeometry: return String(localized: "screenCapture.error.geometry", defaultValue: "The selected area is invalid.")
            case .resourceLimitExceeded: return String(localized: "screenCapture.error.resourceLimit", defaultValue: "The capture exceeds the supported size limit.")
            case .captureFailed: return String(localized: "screenCapture.error.capture", defaultValue: "The image could not be captured.")
            case .encodingFailed: return String(localized: "screenCapture.error.encoding", defaultValue: "The capture could not be encoded.")
            case .clipboardFailed: return String(localized: "screenCapture.error.copy", defaultValue: "Unable to copy the capture.")
            case .staleOperation: return String(localized: "screenCapture.error.stale", defaultValue: "The capture changed before the operation completed.")
            case .cancelled: return String(localized: "screenCapture.error.cancelled", defaultValue: "Capture cancelled.")
            }
        }

        static func reservedAppleScreenshot(_ shortcut: String) -> String {
            String(localized: "screenCapture.shortcut.reservedApple", defaultValue: "\(shortcut) is reserved for Apple screenshots.")
        }

        static func systemWideShortcutDetail(_ detail: String) -> String {
            String(localized: "screenCapture.shortcut.systemWideDetail", defaultValue: "System-wide • \(detail)")
        }

        static func defaultShortcut(_ shortcut: String) -> String {
            String(localized: "screenCapture.shortcut.default", defaultValue: "Default: \(shortcut)")
        }

        static let noDefaultShortcut = String(localized: "screenCapture.shortcut.noDefault", defaultValue: "No default shortcut")

        static func reservedTextEditingShortcut(_ shortcut: String) -> String {
            String(localized: "screenCapture.shortcut.reservedTextEditing", defaultValue: "\"\(shortcut)\" is reserved for text editing.")
        }

        static func shortcutAlreadyAssigned(_ shortcut: String, _ action: String) -> String {
            String(localized: "screenCapture.shortcut.alreadyAssigned", defaultValue: "\"\(shortcut)\" is already assigned to \(action).")
        }

        private static func modeTitle(_ mode: CaptureMode) -> String {
            switch mode {
            case .region: return region
            case .window: return window
            case .display: return display
            }
        }
    }
}
