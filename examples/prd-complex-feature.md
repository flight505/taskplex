# PRD: User Notification System

## Introduction

Implement a comprehensive notification system to keep users informed of important events. Users should see a notification bell icon in the header, be able to view notifications, mark them as read, and configure notification preferences.

## Goals

- Notify users of important events (mentions, task assignments, deadlines)
- Provide centralized notification inbox
- Allow mark-as-read functionality
- Enable user control over notification preferences
- Support extensible notification types

## User Stories

### US-001: Create notifications database schema
**Description:** As a developer, I need to store notifications so they persist across sessions.

**Acceptance Criteria:**
- [ ] Create notifications table with columns: id, user_id, type, content, read, created_at
  - **Must verify:** `sqlite3 app.db ".schema notifications"`
  - **Expected:** Table present with all required columns
- [ ] Add foreign key constraint to users table
  - **Must verify:** `sqlite3 app.db "PRAGMA foreign_key_list(notifications)"`
  - **Expected:** Shows foreign key to users(id)
- [ ] Create index on (user_id, read, created_at) for efficient queries
  - **Must verify:** `sqlite3 app.db ".indexes notifications"`
  - **Expected:** Index exists
- [ ] Generate and run migration successfully
  - **Must verify:** `ls migrations/ | grep notifications`
  - **Expected:** Migration applies without errors
- [ ] Typecheck passes
  - **Must verify:** `pyright --project .`
  - **Expected:** No errors

### US-002: Create notification service (backend)
**Description:** As a developer, I need a service layer for creating and managing notifications.

**Acceptance Criteria:**
- [ ] Create NotificationService class with create_notification() method
  - **Must verify:** `grep -n "class NotificationService" services/`
  - **Expected:** Service class exists with method
- [ ] Implement get_unread_count(user_id) method
  - **Must verify:** `grep -n "get_unread_count" services/notification_service.py`
  - **Expected:** Method returns integer count
- [ ] Implement mark_as_read(notification_id) method
  - **Must verify:** `grep -n "mark_as_read" services/notification_service.py`
  - **Expected:** Method updates database record
- [ ] Add unit tests for all service methods
  - **Must verify:** `pytest tests/services/test_notification_service.py -v`
  - **Expected:** All tests pass
- [ ] Typecheck passes
  - **Must verify:** `pyright --project .`
  - **Expected:** No errors

**Depends on:** US-001 (requires notifications table)
**Implementation hint:** Follow pattern from existing UserService - similar CRUD operations.

### US-003: Create notification API endpoints
**Description:** As a frontend, I need API endpoints to fetch and update notifications.

**Acceptance Criteria:**
- [ ] GET /api/notifications returns paginated list for current user
  - **Must verify:** `curl -H "Authorization: Bearer $TOKEN" http://localhost:5000/api/notifications`
  - **Expected:** Returns JSON array with notifications
- [ ] GET /api/notifications/unread-count returns count as JSON
  - **Must verify:** `curl http://localhost:5000/api/notifications/unread-count`
  - **Expected:** Returns {"count": N}
- [ ] POST /api/notifications/:id/read marks notification as read
  - **Must verify:** `curl -X POST http://localhost:5000/api/notifications/1/read`
  - **Expected:** Returns 200 OK, notification marked read
- [ ] Add API tests for all endpoints
  - **Must verify:** `pytest tests/api/test_notifications.py -v`
  - **Expected:** All tests pass
- [ ] Typecheck passes
  - **Must verify:** `pyright --project .`
  - **Expected:** No errors

**Depends on:** US-002 (requires NotificationService)
**Implementation hint:** Check how TasksAPI is structured - follow same authentication/pagination pattern.

### US-004: Add notification bell icon to header (UI)
**Description:** As a user, I want to see a notification bell in the header showing unread count.

**Acceptance Criteria:**
- [ ] Bell icon appears in header next to user menu
  - **Must verify:** Navigate to app in browser
  - **Expected:** Bell icon visible in top-right area
- [ ] Unread count badge displays when notifications exist
  - **Must verify:** Create test notification, refresh page
  - **Expected:** Badge shows correct count
- [ ] Badge has red background and white text
  - **Must verify:** Inspect badge element styles
  - **Expected:** CSS shows background-color: red
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck`
  - **Expected:** No errors
- [ ] Verify in browser using dev-browser skill
  - **Must verify:** Full visual check of icon and badge
  - **Expected:** Matches design mockup

**Depends on:** US-003 (requires API to fetch count)
**Related to:** US-005 (dropdown will attach to this icon)
**Implementation hint:** Reuse existing IconButton component from header. Check HeaderUserMenu for positioning.

### US-005: Create notification dropdown panel (UI)
**Description:** As a user, I want to click the bell icon and see my recent notifications.

**Acceptance Criteria:**
- [ ] Clicking bell opens dropdown panel below icon
  - **Must verify:** Click bell icon in browser
  - **Expected:** Panel appears with list of notifications
- [ ] Panel shows last 10 notifications with title, content, timestamp
  - **Must verify:** Check panel content
  - **Expected:** Shows notification details correctly
- [ ] Unread notifications have blue background
  - **Must verify:** Inspect unread notification element
  - **Expected:** CSS shows background-color: light blue
- [ ] "View all" link at bottom navigates to full notifications page
  - **Must verify:** Click link
  - **Expected:** Navigates to /notifications
- [ ] Clicking outside panel closes it
  - **Must verify:** Open panel, click outside
  - **Expected:** Panel closes
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck`
  - **Expected:** No errors
- [ ] Verify in browser using dev-browser skill
  - **Must verify:** Test all interactions
  - **Expected:** Smooth UX, no layout issues

**Depends on:** US-004 (requires bell icon), US-003 (requires API)
**Implementation hint:** Similar to UserMenu dropdown - reuse Popover component and positioning logic.

### US-006: Add mark-as-read functionality (UI)
**Description:** As a user, I want to mark notifications as read by clicking them.

**Acceptance Criteria:**
- [ ] Clicking a notification marks it as read
  - **Must verify:** Click unread notification
  - **Expected:** Background color changes to white
- [ ] Unread count badge decrements immediately
  - **Must verify:** Check badge after marking read
  - **Expected:** Count reduces by 1
- [ ] Notification stays in list after marking read
  - **Must verify:** Verify notification still visible
  - **Expected:** Still in list, just different styling
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck`
  - **Expected:** No errors
- [ ] Verify in browser using dev-browser skill
  - **Must verify:** Test mark-as-read flow
  - **Expected:** Instant UI feedback, state persists

**Depends on:** US-005 (requires dropdown panel)
**Related to:** US-003 (uses mark-as-read API)
**Implementation hint:** US-003 already has the POST endpoint - just wire up onClick handler.

### US-007: Create notification preferences page (UI)
**Description:** As a user, I want to control which notification types I receive.

**Acceptance Criteria:**
- [ ] /notifications/preferences page displays toggle switches for each type
  - **Must verify:** Navigate to /notifications/preferences
  - **Expected:** Page shows list of notification types with toggles
- [ ] Toggling a switch saves preference immediately
  - **Must verify:** Toggle a switch
  - **Expected:** API call fires, success message shown
- [ ] Page shows current preferences on load
  - **Must verify:** Refresh page
  - **Expected:** Toggles reflect saved preferences
- [ ] Typecheck passes
  - **Must verify:** `npm run typecheck`
  - **Expected:** No errors
- [ ] Verify in browser using dev-browser skill
  - **Must verify:** Test all toggles and persistence
  - **Expected:** Settings save and load correctly

**Related to:** US-002 (may need to extend service for preferences)
**Implementation hint:** This might need a separate user_preferences table if not already present. Check existing schema first.

## Functional Requirements

- FR-1: Store notifications with user_id, type, content, read status, timestamp
- FR-2: API endpoints for fetching, counting, and marking notifications
- FR-3: Bell icon in header with unread count badge
- FR-4: Dropdown panel showing recent notifications
- FR-5: Click notification to mark as read
- FR-6: Preferences page for controlling notification types
- FR-7: Support extensible notification types (mention, assignment, deadline, etc.)

## Non-Goals

- No push notifications (browser or mobile)
- No email notifications
- No notification grouping/threading
- No notification search functionality
- No bulk mark-as-read operations

## Design Considerations

- Bell icon uses existing icon library (react-icons or similar)
- Dropdown panel max-width: 400px
- Notification item height: auto (multi-line content)
- Unread badge: red background (#ff4444), white text
- Unread notification: light blue background (#e3f2fd)

## Technical Considerations

- Notifications table needs proper indexing for performance
- API should paginate notifications list (10 per page)
- Consider using WebSocket for real-time updates (future enhancement)
- Dropdown panel uses Popover component from UI library
- Preferences stored in user_preferences table or users table

## Success Metrics

- Users can view notifications in <2 clicks
- Mark-as-read action completes in <500ms
- Notification count updates instantly on interaction
- No N+1 query issues with pagination

## Open Questions

- Should we add notification sound/desktop notifications?
- How long should notifications persist (30 days? 90 days?)?
- Should admins be able to send system-wide notifications?
