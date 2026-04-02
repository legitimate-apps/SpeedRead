//  ThemePickerView.swift
import SwiftUI

struct ThemePickerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(ShelfTheme.allThemes) { theme in
                            themeCard(theme)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.agedGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func themeCard(_ theme: ShelfTheme) -> some View {
        let isSelected = themeManager.selectedThemeId == theme.id

        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                themeManager.selectedThemeId = theme.id
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
                    .foregroundStyle(theme.spineTextColor)
                    .padding(.bottom, 12)
            }
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.agedGold : .clear, lineWidth: 2)
            )
        }
    }
}
