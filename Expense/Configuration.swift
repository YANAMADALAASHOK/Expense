import Foundation

#if DEBUG
@objc(Configuration)
public class Configuration: NSObject {
    @objc public static let isDebug = true
}
#endif 