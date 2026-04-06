//
//  PairPhoneView.swift
//  ClaudeIsland
//
//  Shows a QR code for pairing with CodeLight iPhone app.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairPhoneView: View {
    @ObservedObject var syncManager = SyncManager.shared
    @State private var qrImage: NSImage?
    @State private var isPairing = false
    @State private var pairingStatus: String = ""

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "iphone")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text("Pair iPhone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()

                // Connection status
                if syncManager.isEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Connected")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.8))
                    }
                }
            }

            if let qrImage {
                // QR Code display
                VStack(spacing: 8) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .background(Color.white)
                        .cornerRadius(8)

                    Text("Scan with CodeLight app")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))

                    if !pairingStatus.isEmpty {
                        Text(pairingStatus)
                            .font(.system(size: 10))
                            .foregroundColor(.cyan)
                    }
                }
            } else {
                // Generate button
                Button {
                    generateQRCode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 12))
                        Text("Show QR Code")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.3))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.blue.opacity(0.4), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
            }

            // Server URL display
            if let url = syncManager.serverUrl, !url.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 9))
                    Text(url)
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
                .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func generateQRCode() {
        let serverUrl = syncManager.serverUrl ?? "https://island.wdao.chat"
        let deviceName = Host.current().localizedName ?? "Mac"

        // Create QR payload matching PairingQRPayload format
        let payload: [String: String] = [
            "s": serverUrl,
            "k": "", // temp public key (placeholder for now)
            "n": deviceName,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        // Generate QR code image
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return }

        // Scale up for crisp rendering
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return }

        qrImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        pairingStatus = "Waiting for scan..."
    }
}
