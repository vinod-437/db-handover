-- FUNCTION: public.usp_get_subscription_employee_summary(character varying, text)

-- DROP FUNCTION IF EXISTS public.usp_get_subscription_employee_summary(character varying, text);

CREATE OR REPLACE FUNCTION public.usp_get_subscription_employee_summary(
	p_customeraccountid character varying,
	p_actiontype text DEFAULT NULL::text)
    RETURNS json
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_result JSONB;
    v_total_numberofemployees INTEGER := 0;
    v_total_updated_employee INTEGER := 0;
    /*
    ========================================================================================
    Version    : 1.1
    Date       : 09-05-2026
    Description: 1. Bypassed CURRENT_DATE check to support backdated subscriptions.
                 2. Updated active employee count logic to use date_trunc('month', CURRENT_DATE).
                 3. Filtered tbl_receivables to packagename = 'Starting Payment'
                    and service_name = 'Manpower Service' with ORDER BY id LIMIT 1.
    ========================================================================================
    */
BEGIN
    /* =========================================================
       ACTION 1 : GetSubscriptionEmployeeSummary
       ========================================================= */
    IF p_actiontype = 'GetSubscriptionEmployeeSummary' THEN
		-- bypass normal account dated. 29.04.2026
		if not exists (select  1 from tbl_account 
				where payout_mode_type='dfm' 
				and id = p_customeraccountid::BIGINT 
				and status='1') then

			RETURN json_build_object(
                'status', 'true',
                'message', 'Not a dfm order',
                'commonData', jsonb_build_object(
                    'total_numberofemployees', '0',
                    'total_updated_employee', '0'
                ))	;		

		end if;

        SELECT jsonb_agg(
                   jsonb_build_object(
                       'customeraccountid', r.customeraccountid,
                       'total_rows', r.total_rows,
                       'total_numberofemployees', r.total_numberofemployees,
                       'subscriptionfrom', r.subscriptionfrom,
                       'subscriptionto', r.subscriptionto,
                       'total_updated_employee', COALESCE(o.total_updated_employee, 0)
                   )
               )
        INTO v_result
        FROM (
            SELECT
                customeraccountid,
                1 AS total_rows,
                numberofemployees AS total_numberofemployees,
                subscriptionfrom,
                subscriptionto
            FROM public.tbl_receivables
            WHERE customeraccountid = p_customeraccountid::BIGINT 
              AND status = 'Paid'
              AND isactive = '1'
              AND packagename = 'Starting Payment'
              AND service_name = 'Manpower Service'
              -- Bypassed current date check as per request on 09-05-2026 to support back dated subscriptions
              -- AND CURRENT_DATE BETWEEN subscriptionfrom AND subscriptionto
            ORDER BY id
            LIMIT 1
        ) r
        LEFT JOIN (
            SELECT
                customeraccountid,
                COUNT(emp_code) AS total_updated_employee
            FROM openappointments
            WHERE isactive = '1'
              AND appointment_status_id <> 13
              AND (
                    dateofrelieveing IS NULL
                    OR dateofrelieveing >= date_trunc('month', CURRENT_DATE)
					-- Modified on 09-05-2026: Ensure left out employees are not considered
                  )
              AND customeraccountid = p_customeraccountid::BIGINT
            GROUP BY customeraccountid
        ) o
        ON o.customeraccountid = r.customeraccountid;

        IF v_result IS NULL THEN
            RETURN json_build_object(
                'status', 'false',
                'message', 'No record found',
                'commonData', ''
            );
        END IF;

        RETURN json_build_object(
            'status', 'true',
            'message', 'Record(s) fetched successfully',
            'commonData', v_result
        );

    /* =========================================================
       ACTION 2 : CheckEmployeeLimitAgainstSubscription
       ========================================================= */
    ELSIF p_actiontype = 'CheckEmployeeLimitAgainstSubscription' THEN

        -- Get subscription employee limit
       /* SELECT COALESCE(SUM(numberofemployees), 0)
        INTO v_total_numberofemployees
        FROM public.tbl_receivables
        WHERE CURRENT_DATE BETWEEN subscriptionfrom AND subscriptionto
          AND customeraccountid = p_customeraccountid::BIGINT and status = 'Paid';
		*/
		-- bypass normal account dated. 29.04.2026
		if not exists (select  1 from tbl_account 
				where payout_mode_type='dfm' 
				and id = p_customeraccountid::BIGINT 
				and status='1') then

			RETURN json_build_object(
                'status', 'true',
                'message', 'Not a dfm order',
                'commonData', jsonb_build_object(
                    'total_numberofemployees', '0',
                    'total_updated_employee', '0'
                ))	;		

		end if;
		
		SELECT a.numberofemployees
        INTO v_total_numberofemployees
        FROM public.tbl_receivables a inner join tbl_account b on 
		a.customeraccountid= b.id and b.status='1' and b.payout_mode_type='dfm'
        WHERE a.customeraccountid = p_customeraccountid::BIGINT 
          AND a.status = 'Paid'
          AND a.isactive = '1'
          AND a.packagename = 'Starting Payment'
          AND a.service_name = 'Manpower Service'
          -- Bypassed current date check as per request on 09-05-2026 to support back dated subscriptions
          -- AND CURRENT_DATE BETWEEN subscriptionfrom AND subscriptionto
        ORDER BY a.id LIMIT 1;
        
        v_total_numberofemployees := COALESCE(v_total_numberofemployees, 0);			   
	  
		
        -- Get active employee count
        SELECT COUNT(emp_id)
        INTO v_total_updated_employee
        FROM openappointments
        WHERE isactive = '1'
          AND appointment_status_id <> 13
          AND (
                dateofrelieveing IS NULL
                OR dateofrelieveing >= date_trunc('month', CURRENT_DATE)
				-- Modified on 09-05-2026: Ensure left out employees are not considered
              )
          AND customeraccountid = p_customeraccountid::BIGINT;

        -- If no subscription exists
	    IF v_total_numberofemployees = 0 THEN
	        RETURN json_build_object(
	            'status', 'false',
	            'message', 'No subscription available',
	            'commonData', ''
	        );
	    END IF;
		-- Compare and return TRUE / FALSE
        IF (v_total_numberofemployees >= v_total_updated_employee) AND v_total_numberofemployees != 0 THEN
            RETURN json_build_object(
                'status', 'true',
                'message', 'Employee limit is within subscription',
                'commonData', jsonb_build_object(
                    'total_numberofemployees', v_total_numberofemployees,
                    'total_updated_employee', v_total_updated_employee
                )
            );
        ELSE
            RETURN json_build_object(
                'status', 'false',
                'message', 'Your plan allows ' || v_total_numberofemployees ||
			    ' employees, but you are trying to add ' || v_total_updated_employee ||
			    '. Please upgrade your subscription to add more employees.',
                'commonData', jsonb_build_object(
                    'total_numberofemployees', v_total_numberofemployees,
                    'total_updated_employee', v_total_updated_employee
                )
            );
        END IF;

    /* =========================================================
       INVALID ACTION
       ========================================================= */
    ELSE
        RETURN json_build_object(
            'status', 'false',
            'message', 'Invalid request',
            'commonData', ''
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status', 'false',
            'message', SQLERRM,
            'commonData', '[]'::jsonb
        );
END;
$BODY$;

ALTER FUNCTION public.usp_get_subscription_employee_summary(character varying, text)
    OWNER TO payrollingdb;

