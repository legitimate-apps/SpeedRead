//  OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.parchment.ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                rsvpExplanationPage.tag(1)
                getStartedPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.crimsonSoft)

            Text("Welcome to SpeedRead")
                .font(.displayFont(size: 28, weight: .bold))
                .foregroundStyle(Color.inkBlack)

            Text("Your cozy reading library")
                .font(.bodySerif(size: 18))
                .foregroundStyle(Color.walnutLight)

            Spacer()

            nextButton(page: 1)
        }
        .padding(32)
    }

    var rsvpExplanationPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Static RSVP demo
            VStack(spacing: 2) {
                Rectangle()
                    .fill(Color.crimson)
                    .frame(width: 2, height: 8)

                HStack(spacing: 0) {
                    Text("rea")
                        .foregroundStyle(Color.walnutLight)
                    Text("d")
                        .foregroundStyle(Color.crimson)
                    Text("ing")
                        .foregroundStyle(Color.walnutLight)
                }
                .font(.rsvpWord(size: 36))

                Rectangle()
                    .fill(Color.crimson)
                    .frame(width: 2, height: 8)
            }

            Text("One word at a time")
                .font(.displayFont(size: 24, weight: .bold))
                .foregroundStyle(Color.inkBlack)

            Text("The red letter marks where your eye naturally lands, so you read faster with less effort.")
                .font(.bodySerif(size: 16))
                .foregroundStyle(Color.walnutLight)
                .multilineTextAlignment(.center)

            Spacer()

            nextButton(page: 2)
        }
        .padding(32)
    }

    var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.agedGold)

            Text("Your shelf is ready")
                .font(.displayFont(size: 24, weight: .bold))
                .foregroundStyle(Color.inkBlack)

            Text("We've placed a few classics on your shelf to get started. Import your own PDFs and EPUBs anytime.")
                .font(.bodySerif(size: 16))
                .foregroundStyle(Color.walnutLight)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                withAnimation {
                    hasCompletedOnboarding = true
                }
            } label: {
                Text("Open Your Library")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.crimsonSoft, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(32)
    }

    private func nextButton(page: Int) -> some View {
        Button {
            withAnimation {
                currentPage = page
            }
        } label: {
            Text("Next")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.parchment)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.crimsonSoft, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
