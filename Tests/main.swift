import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let reading = Reading("Hello,  café\n👋🏽 world!")
check(reading.words == ["Hello,", "café", "👋🏽", "world!"], "Unicode tokenization")
let offset = (reading.text as NSString).range(of: "world").location
check(reading.word(atUTF16Offset: offset) == 3, "Selection uses UTF-16 offsets")
check(reading.word(atUTF16Offset: 7) == 1, "Whitespace seeks forward")
check(Reading("").word(atUTF16Offset: 0) == 0, "Empty selection")
check(Reading.focalIndex("(hello)") == 2, "Ignore leading punctuation for focal index")
check(Reading.focalIndex("a") == 0, "One character")
check(Reading.focalIndex("👋🏽") == 0, "Emoji")
check(Reading.normalized(" a  \r\nb \n\n") == "a\nb", "Normalize terminal whitespace")
check(Reading.newText(after: "a\nb", in: "a\nb\nc") == "c", "Append detection")
check(Reading.newText(after: "a\nb\nc", in: "b\nc\nd") == "d", "Scroll detection")
check(Reading.newText(after: "a", in: "a").isEmpty, "No repeats")

let claude = #"""
{"type":"assistant","uuid":"1","message":{"role":"assistant","content":[{"type":"thinking","thinking":"PRIVATE"},{"type":"text","text":"Agent reply"},{"type":"tool_use","name":"bash"}]}}
{"type":"user","uuid":"2","message":{"role":"user","content":"MY INPUT"}}
{"type":"user","uuid":"3","message":{"role":"user","content":[{"type":"tool_result","content":"TOOL OUTPUT"}]}}
"""#
check(Conversation.latest(in: claude, agent: .claude, assistantOnly: true)?.text == "Agent reply", "Claude excludes input, tools, thinking")
check(Conversation.latest(in: claude, agent: .claude, assistantOnly: false)?.text == "MY INPUT", "Claude opt-in user input")
let codex = #"""
{"type":"response_item","payload":{"type":"message","id":"1","role":"assistant","content":[{"type":"output_text","text":"Agent reply"}]}}
{"type":"event_msg","payload":{"type":"agent_message","message":"Duplicate"}}
{"type":"response_item","payload":{"type":"reasoning","summary":[{"text":"PRIVATE"}]}}
{"type":"response_item","payload":{"type":"message","id":"2","role":"user","content":[{"type":"input_text","text":"MY INPUT"}]}}
{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"SYSTEM"}]}}
{"broken":
"""#
check(Conversation.latest(in: codex, agent: .codex, assistantOnly: true)?.text == "Agent reply", "Codex role filtering and duplicate exclusion")
check(Conversation.latest(in: codex, agent: .codex, assistantOnly: false)?.text == "MY INPUT", "Codex user opt-in")
let grok = #"""
{"timestamp_us":1,"params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"MY INPUT"}}}}
{"timestamp_us":2,"params":{"update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"PRIVATE"}}}}
{"timestamp_us":3,"params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello "}}}}
{"timestamp_us":4,"params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"world"}}}}
{"timestamp_us":5,"params":{"update":{"sessionUpdate":"turn_completed"}}}
{"timestamp_us":6,"params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"NEXT INPUT"}}}}
"""#
check(Conversation.latest(in: grok, agent: .grok, assistantOnly: true)?.text == "Hello world", "Grok joins chunks, excludes user and thinking")
check(Conversation.latest(in: grok, agent: .grok, assistantOnly: false)?.text == "NEXT INPUT", "Grok user opt-in")

let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try (codex + "\n" + #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"partial"}]}}"#).write(to: temp, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: temp) }
let tailReply = try Conversation.read(temp, agent: .codex, assistantOnly: true)
check(tailReply?.text == "Agent reply", "Ignore incomplete JSONL tail")
print("All reading, selection, terminal-diff, and agent-filter checks passed.")
