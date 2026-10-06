---
name: simple
description: Rewrite a message so a non-native English reader (a client or teammate like Zabih or Matt) understands it at once. Use when the user types /simple, or says "make it shorter", "simple English", "he will not understand", "for him", "short answer for him".
---

# Simple

Rewrite the text the user names. If they name none, rewrite your last draft message.

## Rules
- Keep every fact, number, name, date and link. Drop everything else.
- Short sentences, about 12 words or fewer. One idea per sentence.
- Common words only. Replace jargon with what it means ("deploy" becomes "put it live").
- No em or en dashes, no bold, no headings. Use plain lists only if there are 3 or more steps.
- Lead with the answer or the ask. Context after, only if needed.
- Aim for half the original length or less.

## Output
The rewritten message as plain text, ready to paste. Never use a markdown blockquote (`>`), because it shows a white line down the left side that Hassan does not want; no code block either. No preamble. If something important had to be cut, say so in one line under it, separated by a blank line.
