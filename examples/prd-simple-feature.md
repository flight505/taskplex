# PRD: Task Priority System

## Introduction

Add priority levels to tasks so users can focus on what matters most. Tasks can be marked as high, medium, or low priority, with visual indicators and filtering to help users manage their workload effectively.

## Goals

- Allow assigning priority (high/medium/low) to any task
- Provide clear visual differentiation between priority levels
- Enable filtering and sorting by priority
- Default new tasks to medium priority

## User Stories

### US-001: Add priority field to database
**Description:** As a developer, I need to store task priority so it persists across sessions.

**Acceptance Criteria:**
- [ ] Add priority column to tasks table: 'high' | 'medium' | 'low' (default 'medium')
  - **Must verify:** `sqlite3 tasks.db ".schema tasks" | grep priority`
  - **Expected:** Column present with CHECK constraint
- [ ] Generate and run migration successfully
  - **Must verify:** `ls migrations/ | grep add_priority`
  - **Expected:** Migration file exists and applies without errors
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck` or `pyright --project .`
  - **Expected:** No errors

### US-002: Complete Priority Display and Selection (Full-Stack)
**Description:** As a user, I want to see and change task priorities so I can manage what needs attention.

**Note:** This is a simple feature (4 criteria total), so combining UI + backend in one story.

**Acceptance Criteria:**
- [ ] Each task card shows colored priority badge (red=high, yellow=medium, gray=low)
  - **Must verify:** Navigate to task list in browser
  - **Expected:** Badges visible on all tasks with correct colors
- [ ] Priority dropdown in task edit modal with current value selected
  - **Must verify:** Open edit modal and check dropdown
  - **Expected:** Dropdown shows 3 options, current priority selected
- [ ] Changing priority saves immediately and updates UI
  - **Must verify:** Change priority, verify API call and UI update
  - **Expected:** No page refresh needed, change persists
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck`
  - **Expected:** No errors
- [ ] Verify in browser using dev-browser skill
  - **Must verify:** Full flow: view badge, edit priority, verify change
  - **Expected:** All interactions work smoothly

**Depends on:** US-001 (requires priority column in database)
**Implementation hint:** Reuse existing badge component, just add color variants for priority.

### US-003: Filter tasks by priority
**Description:** As a user, I want to filter the task list to see only high-priority items when I'm focused.

**Acceptance Criteria:**
- [ ] Filter dropdown with options: All | High | Medium | Low
  - **Must verify:** Navigate to task list, check filter dropdown
  - **Expected:** 4 options visible and selectable
- [ ] Filter persists in URL params
  - **Must verify:** Select filter, check URL contains `?priority=high`
  - **Expected:** URL updates, refresh preserves filter
- [ ] Empty state message when no tasks match filter
  - **Must verify:** Filter to priority with no tasks
  - **Expected:** Shows "No tasks found" or similar message
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck`
  - **Expected:** No errors
- [ ] Verify in browser using dev-browser skill
  - **Must verify:** Test all filter options and URL persistence
  - **Expected:** Filtering works, URL updates correctly

**Depends on:** US-002 (requires priority display to filter)
**Implementation hint:** Check if existing filter pattern used elsewhere, follow same approach.

## Functional Requirements

- FR-1: Add `priority` field to tasks table ('high' | 'medium' | 'low', default 'medium')
- FR-2: Display colored priority badge on each task card
- FR-3: Include priority selector in task edit modal
- FR-4: Add priority filter dropdown to task list header
- FR-5: Sort by priority within each status column (high to medium to low)

## Non-Goals

- No priority-based notifications or reminders
- No automatic priority assignment based on due date
- No priority inheritance for subtasks

## Technical Considerations

- Reuse existing badge component with color variants
- Filter state managed via URL search params
- Priority stored in database, not computed

## Success Metrics

- Users can change priority in under 2 clicks
- High-priority tasks immediately visible at top of lists
- No regression in task list performance

## Open Questions

- Should priority affect task ordering within a column?
- Should we add keyboard shortcuts for priority changes?
