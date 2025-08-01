//
//  QRCodeView.swift
//  HealthGuide
//
//  QR code generator for secure group invitations
//  Production-ready with error handling and customization
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

@available(iOS 18.0, *)
struct QRCodeView: View {
    let content: String
    var size: CGFloat = 200
    
    @State private var qrImage: UIImage?
    @State private var hasError = false
    
    private let context = CIContext()
    
    var body: some View {
        Group {
            if let qrImage = qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .accessibilityLabel("QR code for sharing")
            } else if hasError {
                errorView
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            generateQRCode()
        }
        .onChange(of: content) { _, _ in
            generateQRCode()
        }
    }
    
    private var errorView: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.Colors.errorRed)
            
            Text("QR Code Error")
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(width: size, height: size)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
    
    private func generateQRCode() {
        guard !content.isEmpty else {
            hasError = true
            return
        }
        
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M" // Medium error correction
        
        guard let outputImage = filter.outputImage else {
            hasError = true
            return
        }
        
        let scaleX = size / outputImage.extent.width
        let scaleY = size / outputImage.extent.height
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            qrImage = UIImage(cgImage: cgImage)
            hasError = false
        } else {
            hasError = true
        }
    }
}

// MARK: - Preview
#Preview("QR Code") {
    VStack(spacing: 20) {
        QRCodeView(content: "https://apps.apple.com/app/id6749387786")
        
        QRCodeView(content: "ABC123", size: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 2)
            )
        
        QRCodeView(content: "", size: 100)
    }
    .padding()
}