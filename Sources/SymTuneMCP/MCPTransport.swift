import Foundation
import SymTuneCore

/// Content-Length framed JSON-RPC transport over a pair of `FileHandle`s.
/// Defaults to stdio so the MCP server can be driven by a host process.
struct MCPTransport {
    private let input: FileHandle
    private let output: FileHandle
    private let maxHeaderSize = 8192
    /// Maximum allowed MCP payload body size (8 MiB). Prevents a malformed or hostile
    /// client from causing unbounded memory allocation via a huge `Content-Length`.
    private let maxPayloadSize = 8 * 1024 * 1024

    init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.input = input
        self.output = output
    }

    /// Read the next framed JSON-RPC message. Returns `nil` at clean EOF.
    func readMessage() throws -> Data? {
        guard let headerData = try readHeader(), !headerData.isEmpty else { return nil }
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw TuneError.failed("Failed to decode MCP header.")
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let lengthLine = lines.first(where: { $0.lowercased().hasPrefix("content-length:") }) else {
            throw TuneError.failed("Missing Content-Length header.")
        }
        let value = lengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let length = Int(value) else {
            throw TuneError.failed("Invalid Content-Length header.")
        }
        guard length <= maxPayloadSize else {
            throw TuneError.failed("MCP payload size \(length) exceeds maximum allowed \(maxPayloadSize).")
        }
        return try readBytes(count: length)
    }

    /// Serialize `payload` and write it with a `Content-Length` header.
    func send(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        if let header = "Content-Length: \(data.count)\r\n\r\n".data(using: .utf8) {
            output.write(header)
        }
        output.write(data)
    }

    private func readHeader() throws -> Data? {
        var data = Data()
        while data.count < maxHeaderSize {
            guard let byte = try input.read(upToCount: 1), !byte.isEmpty else {
                return data.isEmpty ? nil : data
            }
            data.append(byte)
            if data.count >= 4, let range = data.range(of: Data([13, 10, 13, 10])) {
                return data[data.startIndex..<range.lowerBound]
            }
        }
        throw TuneError.failed("MCP header exceeded \(maxHeaderSize) bytes without terminator.")
    }

    private func readBytes(count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try input.read(upToCount: count - data.count), !chunk.isEmpty else {
                throw TuneError.failed("Unexpected end of input while reading MCP payload.")
            }
            data.append(chunk)
        }
        return data
    }
}
