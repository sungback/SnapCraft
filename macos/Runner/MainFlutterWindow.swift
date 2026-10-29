import Cocoa
import FlutterMacOS

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

    super.awakeFromNib()
  }
}
