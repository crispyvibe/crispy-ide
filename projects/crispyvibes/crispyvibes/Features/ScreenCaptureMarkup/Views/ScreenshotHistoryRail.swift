import SwiftUI

/// Bottom rail showing the current screenshot and bounded recent flattened history.
@MainActor
struct ScreenshotHistoryRail: View {
    @ObservedObject var viewModel: ScreenshotStudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppStrings.ScreenCapture.studioHistory)
                    .font(.caption.weight(.semibold))
                if viewModel.isLoadingHistory {
                    Text(AppStrings.ScreenCapture.studioLoading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    if let current = viewModel.currentItem {
                        currentCard(current)
                    }
                    ForEach(viewModel.historyEntries.filter { $0.id != viewModel.currentItem?.id }) { entry in
                        historyCard(entry)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
        }
        .frame(height: 116)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityIdentifier("screenCapture.studio.historyRail")
    }

    private func currentCard(_ item: ScreenshotStudioItem) -> some View {
        Button { } label: {
            thumbnail(image: item.image, isSelected: true)
                .overlay(alignment: .bottomLeading) {
                    Text(AppStrings.ScreenCapture.studioCurrent)
                        .font(.caption2.weight(.semibold))
                        .padding(4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier("screenCapture.studio.history.current")
    }

    private func historyCard(_ entry: ScreenCaptureHistoryEntry) -> some View {
        HStack(spacing: 3) {
            Button {
                viewModel.selectHistoryItem(id: entry.id)
            } label: {
                Group {
                    if let image = viewModel.thumbnails[entry.id]?.cgImage {
                        thumbnail(image: image, isSelected: viewModel.selectedItemID == entry.id)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(width: 112, height: 78)
                            .overlay {
                                if viewModel.requestedSelectionID == entry.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .accessibilityLabel(AppStrings.ScreenCapture.studioUnavailableThumbnail)
                                }
                            }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(viewModel.selectedItemID == entry.id ? .isSelected : [])
            .accessibilityIdentifier("screenCapture.studio.history.item.\(entry.id.uuidString)")
            Button(role: .destructive) {
                viewModel.deleteItem(id: entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(AppStrings.ScreenCapture.studioDeleteItem)
            .accessibilityLabel(AppStrings.ScreenCapture.studioDeleteItem)
            .accessibilityIdentifier("screenCapture.studio.history.delete.\(entry.id.uuidString)")
        }
    }

    private func thumbnail(image: CGImage, isSelected: Bool) -> some View {
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 112, height: 78)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }
    }
}
