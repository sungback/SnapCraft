import Cocoa
import FlutterMacOS
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
    self.collectionBehavior.insert(.fullScreenPrimary)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let clipboardChannel = FlutterMethodChannel(
      name: "snap_craft/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel.setMethodCallHandler { call, result in
      if call.method == "currentFilePath" {
        let value = NSPasteboard.general.string(forType: .fileURL)
        result(value.flatMap { URL(string: $0)?.path })
      } else if call.method == "copyImageAndFile" {
        guard
          let args = call.arguments as? [String: Any],
          let typedData = args["bytes"] as? FlutterStandardTypedData,
          let filePath = args["path"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing bytes or path", details: nil))
          return
        }

        let pngData = typedData.data
        let pb = NSPasteboard.general
        pb.clearContents()

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let image = NSImage(data: pngData), let tiffData = image.tiffRepresentation {
          item.setData(tiffData, forType: .tiff)
        }
        let fileUrl = URL(fileURLWithPath: filePath)
        item.setString(fileUrl.absoluteString, forType: .fileURL)
        item.setString(filePath, forType: .string)

        let ok = pb.writeObjects([item])
        result(ok)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let ocrChannel = FlutterMethodChannel(
      name: "snap_craft/ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    ocrChannel.setMethodCallHandler { call, result in
      if call.method == "recognizeText" {
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
          return
        }

        let url = URL(fileURLWithPath: path)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
          result(FlutterError(code: "LOAD_FAILED", message: "Failed to load image for OCR", details: nil))
          return
        }

        let request = VNRecognizeTextRequest { request, error in
          if let error = error {
            DispatchQueue.main.async {
              result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
            }
            return
          }

          guard let observations = request.results as? [VNRecognizedTextObservation] else {
            DispatchQueue.main.async {
              result("")
            }
            return
          }

          var recognizedStrings: [String] = []
          for observation in observations {
            if let topCandidate = observation.topCandidates(1).first {
              recognizedStrings.append(topCandidate.string)
            }
          }

          let fullText = recognizedStrings.joined(separator: "\n")
          DispatchQueue.main.async {
            result(fullText)
          }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            try handler.perform([request])
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "OCR_ERROR", message: error.localizedDescription, details: nil))
            }
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
