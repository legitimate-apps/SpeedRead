//  OnboardingView.swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentPage = 0

    init(hasCompletedOnboarding: Binding<Bool>) {
        _hasCompletedOnboarding = hasCompletedOnboarding
        #if canImport(UIKit)
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Color.appAccent)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(Color.appInkSecondary).withAlphaComponent(0.35)
        #endif
    }

    var body: some View {
        ZStack {
            Color.appSurface.ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                rsvpExplanationPage.tag(1)
                getStartedPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
        }
    }

    var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.appAccent)

            Text("Welcome to SpeedRead")
                .font(.displayFont(size: 28, weight: .bold))
                .foregroundStyle(Color.appInk)

            Text("Your cozy reading library")
                .font(.bodySerif(size: 18))
                .foregroundStyle(Color.appInkSecondary)

            Spacer()

            nextButton(page: 1)
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 76)
    }

    var rsvpExplanationPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Static RSVP demo
            VStack(spacing: 2) {
                Rectangle()
                    .fill(Color.pivot)
                    .frame(width: 2, height: 8)

                HStack(spacing: 0) {
                    Text("rea")
                        .foregroundStyle(Color.appInkSecondary)
                    Text("d")
                        .foregroundStyle(Color.pivot)
                    Text("ing")
                        .foregroundStyle(Color.appInkSecondary)
                }
                .font(.rsvpWord(size: 36))

                Rectangle()
                    .fill(Color.pivot)
                    .frame(width: 2, height: 8)
            }

            Text("One word at a time")
                .font(.displayFont(size: 24, weight: .bold))
                .foregroundStyle(Color.appInk)

            Text("The red letter marks where your eye naturally lands, so you read faster with less effort.")
                .font(.bodySerif(size: 16))
                .foregroundStyle(Color.appInkSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            nextButton(page: 2)
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 76)
    }

    var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.appGoldText)

            Text("Your shelf is ready")
                .font(.displayFont(size: 24, weight: .bold))
                .foregroundStyle(Color.appInk)

            Text("We've placed a few classics on your shelf to get started. Import your own PDFs and EPUBs anytime.")
                .font(.bodySerif(size: 16))
                .foregroundStyle(Color.appInkSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                withAnimation {
                    hasCompletedOnboarding = true
                }
            } label: {
                Text("Open Your Library")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.appOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 76)
    }

    private func nextButton(page: Int) -> some View {
        Button {
            withAnimation {
                currentPage = page
            }
        } label: {
            Text("Next")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.appOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
