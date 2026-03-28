-- FUNCTION: public.usp_save_or_update_candidate_policy(character varying, bigint, character varying, character varying, text, bigint, character varying, character varying, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.usp_save_or_update_candidate_policy(character varying, bigint, character varying, character varying, text, bigint, character varying, character varying, character varying, character varying);

CREATE OR REPLACE FUNCTION public.usp_save_or_update_candidate_policy(
	p_action character varying DEFAULT 'insert_update'::character varying,
	p_policy_id bigint DEFAULT NULL::bigint,
	p_policy_name character varying DEFAULT NULL::character varying,
	p_policy_status character varying DEFAULT NULL::character varying,
	p_emp_code_list text DEFAULT ''::text,
	p_customeraccountid bigint DEFAULT NULL::bigint,
	p_remarks character varying DEFAULT NULL::character varying,
	p_record_type character varying DEFAULT NULL::character varying,
	p_user character varying DEFAULT NULL::character varying,
	p_userip character varying DEFAULT NULL::character varying)
    RETURNS TABLE(msgcd character varying, msg text) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    emp_code_val BIGINT;
    emp_code_arr TEXT[];
    v_existing_id BIGINT;
	/**********************************************************************************************
		Version     Date               Change                                                Done_by
		1.1        29/07/2025     Initial Version                                    	Chandra Mohan
		1.2        29/07/2025     p_policy_name v Remove                               	Chandra Mohan
		  --- Insert or Update
		   SELECT * FROM public.usp_save_or_update_candidate_policy(
		    p_action := 'insert_update',
		    p_policy_id := 1,
		    p_policy_name := 'ID Card',
		    p_policy_status := 'Y',
		    p_emp_code_list := '1001,1002,1003',
		    p_customeraccountid := 653,
		    p_remarks := 'Initial Allocation',
		    p_record_type := 'Employee',
		    p_user := '653',
		    p_userip := '127.0.0.1'
		);
		-- Deactivate
	   SELECT * FROM public.usp_save_or_update_candidate_policy(
	    p_action := 'deactivate',
	    p_policy_id := 1,
	    p_emp_code_list := '1001,1003',
	    p_customeraccountid := 653,
	    p_user := '653',
	    p_userip := '127.0.0.1'
		);

	***********************************************************************************************/
BEGIN
    -- Basic validation
    IF p_policy_id IS NULL  THEN --OR p_policy_name IS NULL
        RETURN QUERY SELECT '0'::VARCHAR, 'Policy ID and Name are required';
        RETURN;
    END IF;
    
	  SELECT policy_name INTO p_policy_name
            FROM mst_candidates_policies
            WHERE id = p_policy_id
              AND is_active = '1'
            LIMIT 1;
    -- Convert emp_code_list to array
    emp_code_arr := string_to_array(p_emp_code_list, ',');

    IF p_action = 'insert_update' THEN

        -- Case: No emp_code_list provided, treat as Employer
        IF emp_code_arr IS NULL OR array_length(emp_code_arr, 1) IS NULL THEN
            emp_code_val := NULL;

            SELECT id INTO v_existing_id
            FROM public.tbl_candidates_policies
            WHERE emp_code IS NULL
              AND policy_id = p_policy_id
              AND customeraccountid = p_customeraccountid
              AND is_active = '1'
            LIMIT 1;

            IF v_existing_id IS NOT NULL THEN
                -- Update
                UPDATE public.tbl_candidates_policies
                SET
                    policy_name = p_policy_name,
                    policy_status = p_policy_status,
                    remarks = p_remarks,
                    record_type = 'Employer',
                    modified_user = p_user,
                    modified_on = CURRENT_TIMESTAMP,
                    modified_by_ip = p_userip
                WHERE id = v_existing_id;

            ELSE
                -- Insert
                INSERT INTO public.tbl_candidates_policies (
                    policy_id, policy_name, policy_status,
                    emp_code, customeraccountid,
                    remarks, record_type, is_active,
                    created_user, created_on, created_by_ip
                )
                VALUES (
                    p_policy_id, p_policy_name, p_policy_status,
                    NULL, p_customeraccountid,
                    p_remarks, 'Employer', true,
                    p_user, CURRENT_TIMESTAMP, p_userip
                );
            END IF;

        ELSE
            -- Case: Multiple emp codes - loop
            FOREACH emp_code_val IN ARRAY emp_code_arr LOOP
                SELECT id INTO v_existing_id
                FROM public.tbl_candidates_policies
                WHERE emp_code = emp_code_val
                  AND policy_id = p_policy_id
                  AND customeraccountid = p_customeraccountid
                  AND is_active = '1'
                LIMIT 1;

                IF v_existing_id IS NOT NULL THEN
                    UPDATE public.tbl_candidates_policies
                    SET
                        policy_name = p_policy_name,
                        policy_status = p_policy_status,
                        remarks = p_remarks,
                        record_type = 'Employee',
                        modified_user = p_user,
                        modified_on = CURRENT_TIMESTAMP,
                        modified_by_ip = p_userip
                    WHERE id = v_existing_id;

                ELSE
                    INSERT INTO public.tbl_candidates_policies (
                        policy_id, policy_name, policy_status,
                        emp_code, customeraccountid,
                        remarks, record_type, is_active,
                        created_user, created_on, created_by_ip
                    )
                    VALUES (
                        p_policy_id, p_policy_name, p_policy_status,
                        emp_code_val, p_customeraccountid,
                        p_remarks, 'Employee', true,
                        p_user, CURRENT_TIMESTAMP, p_userip
                    );
                END IF;

                v_existing_id := NULL;
            END LOOP;
        END IF;

        RETURN QUERY SELECT '1'::VARCHAR, 'Insert/Update completed successfully';

    ELSIF p_action = 'deactivate' THEN

        IF emp_code_arr IS NULL OR array_length(emp_code_arr, 1) IS NULL THEN
           /* UPDATE public.tbl_candidates_policies
            SET
                is_active = false,
                modified_user = p_user,
                modified_on = CURRENT_TIMESTAMP,
                modified_by_ip = p_userip
            WHERE emp_code IS NULL
              AND policy_id = p_policy_id
              AND customeraccountid = p_customeraccountid
              AND is_active = true;*/

        ELSE
            FOREACH emp_code_val IN ARRAY emp_code_arr LOOP
                UPDATE public.tbl_candidates_policies
                SET
                    is_active = false,
                    modified_user = p_user,
                    modified_on = CURRENT_TIMESTAMP,
                    modified_by_ip = p_userip
                WHERE emp_code = emp_code_val
                  AND policy_id = p_policy_id
                  AND customeraccountid = p_customeraccountid
                  AND is_active = true;
            END LOOP;
        END IF;

        RETURN QUERY SELECT '1'::VARCHAR, 'Record(s) deactivated successfully';

    ELSE
        RETURN QUERY SELECT '0'::VARCHAR, 'Invalid action specified';
    END IF;
END;
$BODY$;

ALTER FUNCTION public.usp_save_or_update_candidate_policy(character varying, bigint, character varying, character varying, text, bigint, character varying, character varying, character varying, character varying)
    OWNER TO payrollingdb;

