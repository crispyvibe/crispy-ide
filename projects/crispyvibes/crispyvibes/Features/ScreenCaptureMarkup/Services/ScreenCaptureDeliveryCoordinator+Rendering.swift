import Foundation

extension ScreenCaptureDeliveryCoordinator {
    func startRenderedDelivery(
        item: ScreenshotStudioItem,
        session: RasterImageEditSession,
        revision: Int,
        generation: UInt64
    ) {
        guard generation == itemGenerations[item.id], activeItemID == item.id else { return }
        let token = clipboardToken
        eventHandler?(.working(item.id, true))
        let job = session.makeExportJob(destinationURL: nil)
        renderHandle = exporter.export(job) { [weak self, weak session] result in
            guard let self, let session,
                  token == self.clipboardToken,
                  generation == self.itemGenerations[item.id],
                  revision == session.revision else { return }
            self.renderHandle = nil
            switch result {
            case .failure(let error):
                self.report(error, itemID: item.id, stage: .render)
                self.eventHandler?(.working(item.id, false))
            case .success(let rendered):
                let capture = CapturedScreenImage(
                    cgImage: rendered.image,
                    canvasSize: session.canvasSize,
                    exportScale: item.capture.exportScale,
                    nativePixelSize: CGSize(width: rendered.image.width, height: rendered.image.height),
                    colorSpaceName: rendered.image.colorSpace?.name.map { $0 as String },
                    placement: item.capture.placement
                )
                self.encodeRendered(
                    capture,
                    itemID: item.id,
                    revision: revision,
                    generation: generation,
                    token: token
                )
            }
        }
    }

    func encodeRendered(
        _ capture: CapturedScreenImage,
        itemID: UUID,
        revision: Int,
        generation: UInt64,
        token: UInt64
    ) {
        outputTask = Task { [weak self] in
            guard let self else { return }
            do {
                let representations = try await self.encoder.encode(capture)
                guard !Task.isCancelled else { return }
                self.finishEncoded(
                    representations,
                    renderedCapture: capture,
                    itemID: itemID,
                    revision: revision,
                    generation: generation,
                    token: token,
                    persistence: self.historyItemIDs.contains(itemID) ? .update : .add
                )
            } catch {
                guard token == self.clipboardToken,
                      generation == self.itemGenerations[itemID],
                      self.activeItemID == itemID else { return }
                self.report(error, itemID: itemID, stage: .encode)
                self.eventHandler?(.working(itemID, false))
            }
        }
    }

    func finishEncoded(
        _ representations: EncodedScreenCapture,
        renderedCapture: CapturedScreenImage,
        itemID: UUID,
        revision: Int,
        generation: UInt64,
        token: UInt64,
        persistence: PersistenceKind
    ) {
        outputTask = nil
        guard token == clipboardToken,
              generation == itemGenerations[itemID],
              activeItemID == itemID else { return }
        var clipboardCommitted = false
        do {
            try clipboard.writeCompleteRepresentations(representations)
            clipboardCommitted = true
            eventHandler?(.clipboardUpdated(itemID, revision))
        } catch {
            report(error, itemID: itemID, stage: .clipboard)
        }
        enqueuePersistence(
            kind: persistence,
            itemID: itemID,
            revision: revision,
            clipboardCommitted: clipboardCommitted,
            generation: generation,
            token: token,
            png: representations.png,
            capture: renderedCapture
        )
        eventHandler?(.working(itemID, false))
    }
}
