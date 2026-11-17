import Foundation

/// A diagnostic view of the Java VM that actually started on this device.
/// Module coverage is a conservative launcher baseline, not a promise that every
/// Minecraft version or third-party mod is compatible.
public struct HinekaJavaRuntimeReport {
    public static let minecraftBaselineModules: Set<String> = [
        "java.base",
        "java.desktop",
        "java.logging",
        "java.management",
        "java.naming",
        "java.xml",
        "jdk.unsupported"
    ]

    public let javaVersion: String
    public let javaMajorVersion: Int
    public let vmName: String
    public let vmInfo: String
    public let osName: String
    public let architecture: String
    public let availableProcessors: Int
    public let modules: Set<String>

    public var missingBaselineModules: [String] {
        Self.minecraftBaselineModules.subtracting(modules).sorted()
    }

    public var hasBaselineModuleCoverage: Bool {
        missingBaselineModules.isEmpty
    }

    public var is64BitARM: Bool {
        let normalized = architecture.lowercased()
        return normalized == "aarch64" || normalized == "arm64"
    }

    public var isZeroVM: Bool {
        vmName.localizedCaseInsensitiveContains("zero")
    }

    public static func parse(_ output: String) throws -> HinekaJavaRuntimeReport {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "HINEKA_RUNTIME_REPORT=1" else {
            throw HinekaJavaRuntimeReportError.invalidFormat
        }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            guard !key.isEmpty else { continue }
            fields[key] = value
        }

        guard
            let javaVersion = fields["java.version"], !javaVersion.isEmpty,
            let javaMajorRaw = fields["java.major"],
            let javaMajor = Int(javaMajorRaw), javaMajor > 0,
            let vmName = fields["vm.name"], !vmName.isEmpty,
            let osName = fields["os.name"], !osName.isEmpty,
            let architecture = fields["os.arch"], !architecture.isEmpty,
            let processorsRaw = fields["processors"],
            let processors = Int(processorsRaw), processors > 0,
            let moduleList = fields["modules"]
        else {
            throw HinekaJavaRuntimeReportError.missingFields
        }

        let modules = Set(moduleList.split(separator: ",").map(String.init))
        guard modules.contains("java.base") else {
            throw HinekaJavaRuntimeReportError.missingJavaBase
        }

        return HinekaJavaRuntimeReport(
            javaVersion: javaVersion,
            javaMajorVersion: javaMajor,
            vmName: vmName,
            vmInfo: fields["vm.info"] ?? "không có thông tin",
            osName: osName,
            architecture: architecture,
            availableProcessors: processors,
            modules: modules
        )
    }

    public var summary: String {
        var lines = [
            "Java runtime đã khởi động: PASS",
            "Java: \(javaVersion) (major \(javaMajorVersion))",
            "VM: \(vmName)",
            "VM mode: \(vmInfo)",
            "Thiết bị: \(osName) / \(architecture)",
            "CPU khả dụng: \(availableProcessors)",
            "Module hiện có: \(modules.count)",
            "ARM64: \(is64BitARM ? "có" : "không")",
            "Module baseline Minecraft: \(hasBaselineModuleCoverage ? "đủ" : "thiếu")"
        ]

        if !missingBaselineModules.isEmpty {
            lines.append("Thiếu module: " + missingBaselineModules.joined(separator: ", "))
        }
        if isZeroVM {
            lines.append("Hiệu năng: Zero interpreter; chưa có JIT được xác nhận.")
        }
        lines.append("Lưu ý: module baseline không thay thế kiểm thử Minecraft/native renderer trên thiết bị.")
        return lines.joined(separator: "\n")
    }
}

public enum HinekaJavaRuntimeReportError: LocalizedError {
    case invalidFormat
    case missingFields
    case missingJavaBase

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Định dạng báo cáo Java runtime không đúng phiên bản."
        case .missingFields:
            return "Báo cáo Java runtime thiếu trường bắt buộc."
        case .missingJavaBase:
            return "Runtime không báo cáo module java.base."
        }
    }
}
