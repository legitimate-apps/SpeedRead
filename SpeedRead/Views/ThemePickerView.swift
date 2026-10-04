//  ThemePickerView.swift
import SwiftUI

struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appSurface.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(ShelfTheme.allThemes) { theme in
                            themeCard(theme, manager: themeManager)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    func themeCard(_ theme: ShelfTheme, manager: ThemeManager) -> some View {
        let isSelected = manager.selectedThemeId == theme.id

        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                manager.selectedThemeId = theme.id
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.spineColors[i % theme.spineColors.count])
                            .frame(width: 24, height: CGFloat(40 + (i % 3) * 10))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Rectangle()
                    .fill(theme.shelfColor)
                    .frame(height: 6)

                Text(theme.name)
                    .font(.system(size: 15, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.chromeText)
                    .padding(.bottom, 12)
            }
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.agedGold : Color.appInk.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.chromeOnAccent, theme.chromeAccent)
                        .padding(8)
                }
            }
        }
    }
}
