# Performance Optimization: `vw_openappointments`

## Current State Analysis

### Tables Involved
| Table | Type | Rows (est.) | Size |
|---|---|---|---|
| `openappointments` | Regular Table | ~3,868 | 8 MB |
| `mst_tp_designations` | Regular Table | ~226 | 88 kB |

### Root Cause of Slowness

The view is **NOT slow because of foreign tables** (both tables are regular local tables).
The real performance issues are:

---

## 🔴 Issue 1: Missing Index on JOIN Column `designation_id`

The JOIN condition is:
```sql
LEFT JOIN mst_tp_designations mtd_designation
    ON mtd_designation.dsignationid = op.designation_id
   AND op.customeraccountid = mtd_designation.account_id
```

**Problem:**
- `openappointments.designation_id` has **NO index** → every row triggers a lookup without index help
- `mst_tp_designations.account_id` has **NO index** → the second JOIN condition is also unindexed
- Only `dsignationid_pkey` exists on `mst_tp_designations` (on `dsignationid` alone)
- PostgreSQL must do a **nested-loop full scan** or **hash join** for each row

**Fix — Add missing index:**
```sql
-- On openappointments: index the join key designation_id
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_openappointments_designation_id
    ON public.openappointments (designation_id);

-- On mst_tp_designations: composite index for both join conditions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_mst_tp_desig_id_accountid
    ON public.mst_tp_designations (dsignationid, account_id);
```

---

## 🔴 Issue 2: Duplicate Indexes on `openappointments`

There are **two redundant indexes** on `customeraccountid`:
- `idx_openapp_customeraccid` (customeraccountid)
- `idx_openappointments_customerid` (customeraccountid)

These slow down **INSERT/UPDATE** without helping reads. Drop one:
```sql
DROP INDEX CONCURRENTLY IF EXISTS public.idx_openappointments_customerid;
```

Also, `emp_code` has **three overlapping indexes**:
- `openappointments_emp_code_key` (unique)
- `idx_openappointments_empcode`
- `idx_openappointments_emp_code_emp_id` (composite)

The non-unique single-column one is redundant:
```sql
DROP INDEX CONCURRENTLY IF EXISTS public.idx_openappointments_empcode;
```

---

## 🟡 Issue 3: `SELECT *` / Wide Row from View

The view selects **200+ columns** from `openappointments`. When calling code uses `SELECT * FROM vw_openappointments`, PostgreSQL fetches the entire 8 MB of data.

**Fix:** Always filter in the calling query:
```sql
-- Bad (fetches everything):
SELECT * FROM vw_openappointments;

-- Good (filter early):
SELECT emp_id, emp_name, post_offered, designation_id
FROM vw_openappointments
WHERE customeraccountid = 123
  AND isactive = '1';
```

---

## 🟡 Issue 4: COALESCE on JOIN Result (minor)

```sql
COALESCE(NULLIF(mtd_designation.designationname::text, ''), op.post_offered::text)
```
This is fine logically, but the `::text` cast on every row adds minor overhead. It can stay as-is unless profiling shows otherwise.

---

## ✅ Best Fix: Convert to Materialized View (if data is read-heavy)

If this view is queried **many times per minute** but data changes infrequently (e.g., appointments added/updated occasionally), convert it to a **Materialized View** for near-instant reads:

```sql
-- Step 1: Create the materialized view
CREATE MATERIALIZED VIEW public.mvw_openappointments AS
SELECT op.emp_id,
    op.emp_name,
    op.converted,
    op.offered_salary,
    op.appointment_status_id,
    COALESCE(NULLIF(mtd_designation.designationname::text, ''), op.post_offered::text) AS post_offered,
    -- ... all other columns ...
    op.designation_id,
    op.department_id,
    op.blood_group,
    op.emergency_contact_person,
    op.project_id
FROM openappointments op
LEFT JOIN mst_tp_designations mtd_designation
    ON mtd_designation.dsignationid = op.designation_id
   AND op.customeraccountid = mtd_designation.account_id
WITH DATA;

-- Step 2: Add indexes on the materialized view for fast filtering
CREATE INDEX ON public.mvw_openappointments (customeraccountid);
CREATE INDEX ON public.mvw_openappointments (emp_id);
CREATE INDEX ON public.mvw_openappointments (designation_id);
CREATE INDEX ON public.mvw_openappointments (isactive);

-- Step 3: Grant permissions
ALTER MATERIALIZED VIEW public.mvw_openappointments OWNER TO hrmsdb;

-- Step 4: Refresh strategy
-- Option A - Manual refresh (call after bulk inserts)
REFRESH MATERIALIZED VIEW CONCURRENTLY public.mvw_openappointments;

-- Option B - Schedule via pg_cron (every 5 minutes)
SELECT cron.schedule('refresh_mvw_openappointments', '*/5 * * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY public.mvw_openappointments');
```

> [!IMPORTANT]
> `REFRESH MATERIALIZED VIEW CONCURRENTLY` requires at least one **unique index**. Add:
> ```sql
> CREATE UNIQUE INDEX ON public.mvw_openappointments (emp_id);
> ```

---

## Priority Action Plan

| Priority | Action | Impact |
|---|---|---|
| 🔴 **High** | Add `idx_openappointments_designation_id` | Fixes slow JOIN |
| 🔴 **High** | Add composite index on `mst_tp_designations(dsignationid, account_id)` | Fixes JOIN lookup |
| 🟡 **Medium** | Drop duplicate `idx_openappointments_customerid` | Speeds up writes |
| 🟡 **Medium** | Always add `WHERE` filters on calling queries | Reduces data volume |
| 🟢 **Optional** | Convert to Materialized View + schedule refresh | Best for read-heavy scenarios |

---

## Quick Fix Script (Run Immediately)

```sql
-- 1. Fix the JOIN performance
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_openappointments_designation_id
    ON public.openappointments (designation_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_mst_tp_desig_id_accountid
    ON public.mst_tp_designations (dsignationid, account_id);

-- 2. Remove duplicate indexes
DROP INDEX CONCURRENTLY IF EXISTS public.idx_openappointments_customerid;
DROP INDEX CONCURRENTLY IF EXISTS public.idx_openappointments_empcode;

-- 3. Analyze tables to update statistics
ANALYZE public.openappointments;
ANALYZE public.mst_tp_designations;
```
