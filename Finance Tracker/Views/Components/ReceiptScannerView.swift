import SwiftUI
import AVFoundation
import UIKit

struct ReceiptScannerView: View {
    @StateObject private var scanningService = ReceiptScanningService()
    @Binding var isPresented: Bool
    @State private var showingImagePicker = false
    @State private var showingCameraPermissionAlert = false
    @State private var capturedImage: UIImage?
    @State private var scannedData: ReceiptScanningService.ReceiptData?
    
    let onReceiptScanned: (ReceiptScanningService.ReceiptData) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let scannedData = scannedData {
                    // Show scanned results
                    ReceiptResultsView(
                        receiptData: scannedData,
                        onAccept: {
                            onReceiptScanned(scannedData)
                            isPresented = false
                        },
                        onRescan: {
                            self.scannedData = nil
                            self.capturedImage = nil
                        }
                    )
                } else if scanningService.isScanning {
                    // Show scanning progress
                    ScanningProgressView(progress: scanningService.scanProgress)
                } else {
                    // Show camera interface
                    CameraInterfaceView(
                        onImageCaptured: { image in
                            capturedImage = image
                            processReceiptImage(image)
                        },
                        onGalleryTapped: {
                            showingImagePicker = true
                        }
                    )
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $capturedImage) { image in
                    if let image = image {
                        processReceiptImage(image)
                    }
                }
            }
            .alert("Camera Permission Required", isPresented: $showingCameraPermissionAlert) {
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button("Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
            } message: {
                Text("Please allow camera access in Settings to scan receipts.")
            }
            .alert("Scanning Error", isPresented: .constant(scanningService.errorMessage != nil)) {
                Button("Try Again") {
                    scanningService.errorMessage = nil
                    scannedData = nil
                    capturedImage = nil
                }
                Button("Cancel") {
                    isPresented = false
                }
            } message: {
                if let errorMessage = scanningService.errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private func processReceiptImage(_ image: UIImage) {
        Task {
            do {
                let receiptData = try await scanningService.scanReceipt(image: image)
                await MainActor.run {
                    self.scannedData = receiptData
                }
            } catch {
                await MainActor.run {
                    scanningService.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct CameraInterfaceView: View {
    let onImageCaptured: (UIImage) -> Void
    let onGalleryTapped: () -> Void
    
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    
    var body: some View {
        ZStack {
            if cameraPermissionStatus == .authorized {
                CameraPreviewView(onImageCaptured: onImageCaptured)
            } else {
                CameraPermissionView(
                    permissionStatus: cameraPermissionStatus,
                    onRequestPermission: requestCameraPermission
                )
            }
            
            VStack {
                Spacer()
                
                // Camera controls
                HStack {
                    Button(action: onGalleryTapped) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Instructions
                    VStack(spacing: 4) {
                        Text("Position receipt in frame")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text("Tap anywhere to capture")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    // Info button
                    Button(action: {}) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraPermissionStatus = granted ? .authorized : .denied
            }
        }
    }
}

struct CameraPermissionView: View {
    let permissionStatus: AVAuthorizationStatus
    let onRequestPermission: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Camera Access Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("We need camera access to scan your receipts and extract transaction details automatically.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if permissionStatus == .notDetermined {
                Button("Allow Camera Access") {
                    onRequestPermission()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            } else if permissionStatus == .denied {
                Button("Open Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let onImageCaptured: (UIImage) -> Void
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.onImageCaptured = onImageCaptured
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

class CameraPreviewUIView: UIView {
    var onImageCaptured: ((UIImage) -> Void)?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil {
            setupCamera()
            setupTapGesture()
        } else {
            stopCamera()
        }
    }
    
    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            captureSession = AVCaptureSession()
            captureSession?.sessionPreset = .photo
            
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            photoOutput = AVCapturePhotoOutput()
            if let photoOutput = photoOutput,
               captureSession?.canAddOutput(photoOutput) == true {
                captureSession?.addOutput(photoOutput)
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.frame = bounds
            
            if let previewLayer = previewLayer {
                layer.addSublayer(previewLayer)
            }
            
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.captureSession?.startRunning()
            }
            
        } catch {
            print("Camera setup error: \(error)")
        }
    }
    
    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(capturePhoto))
        addGestureRecognizer(tapGesture)
    }
    
    @objc private func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
}

extension CameraPreviewUIView: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onImageCaptured?(image)
        }
    }
}

struct ScanningProgressView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("Scanning Receipt...")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Extracting transaction details")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 200)
            
            Text("\(Int(progress * 100))%")
                .font(.headline)
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct ReceiptResultsView: View {
    let receiptData: ReceiptScanningService.ReceiptData
    let onAccept: () -> Void
    let onRescan: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan Results")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Receipt scanned successfully")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Extracted data
                VStack(alignment: .leading, spacing: 16) {
                    if let merchant = receiptData.merchantName {
                        DataRow(
                            title: "Merchant",
                            value: merchant,
                            icon: "building.2"
                        )
                    }
                    
                    if let amount = receiptData.amount {
                        DataRow(
                            title: "Amount",
                            value: amount.currencyFormatted,
                            icon: "dollarsign.circle"
                        )
                    }
                    
                    if let date = receiptData.date {
                        DataRow(
                            title: "Date",
                            value: date.formatted(date: .abbreviated, time: .omitted),
                            icon: "calendar"
                        )
                    }
                    
                    DataRow(
                        title: "Confidence",
                        value: "\(Int(receiptData.confidence * 100))%",
                        icon: "checkmark.shield"
                    )
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // Raw text (collapsible)
                DisclosureGroup("Raw Text") {
                    Text(receiptData.rawText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onAccept) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Use This Data")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                    
                    Button(action: onRescan) {
                        HStack {
                            Image(systemName: "camera.rotate")
                            Text("Scan Again")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct DataRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onImageSelected: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let selectedImage = info[.originalImage] as? UIImage
            parent.image = selectedImage
            parent.onImageSelected(selectedImage)
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    ReceiptScannerView(isPresented: .constant(true)) { _ in
        // Preview callback
    }
}