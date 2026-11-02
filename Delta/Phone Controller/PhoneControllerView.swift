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

struct PhoneControllerView: View
{
    @ObservedObject private var server = PhoneControllerServer.shared
    
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
                Text(NSLocalizedString("Scan with your phone's camera. Your phone and this iPad must be on the same Wi-Fi.", comment: ""))
                    .multilineTextAlignment(.center)
                
                if let image = PhoneControllerView.qrImage(for: url.absoluteString)
                {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(NSLocalizedString("QR code for the phone controller", comment: ""))
                }
                
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("PhoneControllerURL")
            }
            else
            {
                Text(NSLocalizedString("This iPad isn't on a Wi-Fi network.", comment: ""))
                    .foregroundStyle(.secondary)
            }
            
            self.playerList
            
            Button(NSLocalizedString("Turn Off", comment: ""), role: .destructive) {
                self.server.stop()
            }
        }
    }
    
    private var playerList: some View {
        VStack(spacing: 10) {
            ForEach(0 ..< PhoneControllerServer.maximumPlayers, id: \.self) { slot in
                HStack {
                    Text(String(format: NSLocalizedString("Phone %d", comment: ""), slot + 1))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 28)
                        .background(slot == 0 ? Color.blue : Color.red)
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
