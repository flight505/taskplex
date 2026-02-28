---
name: prd-converter
description: "Convert PRDs to prd.json format for the TaskPlex autonomous agent system. Use when a PRD markdown file exists and needs to be converted to executable format. Triggers on: convert this prd, create prd.json, turn this into taskplex format, ready to execute, let's run this."
context: fork
agent: Explore
model: sonnet
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Write
---

# TaskPlex PRD Converter

Converts existing PRDs to the prd.json format that TaskPlex uses for autonomous execution.

## The Job

Take a PRD (markdown file or text) and convert it to `prd.json` in your project directory.

## Output Format

```json
{
  "project": "[Project Name]",
  "branchName": "taskplex/[feature-name-kebab-case]",
  "description": "[Feature description]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": ["Criterion 1", "Criterion 2", "Typecheck passes"],
      "priority": 1,
      "passes": false,
      "notes": "",
      "depends_on": [],
      "related_to": [],
      "implementation_hint": "",
      "check_before_implementing": []
    }
  ]
}
```

### Schema Fields

| Field | Type | Purpose |
|-------|------|---------|
| `depends_on` | array | IDs of stories that MUST complete first (hard dependency) |
| `related_to` | array | IDs of stories with related work to check (soft dependency) |
| `implementation_hint` | string | Guidance for the agent (e.g., "Reuse existing badge component") |
| `check_before_implementing` | array | Commands to verify existing implementation (e.g., `["grep cabin_class api.py"]`) |

## Story Size: The Number One Rule

**Each story must be completable in ONE TaskPlex iteration (one context window).**

- **Ideal:** 3-5 acceptance criteria
- **Warning:** 6-7 criteria — consider splitting
- **Too large:** 8+ criteria — MUST split

**Check after converting:**
```bash
jq '.userStories[] | select((.acceptanceCriteria | length) > 7) | "\(.id): \(.acceptanceCriteria | length) criteria (TOO LARGE)"'
```

## Story Ordering: Dependencies First

1. Schema/database changes (migrations)
2. Server actions / backend logic
3. UI components that use the backend
4. Dashboard/summary views that aggregate data

## Acceptance Criteria: Must Be Verifiable

**Good:** "Add status column with default 'pending'", "Filter dropdown has options: All, Active, Completed"

**Bad:** "Works correctly", "Good UX", "Handles edge cases"

**Always include:** "Typecheck passes". For UI stories: "Verify in browser".

## Conversion Rules

1. Each user story → one JSON entry
2. IDs: Sequential (US-001, US-002, ...)
3. Priority: Dependency order, then document order
4. All stories: `passes: false`, empty `notes`
5. branchName: Kebab-case, prefixed `taskplex/`
6. Always add "Typecheck passes" to every story
7. Infer dependencies (see below)

## Dependency Inference

**Auto-detect `depends_on` (TRUE blocking):**
- Data model → business logic → API → UI
- Authentication → protected features
- Base component → extensions

**NOT a dependency (use `related_to` instead):**
- Two UI components in different areas
- Two API endpoints serving different purposes
- Sequential numbering alone

**Generate `implementation_hint`:**
- If `related_to` not empty: "Check US-XXX for similar patterns"
- If extending existing work: "Builds on US-XXX, review first"

**Generate `check_before_implementing`:**
- Data models: `grep -rn "[ModelName]" src/models/`
- API: `grep -rn "[endpoint]" src/api/`
- UI: `grep -rn "[ComponentName]" src/components/`

## Example

**Input PRD:** Task Status Feature — toggle status, filter by status, show badge, persist in DB.

**Output prd.json:**
```json
{
  "project": "TaskApp",
  "branchName": "taskplex/task-status",
  "description": "Task Status Feature",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add status field to tasks table",
      "acceptanceCriteria": [
        "Add status column: 'pending' | 'in_progress' | 'done' (default 'pending')",
        "Generate and run migration successfully",
        "Typecheck passes"
      ],
      "priority": 1, "passes": false, "notes": ""
    },
    {
      "id": "US-002",
      "title": "Display status badge and add toggle",
      "acceptanceCriteria": [
        "Each task shows colored status badge",
        "Status dropdown saves immediately without refresh",
        "Typecheck passes",
        "Verify in browser"
      ],
      "priority": 2, "passes": false, "notes": "",
      "depends_on": ["US-001"],
      "implementation_hint": "Reuse existing badge component.",
      "check_before_implementing": ["grep -r 'Badge' components/"]
    }
  ]
}
```

## Archiving Previous Runs

Before writing new prd.json, check if existing one has a different `branchName`:
1. Archive to `archive/YYYY-MM-DD-feature-name/`
2. Move `prd.json`

## Plan Segments (Optional)

Group stories into logical segments for partial re-execution. If a segment fails, only that segment needs re-running.

```json
{
  "segments": [
    {"name": "data-layer", "stories": ["US-001", "US-002"]},
    {"name": "api-layer", "stories": ["US-003", "US-004"]},
    {"name": "ui-layer", "stories": ["US-005", "US-006"]}
  ]
}
```

**Rules:**
- Stories within a segment should have no dependencies on other segments' incomplete stories
- Derive segments from dependency analysis (layer-based is most common)
- Every story must belong to exactly one segment
- Segment order respects cross-segment dependencies

## Checklist Before Saving

- [ ] Previous run archived if different feature
- [ ] Each story completable in one iteration
- [ ] Dependency order correct (schema → backend → UI)
- [ ] Every story has "Typecheck passes"
- [ ] UI stories have "Verify in browser"
- [ ] Criteria are verifiable, not vague
- [ ] No story depends on a later story
- [ ] Segments group related stories logically (if 5+ stories)
