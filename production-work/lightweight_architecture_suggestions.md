# Making the Batch Process Lightweight

Running a heavy stored procedure (`usp_manage_employee_leaves`) for hundreds or thousands of employees in a single loop can cause **long-running transactions**, **table locks**, and **memory bloat** (which blocks other processes). 

To make this completely lightweight and non-blocking, you should move away from a single massive loop and adopt one of these optimized architectures:

### Option 1: The Queue/Staging Table Approach (Recommended)
Instead of trying to process everything at once, separate the "identification" from the "processing".

1. **Fast Identification**: Run a very fast, lightweight query that takes milliseconds. It identifies eligible employees and inserts them into a new table: `tbl_leave_upgrade_queue`.
    ```sql
    INSERT INTO tbl_leave_upgrade_queue (emp_id, account_id, target_template_id, status)
    SELECT b.emp_id, b.account_id, a.prob_prd_over_template, 'PENDING' ...
    ```
2. **Chunked Processing**: Have a Node.js cron job (or a scheduled DB job) run every 5 minutes. It reads `LIMIT 50` records from the queue, calls the `usp_process_employee_leave_template` for those 50, marks them as `COMPLETED`, and stops. 
    * **Why it's better**: The database is only locked for a few seconds at a time. It distributes the CPU load evenly and will never block your live application.

### Option 2: SQL Batching with Loop & Commit
If you must do it entirely within PostgreSQL, avoid opening a single giant cursor (which holds a snapshot lock on the data). Instead, process records in small chunks of `100` and `COMMIT` after each chunk.

```sql
LOOP
    -- Only lock and process 100 records at a time
    FOR r_employee IN (
        SELECT ... FROM tbl_tpleavebank a
        INNER JOIN public.tbl_employee_leavebank b ...
        WHERE b.status = '1' AND CURRENT_DATE >= ...
        LIMIT 100
    ) LOOP
        CALL public.usp_process_employee_leave_template(...);
    END LOOP;
    
    -- Exit the loop if less than 100 records were found (meaning we are done)
    EXIT WHEN NOT FOUND;
END LOOP;
```
* **Why it's better**: By using `LIMIT 100`, you prevent PostgreSQL from building a massive result set in memory, and the frequent `COMMIT`s inside your procedure will instantly release any row locks, preventing other users from being blocked.

### Option 3: Indexing
Whichever option you choose, ensure you have a composite index on the tables you are querying to make the initial `SELECT` blazing fast.
```sql
CREATE INDEX idx_emp_leavebank_status_eff ON public.tbl_employee_leavebank(status, effective_to);
CREATE INDEX idx_openappointments_doj ON public.openappointments(isactive, dateofjoining);
```

---
**Suggestion**: If you have thousands of employees, **Option 1** is the safest for a SaaS platform. It gives you full visibility into what's pending, what failed, and prevents database timeouts. If you want a quick fix, **Option 2** can be implemented right now inside the stored procedure.
