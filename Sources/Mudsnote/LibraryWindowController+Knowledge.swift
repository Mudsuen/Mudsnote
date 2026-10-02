import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func cancelNoteLinksRefresh() {
        noteLinksRefreshTask?.cancel()
        noteLinksRefreshTask = nil
        noteLinksRefreshGeneration += 1
    }

    func refreshNoteLinks(for noteURL: URL, body: String) {
        cancelNoteLinksRefresh()
        let key = noteURL.standardizedFileURL
        if let cached = noteRelationsCache[key], cached.body == body {
            noteLinksView.update(cached.relations)
            updateKnowledgeNavigationControls()
        } else {
            noteLinksView.update(.empty)
        }
        let generation = noteLinksRefreshGeneration
        let noteStore = noteStore
        let roots = noteStore.preferredDirectories + [noteURL.deletingLastPathComponent()]
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }
            let relations = noteStore.knowledgeRelations(
                for: noteURL,
                currentBody: body,
                roots: roots,
                suggestionLimit: 3,
                cancellationCheck: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      generation == self.noteLinksRefreshGeneration,
                      self.selectedURL?.standardizedFileURL == noteURL.standardizedFileURL else {
                    return
                }
                self.noteLinksRefreshTask = nil
                if self.noteRelationsCache.count >= 16 { self.noteRelationsCache.removeAll() }
                self.noteRelationsCache[key] = (body, relations)
                self.noteLinksView.update(relations)
                self.updateKnowledgeNavigationControls()
            }
        }
        noteLinksRefreshTask = task
    }

    func refreshNoteLinksAfterSave(
        for noteURL: URL,
        replacing previousURL: URL?,
        body: String
    ) {
        refreshNoteLinks(for: noteURL, body: body)
        knowledgeGraphWindowController?.reload()
    }

    func acceptKnowledgeSuggestion(_ item: KnowledgeRelationItem) {
        guard selectedScope != .trash, let sourceURL = selectedURL,
              sourceURL.standardizedFileURL != item.url.standardizedFileURL,
              !noteLinksView.knowledgeRelations.outgoing.contains(where: {
                  $0.url.standardizedFileURL == item.url.standardizedFileURL
              }) else { return }
        let link = noteStore.markdownKnowledgeLink(
            from: sourceURL,
            to: item.url,
            title: item.title
        )
        let insertionLocation = editorTextView.string.utf16.count
        editorTextView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
        let prefix = insertionLocation == 0 ? "" : "\n\n"
        replaceSelectionWithRenderedMarkdown(
            "\(prefix)- 关联：\(link)",
            renderingBaseURL: sourceURL
        )
        let previous = noteLinksView.knowledgeRelations
        let confirmed = KnowledgeRelations(currentLayer: previous.currentLayer,
            parents: previous.parents, children: previous.children, related: previous.related,
            suggested: previous.suggested.filter { $0.url.standardizedFileURL != item.url.standardizedFileURL },
            outgoing: previous.outgoing + [item], incoming: previous.incoming)
        noteRelationsCache[sourceURL.standardizedFileURL] = (normalizedEditorMarkdownBody(), confirmed)
        refreshNoteLinks(for: sourceURL, body: normalizedEditorMarkdownBody())
        NSAccessibility.post(
            element: noteLinksView,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "已将 \(item.title) 加入明确关联",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    func openKnowledgeRelation(at url: URL) {
        guard let currentURL = selectedURL?.standardizedFileURL,
              currentURL != url.standardizedFileURL else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        do {
            try openMarkdownDocumentForLibrary(at: url)
            knowledgeBackStack.append(currentURL)
            knowledgeForwardStack.removeAll()
            updateKnowledgeNavigationControls()
            announceKnowledgeNavigation(title: url.deletingPathExtension().lastPathComponent)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
        }
    }

    var canShowKnowledgeGraphForLibrary: Bool {
        selectedURL != nil
    }

    func showKnowledgeGraphForLibrary() {
        guard let selectedURL else { return }
        let controller: KnowledgeGraphWindowController
        if let existing = knowledgeGraphWindowController {
            controller = existing
        } else {
            let noteStore = noteStore
            let created = KnowledgeGraphWindowController(
                noteStore: noteStore,
                rootsProvider: {
                    noteStore.preferredDirectories
                }
            )
            created.onOpenNode = { [weak self] url in
                self?.openKnowledgeRelation(at: url)
            }
            created.onClose = { [weak self, weak created] in
                guard self?.knowledgeGraphWindowController === created else { return }
                self?.knowledgeGraphWindowController = nil
            }
            knowledgeGraphWindowController = created
            controller = created
        }
        controller.show(rootURL: selectedURL)
    }

    @objc func goBackInKnowledgeRelations() {
        guard let targetURL = knowledgeBackStack.last,
              let currentURL = selectedURL?.standardizedFileURL else {
            return
        }
        do {
            try openMarkdownDocumentForLibrary(at: targetURL)
            knowledgeBackStack.removeLast()
            knowledgeForwardStack.append(currentURL)
            updateKnowledgeNavigationControls()
            announceKnowledgeNavigation(title: targetURL.deletingPathExtension().lastPathComponent)
        } catch {
            presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
        }
    }

    @objc func goForwardInKnowledgeRelations() {
        guard let targetURL = knowledgeForwardStack.last,
              let currentURL = selectedURL?.standardizedFileURL else {
            return
        }
        do {
            try openMarkdownDocumentForLibrary(at: targetURL)
            knowledgeForwardStack.removeLast()
            knowledgeBackStack.append(currentURL)
            updateKnowledgeNavigationControls()
            announceKnowledgeNavigation(title: targetURL.deletingPathExtension().lastPathComponent)
        } catch {
            presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
        }
    }

    func updateKnowledgeNavigationControls() {
        noteLinksView.updateNavigation(
            canGoBack: !knowledgeBackStack.isEmpty,
            canGoForward: !knowledgeForwardStack.isEmpty
        )
        window?.toolbar?.validateVisibleItems()
    }

    func recordNoteNavigation(to nextURL: URL) {
        guard let currentURL = selectedURL?.standardizedFileURL,
              currentURL != nextURL.standardizedFileURL else { return }
        knowledgeBackStack.append(currentURL)
        if knowledgeBackStack.count > 100 {
            knowledgeBackStack.removeFirst(knowledgeBackStack.count - 100)
        }
        knowledgeForwardStack.removeAll()
        updateKnowledgeNavigationControls()
    }

    func announceKnowledgeNavigation(title: String) {
        NSAccessibility.post(
            element: noteLinksView,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "已打开 \(title)",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    func cancelKnowledgeSynthesisForSelectionChange(to nextURL: URL?) {
        let currentPath = selectedURL?.standardizedFileURL.path
        let nextPath = nextURL?.standardizedFileURL.path
        guard currentPath != nextPath, knowledgeSynthesisTask != nil else { return }
        knowledgeSynthesisTask?.cancel()
        knowledgeSynthesisTask = nil
        knowledgeSynthesisGeneration += 1
        noteLinksView.setSynthesisInProgress(false)
    }

    func setSelectedURLForLibrary(_ nextURL: URL?) {
        cancelKnowledgeSynthesisForSelectionChange(to: nextURL)
        if selectedURL?.standardizedFileURL != nextURL?.standardizedFileURL {
            cancelNoteLinksRefresh()
            noteLinksView.update(.empty)
        }
        selectedURL = nextURL
        knowledgeGraphWindowController?.setRoot(nextURL, reload: true)
    }

    func generateHigherLayerDraft(targetLayer: KnowledgeLayer) {
        guard selectedScope != .trash,
              targetLayer == .line || targetLayer == .plane else {
            return
        }
        guard noteStore.aiEnabled else {
            presentErrorAlert(message: "AI 功能未启用", details: AIError.disabled.localizedDescription)
            return
        }
        guard let executableURL = CodexRuntimeLocator.resolve(
            configuredPath: noteStore.aiCodexExecutablePath
        ) else {
            presentErrorAlert(
                message: "未找到本机 Codex",
                details: AIError.providerNotConfigured.localizedDescription
            )
            return
        }

        do {
            try saveCurrentNoteIfNeeded()
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return
        }
        guard let currentURL = selectedURL?.standardizedFileURL else { return }

        let currentBody: String
        do {
            currentBody = try noteStore.loadNote(at: currentURL).body
        } catch {
            presentErrorAlert(message: "无法读取当前笔记", details: error.localizedDescription)
            return
        }
        let roots = noteStore.preferredDirectories + [currentURL.deletingLastPathComponent()]
        let relations = noteStore.knowledgeRelations(
            for: currentURL,
            currentBody: currentBody,
            roots: roots,
            suggestionLimit: 0
        )
        let relationItems = relations.related
            + relations.children
        var sourceURLs = [currentURL]
        var seenPaths = Set([currentURL.path])
        for item in relationItems where seenPaths.insert(item.url.standardizedFileURL.path).inserted {
            sourceURLs.append(item.url.standardizedFileURL)
            if sourceURLs.count == 6 { break }
        }
        let synthesisSourceURLs = sourceURLs
        let sourceNames = synthesisSourceURLs.map {
            $0.deletingPathExtension().lastPathComponent
        }.joined(separator: "、")
        let confirmation = NSAlert()
        confirmation.messageText = "将 \(synthesisSourceURLs.count) 篇笔记交给 Codex 生成草案？"
        confirmation.informativeText = "发送范围：\(sourceNames)。只包含当前笔记和已明确关联的下层/同层笔记；Codex 进程会被系统限制在临时目录，不能读取知识库中的其他文件。"
        confirmation.addButton(withTitle: "开始生成")
        confirmation.addButton(withTitle: "取消")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        let noteStore = noteStore
        let provider = CodexAIProvider(executableURL: executableURL)
        knowledgeSynthesisTask?.cancel()
        knowledgeSynthesisGeneration += 1
        let generation = knowledgeSynthesisGeneration
        let previousStatus = statusLabel.stringValue
        noteLinksView.setSynthesisInProgress(true)
        updateEditorStatus("正在生成\(targetLayer.displayName)层草案…")
        knowledgeSynthesisTask = Task { [weak self] in
            do {
                let sources = try await Task.detached(priority: .userInitiated) {
                    try synthesisSourceURLs.map { url -> KnowledgeSynthesisSource in
                        let note = try noteStore.loadNote(at: url)
                        return KnowledgeSynthesisSource(
                            title: note.title.isEmpty
                                ? url.deletingPathExtension().lastPathComponent
                                : note.title,
                            markdown: note.body
                        )
                    }
                }.value
                try Task.checkCancellation()
                let output = try await provider.generate(request: KnowledgeSynthesisRequest(
                    targetLayer: targetLayer,
                    sources: sources
                ))
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          generation == self.knowledgeSynthesisGeneration,
                          self.selectedURL?.standardizedFileURL == currentURL else {
                        return
                    }
                    self.knowledgeSynthesisTask = nil
                    self.noteLinksView.setSynthesisInProgress(false)
                    self.updateEditorStatus(previousStatus)
                    self.presentKnowledgeSynthesis(
                        output,
                        targetLayer: targetLayer,
                        sourceURLs: synthesisSourceURLs
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self,
                          generation == self.knowledgeSynthesisGeneration else {
                        return
                    }
                    self.knowledgeSynthesisTask = nil
                    self.noteLinksView.setSynthesisInProgress(false)
                    self.updateEditorStatus(previousStatus)
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          generation == self.knowledgeSynthesisGeneration,
                          self.selectedURL?.standardizedFileURL == currentURL else {
                        return
                    }
                    self.knowledgeSynthesisTask = nil
                    self.noteLinksView.setSynthesisInProgress(false)
                    self.updateEditorStatus("草案生成失败", kind: .failure)
                    self.presentErrorAlert(message: "无法生成上层草案", details: error.localizedDescription)
                }
            }
        }
    }

    func presentKnowledgeSynthesis(
        _ output: String,
        targetLayer: KnowledgeLayer,
        sourceURLs: [URL]
    ) {
        let document = MarkdownEditorDocument.parse(editorText: output)
        guard !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentErrorAlert(message: "无法创建草案", details: AIError.invalidResponse.localizedDescription)
            return
        }

        let alert = NSAlert()
        alert.messageText = "生成\(targetLayer.displayName)层草案"
        alert.informativeText = "AI 基于 \(sourceURLs.count) 篇笔记生成。只有点击“创建草案”后才会写入，原笔记不会被改动。"
        alert.alertStyle = .informational
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 280))
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = output
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "创建草案")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            window?.makeFirstResponder(editorTextView)
            return
        }

        let referenceSourceURL = noteStore.notesDirectory
            .appendingPathComponent("Knowledge-Synthesis.md")
        let sourceLinks = sourceURLs.enumerated().map { index, url in
            let title = (try? noteStore.loadNote(at: url).title)
                .flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                }
                ?? url.deletingPathExtension().lastPathComponent
            let link = noteStore.markdownKnowledgeLink(
                from: referenceSourceURL,
                to: url,
                title: title
            )
            return "- S\(index + 1): \(link)"
        }.joined(separator: "\n")
        let body = """
        \(document.body)

        ## 来源笔记

        \(sourceLinks)
        """
        do {
            let savedURL = try noteStore.saveNewNote(
                title: document.title,
                body: body,
                tags: ["层级/\(targetLayer.displayName)", "AI草案", "待审核"],
                in: noteStore.notesDirectory
            )
            recordInternalFileSystemChanges(for: [savedURL])
            onSave(savedURL)
            try openMarkdownDocumentForLibrary(at: savedURL)
            announceKnowledgeNavigation(title: document.title)
        } catch {
            presentErrorAlert(message: "无法创建草案", details: error.localizedDescription)
        }
    }
}
