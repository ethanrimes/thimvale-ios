import Foundation
import Darwin

/// All path components are opened relative to an already-open directory descriptor.
/// O_NOFOLLOW on every component prevents symlink traversal and ancestor-swap races.
enum SecureWorkspace {
    static func components(_ path: String, allowEmpty: Bool = false) throws -> [String] {
        guard !path.hasPrefix("/"), !path.contains("\0"), !path.contains("\\") else {
            throw PocketError.message("Use a relative path inside the connected folder.")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.contains(".."), !parts.contains("."), allowEmpty || !parts.isEmpty else {
            throw PocketError.message("That path is outside the allowed folder or is empty.")
        }
        return parts
    }

    static func withParent<T>(root: URL, path: String, body: (Int32, String) throws -> T) throws -> T {
        let parts = try components(path)
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PocketError.message("The connected folder is unavailable. Reconnect it in Permissions.") }
        defer { close(descriptor) }
        for part in parts.dropLast() {
            let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw PocketError.message("Cannot access the folder, or the path contains a symbolic link.") }
            close(descriptor)
            descriptor = next
        }
        return try body(descriptor, parts.last!)
    }

    static func read(root: URL, path: String, offset: Int = 0, limit: Int = 16_000) throws -> String {
        guard offset >= 0, limit > 0, limit <= 64_000 else { throw PocketError.message("Invalid read range.") }
        return try withParent(root: root, path: path) { parent, name in
            let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { throw PocketError.message("The file cannot be opened.") }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw PocketError.message("Only regular text files can be read.") }
            guard info.st_size <= 20_000_000 else { throw PocketError.message("This file is too large for direct reading. Import it into Knowledge.") }
            guard lseek(fd, off_t(offset), SEEK_SET) >= 0 else { throw PocketError.message("Cannot seek in the file.") }
            var bytes = [UInt8](repeating: 0, count: limit)
            let count = Darwin.read(fd, &bytes, limit)
            guard count >= 0 else { throw PocketError.message("The file could not be read.") }
            guard !bytes.prefix(count).contains(0) else { throw PocketError.message("This is not a text file. Import PDFs using Knowledge.") }
            return String(decoding: bytes.prefix(count), as: UTF8.self)
        }
    }

    static func create(root: URL, path: String, content: String) throws {
        let data = Data(content.utf8)
        guard data.count <= 512_000 else { throw PocketError.message("File creation is limited to 512 KB per action.") }
        try withParent(root: root, path: path) { parent, name in
            let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw PocketError.message("The file already exists or the folder is not writable. Choose a new name.") }
            defer { close(fd) }
            do {
                try data.withUnsafeBytes { buffer in
                    var written = 0
                    while written < data.count {
                        let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: written), data.count - written)
                        if count < 0 && errno == EINTR { continue }
                        guard count > 0 else { throw PocketError.message("Could not finish writing the file.") }
                        written += count
                    }
                }
                guard fsync(fd) == 0 else { throw PocketError.message("Could not save the file to storage.") }
            } catch {
                unlinkat(parent, name, 0) // Only remove the incomplete file this operation created.
                throw error
            }
        }
    }

    static func list(root: URL, path: String = "") throws -> [String] {
        let parts = try components(path, allowEmpty: true)
        var fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw PocketError.message("The connected folder is unavailable.") }
        for part in parts {
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            close(fd)
            guard next >= 0 else { throw PocketError.message("The subfolder cannot be opened.") }
            fd = next
        }
        guard let directory = fdopendir(fd) else { close(fd); throw PocketError.message("Cannot list this folder.") }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory), names.count < 500 {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN)) { String(cString: $0) }
            }
            if !name.hasPrefix(".") { names.append(name + (entry.pointee.d_type == DT_DIR ? "/" : "")) }
        }
        return names.sorted()
    }
}
