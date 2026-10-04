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
                transition(to: .permissionRequired(session: generation, state: authorization))
                restoreAndClearOrigin()
                return
            }

            transition(to: .preparingCatalog(session: generation))
            let catalog = try await provider.catalog()
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
            await exclusionProvider.prepareForCapture()
            try checkCurrent(generation)
            transition(to: .capturing(session: generation))
            let image = try await provider.capture(
                selection: selection,
                excludingWindowIDs: exclusionProvider.excludedCaptureWindowIDs
            )
            try checkCurrent(generation)

            let capture = AcquiredScreenCapture(image: image)
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
