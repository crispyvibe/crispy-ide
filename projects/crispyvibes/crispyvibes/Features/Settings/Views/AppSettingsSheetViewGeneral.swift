import SwiftUI

extension AppSettingsSheetView {
    var generalCategoryContent: some View {
        Group {
            SettingsCard(
                title: "Display Mode",
                description: "Controls light/dark window behavior. For automatic matching, use the `System` theme preset."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsFieldRow(
                        title: "Window appearance",
                        detail: "Auto follows macOS. Light and Dark force a fixed appearance."
                    ) {
                        Picker("Appearance", selection: $appearancePreference) {
                            ForEach(AppearancePreference.allCases) { preference in
                                Text(preference.title).tag(preference.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("app.settings.appearance")
                    }

                    if selectedThemePresetBinding.wrappedValue != .system {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(themePreviewPalette.warningColor)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppStrings.Settings.themeOverrideWarning)
                                    .font(AppTypographyTokens.caption)
                                    .foregroundStyle(appThemePalette.secondaryTextColor)
                                Button(AppStrings.Settings.Theme.useSystem) {
                                    applyThemePreset(.system)
                                }
                                .buttonStyle(.crispyvibesText)
                            }
                        }
                    }
                }
            }

            SettingsCard(
                title: "Theme Presets",
                description: "Quick-select a packaged theme. Use `Custom` for low-level token editing."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsFieldRow(
                        title: "Current preset",
                        detail: "System adapts to light/dark. Other presets keep a fixed palette."
                    ) {
                        Picker("Theme preset", selection: selectedThemePresetBinding) {
                            ForEach(groupedThemePresets, id: \.category) { group in
                                Section(group.category.title) {
                                    ForEach(group.presets) { preset in
                                        Text(preset.title).tag(preset)
                                    }
                                }
                            }
                            Section {
                                Text(AppThemePreset.custom.title).tag(AppThemePreset.custom)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("app.settings.theme.preset")
                    }

                    ForEach(groupedThemePresets, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.category.title)
                                .font(AppTypographyTokens.caption)
                                .foregroundStyle(appThemePalette.secondaryTextColor)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 148), spacing: 8)],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(group.presets) { preset in
                                    ThemePresetQuickButton(
                                        preset: preset,
                                        palette: previewPalette(for: preset),
                                        isSelected: selectedThemePresetBinding.wrappedValue == preset,
                                        onSelect: { applyThemePreset(preset) }
                                    )
                                    .accessibilityIdentifier("app.settings.theme.quick.\(preset.rawValue)")
                                }
                            }
                        }
                    }

                    SettingsFieldRow(
                        title: "Palette preview",
                        detail: "Window -> Canvas -> Canvas Secondary -> Border -> Accent"
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                previewSwatch(themePreviewPalette.windowBackgroundColor)
                                previewSwatch(themePreviewPalette.canvasBackgroundColor)
                                previewSwatch(themePreviewPalette.canvasSecondaryBackgroundColor)
                                previewSwatch(themePreviewPalette.borderColorValue)
                                previewSwatch(themePreviewPalette.accentColor)
                            }
                            HStack(spacing: 6) {
                                paletteLegendLabel("Window")
                                paletteLegendLabel("Canvas")
                                paletteLegendLabel("Canvas 2")
                                paletteLegendLabel("Border")
                                paletteLegendLabel("Accent")
                            }
                        }
                    }
                }
            }

            SettingsCard(
                title: "Typography",
                description: "Central text controls shared by app chrome, editors, and terminals."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsFieldRow(
                        title: "Font family",
                        detail: "Used for code editors and terminal text."
                    ) {
                        Picker("Font family", selection: codeFontFamilyBinding) {
                            ForEach(AppCodeFontFamily.allCases) { family in
                                Text(family.title).tag(family)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("app.settings.typography.font-family")
                    }

                    SettingsFieldRow(
                        title: "Text size",
                        detail: "Scales app text, icons, editor text, and focused terminal panes."
                    ) {
                        HStack(spacing: 10) {
                            Slider(
                                value: codeFontSizeBinding,
                                in: AppPreferences.minimumCodeFontSize...AppPreferences.maximumCodeFontSize,
                                step: 1
                            )
                            Text("\(Int(codeFontSizeBinding.wrappedValue)) pt")
                                .font(AppTypographyTokens.captionMonospacedDigit)
                                .foregroundStyle(appThemePalette.secondaryTextColor)
                                .frame(minWidth: 62, alignment: .trailing)
                        }
                        .accessibilityIdentifier("app.settings.typography.font-size")
                    }

                    SettingsFieldRow(
                        title: "Rail terminal font scale",
                        detail: "Ratio of the main font size used for stacked and rail terminals."
                    ) {
                        Picker("Rail terminal font scale", selection: $railFontScale) {
                            ForEach(TerminalRailFontScale.allCases) { scale in
                                Text(scale.title).tag(scale.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("app.settings.rail-font-scale")
                    }

                    SettingsFieldRow(
                        title: "Code + terminal text color",
                        detail: "Direct control of the global text color token."
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                ColorPicker(
                                    "Text color",
                                    selection: globalTextColorBinding,
                                    supportsOpacity: true
                                )
                                .labelsHidden()
                                .frame(width: uiScale.chromeSize(28))
                                .accessibilityIdentifier("app.settings.typography.text-color")

                                TextField(
                                    "#RRGGBB or #RRGGBBAA",
                                    text: globalTextColorTokenBinding
                                )
                                .textFieldStyle(SquareBorderTextFieldStyle())
                                .font(AppTypographyTokens.monospacedCaption)
                                .accessibilityIdentifier("app.settings.typography.text-color-token")
                            }

                            if let error = themeTokenErrors[.terminalForeground] {
                                Text(error)
                                    .font(AppTypographyTokens.caption2)
                                    .foregroundStyle(themePreviewPalette.errorColor)
                                    .accessibilityIdentifier("app.settings.typography.text-color-error")
                            }
                        }
                    }

                    SettingsFieldRow(
                        title: "Typography preview",
                        detail: "Preview of selected family, size, and text color."
                    ) {
                        Text(AppStrings.Settings.typographyPreview)
                            .font(
                                Font(
                                    AppPreferences.codeFont(
                                        familyRawValue: codeFontFamilyRaw,
                                        size: CGFloat(codeFontSizeBinding.wrappedValue)
                                    )
                                )
                            )
                            .foregroundStyle(themePreviewPalette.terminalForegroundColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8))
                                    .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.45))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8))
                                    .stroke(appThemePalette.borderColorValue.opacity(0.65), lineWidth: 1)
                            )
                            .accessibilityIdentifier("app.settings.typography.preview")
                    }
                }
            }

            containerStyleCard

            layoutCategoryContent

            SettingsCard(
                title: "Advanced Theme Tokens",
                description: "Fine-grained role editing for custom themes."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if selectedThemePresetBinding.wrappedValue == .custom {
                        ForEach(AppThemeColorRole.allCases) { role in
                            SettingsFieldRow(title: role.title, detail: role.usageDetail) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        ColorPicker(
                                            "",
                                            selection: themeColorBinding(for: role),
                                            supportsOpacity: true
                                        )
                                        .labelsHidden()
                                        .frame(width: uiScale.chromeSize(28))
                                        .accessibilityIdentifier("app.settings.theme.color.\(role.rawValue)")

                                        TextField("#RRGGBB or #RRGGBBAA", text: themeTokenBinding(for: role))
                                            .textFieldStyle(SquareBorderTextFieldStyle())
                                            .font(AppTypographyTokens.monospacedCaption)
                                            .accessibilityIdentifier("app.settings.theme.token.\(role.rawValue)")
                                    }

                                    if let error = themeTokenErrors[role] {
                                        Text(error)
                                            .font(AppTypographyTokens.caption2)
                                            .foregroundStyle(themePreviewPalette.errorColor)
                                            .accessibilityIdentifier("app.settings.theme.error.\(role.rawValue)")
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button(AppStrings.Settings.Theme.resetCustom) {
                                customThemeDraft = .midnightMono
                                customThemePaletteJSON = AppThemePalette.encodeToJSON(customThemeDraft)
                                themeTokenErrors.removeAll()
                            }
                            .buttonStyle(.crispyvibesText)
                            .accessibilityIdentifier("app.settings.theme.reset-custom")

                            Button(AppStrings.Settings.Theme.useMidnightBase) {
                                customThemeDraft = .midnightMono
                                customThemePaletteJSON = AppThemePalette.encodeToJSON(customThemeDraft)
                                themeTokenErrors.removeAll()
                            }
                            .buttonStyle(.crispyvibesText)
                            .accessibilityIdentifier("app.settings.theme.base-midnight")
                        }
                    } else {
                        Text(AppStrings.Settings.customTokenHint)
                            .font(AppTypographyTokens.footnote)
                            .foregroundStyle(appThemePalette.secondaryTextColor)

                        Button(AppStrings.Settings.Theme.customize) {
                            ensureCustomThemeDraftForEditing()
                        }
                        .buttonStyle(.crispyvibesText)
                        .accessibilityIdentifier("app.settings.theme.customize")
                    }
                }
            }
        }
    }

    func previewSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: crispyvibesTheme.radius(3))
            .fill(color)
            .frame(width: uiScale.chromeSize(24), height: uiScale.chromeSize(14))
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(3))
                    .stroke(themePreviewPalette.borderColorValue, lineWidth: 1)
            )
    }

    func paletteLegendLabel(_ title: String) -> some View {
        Text(title)
            .font(AppTypographyTokens.caption2)
            .foregroundStyle(appThemePalette.secondaryTextColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.5))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(appThemePalette.borderColorValue.opacity(0.55), lineWidth: 1)
            )
    }

    @ViewBuilder
    var containerStyleCard: some View {
        SettingsCard(
            title: "Container Style",
            description: "Border shape and visibility for panes and panels across the app."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(
                    title: "Border shape",
                    detail: "Square uses sharp corners. Rounded applies a subtle radius."
                ) {
                    Picker("Border shape", selection: borderShapeBinding) {
                        ForEach(CrispyVibesBorderShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("app.settings.theme.border-shape")
                }

                SettingsFieldRow(
                    title: "Show borders",
                    detail: "Toggle container border strokes on all panes."
                ) {
                    Toggle("Show borders", isOn: borderVisibleBinding)
                        .labelsHidden()
                        .accessibilityIdentifier("app.settings.theme.border-visible")
                }
            }
        }
    }

    private var borderShapeBinding: Binding<CrispyVibesBorderShape> {
        Binding(
            get: { themeManager.theme.borderShape },
            set: { themeManager.theme.borderShape = $0 }
        )
    }

    private var borderVisibleBinding: Binding<Bool> {
        Binding(
            get: { themeManager.theme.borderVisible },
            set: { themeManager.theme.borderVisible = $0 }
        )
    }
}
