import AppKit

// Atualização: olha a última versão publicada no GitHub, pergunta se você
// quer atualizar e troca o app sozinho.

final class Updater {
    static let shared = Updater()

    /// Onde as versões são publicadas.
    static let repo = "fellipesalazar/ponto"

    struct Release {
        let version: String
        let notes: String
        let zipURL: URL
        let pageURL: URL?
    }

    /// Versão nova encontrada, se houver.
    private(set) var available: Release?
    private(set) var installing = false
    private var checking = false
    private var timer: Timer?

    /// Chamado quando muda algo que o menu mostra.
    var onChange: (() -> Void)?
    /// Diz se dá pra abrir uma janela agora (sem trava na tela, sem chamada).
    var canInterrupt: () -> Bool = { true }

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    private init() {}

    /// Procura logo depois de abrir e de novo a cada 6 horas.
    func start() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.autoCheck()
        }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.autoCheck()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func autoCheck() {
        guard Prefs.autoUpdate else { return }
        check(userInitiated: false)
    }

    // MARK: - Procurar

    func check(userInitiated: Bool) {
        guard !checking, !installing else { return }
        guard let url = URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest") else { return }
        checking = true

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var release: Release? = nil
            if let data = data {
                release = Updater.parse(data)
            }
            DispatchQueue.main.async {
                self?.finishCheck(release, userInitiated: userInitiated)
            }
        }
        task.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            return nil
        }

        var zip: URL? = nil
        for asset in assets {
            if (asset["name"] as? String) == "Ponto.zip", let link = asset["browser_download_url"] as? String {
                zip = URL(string: link)
            }
        }
        guard let zipURL = zip else { return nil }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let notes = (json["body"] as? String) ?? ""
        var page: URL? = nil
        if let link = json["html_url"] as? String {
            page = URL(string: link)
        }
        return Release(version: version, notes: notes, zipURL: zipURL, pageURL: page)
    }

    private func finishCheck(_ release: Release?, userInitiated: Bool) {
        checking = false

        guard let release = release else {
            if userInitiated {
                inform("Não consegui procurar atualização", "Confira a internet e tente de novo.")
            }
            return
        }

        let current = Updater.currentVersion
        if Versao.compare(release.version, current) > 0 {
            available = release
            onChange?()
            if userInitiated || shouldAutoPrompt(release) {
                prompt(release)
            }
        } else {
            available = nil
            onChange?()
            if userInitiated {
                inform("O Ponto está atualizado", "Você tem a versão \(current), a mais recente.")
            }
        }
    }

    /// Sozinho, pergunta no máximo uma vez por dia e nunca no meio de uma trava ou chamada.
    private func shouldAutoPrompt(_ release: Release) -> Bool {
        guard canInterrupt() else { return false }
        let lastVersion = Prefs.d.string(forKey: Prefs.Key.updatePromptedVersion) ?? ""
        let lastTime = Prefs.d.double(forKey: Prefs.Key.updatePromptedAt)
        let now = Date().timeIntervalSince1970
        if lastVersion == release.version && now - lastTime < 24 * 3600 {
            return false
        }
        return true
    }

    // MARK: - Perguntar

    func promptAvailable() {
        if let release = available {
            prompt(release)
        } else {
            check(userInitiated: true)
        }
    }

    private func prompt(_ release: Release) {
        Prefs.d.set(release.version, forKey: Prefs.Key.updatePromptedVersion)
        Prefs.d.set(Date().timeIntervalSince1970, forKey: Prefs.Key.updatePromptedAt)

        var text = "Você tem a versão \(Updater.currentVersion). A \(release.version) está disponível."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            text += "\n\n" + String(notes.prefix(600))
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Tem uma versão nova do Ponto"
        alert.informativeText = text
        alert.addButton(withTitle: "Atualizar agora")
        alert.addButton(withTitle: "Depois")
        if alert.runModal() == .alertFirstButtonReturn {
            install(release)
        }
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Instalar

    private enum Outcome {
        case done
        /// O app novo está pronto, mas trocar pede a senha do Mac.
        case needsPassword(newApp: URL, work: URL)
        case failed(String)
    }

    private func install(_ release: Release) {
        guard !installing else { return }
        installing = true
        onChange?()

        let task = URLSession.shared.downloadTask(with: release.zipURL) { [weak self] location, _, _ in
            var outcome = Outcome.failed("Não consegui baixar a atualização.")
            if let location = location {
                outcome = Updater.apply(zipAt: location, expected: release.version)
            }
            DispatchQueue.main.async {
                self?.finishInstall(outcome, release)
            }
        }
        task.resume()
    }

    /// Abre o zip baixado e tenta trocar o app.
    private static func apply(zipAt location: URL, expected: String) -> Outcome {
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        let work: URL
        do {
            // Pasta temporária no mesmo disco do app, pra troca ser de uma vez só.
            work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                              appropriateFor: current, create: true)
        } catch {
            return .failed("Não consegui preparar a atualização: \(error.localizedDescription)")
        }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", location.path, work.path]
        do {
            try unzip.run()
        } catch {
            try? fm.removeItem(at: work)
            return .failed("Não consegui abrir o arquivo da atualização.")
        }
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            try? fm.removeItem(at: work)
            return .failed("Não consegui abrir o arquivo da atualização.")
        }

        let newApp = work.appendingPathComponent("Ponto.app")
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) == expected else {
            try? fm.removeItem(at: work)
            return .failed("O arquivo baixado não é o Ponto \(expected).")
        }

        do {
            _ = try fm.replaceItemAt(current, withItemAt: newApp)
            try? fm.removeItem(at: work)
            return .done
        } catch {
            // Sem permissão pra mexer na pasta: dá pra trocar com a senha do Mac.
            if fm.fileExists(atPath: newApp.path) {
                return .needsPassword(newApp: newApp, work: work)
            }
            try? fm.removeItem(at: work)
            return .failed("Não consegui trocar o app: \(error.localizedDescription)")
        }
    }

    /// Troca o app pedindo a senha do Mac, na janela padrão do sistema.
    /// Devolve nil se deu certo, ou o que deu errado.
    private static func replaceWithPassword(newApp: URL) -> String? {
        let current = Bundle.main.bundleURL.path
        let command = "/bin/rm -rf \(shellQuote(current))"
            + " && /usr/bin/ditto \(shellQuote(newApp.path)) \(shellQuote(current))"
            + " && /usr/sbin/chown -R \(getuid()) \(shellQuote(current))"
        let source = "do shell script \"\(appleScriptEscape(command))\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            return "Não consegui pedir a senha do Mac."
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            if number == -128 {
                return "Você cancelou o pedido de senha."
            }
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "erro \(number)"
            return "Não consegui trocar o app: \(message)"
        }
        return nil
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func finishInstall(_ outcome: Outcome, _ release: Release) {
        var problem: String? = nil

        switch outcome {
        case .done:
            break
        case .failed(let message):
            problem = message
        case .needsPassword(let newApp, let work):
            problem = Updater.replaceWithPassword(newApp: newApp)
            try? FileManager.default.removeItem(at: work)
        }

        installing = false
        onChange?()

        if let problem = problem {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "A atualização não foi instalada"
            alert.informativeText = problem + "\n\nNada mudou no seu Ponto. Dá pra baixar o instalador pela página da versão."
            alert.addButton(withTitle: "Abrir a página")
            alert.addButton(withTitle: "Fechar")
            if alert.runModal() == .alertFirstButtonReturn, let page = release.pageURL {
                NSWorkspace.shared.open(page)
            }
            return
        }

        available = nil
        relaunch()
    }

    /// Fecha e abre de novo, já na versão nova.
    private func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? reopen.run()
        NSApp.terminate(nil)
    }
}
