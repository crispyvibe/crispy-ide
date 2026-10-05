import Foundation

extension ScreenCaptureCoordinator {
    func run(generation: UInt64) async {
        do {
            transition(to: .checkingPermission(session: generation))
            var authorization = authorizer.authorizationStatus()
            if authorization == .undetermined {
                authorization = authorizer.requestAuthorization()
            }
            guard authorization == .granted else {
                restoreAndClearOrigin()
                transition(to: .permissionRequired(session: generation, state: authorization))
                return
            }

            transition(to: .preparingCatalog(session: generation))
            let provider = provider
            let catalog = try await stageRacer.catalog(timeout: .seconds(15)) {
                try await provider.catalog()
            }
            try checkCurrent(generation)

            let saved = preferences.screenCapturePreferences
            transition(to: .selecting(
                session: generation,
                mode: saved.mode,
                topologyGeneration: catalog.generation
            ))
            guard let selection = try await selectionController.selectTarget(
                from: catalog,
                initialMode: saved.mode,
                options: saved.options,
                sessionGeneration: generation
            ) else {
                throw ScreenCaptureError.cancelled
            }
            guard selection.catalogGeneration == catalog.generation,
                  selection.topology == catalog.topology else {
                throw ScreenCaptureError.topologyChanged
            }
            preferences.updateRememberedMode(selection.target.mode)

            try checkCurrent(generation)
            selectionController.dismissSelection()
            hiddenSurfaceToken = await exclusionProvider.prepareForCapture()
            try checkCurrent(generation)
            transition(to: .capturing(session: generation))
            let excludedWindowIDs = exclusionProvider.excludedCaptureWindowIDs
            let image = try await stageRacer.capture(timeout: .seconds(30)) {
                try await provider.capture(
                    selection: selection,
                    excludingWindowIDs: excludedWindowIDs
                )
            }
            try checkCurrent(generation)

            let capture = AcquiredScreenCapture(image: image)
            hiddenSurfaceToken = nil
            studioRouter.present(capture)
            origin = nil
            transition(to: .presentingStudio(captureID: capture.id))
        } catch is CancellationError {
            handleFailure(.cancelled, generation: generation)
        } catch let error as ScreenCaptureError {
            handleFailure(error, generation: generation)
        } catch {
            handleFailure(.captureFailed, generation: generation)
        }
    }
}
