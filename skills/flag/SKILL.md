---
description: "Flag a behavioral problem for later processing into instruction improvements."
disable-model-invocation: true
user_invocable: true
---

# Flag Behavioral Issue

The user is flagging a problem with Claude's behavior in the current session.
Your job is to capture a structured incident report using the conversation context you already have.

## Configuration

Feedback directory (absolute path):

```
FEEDBACK_DIR=~/dev/claude-forge/feedback
```

## Instructions

1. Read the user's complaint: `$ARGUMENTS`

2. Using your knowledge of the current session (what task was in progress, what actions you took, what the user asked for), produce a structured incident report with these fields:

   - **category**: exactly one of: `supervised-mode` | `premature-implementation` | `scope-creep` | `blind-debugging` | `delegation` | `missing-analysis` | `wrong-output` | `other`
   - **summary**: one-line description of the problem
   - **what_happened**: what you (Claude) actually did — be specific and honest
   - **what_was_expected**: what the user wanted instead
   - **existing_instruction**: which CLAUDE.md or skill instruction (if any) should have prevented this — quote the instruction text if it exists, or write "none" if no instruction covers this
   - **root_cause**: exactly one of: `missing-instruction` | `vague-instruction` | `contradicted-instruction` | `compliance-failure`
   - **diagnosis**: why the existing instruction failed (or what instruction is missing), generalized beyond this specific incident
   - **suggested_fix**: a fix for the CLASS of problems, not the literal scenario — reword for clarity, merge with another rule, escalate to hook, or add a new generalized instruction

3. Do NOT write a fix for the literal scenario described. Trace to the root cause and generalize. If an existing instruction covers this, diagnose why it failed (vague? contradicted? ignored?) rather than inventing a new rule.

4. Show the structured report to the user for validation before writing.

5. After user confirms, write the report as a markdown file to `FEEDBACK_DIR` with filename format `YYYY-MM-DD-HHMMSS.md`.

## Output Format

The written file must follow this exact template:

```markdown
# Flag: <summary>

- **Date:** <YYYY-MM-DD HH:MM>
- **Category:** <category>
- **Project:** <current working directory>

## What Happened

<what_happened>

## What Was Expected

<what_was_expected>

## Existing Instruction

<existing_instruction — quote the rule or "none">

## Root Cause Analysis

- **Root Cause:** <root_cause>
- **Diagnosis:** <diagnosis — generalized beyond this specific incident>

## Suggested Fix

<suggested_fix — targets the class of problems, not the literal scenario>
```

## Rules

- Be honest about what you did wrong. Do not minimize or rationalize.
- The suggested fix must be a specific, actionable instruction — not "be more careful" or "improve behavior."
- If an existing instruction already covers this behavior, say so explicitly — this means the issue is compliance, not a missing rule.
- Every flag is a symptom. The fix must target the underlying instruction gap or compliance failure, never the specific symptom. If you catch yourself writing a rule about the exact scenario described, you're doing it wrong — go one level deeper.
- Keep the report concise. No filler.
