//
//  AskUserQuestionView.swift
//  ClaudeIsland
//
//  Interactive UI for answering AskUserQuestion prompts from Claude Code.
//  Sends the selected option index to the terminal via AppleScript / cmux.
//

import SwiftUI

struct AskUserQuestionView: View {
    let session: SessionState
    let context: QuestionContext
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    @State private var customTexts: [Int: String] = [:]  // per-question custom text
    @State private var hoveredKey: String? = nil
    @State private var isSending: Bool = false
    @State private var multiSelectChoices: Set<Int> = []  // multi-select: selected option indices (0-based)
    @State private var isHeaderHovered = false

    /// First question text for the header
    private var questionTitle: String {
        context.questions.first?.question ?? "Question"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — matches ChatView style: ← project name + question
            Button {
                viewModel.contentType = .instances
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(isHeaderHovered ? 1.0 : 0.6)
                        .frame(width: 24, height: 24)

                    Text(session.projectName)
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(isHeaderHovered ? 1.0 : 0.85)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHeaderHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }
            .padding(.horizontal, 8)
            .padding(.top, 28)
            .padding(.bottom, 4)
            .background(Color.white.opacity(0.04))

            // Questions + options
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(context.questions.enumerated()), id: \.offset) { qIdx, question in
                        questionBlock(questionIndex: qIdx, question: question)
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 4)

            // Bottom input field for custom "Other" text
            HStack(spacing: 6) {
                TextField("Other...", text: Binding(
                    get: { customTexts[0] ?? "" },
                    set: { customTexts[0] = $0 }
                ))
                .textFieldStyle(.plain)
                .notchFont(11)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .onSubmit { submitOtherForQuestion(questionIndex: 0, optionCount: context.questions.first?.options.count ?? 0) }

                Button {
                    submitOtherForQuestion(questionIndex: 0, optionCount: context.questions.first?.options.count ?? 0)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(
                            (customTexts[0] ?? "").isEmpty || isSending
                                ? Color.white.opacity(0.15)
                                : TerminalColors.amber
                        )
                }
                .buttonStyle(.plain)
                .disabled((customTexts[0] ?? "").isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        // Reset state when a new question arrives (different toolUseId)
        .onChange(of: context.toolUseId) { _ in
            isSending = false
            customTexts = [:]
            hoveredKey = nil
        }
    }

    // MARK: - Question Block

    @ViewBuilder
    private func questionBlock(questionIndex: Int, question: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.question)
                .notchFont(12, weight: .semibold)
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 2)

            if question.multiSelect {
                // Multi-select: toggleable options
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    multiSelectRow(questionIndex: questionIndex, optionIndex: index, option: option)
                }

                // Submit button (only when something is selected)
                if !multiSelectChoices.isEmpty {
                    Button {
                        guard !isSending else { return }
                        isSending = true
                        sendMultiSelectViaSocket(questionIndex: questionIndex, question: question)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .notchFont(10)
                            Text("Submit (\(multiSelectChoices.count))")
                                .notchFont(11, weight: .medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(TerminalColors.amber.opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            } else {
                // Single-select: click to send
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionRow(questionIndex: questionIndex, optionIndex: index + 1, option: option, optionCount: question.options.count)
                }
            }

            // Inline "Other" input removed — always-visible input at bottom
        }
    }

    private func optionRow(questionIndex: Int, optionIndex: Int, option: QuestionOption, optionCount: Int) -> some View {
        let hoverKey = "\(questionIndex)-\(optionIndex)"
        let isHovered = hoveredKey == hoverKey

        return Button {
            guard !isSending else { return }
            isSending = true
            DebugLogger.log("AskUser", "Option \(optionIndex) tapped: \(option.label)")
            Task { await approveAndSendOption(index: optionIndex) }
        } label: {
            HStack(spacing: 8) {
                Text("\(optionIndex)")
                    .notchFont(10, weight: .bold)
                    .foregroundColor(TerminalColors.amber)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TerminalColors.amber.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .notchFont(11, weight: .medium)
                        .foregroundColor(.white.opacity(0.85))

                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .notchFont(9, weight: .regular)
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .notchFont(8)
                    .foregroundColor(.white.opacity(isHovered ? 0.5 : 0.15))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? TerminalColors.amber.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isHovered ? TerminalColors.amber.opacity(0.2) : Color.white.opacity(0.06),
                                lineWidth: 0.5
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? hoverKey : nil
        }
    }

    /// Multi-select: toggleable option row with checkbox
    private func multiSelectRow(questionIndex: Int, optionIndex: Int, option: QuestionOption) -> some View {
        let isSelected = multiSelectChoices.contains(optionIndex)
        let hoverKey = "m\(questionIndex)-\(optionIndex)"
        let isHovered = hoveredKey == hoverKey

        return Button {
            if multiSelectChoices.contains(optionIndex) {
                multiSelectChoices.remove(optionIndex)
            } else {
                multiSelectChoices.insert(optionIndex)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .notchFont(12)
                    .foregroundColor(isSelected ? TerminalColors.amber : .white.opacity(0.3))
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .notchFont(11, weight: .medium)
                        .foregroundColor(.white.opacity(isSelected ? 0.95 : 0.85))

                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .notchFont(9, weight: .regular)
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? TerminalColors.amber.opacity(0.1) : (isHovered ? TerminalColors.amber.opacity(0.08) : Color.white.opacity(0.03)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isSelected ? TerminalColors.amber.opacity(0.3) : (isHovered ? TerminalColors.amber.opacity(0.2) : Color.white.opacity(0.06)),
                                lineWidth: 0.5
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKey = hovering ? hoverKey : nil
        }
    }

    // MARK: - Custom Input

    /// Inline "Other" input at the end of a question's options
    @ViewBuilder
    private func inlineOtherInput(questionIndex: Int, optionCount: Int) -> some View {
        HStack(spacing: 6) {
            TextField("Other...", text: Binding(
                get: { customTexts[questionIndex] ?? "" },
                set: { customTexts[questionIndex] = $0 }
            ))
            .textFieldStyle(.plain)
            .notchFont(11)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .onSubmit { submitOtherForQuestion(questionIndex: questionIndex, optionCount: optionCount) }

            Button {
                submitOtherForQuestion(questionIndex: questionIndex, optionCount: optionCount)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(
                        (customTexts[questionIndex] ?? "").isEmpty || isSending
                            ? Color.white.opacity(0.15)
                            : TerminalColors.amber
                    )
            }
            .buttonStyle(.plain)
            .disabled((customTexts[questionIndex] ?? "").isEmpty || isSending)
        }
    }

    // MARK: - Option Sending (Socket or Terminal)

    /// Send a single option via socket if available, otherwise fall back to terminal.
    private func approveAndSendOption(index: Int) async {
        // Try socket path first (works for remote sessions)
        if let permission = session.activePermission,
           let input = permission.toolInput,
           let questionsValue = input["questions"]?.value as? [[String: Any]] {
            var answers: [String: String] = [:]
            var optionOffset = 0
            for q in questionsValue {
                let questionText = q["question"] as? String ?? ""
                if let opts = q["options"] as? [[String: Any]] {
                    let optIndex = index - 1 - optionOffset
                    if optIndex >= 0 && optIndex < opts.count {
                        let selectedLabel = opts[optIndex]["label"] as? String ?? ""
                        answers[questionText] = selectedLabel
                    }
                    optionOffset += opts.count
                }
            }
            if !answers.isEmpty {
                HookSocketServer.shared.respondToAskUser(toolUseId: permission.toolUseId, answers: answers)
                DebugLogger.log("AskUser", "Sent via socket: \(answers)")
                isSending = false
                return
            }
        }

        // Fall back to terminal injection
        let cwd = session.cwd
        let downPresses = index - 1

        for _ in 0..<downPresses {
            performGhosttyAction("csi:B", cwd: cwd) // Arrow Down
        }
        if downPresses > 0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        performGhosttyAction("text:\\r", cwd: cwd) // Enter

        DebugLogger.log("AskUser", "Sent \(downPresses) arrows + Enter")

        // Reset after delay to allow next question click
        try? await Task.sleep(nanoseconds: 800_000_000)
        isSending = false
    }

    /// Send multi-select answers via socket (comma-separated labels)
    private func sendMultiSelectViaSocket(questionIndex: Int, question: QuestionItem) {
        guard let permission = session.activePermission,
              let input = permission.toolInput,
              let questionsValue = input["questions"]?.value as? [[String: Any]],
              questionIndex < questionsValue.count else {
            isSending = false
            return
        }

        let questionText = questionsValue[questionIndex]["question"] as? String ?? question.question
        let selectedLabels = multiSelectChoices.sorted().compactMap { idx -> String? in
            guard idx < question.options.count else { return nil }
            return question.options[idx].label
        }

        if !selectedLabels.isEmpty {
            let answers = [questionText: selectedLabels.joined(separator: ", ")]
            HookSocketServer.shared.respondToAskUser(toolUseId: permission.toolUseId, answers: answers)
            DebugLogger.log("AskUser", "Multi-select sent via socket: \(answers)")
            multiSelectChoices.removeAll()
        }
        isSending = false
    }

    /// Send Enter to confirm "Submit answers" (option 1 in CLI).
    private func confirmSubmit() {
        let cwd = session.cwd
        performGhosttyAction("text:\\r", cwd: cwd) // Enter selects default (Submit)
        DebugLogger.log("AskUser", "Confirmed submit")
    }

    /// Deny the AskUserQuestion and go back to sessions list.
    private func denyAndGoBack() {
        if let permission = session.activePermission {
            HookSocketServer.shared.sendPermissionDecision(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: "Dismissed by user"
            )
            DebugLogger.log("AskUser", "Denied and going back")
        } else {
            // Terminal path: send Escape
            let cwd = session.cwd
            performGhosttyAction("text:\\u{1B}", cwd: cwd)
            DebugLogger.log("AskUser", "Sent Escape to terminal")
        }
    }

    /// Send ↓ + Enter to select "Cancel" (option 2 in CLI).
    private func cancelSubmit() {
        let cwd = session.cwd
        performGhosttyAction("csi:B", cwd: cwd) // Arrow Down to Cancel
        performGhosttyAction("text:\\r", cwd: cwd) // Enter
        DebugLogger.log("AskUser", "Cancelled submit")
    }

    /// Submit custom text for a specific question.
    /// "Type something" is option (optionCount + 1) in the CLI.
    private func submitOtherForQuestion(questionIndex: Int, optionCount: Int) {
        let text = customTexts[questionIndex] ?? ""
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        DebugLogger.log("AskUser", "Q\(questionIndex) custom text: \(text)")

        // Try socket path first
        if let permission = session.activePermission,
           let input = permission.toolInput,
           let questionsValue = input["questions"]?.value as? [[String: Any]],
           questionIndex < questionsValue.count,
           let questionText = questionsValue[questionIndex]["question"] as? String {
            let answers = [questionText: text]
            HookSocketServer.shared.respondToAskUser(toolUseId: permission.toolUseId, answers: answers)
            DebugLogger.log("AskUser", "Other sent via socket: \(answers)")
            customTexts[questionIndex] = ""
            isSending = false
            return
        }

        // Fall back to terminal injection
        Task {
            let cwd = session.cwd
            // Navigate to "Type something" option (after all regular options)
            for _ in 0..<optionCount {
                performGhosttyAction("csi:B", cwd: cwd)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            performGhosttyAction("text:\\r", cwd: cwd) // Select "Type something"
            // Wait for text input prompt
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Type the custom text + Enter
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            performGhosttyAction("text:\(escaped)\\r", cwd: cwd)

            // Reset for next question
            try? await Task.sleep(nanoseconds: 800_000_000)
            isSending = false
        }
    }

    /// Execute a Ghostty action on the cmux terminal via AppleScript.
    /// cmux's `perform action` sends real keyboard events through
    /// Ghostty's input system — works with Claude Code's raw terminal mode.
    @discardableResult
    private func performGhosttyAction(_ action: String, cwd: String) -> Bool {
        let escapedCwd = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "cmux"
            set targetTerm to (first terminal whose working directory is "\(escapedCwd)")
            perform action "\(action)" on targetTerm
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
