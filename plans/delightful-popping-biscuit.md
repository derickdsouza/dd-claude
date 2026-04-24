# UX Audit Implementation Plan (mfcapp-q3em)

## Context

The MFC Community App serves ~15-25 servant leaders managing community activities via a mobile-first PWA. A comprehensive UX audit identified issues across three severity levels. This plan addresses each UX pipeline independently (Servant, Member, Admin) while maintaining design cohesion across all flows.

**Key discovery**: The green color `#2D5A27` from an older branding era persists in 6+ files (ConfirmDialog, vite.config.ts, index.html, favicon.svg, CLAUDE.md, architecture.md) while the live design system uses navy `#1B3A5C`. This creates a visible color split on the app's most critical interaction (ConfirmDialog confirm button renders green while everything else is navy).

**Training/Speaker pages** (7 pages) are architectural scaffolds with no routes or navigation — they are out of scope for this audit.

---

## Phase 1 — Critical (Broken Navigation + Wrong Colors)

### 1.1 EventsPage: Add AppShell wrapper

**File**: `src/pages/EventsPage.tsx`

- Import `AppShell`, `EmptyState`, `ErrorMessage`, `ListSkeleton`, `Card`, `Badge` from `@/components/ui`
- Import `useNavigate`, `useLocation` from react-router-dom
- Add `fromAdmin` detection (same pattern as AttendancePage/UpcomingPage)
- Wrap entire return in `<AppShell title="Events" onBack={fromAdmin ? () => navigate('/admin') : undefined}>`
- Replace loading div (lines 37-46) with `<ListSkeleton count={3} />`
- Replace empty div (lines 48-54) with `<EmptyState title="No upcoming events" description="Events will appear here when scheduled." />`
- Replace error div (lines 56-62) with `<ErrorMessage message={view.message} />`
- Replace raw auth/scope error divs (lines 21-35) with `<EmptyState>` variants
- Replace inline event card divs (lines 71-85) with `<Card>` + `<Badge>` components
- Add `<ChevronRight>` icon to each event card to signal tappability (matching UpcomingPage card pattern)
- Remove duplicate empty check at line 67-69 (redundant with `view.kind === 'empty'`)

### 1.2 EventDetailPage: Add AppShell wrapper

**File**: `src/pages/EventDetailPage.tsx`

- Import `AppShell`, `EmptyState`, `ListSkeleton`, `Card`, `Badge`
- Import `useNavigate` from react-router-dom
- Wrap return in `<AppShell title={detail?.eventTypeName ?? 'Event'} onBack={() => navigate('/events')}>`
- Replace loading state (lines 15-22) with `<ListSkeleton count={2} />`
- Replace not-found state (line 25) with `<EmptyState title="Event not found" description="This event may have been removed." />`
- Replace inline activity divs (lines 43-50) with `<Card>` components
- Replace inline status badge (lines 35-37) with `<Badge variant="primary">`

### 1.3 ConfirmDialog: Replace hardcoded hex with design tokens

**File**: `src/components/ui/ConfirmDialog.tsx` (lines 39-41)

```
OLD: 'bg-[#DC2626] hover:bg-red-700 text-white'
NEW: 'bg-danger hover:bg-red-700 text-white'

OLD: 'bg-[#2D5A27] hover:bg-[#1E3D1A] text-white'
NEW: 'bg-primary hover:bg-primary-dark text-white'
```

**Test file**: `src/components/ui/__tests__/ConfirmDialog.test.tsx`
- Line 173: `'bg-[#DC2626]'` → `'bg-danger'`
- Line 184: `'bg-[#2D5A27]'` → `'bg-primary'`

### 1.4 MemberAttendanceCard: Fix "Saved" → "Saving..."

**File**: `src/components/attendance/MemberAttendanceCard.tsx` (line 47-48)

```
OLD: <span className="text-xs text-green-600 font-medium">Saved</span>
NEW: <span className="text-xs text-amber-500 font-medium">Saving&hellip;</span>
```

**Test file**: `src/components/attendance/__tests__/MemberAttendanceCard.test.tsx`
- Line 133: `'displays Saved indicator when saving'` → `'displays Saving indicator when in-progress'`
- Line 135: `'Saved'` → `'Saving\u2026'`
- Line 138: `'Saved'` → `'Saving\u2026'`
- Line 139: `'text-green-600'` → `'text-amber-500'`

### 1.5 UpcomingPage: Replace inline modal with ConfirmDialog

**File**: `src/pages/UpcomingPage.tsx`

- Import `ConfirmDialog` from `@/components/ui`
- Replace lines 107-122 (inline `<div className="fixed inset-0 bg-black/50...">`) with:
```tsx
<ConfirmDialog
  open={!!confirmMeeting}
  title="Re-enable Meeting?"
  message="This will restore the scheduled meeting for this week."
  confirmLabel="Re-enable"
  cancelLabel="Cancel"
  variant="primary"
  onConfirm={() => void handleReEnable()}
  onCancel={() => setConfirmMeeting(null)}
/>
```

**Depends on**: 1.3 (so the primary variant renders navy, not green)

### 1.6 Purge stale green #2D5A27 from all files

| File | Line | Change |
|------|------|--------|
| `CLAUDE.md` | 49 | `primary` #2D5A27 → #1B3A5C, `primaryLight` #E8F0E6 → #D4DEE8, `primaryDark` #1E3D1A → #122843 |
| `CLAUDE.md` | 51 | PWA theme color #2D5A27 → #1B3A5C |
| `index.html` | 7 | `content="#2D5A27"` → `content="#1B3A5C"` |
| `vite.config.ts` | 22 | `theme_color: '#2D5A27'` → `theme_color: '#1B3A5C'` |
| `public/favicon.svg` | 2 | `fill="#2D5A27"` → `fill="#1B3A5C"` |
| `architecture.md` | 563 | `"#2D5A27"` → `"#1B3A5C"` |
| `beads-issue-prompts.md` | 49,151,429 | All #2D5A27/#E8F0E6/#1E3D1A → #1B3A5C/#D4DEE8/#122843 |

**Verify**: `grep -r '#2D5A27' --include='*.{ts,tsx,html,svg,md,json}' .` should return 0 results (excluding node_modules, .beads, coverage, docs/beads).

### Phase 1 parallelization

```
Parallel: 1.1, 1.2, 1.3, 1.4, 1.6
Sequential after 1.3: 1.5
```

---

## Phase 2 — Refinement (Consistency Across Pipelines)

### 2.1 Loading states → ListSkeleton everywhere

| File | Lines | Replace inline pulse divs with |
|------|-------|-------------------------------|
| `src/pages/AttendancePage.tsx` | 119-125 | `<ListSkeleton count={4} />` |
| `src/pages/UpcomingPage.tsx` | 57-65 | `<ListSkeleton count={6} />` |
| `src/pages/MemberHomePage.tsx` | 19-29 | `<ListSkeleton count={4} />` |
| `src/pages/UpcomingWeekDetailPage.tsx` | 109-113 | `<ListSkeleton count={3} />` |
| `src/pages/MemberDetailPage.tsx` | 106 | Replace inline `animate-pulse` div with `<CardSkeleton />` (already uses CardSkeleton below, just fix first item) |

**ActivityFeed special case**: `src/components/activity/ActivityFeed.tsx` has its own inline `SkeletonCard` (lines 11-24). The ActivityCard layout (8x8 circle + small text) differs from CardSkeleton (larger). Leave ActivityFeed's skeleton as-is — it's a self-contained component with correct proportions.

### 2.2 Empty states → EmptyState component everywhere

| File | Lines | Replace raw text with |
|------|-------|-----------------------|
| `src/pages/UpcomingPage.tsx` | 67 | `<EmptyState title="No household assigned" description="Contact your household servant for more info." />` |
| `src/pages/UpcomingPage.tsx` | 69 | `<EmptyState icon={<Calendar />} title="No upcoming meetings" description="Meetings will appear here once scheduled." />` |
| `src/pages/MemberHomePage.tsx` | 31-35 | `<EmptyState icon={<Calendar />} title="No household assigned" description="Contact your household servant for more info." />` |
| `src/pages/MemberHomePage.tsx` | 37 | `<EmptyState title="No upcoming meetings" />` |
| `src/pages/UpcomingWeekDetailPage.tsx` | 121 | `<EmptyState title="Meeting not found" />` |
| `src/components/activity/ActivityFeed.tsx` | 43-49 | `<EmptyState icon={<Clock />} title="No recent activity" />` |

### 2.3 Error states → ErrorMessage component

**File**: `src/components/activity/ActivityFeed.tsx` (line 40)

```
OLD: <p className="text-sm text-red-600 px-4 py-3">{error}</p>
NEW: <ErrorMessage message={error} />
```

### 2.4 ProfilePage: Remove duplicate role badge

**File**: `src/pages/ProfilePage.tsx` (line 103)

Remove the `Role` row from the Account card:
```
DELETE: <div className="flex justify-between"><span className="text-gray-500">Role</span><Badge variant="primary">{roleName}</Badge></div>
```

The badge remains in the avatar hero section (line 96).

### 2.5 AdminDashboard: Quick Actions → 2-column card tiles

**File**: `src/pages/admin/AdminDashboardPage.tsx` (lines 79-113)

Replace the `flex flex-col gap-3` of stacked `<Button>` elements with a `grid grid-cols-2 gap-3` of `<Card>` tiles, matching the "My Household" section treatment already on this page (lines 121-154). Each tile:

```tsx
<Card padding="md" onClick={() => navigate('/admin/areas')}>
  <div className="flex flex-col items-center gap-2 py-2">
    <div className="p-2 bg-primary-light rounded-lg text-primary">
      <Map className="h-5 w-5" />
    </div>
    <p className="text-sm font-medium text-gray-700">Manage Areas</p>
  </div>
</Card>
```

Four tiles: Manage Areas (Map), Manage Chapters (BookOpen), Add Member (Users), Add Household (Home).

### 2.6 NotificationBell: Remove infinite bounce

**File**: `src/components/layout/NotificationBell.tsx` (line 100)

Remove `animate-bounce` from the unread count badge className. Static red badge is sufficient.

### Phase 2 parallelization

All 6 items are independent — can be fully parallelized.

---

## Phase 3 — Polish

### 3.1 BottomNav: Active tab indicator

**File**: `src/components/layout/BottomNav.tsx` (lines 28-33)

Add a subtle pill background behind the active icon:

```tsx
<span className={`flex items-center justify-center rounded-lg px-3 py-1 transition-colors ${
  active ? 'bg-primary/10' : ''
}`}>
  {item.icon}
</span>
```

### 3.2 Header: Add elevation shadow

**File**: `src/components/layout/Header.tsx` (line 14)

Add `shadow-sm` to the header className.

### 3.3 ProgressBar: Inline styles → Tailwind

**File**: `src/components/ui/ProgressBar.tsx` (lines 26, 29)

- Track div: Remove `style={{ height: 6 }}`, add `h-1.5` to className
- Fill div: Remove `height: 6` from style (keep `width: \`${clamped}%\``), add `h-1.5` to className

### 3.4 Toggle: Inline styles → Tailwind

**File**: `src/components/ui/Toggle.tsx` (lines 33, 40)

- Track: Remove `style={{ width: 44, height: 28 }}`, add `w-11 h-7` to className
- Thumb: Remove `style={{ width: 22, height: 22 }}`, add `w-[22px] h-[22px]` to className

### 3.5 ToastContainer: Replace hardcoded hex with tokens

**File**: `src/components/ui/ToastContainer.tsx` (lines 5-9, 19-24)

```
BORDER:  'border-l-[#16A34A]' → 'border-l-success'
         'border-l-[#DC2626]' → 'border-l-danger'
         'border-l-[#F59E0B]' → 'border-l-warning'

ICON_COLOR: 'text-[#16A34A]' → 'text-success'
            'text-[#DC2626]' → 'text-danger'
            'text-[#F59E0B]' → 'text-warning'
```

### 3.6 Period filter pills: Differentiate from activity toggles

**File**: `src/pages/ReportsPage.tsx` (lines 119-131)

Change inactive state from `bg-gray-100` to `border border-gray-200 bg-white` to distinguish "view filter" pills from "data toggle" pills in MemberAttendanceCard. This is a subtle but intentional distinction.

### Phase 3 parallelization

All 6 items are independent — can be fully parallelized.

---

## Pipeline Impact Summary

| Pipeline | Phase 1 | Phase 2 | Phase 3 |
|----------|---------|---------|---------|
| **Servant** (5 tabs, primary users) | 1.1, 1.2, 1.4, 1.5 | 2.1, 2.2, 2.3 | 3.1, 3.2, 3.6 |
| **Member** (2 tabs, read-only) | — | 2.1, 2.2, 2.4 | 3.1, 3.2 |
| **Admin** (5 tabs, management) | — | 2.5, 2.6 | 3.1, 3.2 |
| **Cross-cutting** (all roles) | 1.3, 1.6 | — | 3.3, 3.4, 3.5 |

---

## Verification

After each phase, run the full quality gate:

```bash
bun run lint:fix && bun run type-check && bun run test:run
```

### Phase 1 smoke tests
1. Navigate to `/events` — Header + BottomNav visible, section logo present
2. Navigate to `/events/:id` — back button returns to `/events`
3. Trigger ConfirmDialog sign-out — confirm button is navy (not green)
4. Toggle attendance — "Saving..." in amber appears during write
5. UpcomingPage re-enable → ConfirmDialog with focus trap, not inline modal
6. `grep -r '#2D5A27' . --include='*.{ts,tsx,html,svg}'` → 0 results (excl. node_modules, .beads)

### Phase 2 smoke tests
1. All loading states render ListSkeleton (card-shaped pulse blocks)
2. All empty states render EmptyState (centered icon + title + description)
3. ProfilePage shows role badge once (hero only, not in Account card)
4. AdminDashboard Quick Actions are 2x2 card grid (matches My Household section)
5. Notification badge is static (no bouncing)

### Phase 3 smoke tests
1. BottomNav active tab has subtle pill background
2. Header has shadow separating it from content
3. Toasts show correct left-border colors
4. Toggle and ProgressBar render correctly without inline styles
