import Foundation
import SwiftUI

enum AppInfo {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    static let copyrightYear = String(Calendar.current.component(.year, from: Date()))
    static let githubURL = URL(string: "https://github.com/austin-smith/ComputerSolitaire")!
}

private enum AboutViewMetrics {
#if os(iOS)
    static let iconSize: CGFloat = 100
    static let iconCornerRadius: CGFloat = 22
    static let contentSpacing: CGFloat = 16
    static let titleFont = Font.system(.title2, design: .monospaced, weight: .bold)
    static let taglineFont = Font.subheadline.weight(.medium)
    static let descriptionFont = Font.subheadline
    static let versionFont = Font.subheadline.weight(.medium)
    static let copyrightFont = Font.caption
#else
    static let iconSize: CGFloat = 128
    static let iconCornerRadius: CGFloat = 22
    static let contentSpacing: CGFloat = 12
    static let titleFont = Font.system(size: 22, weight: .bold, design: .monospaced)
    static let taglineFont = Font.system(size: 13, weight: .medium)
    static let descriptionFont = Font.system(size: 11)
    static let versionFont = Font.system(size: 11, weight: .medium)
    static let copyrightFont = Font.system(size: 10)
#endif
}

struct AboutView: View {
    var body: some View {
#if os(iOS)
        ScrollView {
            aboutContent
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
#else
        aboutContent
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
#endif
    }

    private var aboutContent: some View {
        VStack(spacing: AboutViewMetrics.contentSpacing) {
            Image("AppIconPreviewDefault")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: AboutViewMetrics.iconSize,
                    height: AboutViewMetrics.iconSize
                )
                .clipShape(
                    .rect(
                        cornerRadius: AboutViewMetrics.iconCornerRadius,
                        style: .continuous
                    )
                )
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Computer Solitaire")
                    .font(AboutViewMetrics.titleFont)
                    .foregroundStyle(.primary)

                Text(tagline)
                    .font(AboutViewMetrics.taglineFont)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Text("Computer Solitaire is a low-frills, ad-free solitaire game for your computer. Includes Klondike, FreeCell, and other things you enjoy.")
                .font(AboutViewMetrics.descriptionFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
#if os(iOS)
                .padding(.horizontal, 8)
#endif

            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Text(AppInfo.version)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.primary)
                }
                .font(AboutViewMetrics.versionFont)

                Text("© \(AppInfo.copyrightYear) Austin Smith")
                    .font(AboutViewMetrics.copyrightFont)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                Divider()
                    .padding(.horizontal, 24)

                Link("GitHub", destination: AppInfo.githubURL)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
    }

    private var tagline: String {
        "Fully native solitaire game for your computer."
    }
}

#Preview("About") {
#if os(iOS)
    NavigationStack {
        AboutView()
    }
#else
    AboutView()
        .frame(width: 320, height: 380)
#endif
}
