# OPC Companion

English | [简体中文](README.md)

> **Everyone is an OPC: become the assistant for your own life.**

A private thought-clearing space in the corner of your screen: a macOS menu bar AI assistant that knows when to stop talking.

Press a hotkey to catch whatever just appeared in your mind. Expand it into a full workspace when you need to sort, discuss, or close the loop. When you do not need it, OPC Companion quietly returns to the menu bar without taking over your attention.

---

## What It Is

OPC Companion is not a stronger to-do list or another chat window.

It is a **thought-clearing space**. It catches half-formed ideas, fragments, and anxiety first, then helps you decide whether any of them should become tasks. Its value comes from boundaries: short responses, reversible actions, local capture, archives, and the ability to stop talking.

It appears in four moments: while you are focused, when an idea interrupts you, when thoughts pile up, and when a work session needs closure.

## Core Capabilities

- **Quick Capture**: summon a single-line bar, type, and press Enter. The note stays local and does not call AI.
- **Talk It Through**: discuss a thought with a concise organizer that keeps an exit visible in every turn.
- **Thoughts to Closure**: capture, sort, decide, and quietly return to the main task.
- **Tasks and Focus**: timers, Pomodoro cycles, and deep focus integrated with macOS Focus mode.
- **Two Entry Modes**: Quiet Field front door or the classic panel, switchable in Settings.
- **Memory and Archives**: daily notes, cross-day conversation summaries, weekly reports, and a long-term profile.
- **Notion, Voice, and Themes**: confirmed Notion writes, voice capture, text-to-speech, themes, and fonts.

## Product Screens

### 1. Now: Return to What Is in Front of You

OPC Companion does not begin with a task list. It helps you identify the one thing that matters now and closes the conversation with a concrete next step.

![OPC Companion main panel](docs/assets/readme/01-main-panel.png)

### 2. Quick Capture: An Idea Is Not Automatically a Task

Use the hotkey to leave a thought locally without turning it into a commitment or interrupting your current work.

![OPC Companion Quick Capture](docs/assets/readme/02-quick-capture.png)

### 3. Thought Inbox: Turn Scattered Ideas into a Processable Queue

Thoughts wait in an inbox until you are ready to sort, complete, promote, or delete them.

![OPC Companion thought inbox](docs/assets/readme/03-inbox.png)

### 4. Talk It Through: A Good AI Companion Knows When to Stop

Once the thought is clear enough, OPC Companion closes the loop and gives your attention back to the current task.

![OPC Companion conversation closure](docs/assets/readme/04-wish-clearing.png)

### 5. Confirmed Notion Writes

For external writes, OPC Companion shows a confirmation card instead of silently acting on your behalf.

![OPC Companion Notion write confirmation](docs/assets/readme/05-notion-confirm.png)

## Stack

Swift 6, SwiftUI + AppKit (`NSPanel` / `NSStatusItem`), Swift Package Manager, macOS 15+.

Backend: MiniMax streaming with function calling, Notion API v1, and credentials stored in macOS Keychain.

## Privacy Boundary

OPC Companion keeps local capture and AI conversations deliberately separate:

- **Quick Capture stays local**: hotkey notes are stored under `~/.opc-companion/`. They are not sent to AI.
- **Conversations send context**: to preserve continuity, conversations send local context to **MiniMax**, including long-term memory, profile data, recent daily notes, the latest weekly report, current tasks, inbox state, memory search results, and Notion query results when relevant.
- **Credentials stay in Keychain**: API keys and Notion tokens are never stored as plaintext files or committed to the repository.

In short: **if you do not want it sent out, capture it locally instead of discussing it in chat.**

## Build

```bash
swift build
./build.sh && open OPCCompanion.app
swift test
```

## About ShiyeAI

OPC Companion is built by **ShiyeAI**.

We believe a good AI assistant should not keep talking. It should help you clear your mind, then get out of the way.

- Xiaohongshu: **十页AI** (`naiyoubaba`)
- More AI resources and products: [shiyeai.cn](https://shiyeai.cn/)

## License

This project uses the **PolyForm Noncommercial License 1.0.0**.

You may study, modify, and distribute the source code for **noncommercial** purposes. You must retain the copyright notice for **十页AI** and may not use the project commercially. See [LICENSE](LICENSE).
