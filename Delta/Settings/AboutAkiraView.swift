//
//  AboutAkiraView.swift
//  Delta
//
//  Akira Arcade: who made this fork, where its source is, and what it includes.
//  The AGPL asks that people who get the app can get its source, so the link lives here.
//

import SwiftUI

extension AboutAkiraView
{
    static let sourceURL = URL(string: "https://github.com/yamustofa/akira-arcade")!
    static let issuesURL = URL(string: "https://github.com/yamustofa/akira-arcade/issues")!
    static let privacyURL = URL(string: "https://github.com/yamustofa/akira-arcade/blob/main/PRIVACY.md")!
    static let deltaURL = URL(string: "https://github.com/rileytestut/Delta")!
    static let licenseURL = URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!

    static func makeViewController() -> UIHostingController<some View>
    {
        let aboutView = AboutAkiraView()

        let hostingController = UIHostingController(rootView: aboutView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        hostingController.navigationItem.title = NSLocalizedString("About Akira Arcade", comment: "")

        return hostingController
    }
}

struct AboutAkiraView: View
{
    private var version: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return String(format: NSLocalizedString("Version %@ (%@)", comment: ""), shortVersion, build)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("AppIcon", bundle: Bundle(for: PurchaseManager.self))
                        .resizable()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text("Akira Arcade")
                        .font(.title2.weight(.bold))

                    Text(self.version)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(NSLocalizedString("Phones on your Wi-Fi become game controllers for this iPad. Made for Akira, a retro-computer dock for the iPad.", comment: ""))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Link(destination: AboutAkiraView.deltaURL) {
                    Label(NSLocalizedString("Delta by Riley Testut", comment: ""), systemImage: "heart")
                }
            } header: {
                Text(NSLocalizedString("Built On", comment: ""))
            } footer: {
                Text(NSLocalizedString("Akira Arcade is a community fork of Delta. The emulator, its cores and almost every feature come from Delta and its contributors (see Contributors). The phone controller is Akira's addition. Please send Akira Arcade problems to Akira, not to Delta.", comment: ""))
            }

            Section {
                Link(destination: AboutAkiraView.sourceURL) {
                    Label(NSLocalizedString("Source Code", comment: ""), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AboutAkiraView.issuesURL) {
                    Label(NSLocalizedString("Report a Problem", comment: ""), systemImage: "exclamationmark.bubble")
                }
                Link(destination: AboutAkiraView.privacyURL) {
                    Label(NSLocalizedString("Privacy", comment: ""), systemImage: "hand.raised")
                }
                Link(destination: AboutAkiraView.licenseURL) {
                    Label(NSLocalizedString("License: GNU AGPLv3", comment: ""), systemImage: "doc.text")
                }
            } header: {
                Text(NSLocalizedString("Open Source", comment: ""))
            } footer: {
                Text(NSLocalizedString("Free software: you can read, change and share the source under the AGPLv3. If you share a build, share its source too.", comment: ""))
            }

            Section {
                Text(NSLocalizedString("Akira Arcade ships no games or BIOS files. Play games you own, or free homebrew.", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text(NSLocalizedString("Games", comment: ""))
            }
        }
        .listStyle(.insetGrouped)
    }
}

#Preview {
    NavigationView {
        AboutAkiraView()
    }
}
