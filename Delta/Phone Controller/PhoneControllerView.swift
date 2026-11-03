//
//  PhoneControllerView.swift
//  Delta
//
//  Akira Arcade, stage 2: the screen opened from the pause menu. It starts the phone
//  controller server and shows the QR code a phone scans, the address as text (handy
//  when the QR won't scan), and which players are connected.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import KeychainAccess

struct PhoneControllerView: View
{
    @ObservedObject private var server = PhoneControllerServer.shared
    
    /// The Wi-Fi phones should join, shown as a "join network" QR code. iPadOS doesn't let apps
    /// read Wi-Fi passwords, so the name and password are typed once here; the password stays
    /// in this iPad's Keychain (not synced).
    @AppStorage("AkiraPhoneWiFiName") private var wifiName: String = ""
    @State private var wifiPassword: String = ""
    @State private var isEditingWiFi = false
    
    private static let wifiKeychain = KeychainAccess.Keychain(service: "com.akira.arcade.PhoneController")
    private static let wifiPasswordKey = "wifiPassword"
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    self.content
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(NSLocalizedString("Phone Controller", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "")) {
                        self.dismiss()
                    }
                }
            }
        }
        .onAppear {
            self.server.start()
            self.wifiPassword = (try? PhoneControllerView.wifiKeychain.get(PhoneControllerView.wifiPasswordKey)) ?? ""
        }
        .onChange(of: self.wifiPassword) { _, newValue in
            if newValue.isEmpty
            {
                try? PhoneControllerView.wifiKeychain.remove(PhoneControllerView.wifiPasswordKey)
            }
            else
            {
                try? PhoneControllerView.wifiKeychain.set(newValue, key: PhoneControllerView.wifiPasswordKey)
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch self.server.state
        {
        case .stopped:
            Text(NSLocalizedString("Phone controllers are off.", comment: ""))
                .foregroundStyle(.secondary)
            
            Button(NSLocalizedString("Turn On", comment: "")) {
                self.server.start()
            }
            .buttonStyle(.borderedProminent)
            
        case .starting:
            ProgressView(NSLocalizedString("Starting…", comment: ""))
            
        case .failed(let message):
            VStack(spacing: 8) {
                Text(NSLocalizedString("Couldn't start phone controllers", comment: ""))
                    .font(.headline)
                
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text(NSLocalizedString("If you denied Local Network access, turn it on in Settings › Privacy & Security › Local Network.", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(NSLocalizedString("Try Again", comment: "")) {
                self.server.start()
            }
            .buttonStyle(.borderedProminent)
            
        case .running:
            if let url = self.server.controllerURL
            {
                let wifiName = self.wifiName.trimmingCharacters(in: .whitespaces)
                
                if wifiName.isEmpty
                {
                    Text(NSLocalizedString("Scan with your phone's camera. Your phone and this iPad must be on the same Wi-Fi.", comment: ""))
                        .multilineTextAlignment(.center)
                    
                    self.qrCard(title: nil, string: url.absoluteString, caption: url.absoluteString)
                }
                else
                {
                    Text(NSLocalizedString("Scan 1 to join this iPad's Wi-Fi, then 2 to open the pad. Already on it? Scan 2 only.", comment: ""))
                        .multilineTextAlignment(.center)
                    
                    HStack(alignment: .top, spacing: 28) {
                        self.qrCard(title: NSLocalizedString("1 · Join Wi-Fi", comment: ""),
                                    string: PhoneControllerView.wifiQRString(name: wifiName, password: self.wifiPassword),
                                    caption: wifiName)
                        
                        self.qrCard(title: NSLocalizedString("2 · Open the pad", comment: ""),
                                    string: url.absoluteString,
                                    caption: url.absoluteString)
                    }
                }
            }
            else
            {
                Text(NSLocalizedString("This iPad isn't on a Wi-Fi network. Join one, or your phone's Personal Hotspot, then come back.", comment: ""))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            self.wifiSettings
            
            self.playerList
            
            Text(NSLocalizedString("Full screen on iPhone: Share → Add to Home Screen, then open the pad from its icon. On Android it goes full screen on the first touch.", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            
            HStack(spacing: 24) {
                Button(NSLocalizedString("New Link", comment: "")) {
                    self.server.makeNewLink()
                }
                
                Button(NSLocalizedString("Turn Off", comment: ""), role: .destructive) {
                    self.server.stop()
                }
            }
        }
    }
    
    private func qrCard(title: String?, string: String, caption: String) -> some View
    {
        VStack(spacing: 8) {
            if let title
            {
                Text(title)
                    .font(.headline)
            }
            
            if let image = PhoneControllerView.qrImage(for: string)
            {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(title ?? NSLocalizedString("QR code for the phone controller", comment: ""))
            }
            
            Text(caption)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
    }
    
    private var wifiSettings: some View {
        DisclosureGroup(isExpanded: self.$isEditingWiFi) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(NSLocalizedString("Wi-Fi name", comment: ""), text: self.$wifiName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                SecureField(NSLocalizedString("Password (empty for an open network)", comment: ""), text: self.$wifiPassword)
                
                Text(NSLocalizedString("Phones join this Wi-Fi by scanning the QR code. iPadOS doesn't let apps read Wi-Fi passwords, so type it once; it stays in this iPad's Keychain. Using a phone's Personal Hotspot? Join it from this iPad, and enter the hotspot here for other phones.", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                if !self.wifiName.isEmpty
                {
                    Button(NSLocalizedString("Remove Wi-Fi QR Code", comment: ""), role: .destructive) {
                        self.wifiName = ""
                        self.wifiPassword = ""
                    }
                    .font(.footnote)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 8)
        } label: {
            Text(self.wifiName.isEmpty ? NSLocalizedString("Add a Wi-Fi QR code", comment: "") : String(format: NSLocalizedString("Wi-Fi QR code: %@", comment: ""), self.wifiName))
        }
        .frame(maxWidth: 420)
    }
    
    /// The standard "join network" QR payload that iPhone and Android cameras understand:
    /// WIFI:T:WPA;S:<name>;P:<password>;; with \ ; , : " escaped by a backslash.
    static func wifiQRString(name: String, password: String) -> String
    {
        func escaped(_ text: String) -> String
        {
            var result = ""
            for character in text
            {
                if "\\;,:\"".contains(character)
                {
                    result.append("\\")
                }
                result.append(character)
            }
            return result
        }
        
        if password.isEmpty
        {
            return "WIFI:T:nopass;S:\(escaped(name));;"
        }
        
        return "WIFI:T:WPA;S:\(escaped(name));P:\(escaped(password));;"
    }
    
    private var playerList: some View {
        VStack(spacing: 10) {
            ForEach(0 ..< PhoneControllerServer.maximumPlayers, id: \.self) { slot in
                HStack {
                    Text(String(format: NSLocalizedString("Phone %d", comment: ""), slot + 1))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 28)
                        .background(PhoneControllerView.playerColors[slot % PhoneControllerView.playerColors.count])
                        .clipShape(Capsule())
                    
                    if let player = self.server.players.first(where: { $0.slot == slot })
                    {
                        if let playerIndex = player.playerIndex
                        {
                            Text(String(format: NSLocalizedString("Connected · Player %d", comment: ""), playerIndex + 1))
                        }
                        else
                        {
                            Text(NSLocalizedString("Connected", comment: ""))
                        }
                    }
                    else
                    {
                        Text(NSLocalizedString("Waiting…", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .frame(maxWidth: 320)
    }
    
    /// Phone 1 to 4, in the same colours the phone page uses for its player badge.
    static let playerColors: [Color] = [.blue, .red, .green, .yellow]
    
    static func qrImage(for string: String) -> UIImage?
    {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        guard let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}
