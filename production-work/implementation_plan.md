# Auto-Upgrade Probation Leave Templates

## Goal Description
Create a new PostgreSQL batch procedure (`usp_auto_upgrade_probation_templates`) to automate the transition of employee leave templates when their probation period ends. This implements the 3 exact steps provided.

> [!NOTE]
> You mentioned "no use payrollingdb". I am assuming you meant "**Note: use payrollingdb**" and this script will be executed within your `payrollingdb` database. If you meant something else, please let me know!

## Proposed Changes

### [NEW] `usp_auto_upgrade_probation_templates.sql`
We will create a new stored procedure in the `payrollingdb` database that acts as a background job/cron worker.

It will implement the 3 steps exactly as requested:

#### 1. Get the template list for which the probation rule is applicable
We will query the database to find distinct active templates where `is_probation_prd_enable = 'Y'`.
```sql
-- Step 1: Identify templates with probation rules enabled
FOR r_template IN (
    SELECT DISTINCT template_id, template_txt::jsonb AS template_json
    FROM tbl_employee_leavebank
    WHERE status = '1' 
      AND (template_txt::jsonb->0->'leave_details'->>'is_probation_prd_enable') = 'Y'
) LOOP
```

#### 2. Get the employees of those templates & target template details
For each template found in step 1, we will find the active employees who have exceeded their probation period (in days). We will also fetch the target template (`prob_prd_over_template`) that they should be upgraded to.
```sql
    -- Extract Probation Days and Target Template ID from the JSON configuration
    v_probation_days := (r_template.template_json->0->'leave_details'->>'probation_prd_months')::INT;
    v_target_template_id := (r_template.template_json->0->'leave_details'->>'prob_prd_over_template')::BIGINT;
    
    -- Step 2: Get employees whose probation is over
    FOR r_employee IN (
        SELECT elb.emp_id, elb.account_id, emp.dateofjoining
        FROM tbl_employee_leavebank elb
        JOIN openappointments emp 
          ON elb.emp_id = emp.emp_id AND elb.account_id = emp.customeraccountid
        WHERE elb.template_id = r_template.template_id
          AND elb.status = '1'
          AND elb.effective_to IS NULL
          AND emp.isactive = '1'
          -- Check if CURRENT_DATE has surpassed DOJ + Probation Days
          AND CURRENT_DATE >= (emp.dateofjoining + (v_probation_days || ' days')::interval)
    ) LOOP
        
        -- Get the Target Template JSON Details (The template we want to change to)
        SELECT template_txt INTO v_target_template_txt
        FROM tbl_employee_leavebank -- Or the master template table
        WHERE template_id = v_target_template_id 
          AND status = '1' 
        LIMIT 1;
```

#### 3. Change the template
For every eligible employee, we will dynamically call the wrapper procedure (`usp_process_employee_leave_template`) we built earlier to assign them to the new template, which includes full logging and error handling.
```sql
        -- Step 3: Now change the template
        CALL public.usp_process_employee_leave_template(
            p_account_id => r_employee.account_id::VARCHAR,
            p_emp_id => r_employee.emp_id::VARCHAR,
            p_template_id => v_target_template_id::VARCHAR,
            p_user_ip => 'SYSTEM_AUTO',
            p_user_by => 'SYSTEM_BATCH',
            p_leave_template_json => v_target_template_txt::JSONB,
            p_effective_date => to_char(CURRENT_DATE, 'dd-mm-yyyy')
        );
```

## Open Questions
> [!IMPORTANT]
> 1. In Step 2, to get the target template JSON details, should I query `tbl_employee_leavebank` using a `LIMIT 1` for an employee that already has that template, or is there a specific Master Template table (like `tbl_tpemp_leavetemplates` or `mst_templates`) where the raw JSON is stored?
> 2. Do you want this procedure to log its summary execution (e.g. "Processed 50 employees") into a separate batch log table?
