//  EmptyStateView.swift
import SwiftUI

/// Shared icon + title + helper-copy empty state, tinted by the caller's palette.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = .secondary
    var titleColor: Color = .primary
    var messageColor: Color = .secondary
    var titleFont: Font = .system(size: 16, weight: .medium)
    var messageFont: Font = .system(size: 13)

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(tint)
            Text(title)
                .font(titleFont)
                .foregroundStyle(titleColor)
            Text(message)
                .font(messageFont)
                .foregroundStyle(messageColor)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
