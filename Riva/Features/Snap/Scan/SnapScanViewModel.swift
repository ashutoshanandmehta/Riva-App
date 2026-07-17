import Foundation
import Observation
import UIKit

/// Drives the snap scan flow: photo capture, the scan call, and the
/// accept-and-log step. Identity is handled invisibly (a per-device
/// account), so the flow never asks the user to sign in.
@MainActor
@Observable
final class SnapScanViewModel {

    enum Stage: Equatable {
        case capture
        case scanning
        case result(ScanResult)
        case saving(ScanResult)
        case saved(DayTotals, loggedWater: Bool)
    }

    private(set) var stage: Stage = .capture

    var mode: ScanMode
    var photo: UIImage? {
        didSet { errorMessage = nil }
    }

    /// Transient problem shown near the primary action.
    private(set) var errorMessage: String?

    private let scanRepository: any ScanRepository

    init(mode: ScanMode, scanRepository: any ScanRepository) {
        self.mode = mode
        self.scanRepository = scanRepository
    }

    func scan() async {
        guard let photo else { return }
        guard let jpeg = photo.rivaScanJPEG() else {
            errorMessage = "That photo could not be read. Try another one."
            return
        }
        stage = .scanning
        errorMessage = nil
        do {
            stage = .result(try await scanRepository.scan(imageData: jpeg, mode: mode))
        } catch ScanServiceError.signInRequired {
            stage = .capture
            errorMessage = "Could not connect to your account. Check your connection and try again."
        } catch {
            stage = .capture
            errorMessage = error.localizedDescription
        }
    }

    func accept() async {
        guard case .result(let scan) = stage else { return }
        stage = .saving(scan)
        do {
            let totals = try await scanRepository.accept(scan)
            stage = .saved(totals, loggedWater: scan.scanType == .water)
        } catch ScanServiceError.signInRequired {
            stage = .result(scan)
            errorMessage = "Could not connect to your account. Check your connection and try again."
        } catch {
            stage = .result(scan)
            errorMessage = error.localizedDescription
        }
    }

    func scanAgain() {
        photo = nil
        errorMessage = nil
        stage = .capture
    }

    #if DEBUG
    /// The self-test may fire only once per process, or reopening the flow
    /// during a test session would rescan the stock photo every time.
    private static var didRunAutoTest = false
    #endif

    /// Screenshot / self-test hook: `-riva.scanTestImage <path>` scans a
    /// photo from disk on entry; add `-riva.scanAutoAccept` to also log it.
    func runDebugAutoTestIfRequested() async {
        #if DEBUG
        guard !Self.didRunAutoTest,
              let path = UserDefaults.standard.string(forKey: "riva.scanTestImage"),
              let image = UIImage(contentsOfFile: path) else { return }
        Self.didRunAutoTest = true
        photo = image
        await scan()
        if UserDefaults.standard.bool(forKey: "riva.scanAutoAccept"),
           case .result = stage {
            await accept()
        }
        #endif
    }
}

// MARK: - Upload sizing

extension UIImage {
    /// Downscales and re-encodes for upload. The service reduces images to
    /// 1024 px anyway, so shipping more pixels only slows the scan.
    func rivaScanJPEG(maxDimension: CGFloat = 1280, quality: CGFloat = 0.85) -> Data? {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension else { return jpegData(compressionQuality: quality) }
        let scale = maxDimension / longEdge
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
