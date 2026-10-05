import Foundation

enum AppResources {
    static var root: URL {
        #if SWIFT_PACKAGE
        Bundle.module.resourceURL!
        #else
        Bundle.main.resourceURL!
        #endif
    }
}
