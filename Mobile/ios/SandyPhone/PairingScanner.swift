import SwiftUI
import VisionKit
struct PairingScanner: UIViewControllerRepresentable {
    var onCode: (String)->Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode:onCode) }
    func makeUIViewController(context:Context) -> DataScannerViewController {
        let scanner=DataScannerViewController(recognizedDataTypes:[.barcode(symbologies:[.qr])],isHighlightingEnabled:true)
        scanner.delegate=context.coordinator
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable { try? scanner.startScanning() }
        return scanner
    }
    func updateUIViewController(_ controller:DataScannerViewController,context:Context) {}
    class Coordinator: NSObject,DataScannerViewControllerDelegate {
        let onCode:(String)->Void; var used=false
        init(onCode:@escaping(String)->Void) { self.onCode=onCode }
        func dataScanner(_ dataScanner:DataScannerViewController,didAdd addedItems:[RecognizedItem],allItems:[RecognizedItem]) {
            for item in addedItems { if case .barcode(let code)=item,let text=code.payloadStringValue,!used { used=true;onCode(text) } }
        }
    }
}
