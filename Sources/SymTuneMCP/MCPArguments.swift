import Foundation
import SymTuneCore

/// Extract a required `Double` from a JSON-RPC arguments dictionary.
func requireDouble(_ value: Any?, name: String) throws -> Double {
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String, let double = Double(string) { return double }
    throw TuneError.usage("Missing required numeric argument '\(name)'.")
}

/// Extract a required `Int` from a JSON-RPC arguments dictionary.
func requireInt(_ value: Any?, name: String) throws -> Int {
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String, let int = Int(string) { return int }
    throw TuneError.usage("Missing required integer argument '\(name)'.")
}
