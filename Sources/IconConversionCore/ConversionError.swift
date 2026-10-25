import Foundation

public enum ConversionError: Error, LocalizedError, Sendable {
    case invalidImage(String)
    case invalidInput(String)
    case missingTool(String)
    case unsupportedTool(String)
    case processFailed(String, Int32, String)
    case collision(String)
    case validation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage(let detail): return "Invalid image: \(detail)"
        case .invalidInput(let detail): return "Invalid Icon Composer document: \(detail)"
        case .missingTool(let detail): return "Developer tool unavailable: \(detail). Install and select a full Xcode installation."
        case .unsupportedTool(let detail): return "Unvalidated toolchain: \(detail). Run the rendering integration checks before using this toolchain."
        case .processFailed(let tool, let status, _): return "\(tool) failed (exit \(status)). Check the diagnostic log and verify the document opens with this Xcode's Icon Composer."
        case .collision(let path): return "Output already exists: \(path). Choose another filename or explicitly allow replacement."
        case .validation(let detail): return "Output validation failed: \(detail)"
        }
    }

    public var diagnostic: String? {
        if case .processFailed(_, _, let output) = self { return output }
        return nil
    }
}
