CREATE OR REPLACE PROCEDURE public.usp_auto_upgrade_probation_templates()
LANGUAGE plpgsql
AS $$
DECLARE
    r_employee RECORD;
    v_target_template_txt JSONB;
    v_batch_count INT;
    v_total_processed INT := 0;
BEGIN
    -- STEP 1: Lightweight Staging
    -- We create a temporary table for this session to hold the IDs.
    -- This prevents us from keeping a long-running snapshot lock on the main production tables.
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
        AND CURRENT_DATE >= (emp.dateofjoining + (COALESCE(a.probation_prd_months, '0')::INT || ' days')::interval);

    -- STEP 2: Process in Chunks
    LOOP
        v_batch_count := 0;

        -- Only grab 100 unprocessed records at a time to keep memory footprint tiny
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
                -- STEP 3: Change the template
                -- Call the wrapper we built to safely switch the template & log it
                CALL public.usp_process_employee_leave_template(
                    p_account_id => r_employee.account_id::VARCHAR,
                    p_emp_id => r_employee.emp_id::VARCHAR,
                    p_template_id => r_employee.target_template_id::VARCHAR,
                    p_user_ip => 'SYSTEM_AUTO',
                    p_user_by => 'SYSTEM_BATCH',
                    p_leave_template_json => v_target_template_txt,
                    p_effective_date => to_char(CURRENT_DATE, 'dd-mm-yyyy')
                );
                
                v_total_processed := v_total_processed + 1;
            ELSE
                -- Log a failure if the target template does not exist
                INSERT INTO public.tbl_employee_leave_template_log (
                    emp_id, account_id, template_id, request_json, response_message, status, error_message, created_by, user_ip
                ) VALUES (
                    r_employee.emp_id::VARCHAR, r_employee.account_id::VARCHAR, r_employee.target_template_id::VARCHAR, NULL, 
                    'Target probation-end template not found in tbl_tpleavebank.', 'FAILED', 'Missing Template JSON', 'SYSTEM_BATCH', 'SYSTEM_AUTO'
                );
            END IF;

            -- Mark as processed so it doesn't get picked up in the next loop
            UPDATE tmp_prob_upgrade_batch 
            SET processed = TRUE 
            WHERE emp_id = r_employee.emp_id AND account_id = r_employee.account_id;

            v_batch_count := v_batch_count + 1;
        END LOOP;

        -- COMMIT the batch! 
        -- This is the crucial step that releases all row locks from the database 
        -- so other users/APIs aren't blocked.
        COMMIT;

        -- Exit the loop if we processed less than 100 (meaning the queue is empty)
        EXIT WHEN v_batch_count < 100;
    END LOOP;
    
    RAISE NOTICE 'Total employees upgraded from probation templates: %', v_total_processed;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Batch process failed: %', SQLERRM;
    ROLLBACK;
END;
$$;
