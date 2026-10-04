---
name: stories
description: Verify Passenger user stories against the real passenger-app code and the docs, with evidence and no assumptions. Use when the user types /stories <ids>, or asks to verify, check or audit one or more of Matt's stories in Passenger-development.
---

# Stories

Args: one or more story IDs or titles (for example `/stories B-03 SAL-12`). With no args, ask which stories.

Repository: `/Users/hassanjan/Passenger-development`. The app is `passenger-app/` (components/, lib/, app/, supabase/migrations/, scripts/). READ-ONLY: never edit, create or delete any file in the repo.

## Find each story
- Look it up in `00_Canon/STORY-REGISTRY.md` for its source document. IDs can collide (see section 1 of that file), so match on title too and list every candidate.
- `.docx` sources: convert with `textutil -convert txt -stdout <file>` and quote from that text.
- If the story text cannot be found, the verdict is UNSURE with story_text_found=false.

## Run
- One story: verify it in this session.
- Two or more: one Sonnet subagent per story (`model: "sonnet"`), in parallel, each given the rules below in full plus its story ID and source path.
- Use `/usr/bin/grep`, not `grep` (grep is aliased to ugrep and fails on some patterns).

## Rules (give these to every subagent)
NO ASSUMPTIONS. Every claim needs evidence:
- The story's own words: quote the user story and every acceptance criterion from the source, with file and line numbers.
- Code: `file:line` for anything that exists. When nothing exists, say exactly what was searched for.
- If a verdict cannot be proven either way, use UNSURE and say why. Never guess.
- Verdicts: DONE = every criterion met in real code (not demo, placeholder or hardcoded prototype data). PARTLY = some met. NOT_BUILT = nothing in the code. UNSURE = cannot prove.
- Check `00_Canon/DECISIONS.md` and `passenger-app/DECISIONS-NEEDED.md` for anything that defers, conflicts with or changes the story.
- If the source says the story belongs to another tool (Fulcrum, Power Automate, Xero, a standalone HTML tool, Mono BOM builder), say so and judge only passenger-app.
- Name any other story in the registry that asks for the same thing (possible duplicate), confirmed from source text, not titles alone.

## Report
A table: ID, verdict, criteria met / missing, key evidence (`file:line`). Then one line per UNSURE explaining why. Spot-check at least one subagent claim per story yourself (open the cited `file:line`) before reporting.
