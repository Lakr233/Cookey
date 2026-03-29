import Foundation

public enum TerminalQRCode {
    public static func deepLink(for manifest: LoginManifest) -> String {
        var components = URLComponents()
        components.scheme = "helpmein"
        components.host = "login"
        components.queryItems = [
            URLQueryItem(name: "rid", value: manifest.rid),
            URLQueryItem(name: "server", value: manifest.serverURL),
            URLQueryItem(name: "target", value: manifest.targetURL),
            URLQueryItem(name: "pubkey", value: manifest.cliPublicKey)
        ]

        return components.string ?? "helpmein://login?rid=\(manifest.rid)"
    }

    public static func render(link: String) -> String {
        if let qrencodeOutput = renderWithQRencode(link) {
            return qrencodeOutput
        }

        return fallbackBlock(for: link)
    }

    private static func renderWithQRencode(_ link: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["qrencode", "-t", "ANSIUTF8", link]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
        } catch {
            return nil
        }
    }

    private static func fallbackBlock(for link: String) -> String {
        let border = String(repeating: "#", count: 72)
        return [
            border,
            "# QR rendering fallback",
            "# Install `qrencode` for terminal QR output, or open this deep link manually:",
            "# \(link)",
            border
        ].joined(separator: "\n")
    }
}
