---
description: "Process accumulated behavioral flags into instruction improvements."
disable-model-invocation: true
user_invocable: true
---

# Review Behavioral Flags

Process accumulated feedback flags and turn them into instruction improvements.

## Configuration

```
FEEDBACK_DIR=~/dev/claude-forge/feedback
PROCESSED_DIR=~/dev/claude-forge/feedback/processed
```

## Instructions

1. **Read all unprocessed flags** from `FEEDBACK_DIR` (all `.md` files, excluding the `processed/` subdirectory).

2. **If no flags exist**, tell the user and stop.

3. **Show a summary table** of all flags grouped by category:

   ```
   | # | Date | Category | Summary |
   |---|------|----------|---------|
   | 1 | ...  | ...      | ...     |
   ```

4. **For each category group**, analyze:
   - Is there already an instruction that should prevent this? (compliance failure)
   - Is there a missing instruction? (gap)
   - Is this a pattern (same category appearing multiple times)?
   - What is the minimal instruction change that addresses all flags in this group?

5. **Cross-reference** against:
   - `~/dev/claude-forge/CLAUDE.md` (personal preferences)
   - Any company CLAUDE.md if referenced in the flags
   - Relevant skills
   - `~/dev/claude-forge/memory/forge-master-memory.md` (previous fixes)

6. **Propose changes** — for each group, show:
   - The specific file to edit
   - The exact instruction to add or modify
   - Why this change addresses the flagged behavior

7. **Wait for user approval** before making any changes.

8. **After applying approved changes:**
   - Move processed flag files to `PROCESSED_DIR`
   - Update `memory/forge-master-memory.md` with what was fixed and why
   - Append to `changelog/changelog_<today>.md`

## Rules

- Never modify instructions without showing the change first.
- Prefer strengthening existing instructions over adding new ones — instruction count must stay minimal.
- If 3+ flags share the same category, this is a pattern — consider whether the issue needs a hook (programmatic enforcement) rather than another instruction.
- Follow the instruction-writing skill principles: specific, actionable, NEVER includes alternative, no emphasis inflation.
- If a flag describes a compliance failure (instruction exists but was ignored), note this explicitly — more instructions won't fix compliance; escalation paths are: reword for clarity → add "Violation = stop" pattern → hook.
