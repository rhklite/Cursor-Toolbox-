---
name: Add Built-in Mic Priority
overview: Verify and append the MacBook Pro built-in microphone to the dictation priority list as the last fallback device.
todos:
  - id: confirm-device-name
    content: Use current system device list to confirm exact built-in mic string.
    status: completed
  - id: update-priority-list
    content: Append MacBook Pro Microphone to PRIORITY_INPUTS as last entry.
    status: completed
  - id: sync-docs
    content: Adjust README priority description to include new fallback order.
    status: cancelled
  - id: verify-behavior
    content: Recheck device list and validate expected dictation fallback behavior.
    status: completed
isProject: false
---

# Add MacBook Pro Mic as Lowest Priority

- Confirmed your built-in mic device string is exactly `MacBook Pro Microphone` from the current `--list` output.
- Update the priority array in `[/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/input_source_menubar.py](/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/input_source_menubar.py)` so it becomes:
  - `Yeti X`
  - `Blue Snowball`
  - `MacBook Pro Microphone`
- Update user-facing wording in `[/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/README.md](/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/README.md)` to keep docs aligned with the new fallback order.
- Verify by running `./Input_source.sh --list` and checking dictation behavior still prefers top devices when connected, and only falls back to `MacBook Pro Microphone` when higher-priority devices are unavailable.

