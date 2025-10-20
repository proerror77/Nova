import SwiftUI

/// O00 - Onboarding Splash Screen
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0
    private let pages = OnboardingPage.allPages

    var body: some View {
        VStack(spacing: 0) {
            // Page Indicator
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Theme.Colors.primary : Theme.Colors.divider)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, Theme.Spacing.xl)

            // Content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // CTA
            VStack(spacing: Theme.Spacing.md) {
                if currentPage == pages.count - 1 {
                    PrimaryButton(title: "Get Started", action: onComplete)
                } else {
                    Button("Skip") {
                        onComplete()
                    }
                    .font(Theme.Typography.button)
                    .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.background)
        .onAppear {
            AnalyticsTracker.shared.track(.onboardingView)
        }
    }
}

// MARK: - Onboarding Page View
struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: page.iconName)
                .font(.system(size: 80))
                .foregroundColor(Theme.Colors.primary)

            Text(page.title)
                .font(Theme.Typography.h2)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
        }
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let iconName: String
    let title: String
    let description: String

    static let allPages: [OnboardingPage] = [
        OnboardingPage(
            iconName: "photo.on.rectangle.angled",
            title: "Share Your Moments",
            description: "Capture and share life's beautiful moments with friends and family"
        ),
        OnboardingPage(
            iconName: "person.2.fill",
            title: "Connect with Friends",
            description: "Follow people you care about and stay updated with their stories"
        ),
        OnboardingPage(
            iconName: "heart.fill",
            title: "Discover & Inspire",
            description: "Explore trending content and get inspired by the community"
        )
    ]
}

#Preview {
    OnboardingView(onComplete: {})
}
