# Full Optimization Audit

### 1) Optimization Summary

Current optimization health is **medium risk**: the codebase is functional, but public listing flows and admin notification/listing flows still perform more work than necessary and will scale poorly under heavier traffic.

Top 3 highest-impact improvements:
- Consolidate repeated public `businesses.php` fetches and stop requesting oversized result sets from the homepage and listing pages.
- Replace multi-timer admin polling with a single summary-first strategy plus backoff/visibility throttling.
- Trim server-side payload assembly and DB work on public listing endpoints, especially image/service-heavy responses.

Biggest risk if no changes are made:
- Public traffic and open admin tabs will multiply DB/API load faster than user growth, causing rising latency, unnecessary bandwidth cost, and unstable UX during peak usage.

Assumptions:
- No production traces, `EXPLAIN`, or browser profiles were provided.
- Findings marked as likely are inferred from code paths and should be validated with measurement before larger refactors.

### 2) Findings (Prioritized)

- **Title**: Duplicate full-dataset fetches from the homepage
- **Category**: Network
- **Severity**: High
- **Impact**: Reduces homepage bandwidth, JSON parse cost, client memory, and backend load.
- **Evidence**: [js/index.js](C:/xampp/htdocs/webey/js/index.js#L1314) fetches `/api/public/businesses.php?status=active&limit=400` to build a search index, and [js/index.js](C:/xampp/htdocs/webey/js/index.js#L2102) fetches `/api/public/businesses.php?status=active&limit=100` again for recommended cards.
- **Why it’s inefficient**: The page downloads overlapping business payloads twice, including services/images data that are not all needed for both features.
- **Recommended fix**: Fetch once, cache in-memory, and derive both the search index and recommended carousel from the same normalized dataset. If the search bar only needs lightweight fields, introduce a slimmer endpoint or query mode.
- **Tradeoffs / Risks**: Requires careful normalization so current UI fields stay intact.
- **Expected impact estimate**: High on homepage load; likely 30-60% lower data transfer for this flow.
- **Removal Safety**: Likely Safe
- **Reuse Scope**: module
- **Classification**: Reuse Opportunity

- **Title**: Listing page pulls far more businesses than it renders
- **Category**: I/O
- **Severity**: High
- **Impact**: Improves list-page latency, lowers backend CPU, and reduces client-side filtering cost.
- **Evidence**: [js/kuafor.js](C:/xampp/htdocs/webey/js/kuafor.js#L750) requests `/api/public/businesses.php?status=active&limit=500`, then [js/kuafor.js](C:/xampp/htdocs/webey/js/kuafor.js#L871) clones and filters the full array in the browser.
- **Why it’s inefficient**: The browser downloads and filters a large payload even when the user only sees a subset. This shifts search/filter work to the client and repeats it on every filter interaction.
- **Recommended fix**: Push filtering/pagination/sorting server-side for the main list flow, or migrate this page to `api/public/salons.php` as the primary source and keep client filtering only for already-visible items.
- **Tradeoffs / Risks**: API contract alignment is needed because the page currently expects `businesses.php` field names.
- **Expected impact estimate**: High for public traffic; likely 40%+ lower payload and noticeably lower main-thread work.
- **Removal Safety**: Needs Verification
- **Reuse Scope**: service-wide
- **Classification**: Over-Abstracted Code

- **Title**: Public businesses endpoint builds heavy per-row payloads
- **Category**: CPU
- **Severity**: High
- **Impact**: Reduces PHP CPU time, response size, and client parse overhead.
- **Evidence**: [api/public/businesses.php](C:/xampp/htdocs/webey/api/public/businesses.php) fetches businesses, then performs extra service and hours queries for all IDs, and finally decodes/transforms image JSON again per row via `bizImagesObj()` and `bizCoverUrl()` before returning a large composite object.
- **Why it’s inefficient**: This endpoint is used as a general-purpose data source for multiple screens, so it performs expensive enrichment even when callers only need a small subset of fields.
- **Recommended fix**: Split response modes by use case, such as lightweight cards/search payload vs full profile/list payload. Precompute cover image metadata at write-time if possible.
- **Tradeoffs / Risks**: Multiple consumers already depend on current JSON field names, so additive modes are safer than breaking changes.
- **Expected impact estimate**: High on high-traffic public pages; medium otherwise.
- **Removal Safety**: Needs Verification
- **Reuse Scope**: service-wide
- **Classification**: Reuse Opportunity

- **Title**: Notification system fans out into multiple overlapping polls
- **Category**: Network
- **Severity**: High
- **Impact**: Lowers admin-side QPS, improves tab scalability, and reduces duplicate unread-count work.
- **Evidence**: [js/wb-notifications.js](C:/xampp/htdocs/webey/js/wb-notifications.js#L14) defines separate 30s, 20s, 60s, and 120s timers; [js/wb-notifications.js](C:/xampp/htdocs/webey/js/wb-notifications.js#L797) starts all of them together; [js/wb-notifications.js](C:/xampp/htdocs/webey/js/wb-notifications.js#L386), [js/wb-notifications.js](C:/xampp/htdocs/webey/js/wb-notifications.js#L731), and [js/wb-notifications.js](C:/xampp/htdocs/webey/js/wb-notifications.js#L823) repeatedly fetch notification lists.
- **Why it’s inefficient**: Each open admin tab repeats overlapping reads for badge counts, panel bootstrap, cancellations, subscriptions, and session status.
- **Recommended fix**: Collapse to one summary endpoint or one primary poll loop, then fetch full details only when the panel opens or the summary changes. Add visibility-aware throttling and exponential backoff with jitter.
- **Tradeoffs / Risks**: Requires frontend/backend contract cleanup and careful migration to avoid missed notifications.
- **Expected impact estimate**: High; likely 30-70% fewer notification requests in multi-tab/admin scenarios.
- **Removal Safety**: Needs Verification
- **Reuse Scope**: service-wide
- **Classification**: Reuse Opportunity

- **Title**: Notification script injects large DOM/CSS payload globally
- **Category**: Frontend
- **Severity**: Medium
- **Impact**: Lowers parse/execute cost and reduces unnecessary DOM/style work on admin pages that never open the panel.
- **Evidence**: [js/wb-notifications.js](C:/xampp/htdocs/webey/js/wb-notifications.js#L109) can inject floating bell, panel HTML, audio, and large inline styles at runtime, while [js/wb-notifications.js](C:/xampp/htdocs/webey/js/wb-notifications.js#L1026) initializes on every page load.
- **Why it’s inefficient**: UI shell code, styles, and observers are created even before the user interacts with notifications.
- **Recommended fix**: Lazy-initialize the panel DOM/styles on first bell interaction, while keeping only a lightweight badge/bootstrap path at startup.
- **Tradeoffs / Risks**: The first bell open may become slightly slower unless prewarmed.
- **Expected impact estimate**: Medium on slower devices and admin pages with many scripts.
- **Removal Safety**: Likely Safe
- **Reuse Scope**: module
- **Classification**: Dead Code

- **Title**: Server-side salons query still computes rating aggregates on read
- **Category**: DB
- **Severity**: Medium
- **Impact**: Improves public list latency and reduces DB sort/aggregate cost.
- **Evidence**: [api/public/salons.php](C:/xampp/htdocs/webey/api/public/salons.php) performs a count query, then a second grouped query with `LEFT JOIN reviews`, `AVG`, `COUNT`, optional `HAVING`, and dynamic sort.
- **Why it’s inefficient**: Aggregate-on-read is expensive for listing traffic, especially when sorting by rating or filtering by minimum rating.
- **Recommended fix**: Store denormalized `avg_rating` and `review_count` on `businesses` or in a summary table updated asynchronously.
- **Tradeoffs / Risks**: Requires eventual-consistency handling for new review visibility changes.
- **Expected impact estimate**: Medium to High depending on review volume.
- **Removal Safety**: Needs Verification
- **Reuse Scope**: service-wide
- **Classification**: Reuse Opportunity

- **Title**: Full list re-render and carousel rebind on each filter change
- **Category**: Frontend
- **Severity**: Medium
- **Impact**: Improves responsiveness on mobile and reduces event/listener churn.
- **Evidence**: [js/kuafor.js](C:/xampp/htdocs/webey/js/kuafor.js#L930) rewrites `grid.innerHTML` for the entire result set and immediately calls [js/kuafor.js](C:/xampp/htdocs/webey/js/kuafor.js#L1676) `initCarousels(grid)` after each filter/render path.
- **Why it’s inefficient**: Full DOM replacement invalidates prior state and reattaches per-card carousel listeners even when only filters changed.
- **Recommended fix**: Paginate visible cards, virtualize or chunk long lists, and avoid carousel initialization until cards become visible or hovered.
- **Tradeoffs / Risks**: More complex UI state management.
- **Expected impact estimate**: Medium; especially valuable on low-end phones.
- **Removal Safety**: Likely Safe
- **Reuse Scope**: module
- **Classification**: Over-Abstracted Code

- **Title**: Global mutation observers stay active for broad document scopes
- **Category**: Frontend
- **Severity**: Medium
- **Impact**: Reduces background main-thread work and unexpected observer churn.
- **Evidence**: [js/index.js](C:/xampp/htdocs/webey/js/index.js#L282) observes the full `document.body` subtree to keep auth buttons bound; [js/kuafor.js](C:/xampp/htdocs/webey/js/kuafor.js#L316) watches the full document to bump DOB overlay z-index.
- **Why it’s inefficient**: Wide-scope observers run on unrelated DOM mutations and are easy to forget, especially on script-heavy pages.
- **Recommended fix**: Scope observers to narrow containers, disconnect once the target state is reached, or replace with event delegation and explicit lifecycle hooks.
- **Tradeoffs / Risks**: If the page relies on late DOM injection, observer scope changes must be tested carefully.
- **Expected impact estimate**: Medium in long-lived sessions; low in short sessions.
- **Removal Safety**: Likely Safe
- **Reuse Scope**: local file
- **Classification**: Dead Code

- **Title**: Google login depends on synchronous remote token verification
- **Category**: Reliability
- **Severity**: Medium
- **Impact**: Improves auth latency consistency and reduces third-party dependency stalls.
- **Evidence**: [api/auth/google-login.php](C:/xampp/htdocs/webey/api/auth/google-login.php#L60) performs `file_get_contents()` against Google's tokeninfo endpoint with a 5-second timeout on the login critical path.
- **Why it’s inefficient**: Every Google login depends on a blocking external network call, so latency and availability are coupled to a third-party service.
- **Recommended fix**: Verify ID tokens locally using cached Google JWKs and a JWT library, refreshing keys on TTL.
- **Tradeoffs / Risks**: Key rotation and claim validation must be implemented correctly.
- **Expected impact estimate**: Medium; lower p95 auth latency and fewer transient login failures.
- **Removal Safety**: Needs Verification
- **Reuse Scope**: module
- **Classification**: Reuse Opportunity

- **Title**: Homepage uses continuous timers for decorative effects
- **Category**: Frontend
- **Severity**: Low
- **Impact**: Small CPU/battery savings, especially on mobile.
- **Evidence**: [js/index.js](C:/xampp/htdocs/webey/js/index.js#L450) runs `setInterval(cycleText, 2500)` for the hero title regardless of visibility.
- **Why it’s inefficient**: The timer keeps firing even when the hero is off-screen or the tab is backgrounded.
- **Recommended fix**: Pause decorative timers on `document.hidden`, or replace with CSS animation where practical.
- **Tradeoffs / Risks**: Minimal, mostly UX timing differences.
- **Expected impact estimate**: Low individually, but worthwhile as a quick cleanup.
- **Removal Safety**: Safe
- **Reuse Scope**: local file
- **Classification**: Dead Code

### 3) Quick Wins (Do First)

- Reuse a single homepage business dataset for both search indexing and recommended cards.
- Lower or eliminate `limit=500` public fetches from `kuafor.js`; move filtering/pagination closer to the API.
- Merge notification badge/panel/subscription polling into one poll cadence before attempting bigger architectural changes.
- Add a lightweight response mode to `api/public/businesses.php` so pages can avoid requesting images/services/hours when they do not need them.
- Disconnect or narrow broad `MutationObserver` usage where the target state is already known.

### 4) Deeper Optimizations (Do Next)

- Introduce server-driven pagination and filter contracts for the public salon listing flow.
- Denormalize review aggregates for public ranking/filtering instead of computing `AVG/COUNT` on every list request.
- Move admin notifications toward SSE/WebSocket, with polling only as fallback.
- Split large frontend modules into smaller page-specific responsibilities so parse cost and profiling become manageable.
- Add endpoint-level response caching for common public list/search combinations with short TTL and normalized cache keys.

### 5) Validation Plan

- **Benchmarks**
  - Compare homepage load with one combined businesses fetch vs current dual-fetch design.
  - Load test `GET /api/public/businesses.php` and `GET /api/public/salons.php` at 1x, 5x, and 10x expected concurrency.
  - Simulate multiple open admin tabs to measure notification polling amplification.

- **Profiling strategy**
  - Browser: use Performance panel on `index.html` and `kuafor.html` to measure script evaluation, DOM update cost, and long tasks.
  - PHP/DB: log query count, total SQL time, and response size for the two public listing endpoints.
  - Network: compare payload bytes before/after lighter endpoint modes and reduced polling.

- **Metrics to compare before/after**
  - Public pages: p50/p95 latency, transferred KB, JSON parse time, Largest Contentful Paint, main-thread blocking time.
  - Admin pages: requests/minute per open tab, unread-badge sync latency, notification API p95.
  - Backend: rows scanned, DB CPU, and average bytes per response.

- **Test cases to ensure correctness is preserved**
  - Public list filters still return the same visible businesses for city/district/query/time combinations.
  - Homepage recommended cards still render correctly with the shared dataset path.
  - Notification badge counts remain correct across read/unread transitions and tab visibility changes.
  - Google login still validates issuer/audience/email verification correctly after local token verification changes.

### 6) Optimized Code / Patch (when possible)

The following are proposal snippets only. No source files were changed in this audit pass.

```js
// index.js: fetch once, derive multiple views
let businessesCachePromise;

function loadBusinessesOnce() {
  if (!businessesCachePromise) {
    businessesCachePromise = fetch("/api/public/businesses.php?status=active&limit=200")
      .then(r => r.ok ? r.json() : { ok: false })
      .then(j => Array.isArray(j.data) ? j.data : []);
  }
  return businessesCachePromise;
}

async function ensureSalonIndex() {
  const items = await loadBusinessesOnce();
  // derive search index from items
}

async function loadRecommended() {
  const items = await loadBusinessesOnce();
  // derive carousel cards from same items
}
```

```js
// wb-notifications.js: single loop with visibility-aware cadence
let notifTimer = null;

async function pollNotificationsSummary() {
  if (!_isAdmin) return;
  const hidden = document.hidden;
  const interval = hidden ? 120000 : 30000;

  try {
    const res = await apiFetch('/api/notifications/list.php?limit=50');
    if (res?.ok) {
      const items = res.data?.items || [];
      applyBellCount(items.filter(n => !n.isRead).length);
    }
  } finally {
    clearTimeout(notifTimer);
    notifTimer = setTimeout(pollNotificationsSummary, interval);
  }
}
```

```php
// api/public/businesses.php: lightweight mode idea
$mode = $_GET['mode'] ?? 'full';

if ($mode === 'card') {
    // select only fields required by homepage/list cards
    // skip service + hours enrichment
}
```
