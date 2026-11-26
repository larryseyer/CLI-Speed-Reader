# CLI Speed Reader for macOS

A native Swift/AppKit floating reader for Claude Code, Codex, and Grok Build. No dependencies beyond Apple's command-line tools. Words appear one at a time with a red focal letter aligned to a fixed position. This uses a simple length-based focal-letter heuristic, not licensed Spritz technology. It displays text visually; it does not synthesize speech.

## Run

```sh
bash scripts/build.sh
open "build/CLI Speed Reader.app"
```

The app is built locally and ad-hoc signed. Keep it in this location to avoid unnecessary changes to macOS permission identity.

Launch the `.app` from Finder or run the `open` command above in your own Terminal. Launching its inner executable from a restricted coding-agent shell can abort inside macOS `_RegisterApplication` before the reader initializes. A normal desktop launch works.

## Use

1. Choose **Claude Code**, **Codex**, or **Grok Build**. Leave **Assistant replies only** checked to exclude your prompts, internal reasoning, and tool results.
2. **Connect latest session** attaches to that agent's most recently modified main conversation file. Verify the path shown in the reader: the newest session may belong to another project or to the Codex desktop app. **Choose session…** selects a specific JSONL file. The connection stays on that file until you reconnect.
3. The latest reply loads paused. Press **Play**. New replies append to the transcript and play when you have reached the end. Pausing in the middle holds your position while new replies arrive.
4. Set **60–1000 WPM** with the speed slider; the speed is saved between launches.
5. Move the **Start / position** slider to any word, then press **Play**. Or select a word in the transcript and press **Start at selection**. **Restart** reads from the beginning of the retained text.
6. **Disconnect** before changing the agent or the assistant-only setting. Reconnecting loads the latest reply afresh.

Conversation files are under `~/.claude/projects`, `~/.codex/sessions`, and `~/.grok/sessions` (Grok's `updates.jsonl`). No terminal permissions are needed for this mode. Hidden folders appear in the session chooser because it opens directly at the agent's storage directory; use Command-Shift-G to enter a path if needed.

For manual text, copy a reply in Terminal and click **Read Clipboard**. The clipboard is only read when clicked. Clipboard text is read exactly as chosen, regardless of the assistant-only checkbox.

For generic Terminal output, choose **Terminal screen**, uncheck **Assistant replies only**, select the desired Terminal tab, and click **Watch front Terminal tab**. Approve macOS's Automation permission for Terminal when prompted. This watches that tab's TTY even when you switch windows. It establishes a baseline, then reads screen changes after they settle for about two seconds. Terminal mode includes user input and status text. If permission was denied, enable CLI Speed Reader → Terminal in System Settings → Privacy & Security → Automation, then reconnect.

Close the floating window or press Command-Q to quit.

## Limits

- The agent log adapters match the formats installed on this Mac. Agent updates can change them. Unsupported records are ignored, never treated as assistant text.
- Only the latest reply at each poll is collected; several separate replies written within one second can cause intermediate replies to be skipped. Streaming updates to the same reply replace that reply's text while preserving the word position.
- Each poll reads the final 8 MiB of the selected log. Extremely large replies can be unavailable if their record falls outside that window.
- Screen mode compares visible text, not semantic messages. Full-screen redraws, resizing, and spinners can repeat or omit text. Use agent logs or the clipboard for exact text.
- Assistant-only means records authored by the assistant. If an assistant quotes your prompt in its own response, the quotation remains.
- Text stays in memory; the app makes no network requests and writes no conversation copies. Only speed and window preferences persist.
- The focal letter stays fixed. Very long tokens shrink to fit and may be difficult to read.

## Checks

```sh
bash scripts/test.sh
```

Checks cover word selection with Unicode, focal letters, terminal scrolling, role filtering for all three agents, Grok streaming chunks, malformed records, and incomplete JSONL writes.
