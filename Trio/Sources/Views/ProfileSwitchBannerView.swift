import SwiftUI

/// A banner view that displays when a therapy profile has been switched.
/// Auto-dismisses after a set duration or can be manually dismissed.
struct ProfileSwitchBannerView: View {
    let event: ProfileSwitchEvent
    let onDismiss: () -> Void

    /// Auto-dismiss duration in seconds
    var autoDismissDuration: Double = 8.0

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if isVisible {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            showBanner()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Profile Switched")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(event.toProfileName)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(event.reasonDescription)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func showBanner() {
        withAnimation {
            isVisible = true
        }

        // Schedule auto-dismiss
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoDismissDuration * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation {
            isVisible = false
        }
        // Delay the actual callback to allow animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}

/// A view modifier to add profile switch banner overlay
struct ProfileSwitchBannerModifier: ViewModifier {
    @Binding var switchEvent: ProfileSwitchEvent?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.overlay(
            Group {
                if let event = switchEvent {
                    ProfileSwitchBannerView(event: event) {
                        onDismiss()
                    }
                }
            }
        )
    }
}

extension View {
    /// Adds a profile switch banner overlay to the view.
    /// - Parameters:
    ///   - event: Binding to the optional switch event. When non-nil, the banner is shown.
    ///   - onDismiss: Callback when the banner is dismissed.
    func profileSwitchBanner(
        event: Binding<ProfileSwitchEvent?>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(ProfileSwitchBannerModifier(switchEvent: event, onDismiss: onDismiss))
    }
}

// MARK: - Compact Banner for Settings

/// A smaller, inline banner for use within settings views
struct ProfileSwitchInfoBanner: View {
    let profileName: String
    let isOverride: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOverride ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isOverride ? .orange : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Active Profile")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(profileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            if isOverride {
                Text("Override")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Preview

#if DEBUG
    struct ProfileSwitchBannerView_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                ProfileSwitchBannerView(
                    event: ProfileSwitchEvent(
                        fromProfileId: UUID(),
                        fromProfileName: "Weekday",
                        toProfileId: UUID(),
                        toProfileName: "Weekend",
                        reason: .scheduled
                    ),
                    onDismiss: {}
                )

                Spacer()

                ProfileSwitchInfoBanner(
                    profileName: "Weekend Profile",
                    isOverride: true
                )
                .padding()
            }
        }
    }
#endif
