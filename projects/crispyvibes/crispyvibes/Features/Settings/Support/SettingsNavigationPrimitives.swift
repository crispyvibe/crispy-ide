import SwiftUI

struct SettingsCategoryItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
}

struct SettingsSplitView<DetailContent: View>: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @State private var sidebarSearchQuery = ""
    let title: String
    let subtitle: String
    let doneAccessibilityIdentifier: String
    var dismissButtonTitle: String = "Back"
    let categories: [SettingsCategoryItem]
    @Binding var selectedCategoryID: String
    let onClose: () -> Void
    @ViewBuilder let detailContent: () -> DetailContent

    private var filteredCategories: [SettingsCategoryItem] {
        let query = sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return categories }
        return categories.filter {
            $0.title.lowercased().contains(query) ||
            $0.subtitle.lowercased().contains(query)
        }
    }

    private var isDarkPalette: Bool {
        appThemePalette.prefersDarkWindowChrome
    }

    private var shellBackgroundColor: Color {
        appThemePalette.canvasBackgroundColor
    }

    private var sidebarBackgroundColor: Color {
        appThemePalette.canvasSecondaryBackgroundColor.opacity(isDarkPalette ? 0.44 : 0.90)
    }

    private var headerBackgroundColor: Color {
        appThemePalette.canvasBackgroundColor
    }

    private var dividerColor: Color {
        appThemePalette.borderColorValue.opacity(isDarkPalette ? 0.30 : 0.20)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(dividerColor)
                    .frame(width: 1)
                detailContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(shellBackgroundColor)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(shellBackgroundColor)
        .foregroundStyle(appThemePalette.primaryTextColor)
        .preferredColorScheme(appThemePalette.preferredColorScheme)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypographyTokens.settingsHeaderTitle)
                Text(subtitle)
                    .font(AppTypographyTokens.settingsHeaderSubtitle)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }

            Spacer(minLength: 12)

            Button {
                onClose()
            }
            label: {
                Label(dismissButtonTitle, systemImage: "chevron.left")
            }
            .buttonStyle(.crispyvibesText)
            .accessibilityIdentifier(doneAccessibilityIdentifier)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(headerBackgroundColor)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search settings", text: $sidebarSearchQuery)
                .textFieldStyle(.plain)
                .font(AppTypographyTokens.settingsSearchField)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(7), style: .continuous)
                        .fill(appThemePalette.canvasBackgroundColor.opacity(isDarkPalette ? 0.5 : 0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(7), style: .continuous)
                        .stroke(appThemePalette.borderColorValue.opacity(isDarkPalette ? 0.3 : 0.18), lineWidth: 1)
                )
                .accessibilityIdentifier("settings.search")

            Text(AppStrings.Sidebar.navigationTab)
                .font(AppTypographyTokens.settingsSidebarLabel)
                .textCase(.uppercase)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .padding(.horizontal, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredCategories) { category in
                        categoryButton(for: category)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: uiScale.chromeSize(248))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackgroundColor)
    }

    private func categoryButton(for category: SettingsCategoryItem) -> some View {
        let isSelected = category.id == selectedCategoryID
        let rowBackground = isSelected
            ? appThemePalette.selectionBackgroundColor.opacity(isDarkPalette ? 0.24 : 0.34)
            : Color.clear

        return Button {
            selectedCategoryID = category.id
        } label: {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous)
                        .fill(
                            isSelected
                                ? appThemePalette.accentColor.opacity(isDarkPalette ? 0.24 : 0.16)
                                : appThemePalette.canvasBackgroundColor.opacity(isDarkPalette ? 0.38 : 0.84)
                        )
                    Image(systemName: category.iconSystemName)
                        .font(AppTypographyTokens.settingsSidebarIcon)
                        .foregroundStyle(
                            isSelected
                                ? appThemePalette.accentColor
                                : appThemePalette.secondaryTextColor
                        )
                }
                .frame(width: uiScale.iconSize(22), height: uiScale.iconSize(22))

                Text(category.title)
                    .font(AppTypographyTokens.settingsSidebarTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(
                        isSelected
                            ? appThemePalette.selectionTextColor
                            : appThemePalette.primaryTextColor
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                    .stroke(
                        isSelected
                            ? appThemePalette.borderColorValue.opacity(0.42)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous))
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.category.\(category.id)")
    }
}
