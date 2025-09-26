//
//  FileManager+Extensions.swift
//  MacScreenCapture
//
//  Created by Developer on 2025/9/25.
//

import Foundation
import UniformTypeIdentifiers
import AppKit

extension FileManager {
    
    /// 获取默认截图保存目录
    static var defaultScreenshotDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotDir = documentsPath.appendingPathComponent("Screenshots")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        
        return screenshotDir
    }
    
    /// 获取默认录制保存目录
    static var defaultRecordingDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingDir = documentsPath.appendingPathComponent("Recordings")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: recordingDir, withIntermediateDirectories: true)
        
        return recordingDir
    }
    
    /// 生成唯一的文件名
    static func generateUniqueFileName(baseName: String, extension: String, in directory: URL) -> String {
        let baseURL = directory.appendingPathComponent("\(baseName).\(`extension`)")
        
        // 如果文件不存在，直接返回原名称
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            return "\(baseName).\(`extension`)"
        }
        
        // 如果文件存在，添加数字后缀
        var counter = 1
        while true {
            let fileName = "\(baseName)_\(counter).\(`extension`)"
            let fileURL = directory.appendingPathComponent(fileName)
            
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                return fileName
            }
            
            counter += 1
        }
    }
    
    /// 获取文件大小（格式化字符串）
    static func formattedFileSize(for url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            print("获取文件大小失败: \(error)")
        }
        return "未知大小"
    }
    
    /// 在Finder中显示文件
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    /// 移动文件到废纸篓
    static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
    
    /// 复制文件到剪贴板
    static func copyToClipboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .fileURL)
    }
    
    /// 检查磁盘空间
    static func availableDiskSpace() -> Int64? {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = attributes[.systemFreeSize] as? Int64 {
                return freeSpace
            }
        } catch {
            print("获取磁盘空间失败: \(error)")
        }
        return nil
    }
    
    /// 清理旧文件（保留最近N个文件）
    static func cleanupOldFiles(in directory: URL, keepRecent count: Int, fileExtension: String) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
            
            // 过滤指定扩展名的文件
            let filteredFiles = files.filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }
            
            // 按创建时间排序（最新的在前）
            let sortedFiles = filteredFiles.sorted { file1, file2 in
                do {
                    let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1 > date2
                } catch {
                    return false
                }
            }
            
            // 删除多余的文件
            if sortedFiles.count > count {
                let filesToDelete = Array(sortedFiles.dropFirst(count))
                for file in filesToDelete {
                    try? FileManager.default.removeItem(at: file)
                    print("删除旧文件: \(file.lastPathComponent)")
                }
            }
            
        } catch {
            print("清理旧文件失败: \(error)")
        }
    }
}

// MARK: - URL Extensions

extension URL {
    
    /// 获取文件的创建时间
    var creationDate: Date? {
        do {
            let resourceValues = try self.resourceValues(forKeys: [.creationDateKey])
            return resourceValues.creationDate
        } catch {
            return nil
        }
    }
    
    /// 获取文件的修改时间
    var modificationDate: Date? {
        do {
            let resourceValues = try self.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            return nil
        }
    }
    
    /// 获取文件大小
    var fileSize: Int64? {
        do {
            let resourceValues = try self.resourceValues(forKeys: [.fileSizeKey])
            return Int64(resourceValues.fileSize ?? 0)
        } catch {
            return nil
        }
    }
    
    /// 检查文件是否存在
    var exists: Bool {
        return FileManager.default.fileExists(atPath: self.path)
    }
    
    /// 获取文件的MIME类型
    var mimeType: String? {
        do {
            let resourceValues = try self.resourceValues(forKeys: [.typeIdentifierKey])
            if let typeIdentifier = resourceValues.typeIdentifier {
                return UTType(typeIdentifier)?.preferredMIMEType
            }
        } catch {
            print("获取MIME类型失败: \(error)")
        }
        return nil
    }
}