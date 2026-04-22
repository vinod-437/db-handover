-- ==============================================================================
-- 1. Log Table DDL
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.tbl_employee_leave_template_log (
    log_id BIGSERIAL PRIMARY KEY,
    emp_id VARCHAR(50),
    account_id VARCHAR(50),
    template_id VARCHAR(50),
    request_json JSONB,
    response_message TEXT,
    status VARCHAR(20), -- 'SUCCESS' or 'FAILED'
    error_message TEXT,
    created_on TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(50),
    user_ip VARCHAR(50)
);

CREATE INDEX IF NOT EXISTS idx_leave_log_emp_account ON public.tbl_employee_leave_template_log(account_id, emp_id);

-- ==============================================================================
-- 2. Core Function: usp_apply_employee_leave_template
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.usp_apply_employee_leave_template(
    p_account_id VARCHAR,
    p_emp_id VARCHAR,
    p_template_id VARCHAR,
    p_user_ip VARCHAR,
    p_user_by VARCHAR,
    p_leave_template_json JSONB,
    p_effective_date VARCHAR
)
RETURNS JSON AS $$
DECLARE
    v_response TEXT;
    v_response_json JSON;
BEGIN
    -- 1. Validate mandatory inputs (Null and empty string checks)
    IF COALESCE(p_account_id, '') = '' OR COALESCE(p_emp_id, '') = '' OR COALESCE(p_template_id, '') = '' THEN
        RETURN json_build_object('msgcd', '0', 'msg', 'Account ID, Employee ID, or Template ID cannot be null or empty.');
    END IF;

    IF p_leave_template_json IS NULL OR jsonb_typeof(p_leave_template_json) = 'null' THEN
        RETURN json_build_object('msgcd', '0', 'msg', 'Leave Template JSON cannot be null.');
    END IF;

    -- 2. Idempotency Check: Verify if the template is already currently active for the employee
    IF EXISTS (
        SELECT 1 
        FROM tbl_employee_leavebank 
        WHERE account_id = p_account_id::BIGINT 
          AND emp_id = p_emp_id::BIGINT 
          AND status = '1' 
          AND template_id = p_template_id::BIGINT
    ) THEN
        RETURN json_build_object('msgcd', '1', 'msg', 'Template is already active for this employee. No action taken.');
    END IF;

    -- 3. Call the base function
    SELECT * INTO v_response 
    FROM public.usp_manage_employee_leaves(
        p_action => 'change_employee_leave_template',
        p_account_id => p_account_id,
        p_emp_id => p_emp_id,
        p_template_id => p_template_id,
        p_user_ip => p_user_ip,
        p_user_by => p_user_by,
        p_leavetemplate_text => p_leave_template_json::TEXT,
        p_effective_dt => p_effective_date
    );

    -- 4. Safely parse the text response into JSON format
    BEGIN
        v_response_json := v_response::JSON;
    EXCEPTION WHEN OTHERS THEN
        v_response_json := json_build_object('msgcd', '0', 'msg', 'Invalid JSON response from inner function.', 'raw_response', v_response);
    END;

    RETURN v_response_json;
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- 3. Wrapper Stored Procedure: usp_process_employee_leave_template
-- ==============================================================================
CREATE OR REPLACE PROCEDURE public.usp_process_employee_leave_template(
    p_account_id VARCHAR,
    p_emp_id VARCHAR,
    p_template_id VARCHAR,
    p_user_ip VARCHAR,
    p_user_by VARCHAR,
    p_leave_template_json JSONB,
    p_effective_date VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_response JSON;
    v_status VARCHAR(20);
    v_response_message TEXT;
    v_error_message TEXT := NULL;
    v_msgcd VARCHAR;
BEGIN
    -- 1. Call the core processing function
    SELECT public.usp_apply_employee_leave_template(
        p_account_id,
        p_emp_id,
        p_template_id,
        p_user_ip,
        p_user_by,
        p_leave_template_json,
        p_effective_date
    ) INTO v_response;

    -- 2. Extract Response Values
    v_msgcd := v_response->>'msgcd';
    v_response_message := v_response->>'msg';

    -- 3. Handle Logical Transaction Success/Failure
    IF v_msgcd = '1' THEN
        v_status := 'SUCCESS';
    ELSE
        v_status := 'FAILED';
        ROLLBACK; -- Rollback any partial database modifications if the logic returned failure
    END IF;

    -- 4. Write to Log Table and Commit
    INSERT INTO public.tbl_employee_leave_template_log (
        emp_id, account_id, template_id, request_json, response_message, status, error_message, created_by, user_ip
    ) VALUES (
        p_emp_id, p_account_id, p_template_id, p_leave_template_json, v_response_message, v_status, v_error_message, p_user_by, p_user_ip
    );
    COMMIT; -- Permanently save the logs and logical changes

EXCEPTION WHEN OTHERS THEN
    -- 5. Exception Handling & Safe Logging
    v_status := 'FAILED';
    v_error_message := SQLERRM;
    v_response_message := 'Transaction failed due to an exception.';
    
    ROLLBACK; -- Discard the failing transaction block
    
    -- Insert the error into the log table as a fresh transaction
    INSERT INTO public.tbl_employee_leave_template_log (
        emp_id, account_id, template_id, request_json, response_message, status, error_message, created_by, user_ip
    ) VALUES (
        p_emp_id, p_account_id, p_template_id, p_leave_template_json, v_response_message, v_status, v_error_message, p_user_by, p_user_ip
    );
    COMMIT; -- Save the exception log
END;
$$;

-- ==============================================================================
-- 4. Lightweight Batch Automation: usp_auto_upgrade_probation_templates
-- ==============================================================================
CREATE OR REPLACE PROCEDURE public.usp_auto_upgrade_probation_templates()
LANGUAGE plpgsql
AS $$
DECLARE
    -- Hardcode your specific account IDs here:
    v_allowed_accounts BIGINT[] := ARRAY[653, 981];
    
    r_employee RECORD;
    v_target_template_txt JSONB;
    v_batch_count INT;
    v_total_processed INT := 0;
BEGIN
    -- STEP 1: Lightweight Staging
    CREATE TEMP TABLE IF NOT EXISTS tmp_prob_upgrade_batch (
        emp_id BIGINT,
        account_id BIGINT,
        probation_prd_days INT,
        target_template_id BIGINT,
        processed BOOLEAN DEFAULT FALSE
    );
    TRUNCATE TABLE tmp_prob_upgrade_batch;

    -- Fast Identification: Load eligible employees into the staging table instantly
    INSERT INTO tmp_prob_upgrade_batch (emp_id, account_id, probation_prd_days, target_template_id)
    SELECT 
        b.emp_id, 
        b.account_id, 
        COALESCE(a.probation_prd_months, '0')::INT,
        a.prob_prd_over_template::BIGINT
    FROM tbl_tpleavebank a
    INNER JOIN public.tbl_employee_leavebank b 
        ON a.template_id = b.template_id AND a.account_id = b.account_id
    INNER JOIN public.openappointments emp 
        ON b.emp_id = emp.emp_id AND b.account_id = emp.customeraccountid
    WHERE 
        b.status = '1' 
        AND a.status = '1'
        AND a.is_probation_prd_enable = 'Y'
        AND b.effective_to IS NULL
        AND emp.isactive = '1'
        AND emp.appointment_status_id <> '13' -- Ensure active
        AND b.account_id = ANY(v_allowed_accounts)
        AND CURRENT_DATE >= (emp.dateofjoining + (COALESCE(a.probation_prd_months, '0')::INT || ' days')::interval);

    -- STEP 2: Process in Chunks
    LOOP
        v_batch_count := 0;

        FOR r_employee IN (
            SELECT * FROM tmp_prob_upgrade_batch WHERE processed = FALSE LIMIT 100
        ) LOOP
            
            -- Fetch the target template's JSON text
            SELECT template_txt::JSONB INTO v_target_template_txt
            FROM public.tbl_tpleavebank
            WHERE template_id = r_employee.target_template_id 
              AND status = '1'
            LIMIT 1;

            IF v_target_template_txt IS NOT NULL THEN
                -- Ensure the template text is a JSON array (fixes "cannot call jsonb_populate_recordset on a non-array")
                IF jsonb_typeof(v_target_template_txt) = 'object' THEN
                    v_target_template_txt := jsonb_build_array(v_target_template_txt);
                END IF;

                -- STEP 3: Change the template using a subtransaction block
                -- This implicitly sets a savepoint. If an error occurs, it rolls back this employee's changes only.
                DECLARE
                    v_response JSON;
                BEGIN
                    -- Call the core API function directly
                    SELECT public.usp_apply_employee_leave_template(
                        r_employee.account_id::VARCHAR,
                        r_employee.emp_id::VARCHAR,
                        r_employee.target_template_id::VARCHAR,
                        'SYSTEM_AUTO',
                        'SYSTEM_BATCH',
                        v_target_template_txt,
                        to_char(CURRENT_DATE, 'dd-mm-yyyy')
                    ) INTO v_response;
                    
                    IF v_response->>'msgcd' = '1' THEN
                        -- Success!
                        v_total_processed := v_total_processed + 1;
                        
                        INSERT INTO public.tbl_employee_leave_template_log (
                            emp_id, account_id, template_id, request_json, response_message, status, error_message, created_by, user_ip
                        ) VALUES (
                            r_employee.emp_id::VARCHAR, r_employee.account_id::VARCHAR, r_employee.target_template_id::VARCHAR, 
                            v_target_template_txt, v_response->>'msg', 'SUCCESS', NULL, 'SYSTEM_BATCH', 'SYSTEM_AUTO'
                        );
                    ELSE
                        -- Logical failure: Raise exception to trigger rollback of this specific employee's transaction
                        RAISE EXCEPTION 'Logical Failure: %', v_response->>'msg';
                    END IF;

                EXCEPTION WHEN OTHERS THEN
                    -- The database automatically rolled back this employee's changes!
                    -- Now we log the failure and continue to the next employee.
                    INSERT INTO public.tbl_employee_leave_template_log (
                        emp_id, account_id, template_id, request_json, response_message, status, error_message, created_by, user_ip
                    ) VALUES (
                        r_employee.emp_id::VARCHAR, r_employee.account_id::VARCHAR, r_employee.target_template_id::VARCHAR, 
                        v_target_template_txt, 'Transaction Failed', 'FAILED', SQLERRM, 'SYSTEM_BATCH', 'SYSTEM_AUTO'
                    );
                END;
                
            ELSE
                -- Log a failure if target template missing
                INSERT INTO public.tbl_employee_leave_template_log (
                    emp_id, account_id, template_id, request_json, response_message, status, error_message, created_by, user_ip
                ) VALUES (
                    r_employee.emp_id::VARCHAR, r_employee.account_id::VARCHAR, r_employee.target_template_id::VARCHAR, NULL, 
                    'Target probation-end template not found in tbl_tpleavebank.', 'FAILED', 'Missing Template JSON', 'SYSTEM_BATCH', 'SYSTEM_AUTO'
                );
            END IF;

            -- Mark as processed
            UPDATE tmp_prob_upgrade_batch 
            SET processed = TRUE 
            WHERE emp_id = r_employee.emp_id AND account_id = r_employee.account_id;

            v_batch_count := v_batch_count + 1;
        END LOOP;

        -- COMMIT the batch! (Releases row locks)
        COMMIT;

        -- Exit when the queue is empty
        EXIT WHEN v_batch_count < 100;
    END LOOP;
    
    RAISE NOTICE 'Total employees upgraded from probation templates: %', v_total_processed;

    -- Notice: We do NOT use an outer EXCEPTION block here, because PostgreSQL 
    -- does not allow COMMITs inside a block that has an EXCEPTION handler!
END;
$$;


-- schedule every night at 16:30 UTC (10:00 PM IST)
SELECT cron.schedule(
  job_name := 'nightly_probation_template_upgrade', 
  schedule := '30 16 * * *',                        
  command  := 'CALL public.usp_auto_upgrade_probation_templates();'
);