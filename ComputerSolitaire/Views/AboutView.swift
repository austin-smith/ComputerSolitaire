#if os(macOS)
import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    }

    private var copyrightYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                VStack(spacing: 4) {
                    Text("Computer Solitaire")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }

            VStack(spacing: 16) {
                Text("Fully native solitaire game for your computer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
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
                        .padding(.top, 12)
                }
            }

            VStack(spacing: 8) {
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
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 0))
    }
}

#Preview("About Us") {
    AboutView()
        .frame(width: 320, height: 380)
}

#endif
