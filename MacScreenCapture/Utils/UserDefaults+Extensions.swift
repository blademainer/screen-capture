import Foundation

// MARK: - UserDefaults Extensions for Floating Window Settings
extension UserDefaults {
    
    // MARK: - Floating Window Settings
    var floatingWindowAlwaysOnTop: Bool {
        get {
            return bool(forKey: "floatingWindowAlwaysOnTop")
        }
        set {
            set(newValue, forKey: "floatingWindowAlwaysOnTop")
        }
    }
    
    var floatingWindowAutoHide: Bool {
        get {
            return bool(forKey: "floatingWindowAutoHide")
        }
        set {
            set(newValue, forKey: "floatingWindowAutoHide")
        }
    }
    
    var floatingWindowAutoHideDelay: Double {
        get {
            let value = double(forKey: "floatingWindowAutoHideDelay")
            return value > 0 ? value : 3.0 // 默认3秒
        }
        set {
            set(newValue, forKey: "floatingWindowAutoHideDelay")
        }
    }
    
    var floatingWindowOpacity: Double {
        get {
            let value = double(forKey: "floatingWindowOpacity")
            return value > 0 ? value : 0.95 // 默认95%透明度
        }
        set {
            set(newValue, forKey: "floatingWindowOpacity")
        }
    }
    
    var floatingWindowShowPreview: Bool {
        get {
            return bool(forKey: "floatingWindowShowPreview")
        }
        set {
            set(newValue, forKey: "floatingWindowShowPreview")
        }
    }
    
    var floatingWindowPosition: String {
        get {
            return string(forKey: "floatingWindowPosition") ?? "topRight"
        }
        set {
            set(newValue, forKey: "floatingWindowPosition")
        }
    }
    
    // MARK: - Initialize Default Values
    static func registerFloatingWindowDefaults() {
        UserDefaults.standard.register(defaults: [
            "floatingWindowAlwaysOnTop": true,
            "floatingWindowAutoHide": false,
            "floatingWindowAutoHideDelay": 3.0,
            "floatingWindowOpacity": 0.95,
            "floatingWindowShowPreview": true,
            "floatingWindowPosition": "topRight"
        ])
    }
}