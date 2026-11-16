import Foundation
import HinekaJavaRuntimeBridge

public enum HinekaJavaRuntimeError: LocalizedError {
    case missingResources
    case missingModules
    case missingSmokeTestJar
    case javaStartupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingResources:
            return "Không tìm thấy tài nguyên runtime đi kèm Hineka."
        case .missingModules:
            return "Thiếu OpenJDK java.base modules image."
        case .missingSmokeTestJar:
            return "Thiếu Java smoke-test JAR."
        case .javaStartupFailed(let message):
            return message
        }
    }
}

/// Experimental wrapper around the upstream OpenJDK Mobile Zero VM.
/// It only runs a short HelloWorld-style diagnostic; it is not a Minecraft launcher runtime.
public enum HinekaJavaRuntime {
    public static func runSmokeTest() throws -> String {
        guard let resourceURL = Bundle.module.resourceURL else {
            throw HinekaJavaRuntimeError.missingResources
        }

        let modulesURL = resourceURL.appendingPathComponent("lib/modules", isDirectory: false)
        let jarURL = resourceURL.appendingPathComponent("HinekaRuntimeSmokeTest.jar", isDirectory: false)

        guard FileManager.default.fileExists(atPath: modulesURL.path) else {
            throw HinekaJavaRuntimeError.missingModules
        }
        guard FileManager.default.fileExists(atPath: jarURL.path) else {
            throw HinekaJavaRuntimeError.missingSmokeTestJar
        }

        var nativeError: NSError?
        guard let output = HinekaJavaRunSmokeTest(
            resourceURL.path,
            jarURL.path,
            &nativeError
        ) else {
            throw HinekaJavaRuntimeError.javaStartupFailed(
                nativeError?.localizedDescription ?? "Không khởi tạo được OpenJDK Zero."
            )
        }

        return output
    }
}
