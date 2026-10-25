import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 程序坞图标跟随主题色。
    let channel = FlutterMethodChannel(name: "yunyin/app_icon", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setIcon",
            let args = call.arguments as? [String: Any],
            let asset = args["asset"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      // Flutter 资源位于 App.framework/Resources/flutter_assets 中。
      let key = FlutterDartProject.lookupKey(forAsset: asset)
      let appFramework = Bundle.main.privateFrameworksPath.flatMap { Bundle(path: $0 + "/App.framework") }
      let path = appFramework?.path(forResource: key, ofType: nil) ?? Bundle.main.path(forResource: key, ofType: nil)
      if let path = path, let image = NSImage(contentsOfFile: path) {
        NSApplication.shared.applicationIconImage = image
      }
      result(nil)
    }

    super.awakeFromNib()
  }
}
