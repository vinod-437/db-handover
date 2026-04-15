-- FUNCTION: public.update_weekly_off_holiday_by_account(character varying, character varying, character varying, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.update_weekly_off_holiday_by_account(character varying, character varying, character varying, character varying, character varying);

CREATE OR REPLACE FUNCTION public.update_weekly_off_holiday_by_account(
	p_customeraccountid character varying DEFAULT ''::character varying,
	p_mpr_year character varying DEFAULT ''::character varying,
	p_mpr_month character varying DEFAULT ''::character varying,
	p_user_ip character varying DEFAULT ''::character varying,
	p_user_by character varying DEFAULT ''::character varying)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_record RECORD;
    v_result text;
    v_return_message text;
    v_error_message text;  -- To store error messages for debugging
BEGIN
    -- Input validation: Check for empty or invalid inputs
    IF p_customeraccountid IS NULL OR p_customeraccountid = '' THEN
        v_return_message := '{"status_code": 400, "message": "customeraccountid cannot be empty"}';
        RETURN v_return_message;
    END IF;

    IF p_mpr_year IS NULL OR p_mpr_year = '' OR NOT p_mpr_year ~ '^[0-9]+$' THEN
        v_return_message := '{"status_code": 400, "message": "Invalid year format"}';
        RETURN v_return_message;
    END IF;

    IF p_mpr_month IS NULL OR p_mpr_month = '' OR NOT p_mpr_month ~ '^[0-9]+$' OR p_mpr_month::int < 1 OR p_mpr_month::int > 12 THEN
        v_return_message := '{"status_code": 400, "message": "Invalid month format"}';
        RETURN v_return_message;
    END IF;

    -- Loop through distinct emp_codes
    FOR v_record IN
        SELECT DISTINCT emp_code
        FROM tbl_monthly_attendance
        WHERE customeraccountid = p_customeraccountid::bigint
          AND att_date BETWEEN make_date(p_mpr_year::int, p_mpr_month::int, 1) 
		  AND eomonth(make_date(p_mpr_year::int, p_mpr_month::int, 1))
    LOOP
        BEGIN -- Use a nested BEGIN...END block to handle individual usp_update_weekly_off_holiday errors

            perform public.usp_update_weekly_off_holiday(
                p_action => 'update_weekly_off',
                p_account_id => p_customeraccountid::text,
                p_emp_code => v_record.emp_code::text,
                p_month => p_mpr_month::text,
                p_year => p_mpr_year::text,
                p_user_by =>  p_customeraccountid::text,
                p_user_ip => p_user_ip::text
            ) ;
			RAISE NOTICE 'Result for emp_code %', v_record.emp_code;
           -- RAISE NOTICE 'Result for emp_code %: %', v_record.emp_code, v_result;

        EXCEPTION
           WHEN OTHERS THEN
             --   GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
               -- RAISE WARNING 'Error updating emp_code %: %', v_record.emp_code, v_error_message; -- Log the error
               -- Consider continuing or re-raising the exception, depending on your needs.  If you want the function to continue after an error, you can do nothing here.  If you want it to stop:
               --  RAISE; -- Re-raise the exception to be caught by the outer exception block, which will terminate the function

        END; -- End of inner BEGIN...END block (handling errors within the loop)

    END LOOP;

    v_return_message := '{"status_code": 200, "message": "Record has been successfully updated"}'; -- JSON as text

    RETURN v_return_message;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT; -- Capture the error message
        v_return_message := format('{"status_code": 500, "message": "Error: %s"}', v_error_message); -- Return error as JSON
        RETURN v_return_message;
END;
$BODY$;

ALTER FUNCTION public.update_weekly_off_holiday_by_account(character varying, character varying, character varying, character varying, character varying)
    OWNER TO payrollingdb;

