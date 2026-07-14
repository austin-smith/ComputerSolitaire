import Foundation
import SwiftUI

enum AppInfo {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    static let copyrightYear = String(Calendar.current.component(.year, from: Date()))
    static let githubURL = URL(string: "https://github.com/austin-smith/ComputerSolitaire")
}

#if os(iOS)
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("AppIconPreviewDefault")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("Computer Solitaire")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text("Solitaire game for your computer")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Computer Solitaire is a low-frills, ad-free solitaire game for your computer. "
                        + "Includes Klondike, Spider, FreeCell, and other things you enjoy."
                )
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Version")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(AppInfo.version)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Text("© \(AppInfo.copyrightYear) Austin Smith")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 24)

                    if let githubURL = AppInfo.githubURL {
                        Link("GitHub", destination: githubURL)
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("About") {
    NavigationStack {
        AboutView()
    }
}
#else
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var copyrightYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                    .accessibilityHidden(true)

                VStack(spacing: 3) {
                    Text("Computer Solitaire")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text("Solitaire game for your computer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Computer Solitaire is a low-frills, ad-free solitaire game for your computer. "
                    + "Includes Klondike, Spider, FreeCell, and other things you enjoy."
            )
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text("Version")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(appVersion)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                Text("© \(copyrightYear) Austin Smith")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }

            VStack(spacing: 6) {
                Divider()
                    .padding(.horizontal, 24)

                Button {
                    guard let url = URL(string: "https://github.com/austin-smith/ComputerSolitaire") else { return }
                    openURL(url)
                } label: {
                    Text("GitHub")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        // Match the About window's column so hosts of any width (like the
        // settings pane) wrap the copy identically.
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 0))
    }
}

#Preview("About Us") {
    AboutView()
        .frame(width: 320, height: 380)
}
#endif
