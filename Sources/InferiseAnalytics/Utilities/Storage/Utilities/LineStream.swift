//
//  LineStream.swift
//
//
//  Created by Brandon Sneed on 11/30/23.
//

import Foundation

enum LineStreamConstants {
    static let delimiter = Data("\n".utf8)
}

class LineStreamReader {
    let fileHandle: FileHandle
    let bufferSize: Int
    var eof = false

    var buffer: Data

    init?(url: URL, bufferSize: Int = 4096) {
        guard let validURL = try? FileHandle.createIfNecessary(url: url) else { return nil }
        guard let fileHandle = try? FileHandle(forReadingFrom: validURL) else { return nil }
        self.fileHandle = fileHandle
        self.bufferSize = bufferSize
        self.buffer = Data(capacity: bufferSize)
    }

    deinit {
        fileHandle.closeFile()
    }

    func reset() {
        self.fileHandle.seek(toFileOffset: 0)
        self.buffer.removeAll(keepingCapacity: true)
        self.eof = false
    }

    func readLine() -> String? {
        if self.eof {
            return nil
        }

        repeat {
            if let range = buffer.range(of: LineStreamConstants.delimiter, options: [], in: buffer.startIndex..<buffer.endIndex) {
                let subData = self.buffer.subdata(in: self.buffer.startIndex..<range.lowerBound)
                let line = String(data: subData, encoding: .utf8)
                self.buffer.replaceSubrange(self.buffer.startIndex..<range.upperBound, with: [])
                return line
            } else {
                let tempData = self.fileHandle.readData(ofLength: self.bufferSize)
                if tempData.isEmpty {
                    self.eof = true
                    return (!self.buffer.isEmpty) ? String(data: self.buffer, encoding: .utf8) : nil
                }
                self.buffer.append(tempData)
            }
        } while true
    }
}

class LineStreamWriter {
    let fileHandle: FileHandle
    let url: URL
    var bytesWritten: UInt64 = 0

    init?(url: URL) {
        self.url = url
        guard let validURL = try? FileHandle.createIfNecessary(url: url) else { return nil }
        guard let fileHandle = try? FileHandle(forUpdating: validURL) else { return nil }
        self.fileHandle = fileHandle

        self.reset()
    }

    deinit {
        if #available(tvOS 13.0, *) {
            _ = try? fileHandle.synchronize() // this might be overkill, but JIC.
            _ = try? fileHandle.close()
        } else {
            // Fallback on earlier versions
            fileHandle.synchronizeFile()
            fileHandle.closeFile()
        }
    }

    func reset() {
        if #available(iOS 13.4, macOS 10.15.4, tvOS 13.4, *) {
            _ = try? self.fileHandle.seekToEnd()
        } else if #available(tvOS 13.0, *) {
            try? self.fileHandle.seek(toOffset: .max)
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            guard let size = attrs[FileAttributeKey.size] as? Int else {
                #if DEBUG
                    assertionFailure("Unable to get the size of \(self.url)")
                #endif
                return
            }
            self.bytesWritten = UInt64(size)
        }
    }

    func writeLine(_ str: String) throws {
        var data = str.data(using: .utf8)
        data?.append(LineStreamConstants.delimiter)
        guard let data else { return }
        if #available(macOS 10.15.4, iOS 13.4, macCatalyst 13.4, tvOS 13.4, watchOS 13.4, *) {
            do {
                try self.fileHandle.write(contentsOf: data)
                self.bytesWritten += UInt64(data.count)
            } catch {
                throw error
            }
        } else {
            // Fallback on earlier versions
            self.fileHandle.write(data)
            self.bytesWritten += UInt64(data.count)
        }
    }
}
