import Foundation

extension MonitoredTerminalView {
    struct OutputClassification {
        let hasRenderableText: Bool
        let hasSignificantText: Bool
        let renderableSample: String?
    }

    func enqueueClassificationResult(_ classification: OutputClassification) {
        if classification.hasRenderableText {
            if pendingRenderableSample == nil,
               let renderableSample = classification.renderableSample {
                pendingRenderableSample = renderableSample
            }

            if hasDispatchedInitialRenderableCallback {
                pendingRenderableCallback = true
            } else {
                hasDispatchedInitialRenderableCallback = true
                let initialRenderableSample = classification.renderableSample
                pendingRenderableSample = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onRenderableOutputReceived?(initialRenderableSample)
                }
            }
        }

        if classification.hasSignificantText {
            pendingSignificantCallback = true
        }

        scheduleCallbackFlushIfNeeded()
    }

    func scheduleCallbackFlushIfNeeded() {
        guard !callbackFlushScheduled else { return }
        guard pendingRenderableCallback || pendingSignificantCallback else { return }
        callbackFlushScheduled = true

        outputClassificationQueue.asyncAfter(deadline: .now() + callbackCoalescingInterval) { [weak self] in
            guard let self else { return }
            let shouldEmitRenderable = self.pendingRenderableCallback
            let renderableSample = self.pendingRenderableSample
            let shouldEmitSignificant = self.pendingSignificantCallback
            self.pendingRenderableCallback = false
            self.pendingRenderableSample = nil
            self.pendingSignificantCallback = false
            self.callbackFlushScheduled = false

            guard shouldEmitRenderable || shouldEmitSignificant else {
                self.scheduleCallbackFlushIfNeeded()
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if shouldEmitRenderable {
                    self.onRenderableOutputReceived?(renderableSample)
                }
                if shouldEmitSignificant {
                    self.onSignificantOutputReceived?()
                }
            }

            self.scheduleCallbackFlushIfNeeded()
        }
    }

    static func classifyOutput(
        for bytes: [UInt8],
        significantChangeThreshold: Int
    ) -> OutputClassification {
        guard !isPureOSCControlPayload(bytes) else {
            return OutputClassification(
                hasRenderableText: false,
                hasSignificantText: false,
                renderableSample: nil
            )
        }

        let hasRenderableText = containsRenderableText(bytes)
        let renderableSample = hasRenderableText ? extractRenderableTextSample(bytes) : nil
        let hasSignificantText = hasRenderableText && bytes.count >= significantChangeThreshold
        return OutputClassification(
            hasRenderableText: hasRenderableText,
            hasSignificantText: hasSignificantText,
            renderableSample: renderableSample
        )
    }

    static func containsRenderableText(_ bytes: [UInt8]) -> Bool {
        bytes.contains { byte in
            (byte >= 0x20 && byte != 0x7F) || byte >= 0x80
        }
    }

    static func isPureOSCControlPayload(_ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty else { return false }

        var index = 0
        while index < bytes.count {
            guard bytes[index] == 0x1B, index + 1 < bytes.count, bytes[index + 1] == 0x5D else {
                return false
            }
            index += 2

            var terminated = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x07 {
                    index += 1
                    terminated = true
                    break
                }
                if byte == 0x1B, index + 1 < bytes.count, bytes[index + 1] == 0x5C {
                    index += 2
                    terminated = true
                    break
                }
                index += 1
            }

            if !terminated {
                return false
            }
        }

        return true
    }

    static func extractRenderableTextSample(_ bytes: [UInt8], maxLength: Int = 120) -> String? {
        let decoded = String(decoding: bytes, as: UTF8.self)
        guard !decoded.isEmpty else { return nil }

        var sanitizedScalars: [UnicodeScalar] = []
        sanitizedScalars.reserveCapacity(decoded.unicodeScalars.count)
        for scalar in decoded.unicodeScalars {
            let value = scalar.value
            if value == 0x09 || value == 0x0A || value == 0x0D {
                sanitizedScalars.append(UnicodeScalar(0x20)!)
                continue
            }
            if value >= 0x20, value != 0x7F {
                sanitizedScalars.append(scalar)
            }
        }

        guard !sanitizedScalars.isEmpty else { return nil }
        let collapsed = String(String.UnicodeScalarView(sanitizedScalars))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }
}
