-- FUNCTION: public.calculate_advance_employee_attandance_policy(bigint, bigint, character varying)

-- DROP FUNCTION IF EXISTS public.calculate_advance_employee_attandance_policy(bigint, bigint, character varying);

CREATE OR REPLACE FUNCTION public.calculate_advance_employee_attandance_policy(
	p_customeraccountid bigint,
	p_emp_code bigint,
	p_att_date character varying)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
/*******|***************|*******************|******************************************************
Version	|	Date		|	Done_By			|	Changes
--------|---------------|-------------------|------------------------------------------------------
1.0		|	25-Aug-2025	|	Parveen Kumar	|	Initial Version
1.1		|	25-Dec-2025	|	Parveen Kumar	|	Half-Day, Leave Deduction in Monthly Hours.
1.2		|	25-Dec-2025	|	Parveen Kumar	|	Working Hours Calculation (Check In) from Start Time.
1.3		|	07-Jan-2026	|	Parveen Kumar	|	Add penalty_mode (strict/lenient) changes in Penalty Policy.
**************************************************************************************************/
DECLARE
	response refcursor;
	v_att_date DATE;
	v_shift_details record;
	v_assigned_shift_details record;
	v_emp_salary record;
	v_head_amount NUMERIC(16, 2);
	v_head_amount_saot NUMERIC(16, 2);
	v_shift_id INT;

	v_shift_start_timing timestamp;
	v_shift_start_timing_IST timestamp;
	v_shift_end_timing timestamp;
	v_shift_end_timing_IST timestamp;
	v_shift_working_minutes double precision := 0;
	v_shift_working_minutes_assigned double precision := 0;
	v_shift_working_minutes_assigned_after_unpaid_break double precision := 0;
	v_first_check_in_time_and_shift_minutes_diff double precision := 0;
	v_last_check_out_time_and_shift_minutes_diff double precision := 0;

	v_first_check_in_time TIMESTAMP;
	v_last_check_out_time TIMESTAMP;
	v_no_of_hours_worked TEXT;
	v_no_of_minutes_worked double precision := 0;
	v_attandance_type TEXT := 'PP';
	v_attandance_category TEXT := NULL;
	v_attandance_leave_type TEXT := NULL;

	v_grace_period_JSON JSONB;
	v_is_grace_policy_applied TEXT := 'N';

	v_grace_row_data jsonb;

	v_is_late_comer character varying(1) := 'N';
	v_deviation_in_checkin INT := 0;
	v_deviation_in_checkin_time TEXT := '00:00:00';
	v_deviation_in_checkin_time_in_minutes NUMERIC(16, 2);
	v_fixed_amount_penalty_on_checkin NUMERIC(16, 2);
	v_per_minute_penalty_on_checkin NUMERIC(16, 2);
	v_qtrs_penalty_on_checkin NUMERIC(16, 2);
	v_penality_on_checkin NUMERIC(16, 2);
	v_penality_on_checkin_msg TEXT;

	v_deviation_in_checkout INT := 0;
	v_deviation_in_checkout_time TEXT := '00:00:00';
	v_deviation_in_checkout_time_in_minutes NUMERIC(16, 2);
	v_fixed_amount_penalty_on_checkout NUMERIC(16, 2);
	v_per_minute_penalty_on_checkout NUMERIC(16, 2);
	v_qtrs_penalty_on_checkout NUMERIC(16, 2);
	v_penality_on_checkout NUMERIC(16, 2);
	v_penality_on_checkout_msg TEXT;

	v_deviation_in_working_hours INT := 0;
	v_deviation_in_working_hours_time TEXT := '00:00:00';
	v_deviation_in_working_hours_time_in_minutes NUMERIC(16, 2);
	v_fixed_amount_penalty_on_working_hours NUMERIC(16, 2);
	v_per_minute_penalty_on_working_hours NUMERIC(16, 2);
	v_penality_on_working_hours NUMERIC(16, 2);
	v_penality_on_working_hours_msg TEXT;

	v_full_day_min_minutes INT := 0;
	v_half_day_min_minutes INT := 0;
	v_per_day_min_minutes INT := 0;

	v_full_day_max_minutes INT := 0;
	v_half_day_max_minutes INT := 0;
	v_per_day_max_minutes INT := 0;

	v_overtime character varying(1) := 'N';
	v_overtime_minutes double precision := 0;

	v_emp_id INT;
	v_month INT;
	v_year INT;
	v_leave_template_details RECORD;
	v_leave_balance_details_JSON JSONB;
	v_leave_type TEXT;
	v_leave_type_prev_balance DECIMAL;

	v_is_time_exists_between_assigned_att_policy character varying(1) := 'Y';
	v_is_auto_assign_shift character varying(1) := 'N';
	v_auto_shift_rotation character varying(1) := 'Y';

    v_rounded_check_out TIMESTAMP;
    v_rounded_check_in TIMESTAMP;
    v_rounded_no_of_hours_worked TEXT;
	v_rounded_no_of_minutes_worked double precision := 0;

	-- START - Grace Policy Calculations
		-- v_total_deviation_checkin INT := 0;
		v_total_deviation_checkout INT := 0;
		v_deviation_in_total_working_hours NUMERIC := 0;
		v_deviation_type TEXT;
		v_grace_period_in_minutes NUMERIC(18, 2);
		v_grace_period_max_uses INT;
		v_grace_period_max_uses_period TEXT;
		
		v_leave_deduction_days NUMERIC := 0;
		v_deviations_more_than_period TEXT;
		v_deviations_frequency TEXT;
		v_deviations_uses INT := 0;
		v_deviations_more_than_times INT := 0;
		v_leave_deduction_reason jsonb;
		v_deduction_row_data INT;
		v_emp_deviations INT;
		v_emp_deviations_till_att_date INT;
		v_leave_emp_deviations INT;
		v_qtrs_emp_deviations INT;
		v_emp_deviations_already_deducted INT := 0;
		v_deviations_from_date CHARACTER VARYING(10); -- dd/mm/yyyy
		v_deviations_to_date CHARACTER VARYING(10); -- dd/mm/yyyy
		v_deviation_start_time CHARACTER VARYING(10) := '00:00:01';
		v_deviation_end_time CHARACTER VARYING(10) := '23:59:59';

		-- Penality Rules
	    v_penality_rules jsonb;
	    v_rule jsonb;
	    v_penalty jsonb;
	    v_leave jsonb;
	    -- v_fixed_amount_penalty NUMERIC(16, 2) := 0;
	    v_final_fixed_amount_penalty NUMERIC(16, 2) := 0;
	    v_per_minute_penalty NUMERIC(16, 2) := 0;
	    v_qtrs_penalty NUMERIC(16, 2) := 0;
	    v_final_per_minute_penalty NUMERIC(16, 2) := 0;
	    v_final_qtrs_penalty NUMERIC(16, 2) := 0;
		v_penalty_mode character varying(10) := 'strict';
		v_penalty_workflow_enabled character varying(1) := 'N';
	    v_one_day_salary NUMERIC := 0;
	    v_one_qtrs_minutes NUMERIC := 0;
	    v_one_qtrs_minutes_salary NUMERIC := 0;
		v_penality_rule_window RECORD;
		v_penalty_as_fixed_amount_enabled CHARACTER VARYING(1) := 'N';
		v_penalty_as_qtrs_deduction_enabled CHARACTER VARYING(1) := 'N';
		v_penalty_as_per_minutes_enabled CHARACTER VARYING(1) := 'N';
	    v_penalty_qtrs_deduction NUMERIC(16, 2) := 0;
	    v_penalty_as_ot_config_deduction_enabled CHARACTER VARYING(1) := 'N';
	    v_penalty_as_leave_deduction_enabled CHARACTER VARYING(1) := 'N';
	    v_penalty_as_leave_deduction double precision := 0;
		v_penalty_as_leave_deduction_priority JSONB;

		-- Same as OT Penality
		v_penality_remaning_minutes_calculations_saot NUMERIC(16, 2) := 0;
		v_penality_limit_minutes_saot NUMERIC(16, 2) := 0;

		v_penality_in_check_in_amount_before_multiplier_saot NUMERIC(16, 2) := 0;
		v_penality_in_check_in_amount_after_multiplier_saot NUMERIC(16, 2) := 0;
		v_check_in_final_amount_saot NUMERIC(16, 2) := 0;
		v_check_in_penality_applicable_minutes_saot NUMERIC(16, 2) := 0;
		v_check_in_penality_summary_saot TEXT;

		v_penality_in_check_out_amount_before_multiplier_saot NUMERIC(16, 2) := 0;
		v_penality_in_check_out_amount_after_multiplier_saot NUMERIC(16, 2) := 0;
		v_check_out_final_amount_saot NUMERIC(16, 2) := 0;
		v_check_out_penality_applicable_minutes_saot NUMERIC(16, 2) := 0;
		v_check_out_penality_summary_saot TEXT;
	-- END - Grace Policy Calculations

	v_ishourlysetup TEXT;

	-- START - Break Policy Changes
		v_total_break_paid INTERVAL := INTERVAL '0 minutes';
		v_total_break_unpaid INTERVAL := INTERVAL '0 minutes';
		v_break_record JSONB;
		v_break_duration INTERVAL;
		v_break_paid_flag TEXT;

		v_assigned_total_break_paid INTERVAL := INTERVAL '0 minutes';
		v_assigned_total_break_unpaid INTERVAL := INTERVAL '0 minutes';
		v_assigned_break_record JSONB;
		v_assigned_break_duration INTERVAL;
		v_assigned_break_paid_flag TEXT;
	-- END - Break Policy Change

	-- START- OT Calculations
		v_wo_ho_type TEXT := '';
		v_overtime_applicable_days TEXT := 'daily';
		v_overtime_summary TEXT;
		v_overtime_restriction_summary TEXT;
		v_ot_rules JSONB;
	    v_ot_rules_restrictions JSONB;
	    v_multiplier JSONB;
	    v_ot_rules_rate_structure JSONB;
		v_overtime_amount_before_multiplier NUMERIC(16, 2) := 0;
		v_overtime_amount_after_multiplier NUMERIC(16, 2) := 0;
		v_overtime_final_amount NUMERIC(16, 2) := 0;
		v_overtime_minutes_calculations NUMERIC(16, 2) := 0;
		v_overtime_limit_minutes NUMERIC(16, 2) := 0;
		v_applicable_minutes NUMERIC(16, 2) := 0;
		v_overtime_max_minutes NUMERIC(16, 2) := 0;
	-- END - OT Calculations
	v_total_working_hours_calculation TEXT;
	v_leave_penality_rec RECORD;
	v_qtrs_penality_rec RECORD;
	v_leave_grace_max_uses INT;
	v_leave_grace_used INT;

	v_tmp_penalty_rules record;
	v_is_working_hrs_completed CHARACTER VARYING(1) := 'N';

	v_days int;
	v_holidaycount int;

	v_ot_exclude_hrs_status CHARACTER VARYING(1) := 'N';
	v_ot_exclude_hrs TEXT;
	v_ot_exclude_minutes int;
	v_ot_trigger_after_hrs TEXT;
	-- v_ot_trigger_after_minutes int;

	v_ot_start_mode TEXT;
	v_ot_start_hrs TEXT;
	v_ot_start_minutes int;
	v_att_time_summary RECORD;
	v_shift_start_time timestamp;
	v_shift_end_time timestamp;
	v_fore_color TEXT;
	v_background_color TEXT;

	v_last_penalty_date DATE;
	v_penalty_search_from DATE;
	v_penalty_search_to DATE;

	v_LC_EG_enabled_in_app_setting CHARACTER VARYING(100) := 'Y';
	v_LC_enabled_in_app_setting CHARACTER VARYING(1) := 'N';
	v_EG_enabled_in_app_setting CHARACTER VARYING(1) := 'N';

BEGIN
	IF p_att_date IS NULL THEN
		v_att_date = CURRENT_DATE;
	ELSE
		v_att_date = TO_DATE(p_att_date, 'dd/mm/yyyy');
	END IF;

	-- START - Extrat Month and Year from v_att_date
		SELECT EXTRACT('MONTH' FROM v_att_date), EXTRACT('YEAR' FROM v_att_date) INTO v_month, v_year;
	-- START - Extrat Month and Year from v_att_date

	-- START - Check the roster assignment and get the shift according to the roster shift ID.
		SELECT COALESCE(auto_shift_rotation_yn, 'Y')
		INTO v_auto_shift_rotation 
		FROM tbl_employee_auto_rotation
		WHERE account_id = p_customeraccountid AND emp_code = p_emp_code AND status = '1';
		v_auto_shift_rotation := COALESCE(v_auto_shift_rotation, 'Y');
		IF v_auto_shift_rotation = 'N' THEN
			SELECT shift_id INTO v_shift_id
			FROM tbl_employee_shift_roster
			WHERE account_id = p_customeraccountid AND emp_code::BIGINT = p_emp_code  AND status = '1' AND roster_date = v_att_date;
		END IF;

		IF v_shift_id IS NOT NULL THEN
			SELECT * FROM vw_shifts WHERE shift_id::bigint = v_shift_id AND is_active = '1' LIMIT 1 INTO v_shift_details;
		ELSE
			SELECT * FROM vw_shifts_emp_wise WHERE emp_code::bigint = p_emp_code AND is_active = '1' INTO v_shift_details;
			SELECT v_shift_details.shift_id INTO v_shift_id;
		END IF;

		SELECT * FROM vw_shifts_emp_wise WHERE emp_code::bigint = p_emp_code AND is_active='1' INTO v_assigned_shift_details; -- This is used for Highflow Client for Overtime Calculations

		IF p_customeraccountid IN (7158, 7196, 7197) THEN -- Agro Client
			IF EXISTS(SELECT 1 FROM tbl_attendance WHERE emp_code = p_emp_code AND att_date = v_att_date AND isactive = '1') THEN
				SELECT check_in_time::TIMESTAMP
				FROM tbl_attendance
				WHERE emp_code = p_emp_code AND att_date = v_att_date AND isactive = '1'
				ORDER BY id ASC LIMIT 1 INTO v_first_check_in_time;

				SELECT s.shift_id, s.shift_start_timing, s.shift_end_timing, s.in_time, (s.in_time - s.shift_start_timing) AS diff
				INTO v_shift_id, v_shift_start_timing, v_shift_end_timing
				FROM (
					SELECT
						shift_id,
						(v_att_date + default_shift_time_from::interval)::timestamp - COALESCE(NULLIF(shift_margin_hours_from, ''), '00:00:00')::interval AS shift_start_timing,
						((v_att_date + default_shift_time_to::interval)::timestamp + CASE WHEN is_night_shift = 'Y' THEN INTERVAL '1 DAY' ELSE INTERVAL '0 DAY' END)::timestamp AS shift_end_timing,
						(v_first_check_in_time + INTERVAL '5 hours 30 minutes') in_time
					FROM vw_shifts_emp_wise
					WHERE is_active = '1' AND emp_code::bigint = p_emp_code
				) s
				WHERE s.in_time BETWEEN s.shift_start_timing AND s.shift_end_timing ORDER BY diff LIMIT 1;

				SELECT * FROM vw_shifts WHERE shift_id::bigint = v_shift_id AND is_active = '1' LIMIT 1 INTO v_shift_details;
				v_assigned_shift_details := v_shift_details;
			END IF;
		END IF;
	-- END - Check the roster assignment and get the shift according to the roster shift ID.

	-- START - Default Shift Timing
		v_shift_start_timing := (v_att_date + v_shift_details.default_shift_time_from::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
		v_shift_start_timing_IST := (v_att_date + v_shift_details.default_shift_time_from::time)::timestamp;
		IF v_shift_details.is_night_shift = 'Y' THEN
			v_shift_end_timing := ((v_att_date + INTERVAL '1 DAY') + v_shift_details.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
			v_shift_end_timing_IST := ((v_att_date + INTERVAL '1 DAY') + v_shift_details.default_shift_time_to::time)::timestamp;
		ELSE
			v_shift_end_timing := (v_att_date + v_shift_details.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
			v_shift_end_timing_IST := (v_att_date + v_shift_details.default_shift_time_to::time)::timestamp;
		END IF;
		v_shift_working_minutes := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_shift_start_timing::TIMESTAMP) / 60);
		v_shift_working_minutes_assigned := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_shift_start_timing::TIMESTAMP) / 60);
	-- END - Default Shift Timing

	-- START - Get Check-In/Out Time and Total No of Hours Worked
		SELECT
			op.emp_id,
			CASE WHEN emp_spec.total_working_hours_calculation = 'after_shift_start_timing' THEN
				GREATEST((check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp, v_shift_start_timing)
			ELSE
				(check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp
			END AS actual_check_in_time_as_per_shift,
			CASE WHEN emp_spec.total_working_hours_calculation = 'first_last_check' THEN
				COALESCE(NULLIF(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time', ''), check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_in_time')::timestamp
			WHEN json_array_length(check_in_out_data.check_in_out_details) > 1 AND check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
				(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp
			ELSE
				(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp
			END AS actual_check_out_time,
			CASE WHEN emp_spec.total_working_hours_calculation = 'after_shift_start_timing' THEN
				CASE WHEN json_array_length(check_in_out_data.check_in_out_details) > 1 AND check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
					LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - GREATEST((check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp, v_shift_start_timing))) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - GREATEST((check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp, v_shift_start_timing))) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - GREATEST((check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp, v_shift_start_timing))) % 60))::TEXT, 2, '0')
				ELSE
					LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - GREATEST((check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp, v_shift_start_timing))) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - GREATEST((check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp, v_shift_start_timing))) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - GREATEST((check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp, v_shift_start_timing))) % 60))::TEXT, 2, '0')
				END
			WHEN emp_spec.total_working_hours_calculation = 'first_last_check' THEN
				CASE WHEN json_array_length(check_in_out_data.check_in_out_details) > 1 AND check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
					LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
				ELSE
					LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
				END
			WHEN emp_spec.total_working_hours_calculation = 'first_last_mark_time' THEN
				LPAD(FLOOR(EXTRACT(EPOCH FROM (COALESCE(NULLIF(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time', ''), check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_in_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (COALESCE(NULLIF(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time', ''), check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_in_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (COALESCE(NULLIF(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time', ''), check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_in_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
			ELSE
				(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(check_in_out_data.check_in_out_details) AS trips(trip))
			END AS no_of_hours_worked,
			COALESCE(NULLIF(esr.ishourlysetup, ''), 'N') ishourlysetup, emp_spec.total_working_hours_calculation,
			COALESCE(working_hours_policy::JSONB->>'lc_eg', 'penality-rule')
		FROM openappointments op
		LEFT JOIN vw_shifts_emp_wise AS emp_spec ON emp_spec.emp_code::bigint = op.emp_code::bigint AND emp_spec.is_active='1'
		LEFT JOIN
		(
			SELECT json_agg(trips) check_in_out_details
			FROM
			(
				SELECT
					json_build_object
					(
						'att_date', TO_CHAR(COALESCE(att_date::DATE, v_att_date), 'dd-mm-yyyy'),
						'actual_check_in_time', t.check_in_time,
						'actual_check_out_time', t.check_out_time,
						'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0')
					) AS trips
				FROM openappointments op
				LEFT JOIN tbl_attendance t ON t.emp_code = op.emp_code AND att_date = v_att_date AND t.isactive='1'
				WHERE op.emp_code = p_emp_code AND op.customeraccountid = p_customeraccountid AND op.converted = 'Y' AND op.appointment_status_id IN (11,14)
				GROUP BY t.id
				ORDER BY t.id ASC
			) check_in_out_details
		) check_in_out_data ON TRUE
		LEFT JOIN empsalaryregister esr ON esr.appointment_id = op.emp_id AND esr.isactive = '1'
		WHERE op.emp_code=p_emp_code AND op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id IN (11,14)
		INTO v_emp_id, v_first_check_in_time, v_last_check_out_time, v_no_of_hours_worked, v_ishourlysetup, v_total_working_hours_calculation, v_LC_EG_enabled_in_app_setting;

		v_no_of_hours_worked := (CASE WHEN v_no_of_hours_worked LIKE '-%' THEN '00:00:00' ELSE v_no_of_hours_worked END);
		v_no_of_minutes_worked := CEIL(EXTRACT(EPOCH FROM v_no_of_hours_worked::INTERVAL)/60);
	-- END - Get Check-In/Out Time and Total No of Hours Worked

	-- 22 [Late Coming], 21 [Early Going] - Setting in mst_candidates_policies
	IF v_LC_EG_enabled_in_app_setting = 'app-setting' THEN
		SELECT COALESCE(policy_status, 'N') INTO v_EG_enabled_in_app_setting
		FROM public.tbl_candidates_policies
		WHERE is_active = '1' AND policy_id = 21 AND emp_code = p_emp_code;

		SELECT COALESCE(policy_status, 'N') INTO v_LC_enabled_in_app_setting
		FROM public.tbl_candidates_policies
		WHERE is_active = '1' AND policy_id = 22 AND emp_code = p_emp_code;
	END IF;

	SELECT * INTO v_emp_salary
	FROM
	(
		SELECT
			CASE
				WHEN salaryindaysopted = 'N' THEN EXTRACT(DAY FROM (make_date(v_year, v_month, 1) + INTERVAL '1 MONTH - 1 DAY'))::INT
				ELSE salarydays
			END month_days,
			salaryindaysopted, salarydays, *
		FROM empsalaryregister WHERE appointment_id = v_emp_id AND isactive = '1'
	);

	IF COALESCE(v_emp_salary.flexiblemonthdays,'N') = 'Y' THEN	
		SELECT COUNT(*) INTO v_holidaycount
		FROM public.usp_get_weekly_off_n_holiday_dates
		(
			p_accountid => p_customeraccountid,
			p_emp_id  => v_emp_salary.appointment_id,
			p_month => v_month,
			p_year => v_year
		);
		v_days := date_part('day', DATE_TRUNC('MONTH', (v_year||'-'||v_month||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');
		v_emp_salary.month_days := v_days - COALESCE(v_holidaycount, 0);
	END IF;

	-- START - Check whether the employee's check-in time is within the assigned attendance policy; if not, then the system should automatically assign a shift.
		IF COALESCE(NULLIF(v_shift_details.shift_margin, ''), 'N') = 'Y' THEN
			SELECT CASE WHEN v_first_check_in_time::timestamp BETWEEN (v_shift_start_timing - COALESCE(NULLIF(v_shift_details.shift_margin_hours_from, ''), '00:00:00')::interval) AND (v_shift_end_timing + COALESCE(NULLIF(v_shift_details.shift_margin_hours_to, ''), '00:00:00')::interval) THEN 'Y' ELSE 'N' END INTO v_is_time_exists_between_assigned_att_policy;
		ELSE
			SELECT CASE WHEN v_first_check_in_time::timestamp BETWEEN v_shift_start_timing AND v_shift_end_timing THEN 'Y' ELSE 'N' END INTO v_is_time_exists_between_assigned_att_policy;
		END IF;

		IF v_is_time_exists_between_assigned_att_policy = 'N' AND p_customeraccountid NOT IN (6878, 6872)  AND v_auto_shift_rotation = 'Y' THEN
			-- START - Get employer auto shift (latest)
				IF NOT EXISTS (SELECT * FROM vw_shifts WHERE customeraccountid = p_customeraccountid AND is_active='1' AND v_first_check_in_time::timestamp BETWEEN ((v_att_date + default_shift_time_from::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' - COALESCE(NULLIF(shift_margin_hours_from, ''), '00:00:00')::interval) AND CASE WHEN is_night_shift = 'Y' THEN ((v_att_date + INTERVAL '1 DAY') + default_shift_time_to::interval + COALESCE(NULLIF(shift_margin_hours_to, ''), '00:00:00')::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' ELSE (v_att_date + default_shift_time_to::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' + COALESCE(NULLIF(shift_margin_hours_to, ''), '00:00:00')::interval END ORDER BY shift_id DESC LIMIT 1) THEN
					OPEN response FOR
						SELECT
						0 status_code,
						'The assignment of the attendance policy is not possible because the user''s check-in time falls outside the scope of any existing attendance policy.' msg,
						p_emp_code emp_code,
						v_att_date att_date,
						0 shift_id,
						'' attendance_policy_type,
						0::bigint attendance_policy_id,
						v_no_of_minutes_worked no_of_minutes_worked,
						TO_CHAR((v_no_of_minutes_worked * INTERVAL '1 minute'), 'HH24:MI:SS') no_of_hours_worked,
						v_overtime_final_amount overtime_amount,
						v_overtime_summary overtime_summary,
						v_overtime is_overtime,
						TO_CHAR((v_overtime_minutes * INTERVAL '1 minute'), 'HH24:MI:SS') no_of_overtime_hours_worked,
						v_attandance_type attandance_type,
						v_attandance_category attandance_category,
						v_is_grace_policy_applied grace_policy_applied,
						v_deviation_in_checkin deviation_in_checkin,
						v_deviation_in_checkin_time deviation_in_checkin_time,
						v_penality_on_checkin_msg penality_on_checkin_summary,
						v_penality_on_checkin penality_amount_on_checkin,
						v_deviation_in_checkout deviation_in_checkout,
						v_deviation_in_checkout_time deviation_in_checkout_time,
						v_penality_on_checkout_msg penality_on_checkout_summary,
						v_penality_on_checkout penality_amount_on_checkout,
						v_deviation_in_working_hours deviation_in_working_hours,
						v_deviation_in_working_hours_time deviation_in_working_hours_time,
						v_penality_on_working_hours_msg penality_on_working_hours_msg,
						v_penality_on_working_hours penality_amount_on_working_hours,
						v_penalty_workflow_enabled penalty_workflow_enabled,
						0::bigint leave_bank_id,
						v_attandance_leave_type leave_type,
						v_is_auto_assign_shift is_auto_assign_shift,
						TO_CHAR(v_first_check_in_time, 'HH24:MI:SS') first_check_in_time,
						TO_CHAR(v_last_check_out_time, 'HH24:MI:SS') last_check_out_time,
                        v_is_late_comer is_late_comer,
						v_fore_color fore_color,
						v_background_color background_color;
					RETURN response;
				END IF;

				v_shift_details := NULL;
				SELECT * FROM vw_shifts WHERE customeraccountid = p_customeraccountid AND is_active='1' AND v_first_check_in_time::timestamp BETWEEN ((v_att_date + default_shift_time_from::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' - COALESCE(NULLIF(shift_margin_hours_from, ''), '00:00:00')::interval) AND CASE WHEN is_night_shift = 'Y' THEN ((v_att_date + INTERVAL '1 DAY') + default_shift_time_to::interval + COALESCE(NULLIF(shift_margin_hours_to, ''), '00:00:00')::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' ELSE (v_att_date + default_shift_time_to::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' + COALESCE(NULLIF(shift_margin_hours_to, ''), '00:00:00')::interval END ORDER BY shift_id DESC LIMIT 1
				INTO v_shift_details;

				v_is_auto_assign_shift := 'Y';
				v_shift_start_timing := (v_att_date + v_shift_details.default_shift_time_from::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
				IF v_shift_details.is_night_shift = 'Y' THEN
					v_shift_end_timing := ((v_att_date + INTERVAL '1 DAY') + v_shift_details.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
				ELSE
					v_shift_end_timing := (v_att_date + v_shift_details.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
				END IF;
				v_shift_working_minutes := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_shift_start_timing::TIMESTAMP) / 60);
				SELECT v_shift_details.shift_id INTO v_shift_id;
			-- END - Get employer auto shift (latest)
		END IF;
	-- END - Check whether the employee's check-in time is within the assigned attendance policy; if not, then the system should automatically assign a shift.

	-- START - Break Policy
		IF NULLIF(v_shift_details.break_policy, '') IS NOT NULL AND v_shift_details.break_policy <> '[]' THEN
			FOR v_break_record IN SELECT * FROM jsonb_array_elements(v_shift_details.break_policy::jsonb) LOOP
				v_break_duration := (COALESCE(NULLIF(v_break_record->>'break_type_duration', ''), '00:00:00'))::INTERVAL;
				v_break_paid_flag     := UPPER(TRIM(v_break_record->>'break_type_paid_unpaid'));

				IF v_break_paid_flag = 'PAID' THEN
					v_total_break_paid := v_total_break_paid + v_break_duration;
				ELSE
					v_total_break_unpaid := v_total_break_unpaid + v_break_duration;
				END IF;
			END LOOP;
		END IF;

		-- Assigned Shift Break Policy Calculations
		IF NULLIF(v_assigned_shift_details.break_policy, '') IS NOT NULL AND v_assigned_shift_details.break_policy <> '[]' THEN
			FOR v_assigned_break_record IN SELECT * FROM jsonb_array_elements(v_assigned_shift_details.break_policy::jsonb) LOOP
				v_assigned_break_duration := (COALESCE(NULLIF(v_assigned_break_record->>'break_type_duration', ''), '00:00:00'))::INTERVAL;
				v_assigned_break_paid_flag := UPPER(TRIM(v_assigned_break_record->>'break_type_paid_unpaid'));

				IF v_assigned_break_paid_flag = 'PAID' THEN
					v_assigned_total_break_paid := v_assigned_total_break_paid + v_assigned_break_duration;
				ELSE
					v_assigned_total_break_unpaid := v_assigned_total_break_unpaid + v_assigned_break_duration;
				END IF;
			END LOOP;
		END IF;
		v_shift_working_minutes_assigned_after_unpaid_break := v_shift_working_minutes_assigned - (EXTRACT(EPOCH FROM v_assigned_total_break_unpaid::INTERVAL) / 60);
	-- END - Break Policy Changes

	-- START - Round Off Calculations
		IF v_shift_details.is_round_off = 'Y' THEN
			v_first_check_in_time_and_shift_minutes_diff := (EXTRACT(EPOCH FROM v_first_check_in_time::TIMESTAMP - v_shift_start_timing::TIMESTAMP) / 60);
			IF v_first_check_in_time_and_shift_minutes_diff > 0 AND v_first_check_in_time_and_shift_minutes_diff <= COALESCE(v_shift_details.firstcheckin_round_off_minutes, 0) THEN
				v_first_check_in_time := v_shift_start_timing;
				v_no_of_minutes_worked := v_no_of_minutes_worked + v_first_check_in_time_and_shift_minutes_diff;
			END IF;

			v_last_check_out_time_and_shift_minutes_diff := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP) / 60);
			IF v_last_check_out_time_and_shift_minutes_diff > 0 AND v_last_check_out_time_and_shift_minutes_diff <= COALESCE(v_shift_details.last_check_out_round_off_minutes, 0) THEN
				v_last_check_out_time := v_shift_end_timing;
				v_no_of_minutes_worked := v_no_of_minutes_worked + v_last_check_out_time_and_shift_minutes_diff;
			END IF;

			v_no_of_minutes_worked := CEIL(v_no_of_minutes_worked);
		END IF;
	-- END - Round Off Calculations

	-- START - Min/Max working hours Calculations
		IF v_shift_details.min_working_hrs_request_mode = 'Strict' THEN
			IF v_shift_details.min_working_hrs_request_mode_type = 'manual_input' OR v_shift_details.min_working_hrs_request_mode_type = 'manual' THEN
				v_full_day_min_minutes := EXTRACT(EPOCH FROM v_shift_details.strict_manual_full_day_hrs::INTERVAL)/60;
				v_half_day_min_minutes := EXTRACT(EPOCH FROM v_shift_details.strict_manual_half_day_hrs::INTERVAL)/60;
			ELSIF v_shift_details.min_working_hrs_request_mode_type = 'shift_hours' OR v_shift_details.min_working_hrs_request_mode_type = 'shift_hrs' OR v_shift_details.min_working_hrs_request_mode_type = 'shift' THEN
				v_full_day_min_minutes := EXTRACT(EPOCH FROM v_shift_details.default_shift_full_hours::INTERVAL)/60;
				v_half_day_min_minutes := EXTRACT(EPOCH FROM v_shift_details.default_shift_half_hours::INTERVAL)/60;
			END IF;

			IF COALESCE(v_shift_details.is_max_hours_required, 'N') = 'Y' THEN
				v_half_day_max_minutes := EXTRACT(EPOCH FROM v_shift_details.max_half_day_hrs::INTERVAL)/60;
				v_full_day_max_minutes := EXTRACT(EPOCH FROM v_shift_details.max_full_day_hrs::INTERVAL)/60;
			END IF;
			IF v_no_of_minutes_worked <= 0 THEN
				-- v_attandance_type := 'MP';
			 	v_attandance_type := 'PP';  -- as per discussed with Yatin Sir on dated 30/12/2025
				v_attandance_category := 'MP';
			ELSIF v_no_of_minutes_worked < v_half_day_min_minutes THEN
				v_attandance_type := 'MP';
				v_attandance_category := 'DE';
			ELSIF v_no_of_minutes_worked < v_full_day_min_minutes THEN
				v_attandance_type := 'HD';
			ELSIF v_no_of_minutes_worked > v_full_day_min_minutes THEN
				v_attandance_type := 'PP';
			END IF;
		END IF;

		IF v_shift_details.min_working_hrs_request_mode = 'Lenient' THEN
			IF v_shift_details.min_working_hrs_request_mode_type = 'manual_input_len' OR v_shift_details.min_working_hrs_request_mode_type = 'manual' THEN
				v_per_day_min_minutes := EXTRACT(EPOCH FROM COALESCE(NULLIF(v_shift_details.lenient_per_day_hrs, ''), '00:00:00')::INTERVAL)/60;
			ELSIF v_shift_details.min_working_hrs_request_mode_type = 'shift_hours_len' OR v_shift_details.min_working_hrs_request_mode_type = 'shift' THEN
				v_per_day_min_minutes := EXTRACT(EPOCH FROM v_shift_details.default_shift_full_hours::INTERVAL)/60;
			END IF;

			IF COALESCE(v_shift_details.is_max_hours_required, 'N') = 'Y' THEN
				v_per_day_max_minutes := EXTRACT(EPOCH FROM COALESCE(NULLIF(v_shift_details.max_hours_per_day_time, ''), '00:00:00')::INTERVAL)/60;
			END IF;

			v_attandance_type := 'PP';
		END IF;
	-- END - Min/Max working hours Calculations

	-- START - Overtime Calculations
		IF p_customeraccountid IN (6969, 8895) THEN -- High-Flow Client
			v_ot_rules := NULLIF(v_assigned_shift_details.overtime_policy, '')::JSONB;
		ELSE
			v_ot_rules := NULLIF(v_shift_details.overtime_policy, '')::JSONB;
		END IF;

		v_overtime := (CASE WHEN v_ot_rules IS NOT NULL THEN 'Y' ELSE 'N' END);
		IF v_overtime = 'Y' THEN
		    SELECT t.wo_ho_type::TEXT INTO v_wo_ho_type
		    FROM public.usp_get_weekly_off_n_holiday_dates(
		        p_accountid => p_customeraccountid::bigint,
		        p_emp_id    => v_emp_id::bigint,
		        p_month     => v_month::INT,
		        p_year      => v_year::INT
		    ) t WHERE t.weekly_off_ho_date = v_att_date LIMIT 1;
		    IF v_wo_ho_type IS NOT NULL THEN
		        v_overtime_applicable_days := UPPER(v_wo_ho_type);
		    END IF;

			IF v_overtime_applicable_days = 'WO' THEN
				v_ot_rules_rate_structure := (CASE WHEN jsonb_typeof(v_ot_rules->'ot_rate_structure_week_off') = 'object' THEN v_ot_rules->'ot_rate_structure_week_off' ELSE '[]'::jsonb END);
			ELSIF v_overtime_applicable_days = 'HO' THEN
				v_ot_rules_rate_structure := (CASE WHEN jsonb_typeof(v_ot_rules->'ot_rate_structure_holiday') = 'object' THEN v_ot_rules->'ot_rate_structure_holiday' ELSE '[]'::jsonb END);
			ELSE
				v_ot_rules_rate_structure := (CASE WHEN jsonb_typeof(v_ot_rules->'ot_rate_structure_daily') = 'object' THEN v_ot_rules->'ot_rate_structure_daily' ELSE '[]'::jsonb END);
			END IF;

			v_ot_exclude_hrs_status := COALESCE(v_ot_rules_rate_structure->>'ot_exclude_hrs_status', 'N');
			v_ot_exclude_hrs := COALESCE(NULLIF(v_ot_rules_rate_structure->>'ot_exclude_hrs'::TEXT, ''), '00:00:00');
			v_ot_exclude_minutes := (EXTRACT(EPOCH FROM v_ot_exclude_hrs::interval) / 60)::INT;
			v_ot_start_mode := COALESCE(v_ot_rules_rate_structure->>'ot_start_mode', 'after_working_hours_completed');
			v_ot_start_minutes := v_shift_working_minutes_assigned;
			IF v_ot_start_mode = 'after_manual_hours' THEN
				v_ot_start_hrs := COALESCE(NULLIF(v_ot_rules_rate_structure->>'ot_start_hrs'::TEXT, ''), '00:00:00');
				v_ot_start_minutes := (EXTRACT(EPOCH FROM v_ot_start_hrs::interval) / 60)::INT;
			END IF;

			IF LOWER(v_ot_rules_rate_structure->>'ot_trigger_status') = 'true' THEN
				v_ot_trigger_after_hrs := COALESCE(NULLIF(v_ot_rules->>'ot_trigger_after_time'::TEXT, ''), '00:00:00');
				IF ((v_no_of_minutes_worked - v_shift_working_minutes) > 0 OR (v_no_of_minutes_worked - v_shift_working_minutes_assigned) > 0) OR (v_ishourlysetup = 'Y' AND v_no_of_minutes_worked > 0) OR v_overtime_applicable_days = 'WO' OR v_overtime_applicable_days = 'HO' THEN
					IF v_total_working_hours_calculation = 'every_valid_check' THEN
						IF (v_shift_working_minutes_assigned > v_no_of_minutes_worked AND v_overtime_applicable_days IN ('WO', 'HO')) OR (v_ishourlysetup = 'Y' AND v_no_of_minutes_worked > 0) THEN
							v_overtime_minutes := v_no_of_minutes_worked;
						ELSE
							v_overtime_minutes := (v_no_of_minutes_worked - v_shift_working_minutes_assigned);
						END IF;
					ELSE
						v_rounded_check_in := v_first_check_in_time;
						v_rounded_check_out := v_last_check_out_time;
						IF COALESCE(v_ot_rules_rate_structure ->> 'ot_rounding_in_time_enable', 'N') = 'Y' THEN
							v_rounded_check_in :=
								(
									SELECT date_trunc('hour', v_first_check_in_time + INTERVAL '5 hours 30 minutes') + (COALESCE((r->>'round_to_minutes')::int, 0) * INTERVAL '1 minute') 
									FROM jsonb_array_elements(COALESCE(v_ot_rules_rate_structure -> 'ot_rounding_in_time_rule', '[]'::jsonb)) AS r
									WHERE EXTRACT(minute FROM (v_first_check_in_time + INTERVAL '5 hours 30 minutes')) BETWEEN (r->>'start_minutes')::int AND (r->>'end_minutes')::int
									ORDER BY (r->>'start_minutes')::int
									LIMIT 1
								);
						ELSE
							v_rounded_check_in := DATE_TRUNC('hour', (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES')) +
								CASE
									WHEN EXTRACT(MINUTE FROM (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES')) < 15 THEN INTERVAL '0 minutes'
									WHEN EXTRACT(MINUTE FROM (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES')) < 30 THEN INTERVAL '30 minutes'
									ELSE INTERVAL '1 hour'
								END;
						END IF;

						IF COALESCE(v_ot_rules_rate_structure ->> 'ot_rounding_out_time_enable', 'N') = 'Y' THEN
							v_rounded_check_out :=
								(
									SELECT date_trunc('hour', v_last_check_out_time + INTERVAL '5 hours 30 minutes') + (COALESCE((r->>'round_to_minutes')::int, 0) * INTERVAL '1 minute') 
									FROM jsonb_array_elements(COALESCE(v_ot_rules_rate_structure -> 'ot_rounding_in_time_rule', '[]'::jsonb)) AS r
									WHERE EXTRACT(minute FROM (v_last_check_out_time + INTERVAL '5 hours 30 minutes')) BETWEEN (r->>'start_minutes')::int AND (r->>'end_minutes')::int
									ORDER BY (r->>'start_minutes')::int
									LIMIT 1
								);
						ELSE
							v_rounded_check_out := DATE_TRUNC('hour', (v_last_check_out_time + INTERVAL '5 HOURS 30 MINUTES')) +
								CASE
									WHEN EXTRACT(MINUTE FROM (v_last_check_out_time + INTERVAL '5 HOURS 30 MINUTES')) < 15 THEN INTERVAL '0 minutes'
									WHEN EXTRACT(MINUTE FROM (v_last_check_out_time + INTERVAL '5 HOURS 30 MINUTES')) < 59 THEN INTERVAL '30 minutes'
									ELSE INTERVAL '1 hour'
								END;
						END IF;

						-- Calculate the duration
						v_rounded_no_of_hours_worked := 
							LPAD(FLOOR(EXTRACT(EPOCH FROM (v_rounded_check_out - v_rounded_check_in)) / 3600)::TEXT, 2, '0') || ':' ||
							LPAD(FLOOR((EXTRACT(EPOCH FROM (v_rounded_check_out - v_rounded_check_in)) % 3600) / 60)::TEXT, 2, '0') || ':' ||
							LPAD(FLOOR((EXTRACT(EPOCH FROM (v_rounded_check_out - v_rounded_check_in)) % 60))::TEXT, 2, '0');
	
						v_rounded_no_of_minutes_worked := EXTRACT(EPOCH FROM (v_rounded_no_of_hours_worked::INTERVAL - v_assigned_total_break_unpaid))/60;
						IF v_overtime_applicable_days = 'WO' OR v_overtime_applicable_days = 'HO' THEN
							v_overtime_minutes := v_rounded_no_of_minutes_worked; -- after_working_hours_completed
							v_shift_start_time := v_shift_start_timing_IST;
							v_shift_end_time := v_shift_end_timing_IST;
							IF v_ot_exclude_hrs_status = 'Y' THEN
								v_shift_end_time := v_shift_end_timing_IST - v_ot_exclude_hrs::INTERVAL;
								v_shift_end_timing := v_shift_end_timing - v_ot_exclude_hrs::INTERVAL;
								-- v_shift_working_minutes_assigned_after_unpaid_break := v_shift_working_minutes_assigned_after_unpaid_break - v_ot_exclude_minutes;
							END IF;

							-- NOTE: - This query response will be in seconds, so please divide by 60 to get the minutes
								SELECT
									v_rounded_check_in check_in, v_rounded_check_out check_out,
									v_shift_start_time shift_start_time, v_shift_end_time shift_end_time,
									EXTRACT(EPOCH FROM GREATEST(v_shift_start_time - v_rounded_check_in, INTERVAL '0')) AS check_in_before_shift_start,
									EXTRACT(EPOCH FROM GREATEST(v_rounded_check_in - v_shift_start_time, INTERVAL '0')) AS check_in_after_shift_start,
									EXTRACT(EPOCH FROM GREATEST(v_shift_end_time - v_rounded_check_out, INTERVAL '0')) AS check_out_before_shift_end,
									EXTRACT(EPOCH FROM GREATEST(v_rounded_check_out - v_shift_end_time, INTERVAL '0')) AS check_out_after_shift_end,
									EXTRACT(EPOCH FROM GREATEST(LEAST(v_rounded_check_out, v_shift_end_time) - GREATEST(v_rounded_check_in, v_shift_start_time), INTERVAL '0')) AS worked_within_shift
								INTO v_att_time_summary;
							-- NOTE: - This query response will be in seconds, so please divide by 60 to get the minutes
		
							IF v_ot_start_mode = 'shift_hours' THEN
								v_overtime_minutes := v_rounded_no_of_minutes_worked;
							ELSIF v_ot_start_mode = 'after_shift_ends' THEN
								v_overtime_minutes := (v_att_time_summary.check_out_after_shift_end/60);
							ELSIF v_ot_start_mode = 'after_manual_hours' THEN
								v_ot_start_hrs := COALESCE(NULLIF(v_ot_rules_rate_structure->>'ot_start_hrs'::TEXT, ''), '00:00:00');
								v_overtime_minutes := v_rounded_no_of_minutes_worked - v_ot_start_minutes;
							ELSE -- after_working_hours_completed
								v_overtime_minutes := v_rounded_no_of_minutes_worked;
							END IF;
						ELSE
							v_overtime_minutes := v_rounded_no_of_minutes_worked - v_shift_working_minutes_assigned;
						END IF;
						IF v_overtime_minutes <= 0 THEN
							v_overtime_minutes := 0;
						END IF;
					END IF;

					-- START - OT Round-Off Minutes;
						IF COALESCE(v_ot_rules_rate_structure ->> 'ot_rounding_no_of_working_hrs_enable', 'N') = 'Y' THEN
						    SELECT (v_overtime_minutes::INT / 60) * 60 + COALESCE((r->>'round_to_minutes')::int, v_overtime_minutes::INT % 60)
						    INTO v_overtime_minutes
						    FROM jsonb_array_elements((v_ot_rules_rate_structure ->> 'ot_rounding_no_of_working_hrs_rule')::JSONB) AS r
						    WHERE (v_overtime_minutes::INT % 60) BETWEEN (r->>'start_minutes')::int AND (r->>'end_minutes')::int
						    ORDER BY (r->>'start_minutes')::int
						    LIMIT 1;
						ELSIF COALESCE(NULLIF(v_ot_rules_rate_structure->>'ot_rounding_minutes', ''), '0')::numeric > 0 THEN
							v_overtime_minutes := round(v_overtime_minutes::numeric / (v_ot_rules_rate_structure->>'ot_rounding_minutes')::numeric) * (v_ot_rules_rate_structure->>'ot_rounding_minutes')::numeric;
						END IF;
					-- END - OT Round-Off Minutes;
				END IF;

				-- Daily capping on overtime
				FOR v_ot_rules_restrictions IN (SELECT elem FROM jsonb_array_elements(v_ot_rules->'ot_rules_restrictions') elem WHERE elem->>'calculation_type' = 'daily') LOOP
					v_overtime_max_minutes := (EXTRACT(EPOCH FROM COALESCE(NULLIF(v_ot_rules_restrictions->>'max_hours',''),'00:00:00')::time) / 60)::NUMERIC;
					IF v_overtime_minutes > v_overtime_max_minutes THEN
						v_overtime_minutes := v_overtime_max_minutes;
						v_overtime_restriction_summary := format(' | Daily Cap: %s minutes', v_overtime_max_minutes);
					END IF;
				END LOOP;

				v_overtime_minutes_calculations := v_overtime_minutes;
				-- Multiplier loop ot_time_calculation
				IF EXISTS (
					SELECT 1
					FROM jsonb_array_elements(jsonb_build_array(v_ot_rules_rate_structure)) AS rate_struct
					CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(rate_struct->'ot_time_calculation') = 'array' THEN rate_struct->'ot_time_calculation' ELSE '[]'::jsonb END) AS calc
				) THEN
					FOR v_multiplier IN
						SELECT calc
						FROM jsonb_array_elements(jsonb_build_array(v_ot_rules_rate_structure)) AS rate_struct
						CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(rate_struct->'ot_time_calculation') = 'array' THEN rate_struct->'ot_time_calculation' ELSE '[]'::jsonb END) AS calc
					LOOP
						EXIT WHEN v_overtime_minutes_calculations <= 0;

						-- convert hours_limit (HH:MI:SS) to minutes
						v_overtime_limit_minutes := (EXTRACT(EPOCH FROM COALESCE(NULLIF(v_multiplier->>'hours_limit',''),'00:00:00')::time) / 60)::numeric;

						-- how many minutes apply for this slab
						v_applicable_minutes := LEAST(v_overtime_minutes_calculations, v_overtime_limit_minutes);

						-- subtract used minutes
						v_overtime_minutes_calculations := v_overtime_minutes_calculations - v_applicable_minutes;

						IF v_multiplier->>'pay_on_salary_head' = 'fixed_amount' THEN
							v_head_amount := coalesce((v_multiplier->>'rate_multiplier')::numeric, 0);

							-- BEFORE multiplier
							v_overtime_amount_before_multiplier := v_head_amount * (v_applicable_minutes / 60);

							-- accumulate final amount (use post-multiplier amount)
							v_overtime_final_amount := v_overtime_final_amount + v_overtime_amount_before_multiplier;

							-- append a narrative line (formatted numbers)
							v_overtime_summary := COALESCE(v_overtime_summary, '') || format(
								E'\n\nIn this rule, pay was based on a fixed amount of ₹%s/Hrs with a %s-minute cap. The usage was %s minutes, yielding ₹%s from the fixed amount. Remaining OT minutes: %s.',
								v_head_amount,
								to_char(v_overtime_limit_minutes,'FM9999990'),
								to_char(v_applicable_minutes,'FM999990.00'),
								to_char(v_overtime_amount_before_multiplier,'FM999999990.00'),
								to_char(v_overtime_minutes_calculations,'FM999990.00')
							);
						ELSE
							EXECUTE format(
								'SELECT %I FROM empsalaryregister WHERE appointment_id = $1 AND isactive = ''1''',
								v_multiplier->>'pay_on_salary_head'
							) INTO v_head_amount USING v_emp_id;

							-- BEFORE multiplier
							v_overtime_amount_before_multiplier := (v_head_amount / v_emp_salary.month_days::NUMERIC) * (v_applicable_minutes / v_shift_working_minutes_assigned_after_unpaid_break);

							-- AFTER multiplier
							v_overtime_amount_after_multiplier := v_overtime_amount_before_multiplier * coalesce((v_multiplier->>'rate_multiplier')::numeric, 1);

							-- accumulate final amount (use post-multiplier amount)
							v_overtime_final_amount := v_overtime_final_amount + v_overtime_amount_after_multiplier;

							-- append a narrative line (formatted numbers)
							v_overtime_summary := COALESCE(v_overtime_summary, '') || format(
								E'\n\nIn this rule, pay was based on %s (₹%s) on %s salary setup days with a %sx multiplier and a %s-minute cap. This used %s minutes, producing ((₹%s %s / %s Salary Days) * (%s Over Time Minutes / %s Shift Minutes)) = ₹%s before the multiplier and ₹%s after %sx multiplier. Remaining OT minutes: %s.',
								v_multiplier->>'pay_on_salary_head', v_head_amount,
								v_emp_salary.month_days,
								v_multiplier->>'rate_multiplier',
								to_char(v_overtime_limit_minutes,'FM9999990'),
								to_char(v_applicable_minutes,'FM999990.00'),
								v_head_amount, v_multiplier->>'pay_on_salary_head', (v_emp_salary.month_days::NUMERIC), v_applicable_minutes, v_shift_working_minutes_assigned_after_unpaid_break,
								to_char(v_overtime_amount_before_multiplier,'FM999999990.00'),
								to_char(v_overtime_amount_after_multiplier,'FM999999990.00'),
								v_multiplier->>'rate_multiplier',
								to_char(v_overtime_minutes_calculations,'FM999990.00')
							);
						END IF;
					END LOOP;
				END IF;

				-- final paragraph
				v_overtime_summary := format(
					E'Overtime: %s minutes | Shift After Unpaid Break: %s minutes%s. %s \n\nTogether, the final overtime pay is %s.',
					to_char(v_overtime_minutes,'FM999990'),
					to_char(v_shift_working_minutes_assigned,'FM999990'),
					v_overtime_restriction_summary, 
					v_overtime_summary,
					to_char(v_overtime_final_amount,'FM999999990.00')
				);
			END IF;
		END IF;
	-- END - Overtime Calculations

	-- START - Leave Details (As Discussed with Yatin Sir and Chander Mohan Sir)
		/*
			Leave deductions should adhere to the established order of precedence:
			1. First, deduct from Casual Leave (CL).
			2. If CL is exhausted, deduct from Medical Leave (ML).
			3. If both CL and ML are unavailable, deduct from Earned Leave (EL).
		*/

		DROP TABLE IF EXISTS tmp_candidate_leave_balance;
		CREATE TEMPORARY TABLE tmp_candidate_leave_balance 
		(
			typecode text,
			typename text,
			effective_min_paid_days text,
			prev_bal DECIMAL
		) ON COMMIT DROP;

		SELECT * FROM get_leave_balance_by_account
		(
			p_account_id => p_customeraccountid::text,
			p_att_month => v_month::text,
			p_att_year => v_year::text,
			p_emp_id => v_emp_id::text,
			p_att_processdt => p_att_date::text
		)
		INTO v_leave_template_details LIMIT 1;
		IF COUNT(v_leave_template_details) > 0 THEN
			WITH json_data AS
			(
				SELECT jsonb_array_elements(v_leave_template_details.balance_txt::jsonb) AS elem
			)
			INSERT INTO tmp_candidate_leave_balance
			SELECT elem->>'typecode', elem->>'typename', elem->>'effective_min_paid_days', COALESCE(elem->>'prev_bal', '0')::DECIMAL FROM json_data;

			IF v_attandance_type = 'HD' THEN
				v_attandance_leave_type := 'AA';

				IF p_customeraccountid = 5852 THEN
					v_attandance_leave_type := 'AA';
				END IF;
			END IF;
		END IF;
	-- START - Leave Details

	-- START - Grace Policy Changes
		v_is_grace_policy_applied := (CASE WHEN v_shift_details.grace_period_policy IS NOT NULL THEN 'Y' ELSE 'N' END);
		IF v_is_grace_policy_applied = 'Y' THEN
			IF NULLIF(v_shift_details.grace_period_policy, ''::text)::jsonb ->> 'deviations' IS NOT NULL THEN
				SELECT (NULLIF(v_shift_details.grace_period_policy, ''::text)::jsonb ->> 'deviations')::jsonb INTO v_grace_period_JSON;
				FOR v_grace_row_data IN SELECT * FROM jsonb_array_elements(v_grace_period_JSON) LOOP
					v_deviation_type := (NULLIF((v_grace_row_data->>'deviation_type'), ''));
					v_grace_period_in_minutes := (COALESCE(NULLIF((v_grace_row_data->>'grace_period_in_minutes'), ''), '0'))::NUMERIC;
					v_grace_period_max_uses := (COALESCE(NULLIF((v_grace_row_data->>'max_uses'), ''), '0'))::INT;
					v_grace_period_max_uses_period := (NULLIF((v_grace_row_data->>'reset_period'), '')); -- weekly, monthly, quarterly, yearly

					v_deviations_from_date := p_att_date;
					v_deviations_to_date := p_att_date;
					IF v_grace_period_max_uses_period = 'weekly' THEN
						v_deviations_from_date := TO_CHAR(date_trunc('week', TO_DATE(p_att_date, 'DD/MM/YYYY'))::date, 'DD/MM/YYYY');
					ELSIF v_grace_period_max_uses_period = 'monthly' THEN
						v_deviations_from_date := TO_CHAR(date_trunc('month', TO_DATE(p_att_date, 'DD/MM/YYYY'))::date, 'DD/MM/YYYY');
					ELSIF v_grace_period_max_uses_period = 'quarterly' THEN
						v_deviations_from_date := TO_CHAR(date_trunc('month', TO_DATE(p_att_date,'DD/MM/YYYY') - interval '2 month')::date, 'DD/MM/YYYY');
					ELSIF v_grace_period_max_uses_period = 'yearly' THEN
						v_deviations_from_date := TO_CHAR(date_trunc('year', TO_DATE(p_att_date,'DD/MM/YYYY'))::date, 'DD/MM/YYYY');
					END IF;

					SELECT public.usp_calculate_employee_deviations(
						p_action => v_deviation_type::character varying,
						p_customeraccountid => p_customeraccountid::bigint,
						p_emp_code => p_emp_code::bigint,
						p_from_date => v_deviations_from_date::character varying,
						p_to_date => v_deviations_to_date::character varying
					) INTO v_emp_deviations;

					v_final_fixed_amount_penalty := 0;
					v_final_per_minute_penalty := 0;
					v_final_qtrs_penalty := 0;
					v_penalty_qtrs_deduction := 0;
					SELECT jsonb_agg(j_elem ORDER BY (j_elem->>'deviation_after_minutes')::int ASC)
				    INTO v_penality_rules
				    FROM jsonb_array_elements(COALESCE((v_shift_details.penality_policy::jsonb -> v_deviation_type), '[]'::jsonb)) AS j_elem
					WHERE (j_elem->>'enabled')::boolean = TRUE;
					v_penalty_mode := LOWER(COALESCE(NULLIF(v_shift_details.penality_policy::JSONB ->>'penalty_mode', ''), 'Strict'));
					v_penalty_workflow_enabled := v_shift_details.penality_policy::JSONB ->>'penalty_workflow_enabled';
					IF v_penalty_workflow_enabled = 'Y' THEN
						v_grace_period_in_minutes := 0;
					END IF;

					-- Create temp table
					DROP TABLE IF EXISTS tmp_leave_penalty_rules;
					CREATE TEMP TABLE tmp_leave_penalty_rules (
						title TEXT,
						start_time INT,
						end_time INT,
						max_uses_mode TEXT DEFAULT 'deviation_more_than',
						max_uses INT DEFAULT 0,
						used_deviations INT DEFAULT 0,
						balance_deviations INT DEFAULT 0,
						leave_deduction INT DEFAULT 0,
						leave_priority JSONB
					);

					DROP TABLE IF EXISTS tmp_penalty_rules;
					CREATE TEMP TABLE tmp_penalty_rules (
						title TEXT,
						start_time INT,
						end_time INT,
						qtrs_deduction NUMERIC DEFAULT 0,
						max_uses_mode TEXT DEFAULT 'deviation_more_than',
						max_uses INT DEFAULT 0,
						used_deviations INT DEFAULT 0,
						balance_deviations INT DEFAULT 0,
						fixed_amount_deduction BIGINT DEFAULT 0,
						per_minute_deduction BIGINT DEFAULT 0,
						same_as_ot_config_deduction character varying DEFAULT 'N',
						leave_deduction_enabled character varying DEFAULT 'N',
						exempt_deviation_after_working_hrs_completed BOOLEAN DEFAULT false,
						fore_color TEXT DEFAULT NULL,
						background_color TEXT DEFAULT NULL,
						leave_deduction NUMERIC DEFAULT 0,
						leave_priority JSONB
					);

					FOR v_rule IN SELECT value FROM jsonb_array_elements(COALESCE(v_penality_rules, '[]'::jsonb)) LOOP
						-- v_fixed_amount_penalty := 0;
						v_per_minute_penalty := 0;
						IF COALESCE(v_rule->>'enabled','false') = 'true' THEN
							FOR v_penalty IN SELECT * FROM jsonb_array_elements(COALESCE(v_rule->'penalty_type', '[]'::jsonb)) LOOP
								IF v_penalty->>'value' = 'fixed_amount' THEN
									v_penalty_as_fixed_amount_enabled := 'Y';
								ELSIF v_penalty->>'value' = 'per_minute' THEN
									v_penalty_as_per_minutes_enabled := 'Y';
								ELSIF v_penalty->>'value' = 'time_deduction' THEN
									v_shift_working_minutes := v_shift_working_minutes - (EXTRACT(EPOCH FROM v_total_break_unpaid) / 60);
									v_one_qtrs_minutes := (v_shift_working_minutes/4); -- Get shift timing and get one quarter’s value by dividing by 4.
									v_one_day_salary := (v_emp_salary.gross / v_emp_salary.month_days::NUMERIC);
									v_one_qtrs_minutes_salary := (v_one_day_salary/4);
									v_penalty_as_qtrs_deduction_enabled := 'Y';
								ELSIF v_penalty->>'value' = 'same_as_ot_config' THEN
									v_penalty_as_ot_config_deduction_enabled := 'Y';
								ELSIF v_penalty->>'value' = 'leave' THEN
									v_penalty_as_leave_deduction_enabled := 'Y';
								END IF;
							END LOOP;
						END IF;
					END LOOP;
					v_deviations_more_than_times := v_rule->>'deviation_after_minutes';

					IF NULLIF(v_penality_rules, '[]'::JSONB) IS NOT NULL THEN
						-- START - Leave Deduction Rules
							DROP TABLE IF EXISTS tmp_leave_penalty_rules;
							CREATE TEMP TABLE tmp_leave_penalty_rules ON COMMIT DROP AS
							WITH penalty_data AS (SELECT jsonb_array_elements(v_penality_rules) AS elem)
							SELECT
								elem->>'title' AS title,
								(elem->>'deviation_after_minutes')::INT AS start_time,
								COALESCE(LEAD((elem->>'deviation_after_minutes')::INT) OVER (ORDER BY (elem->>'deviation_after_minutes')::INT), 44640) AS end_time,
								COALESCE(elem->>'max_uses_mode', 'deviation_more_than') AS max_uses_mode,
								(elem->>'max_uses')::INT AS max_uses,
								0 used_deviations,
								(elem->>'max_uses')::INT balance_deviations,
								(SELECT (pt->>'leave_deduction')::NUMERIC FROM jsonb_array_elements(elem->'penalty_type') AS pt WHERE pt->>'value' = 'leave' LIMIT 1) AS leave_deduction,
								NULLIF(elem->'leave_priority', '[]'::jsonb) AS leave_priority
							FROM penalty_data
							WHERE (elem->>'enabled')::BOOLEAN = TRUE;
						-- END - Leave Deduction Rules

						-- START - Penality (Fixed and Qtrs Deduction) Rules
							FOR v_penality_rule_window IN
								SELECT
									value AS rule,
									(value->>'title') AS title,
									(value->>'deviation_after_minutes')::int AS start_time,
									COALESCE(LEAD((value->>'deviation_after_minutes')::int) OVER (ORDER BY (value->>'deviation_after_minutes')::int), 1440) AS end_time,
									(value->>'max_uses')::int AS max_uses,
									COALESCE(value->>'max_uses_mode', 'deviation_more_than') AS max_uses_mode
								FROM jsonb_array_elements(v_penality_rules)
							LOOP
								v_rule := v_penality_rule_window.rule;
								FOR v_penalty IN SELECT * FROM jsonb_array_elements(v_rule->'penalty_type') LOOP
									IF v_penalty->>'value' = 'fixed_amount' THEN
										IF EXISTS (SELECT 1 FROM tmp_penalty_rules WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time) THEN
											UPDATE tmp_penalty_rules
											SET
												fixed_amount_deduction = (COALESCE(NULLIF(v_penalty->>'amount'::TEXT, ''), '0'))::NUMERIC(16, 2),
												max_uses_mode = v_penality_rule_window.max_uses_mode,
												fore_color = (v_rule->>'fore_color'),
												background_color = (v_rule->>'background_color')
											WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time;
										ELSE
											INSERT INTO tmp_penalty_rules(title, start_time, end_time, fixed_amount_deduction, max_uses, max_uses_mode, exempt_deviation_after_working_hrs_completed, fore_color, background_color)
											VALUES (v_penality_rule_window.title, v_penality_rule_window.start_time, v_penality_rule_window.end_time, (COALESCE(NULLIF(v_penalty->>'amount'::TEXT, ''), '0'))::NUMERIC(16, 2), v_penality_rule_window.max_uses, v_penality_rule_window.max_uses_mode, (v_rule->>'exempt_deviation_after_working_hrs_completed')::BOOLEAN, (v_rule->>'fore_color'), (v_rule->>'background_color'));
										END IF;
									ELSIF v_penalty->>'value' = 'per_minute' THEN
										IF EXISTS (SELECT 1 FROM tmp_penalty_rules WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time) THEN
											UPDATE tmp_penalty_rules
											SET
												per_minute_deduction = (COALESCE(NULLIF(v_penalty->>'amount'::TEXT, ''), '0'))::NUMERIC(16, 2),
												max_uses_mode = v_penality_rule_window.max_uses_mode,
												fore_color = (v_rule->>'fore_color'),
												background_color = (v_rule->>'background_color')
											WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time;
										ELSE
											INSERT INTO tmp_penalty_rules(title, start_time, end_time, per_minute_deduction, max_uses, max_uses_mode, exempt_deviation_after_working_hrs_completed, fore_color, background_color)
											VALUES (v_penality_rule_window.title, v_penality_rule_window.start_time, v_penality_rule_window.end_time, (COALESCE(NULLIF(v_penalty->>'amount'::TEXT, ''), '0'))::NUMERIC(16, 2), v_penality_rule_window.max_uses, v_penality_rule_window.max_uses_mode, (v_rule->>'exempt_deviation_after_working_hrs_completed')::BOOLEAN, (v_rule->>'fore_color'), (v_rule->>'background_color'));
										END IF;
									ELSIF v_penalty->>'value' = 'time_deduction' THEN
										IF EXISTS (SELECT 1 FROM tmp_penalty_rules WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time) THEN
											UPDATE tmp_penalty_rules
											SET
												qtrs_deduction = (v_penalty->>'time_deduction')::NUMERIC,
												max_uses_mode = v_penality_rule_window.max_uses_mode,
												fore_color = (v_rule->>'fore_color'),
												background_color = (v_rule->>'background_color')
											WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time;
										ELSE
											INSERT INTO tmp_penalty_rules(title, start_time, end_time, qtrs_deduction, max_uses, max_uses_mode, exempt_deviation_after_working_hrs_completed, fore_color, background_color)
											VALUES (v_penality_rule_window.title, v_penality_rule_window.start_time, v_penality_rule_window.end_time, (v_penalty->>'time_deduction')::NUMERIC, v_penality_rule_window.max_uses, v_penality_rule_window.max_uses_mode, (v_rule->>'exempt_deviation_after_working_hrs_completed')::BOOLEAN, (v_rule->>'fore_color'), (v_rule->>'background_color'));
										END IF;
									ELSIF v_penalty->>'value' = 'same_as_ot_config' THEN
										IF EXISTS (SELECT 1 FROM tmp_penalty_rules WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time) THEN
											UPDATE tmp_penalty_rules
											SET
												same_as_ot_config_deduction = v_penalty_as_ot_config_deduction_enabled,
												max_uses_mode = v_penality_rule_window.max_uses_mode,
												fore_color = (v_rule->>'fore_color'),
												background_color = (v_rule->>'background_color')
											WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time;
										ELSE
											INSERT INTO tmp_penalty_rules(title, start_time, end_time, same_as_ot_config_deduction, max_uses, max_uses_mode, exempt_deviation_after_working_hrs_completed, fore_color, background_color)
											VALUES (v_penality_rule_window.title, v_penality_rule_window.start_time, v_penality_rule_window.end_time, v_penalty_as_ot_config_deduction_enabled, v_penality_rule_window.max_uses, v_penality_rule_window.max_uses_mode, (v_rule->>'exempt_deviation_after_working_hrs_completed')::BOOLEAN, (v_rule->>'fore_color'), (v_rule->>'background_color'));
										END IF;
									ELSIF v_penalty->>'value' = 'leave' THEN
										IF EXISTS (SELECT 1 FROM tmp_penalty_rules WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time) THEN
											UPDATE tmp_penalty_rules
											SET
												leave_deduction_enabled = v_penalty_as_leave_deduction_enabled,
												max_uses_mode = v_penality_rule_window.max_uses_mode,
												fore_color = (v_rule->>'fore_color'),
												background_color = (v_rule->>'background_color'),
												leave_deduction = (v_penalty->>'leave_deduction')::NUMERIC,
												leave_priority = (v_rule->'leave_priority')
											WHERE title = v_penality_rule_window.title AND start_time = v_penality_rule_window.start_time AND end_time = v_penality_rule_window.end_time;
										ELSE
											INSERT INTO tmp_penalty_rules(title, start_time, end_time, leave_deduction_enabled, max_uses, max_uses_mode, exempt_deviation_after_working_hrs_completed, fore_color, background_color, leave_deduction, leave_priority)
											VALUES (v_penality_rule_window.title, v_penality_rule_window.start_time, v_penality_rule_window.end_time, v_penalty_as_leave_deduction_enabled, v_penality_rule_window.max_uses, v_penality_rule_window.max_uses_mode, (v_rule->>'exempt_deviation_after_working_hrs_completed')::BOOLEAN, (v_rule->>'fore_color'), (v_rule->>'background_color'), (v_penalty->>'leave_deduction')::NUMERIC, (v_rule->'leave_priority'));
										END IF;
									END IF;
								END LOOP;
							END LOOP;
						-- END - Penality (Fixed and Qtrs Deduction) Rules
					END IF;

					IF v_penalty_as_leave_deduction_enabled = 'Y' AND NULLIF(v_penality_rules, '[]'::JSONB) IS NOT NULL THEN
						FOR v_leave_penality_rec IN SELECT * FROM tmp_leave_penalty_rules LOOP
							-- Call the deviation calculation function
							IF p_customeraccountid IN (8613, 8887) THEN
								SELECT public.usp_calculate_employee_deviations(
									p_action              => 'check-in/out'::varchar,
									p_customeraccountid   => p_customeraccountid::bigint,
									p_emp_code            => p_emp_code::bigint,
									p_from_date           => v_deviations_from_date::varchar,
									p_to_date             => v_deviations_to_date::varchar,
									p_start_time          => to_char(make_interval(mins := v_leave_penality_rec.start_time), 'HH24:MI:SS')::varchar,
									p_end_time            => to_char(make_interval(mins := v_leave_penality_rec.end_time), 'HH24:MI:SS')::varchar
								)
								INTO v_leave_emp_deviations;
							ELSE
								SELECT public.usp_calculate_employee_deviations(
									p_action              => 'check-in/out'::varchar,
									p_customeraccountid   => p_customeraccountid::bigint,
									p_emp_code            => p_emp_code::bigint,
									p_from_date           => v_deviations_from_date::varchar,
									p_to_date             => v_deviations_to_date::varchar
								) INTO v_leave_emp_deviations;
								-- END - Change [1.4] - Multiple Occurrence Penalty Deduction
							END IF;

							-- Update the current record with the result
							UPDATE tmp_leave_penalty_rules
							SET
								used_deviations = v_leave_emp_deviations,
								balance_deviations = GREATEST(v_leave_penality_rec.max_uses - v_leave_emp_deviations, 0)
							WHERE title = v_leave_penality_rec.title AND start_time = v_leave_penality_rec.start_time AND end_time = v_leave_penality_rec.end_time;
						END LOOP;
					END IF;

					IF NULLIF(v_penality_rules, '[]'::JSONB) IS NOT NULL THEN
						-- Loop through each row
						FOR v_qtrs_penality_rec IN SELECT * FROM tmp_penalty_rules LOOP
							-- Call the deviation calculation function
							SELECT public.usp_calculate_employee_deviations(
								p_action              => v_deviation_type::varchar,
								p_customeraccountid   => p_customeraccountid::bigint,
								p_emp_code            => p_emp_code::bigint,
								p_from_date           => v_deviations_from_date::varchar,
								p_to_date             => (CASE WHEN v_deviations_from_date = v_deviations_to_date THEN v_deviations_to_date ELSE TO_CHAR(TO_DATE(v_deviations_to_date, 'DD/MM/YYYY') - INTERVAL '1 DAY', 'DD/MM/YYYY') END)::varchar,
								p_start_time          => to_char(make_interval(mins := v_qtrs_penality_rec.start_time), 'HH24:MI:SS')::varchar,
								p_end_time            => to_char(make_interval(mins := v_qtrs_penality_rec.end_time), 'HH24:MI:SS')::varchar
							) INTO v_qtrs_emp_deviations;

							-- Update the current record with the result
							UPDATE tmp_penalty_rules
							SET
								used_deviations = v_qtrs_emp_deviations,
								balance_deviations = GREATEST(v_qtrs_penality_rec.max_uses - v_qtrs_emp_deviations, 0)
							WHERE title = v_qtrs_penality_rec.title AND start_time = v_qtrs_penality_rec.start_time AND end_time = v_qtrs_penality_rec.end_time;
						END LOOP;
					END IF;

					IF v_deviation_type = 'check-in' THEN
						v_deviation_in_checkin := 0;
						IF ((EXTRACT(EPOCH FROM v_first_check_in_time::TIMESTAMP - v_shift_start_timing::TIMESTAMP) / 60) > v_grace_period_in_minutes) AND ((v_LC_EG_enabled_in_app_setting = 'app-setting' AND v_LC_enabled_in_app_setting = 'Y') OR v_LC_EG_enabled_in_app_setting = 'penality-rule') THEN
							v_is_late_comer := 'Y';
							v_deviation_in_checkin := 1;
							IF v_emp_deviations > v_grace_period_max_uses THEN
								v_deviation_in_checkin_time := (TO_CHAR((v_first_check_in_time::TIMESTAMP - v_shift_start_timing::TIMESTAMP), 'HH24:MI:SS'))::TEXT;
								v_deviation_in_checkin_time_in_minutes := ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkin_time::time) / 60)::int;
								v_penality_remaning_minutes_calculations_saot := v_deviation_in_checkin_time_in_minutes - v_deviations_more_than_times;

								IF v_penalty_mode = 'strict' THEN
									SELECT * INTO v_tmp_penalty_rules
									FROM tmp_penalty_rules
									WHERE v_deviation_in_checkin_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC;

									SELECT att_date INTO v_last_penalty_date
									FROM tbl_monthly_attendance tma
									WHERE
										tma.isactive = '1' AND tma.emp_code = p_emp_code AND tma.att_date < v_att_date AND tma.deviation_in_checkin = '1' AND
										(COALESCE(NULLIF(latehours, ''), '00:00:00')::INTERVAL BETWEEN to_char(make_interval(mins := v_tmp_penalty_rules.start_time), 'HH24:MI:SS')::INTERVAL AND to_char(make_interval(mins := v_tmp_penalty_rules.end_time), 'HH24:MI:SS')::INTERVAL
										AND (latehoursdeduction > 0 OR tma.attendance_type = 'HD'))
									ORDER BY tma.att_date DESC LIMIT 1;
									v_last_penalty_date := GREATEST(v_last_penalty_date, (DATE_TRUNC('MONTH', v_att_date))::date);

									-- START - Change [1.4] - Multiple Occurrence Penalty (Continuous/Every) Deduction
									IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_after' OR v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_of_every' THEN
										v_penalty_search_to := (v_att_date - INTERVAL '1 DAY')::DATE;
										IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_of_every' THEN
											v_penalty_search_from := CASE WHEN v_last_penalty_date IS NOT NULL THEN (v_last_penalty_date + INTERVAL '1 DAY')::DATE ELSE (DATE_TRUNC('month', v_att_date))::DATE END;
										ELSE
											v_penalty_search_from := GREATEST((v_last_penalty_date + INTERVAL '1 DAY')::DATE, (v_att_date - (v_tmp_penalty_rules.max_uses || ' days')::INTERVAL)::DATE);
										END IF;
										SELECT public.usp_calculate_employee_deviations(
											p_action => v_deviation_type::character varying,
											p_customeraccountid => p_customeraccountid::bigint,
											p_emp_code => p_emp_code::bigint,
											p_from_date => TO_CHAR(v_penalty_search_from, 'DD/MM/YYYY')::character varying,
											p_to_date => TO_CHAR(v_penalty_search_to, 'DD/MM/YYYY')::character varying,
											p_start_time => to_char(make_interval(mins := v_tmp_penalty_rules.start_time), 'HH24:MI:SS')::varchar,
											p_end_time => to_char(make_interval(mins := v_tmp_penalty_rules.end_time), 'HH24:MI:SS')::varchar
										) INTO v_emp_deviations;

										IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_after' THEN
											UPDATE tmp_penalty_rules SET used_deviations = v_emp_deviations, balance_deviations = GREATEST(v_tmp_penalty_rules.max_uses - v_emp_deviations, 0) WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
											UPDATE tmp_leave_penalty_rules SET used_deviations = v_emp_deviations, balance_deviations = GREATEST(v_tmp_penalty_rules.max_uses - v_emp_deviations, 0); -- WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
										ELSIF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_of_every' THEN
											UPDATE tmp_penalty_rules SET used_deviations = CASE WHEN (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) = 0 THEN v_emp_deviations ELSE (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) END, balance_deviations = (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
											UPDATE tmp_leave_penalty_rules SET used_deviations = CASE WHEN (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) = 0 THEN v_emp_deviations ELSE (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) END, balance_deviations = (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)); -- WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
										END IF;
										SELECT * INTO v_tmp_penalty_rules
										FROM tmp_penalty_rules
										WHERE v_deviation_in_checkin_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC;
									END IF;
									-- END - Change [1.4] - Multiple Occurrence Penalty Deduction
								ELSE
									SELECT att_date INTO v_last_penalty_date
									FROM tbl_monthly_attendance tma
									WHERE tma.isactive = '1' AND tma.emp_code = p_emp_code AND tma.att_date < v_att_date AND tma.deviation_in_checkin = '1' AND (latehoursdeduction > 0 OR tma.attendance_type = 'HD')
									ORDER BY tma.att_date DESC LIMIT 1;
									IF v_emp_deviations > (SELECT SUM(max_uses) FROM tmp_penalty_rules) THEN
										UPDATE tmp_penalty_rules SET used_deviations = v_emp_deviations;
										SELECT * INTO v_tmp_penalty_rules
										FROM tmp_penalty_rules
										WHERE v_deviation_in_checkin_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC;

										-- START - Change [1.4] - Multiple Occurrence Penalty Deduction
										IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_after' OR v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_of_every' THEN
											v_penalty_search_to := (v_att_date - INTERVAL '1 DAY')::DATE;
											IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_of_every' THEN
												v_penalty_search_from := CASE WHEN v_last_penalty_date IS NOT NULL THEN (v_last_penalty_date + INTERVAL '1 DAY')::DATE ELSE (DATE_TRUNC('month', v_att_date))::DATE END;
											ELSE
												v_penalty_search_from := GREATEST((v_last_penalty_date + INTERVAL '1 DAY'), (v_att_date - (v_tmp_penalty_rules.max_uses || ' days')::INTERVAL)::DATE);
											END IF;
											SELECT public.usp_calculate_employee_deviations(
												p_action => v_deviation_type::character varying,
												p_customeraccountid => p_customeraccountid::bigint,
												p_emp_code => p_emp_code::bigint,
												p_from_date => TO_CHAR(v_penalty_search_from, 'DD/MM/YYYY')::character varying,
												p_to_date => TO_CHAR(v_penalty_search_to, 'DD/MM/YYYY')::character varying
											) INTO v_emp_deviations;

											IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_after' THEN
												UPDATE tmp_penalty_rules SET used_deviations = v_emp_deviations WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
												UPDATE tmp_leave_penalty_rules SET used_deviations = v_emp_deviations, balance_deviations = GREATEST(v_tmp_penalty_rules.max_uses - v_emp_deviations, 0) WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
											ELSIF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_of_every' THEN
												UPDATE tmp_penalty_rules SET used_deviations = CASE WHEN (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) = 0 THEN v_emp_deviations ELSE (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) END, balance_deviations = (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
												UPDATE tmp_leave_penalty_rules SET used_deviations = CASE WHEN (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) = 0 THEN v_emp_deviations ELSE (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)) END, balance_deviations = (v_emp_deviations % NULLIF(v_tmp_penalty_rules.max_uses, 0)); -- WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
											END IF;
											v_tmp_penalty_rules.used_deviations := v_emp_deviations;
										END IF;
										-- END - Change [1.4] - Multiple Occurrence Penalty Deduction
									ELSE
										SELECT * INTO v_tmp_penalty_rules FROM tmp_penalty_rules WHERE max_uses = -1;
									END IF;
								END IF;

								IF v_tmp_penalty_rules.exempt_deviation_after_working_hrs_completed = true THEN
									v_is_working_hrs_completed = (CASE WHEN v_no_of_minutes_worked >= v_shift_working_minutes THEN 'Y' ELSE 'N' END);
								END IF;

								IF (v_deviation_in_checkin_time_in_minutes > v_grace_period_in_minutes OR COALESCE(v_tmp_penalty_rules.used_deviations, 0) > COALESCE(v_tmp_penalty_rules.max_uses, 0)) AND v_is_working_hrs_completed = 'N' THEN
									IF v_overtime = 'Y' AND v_penalty_as_ot_config_deduction_enabled = 'Y' THEN
										IF LOWER(v_ot_rules_rate_structure->>'ot_trigger_status') = 'true' THEN
											IF EXISTS (
												SELECT 1
												FROM jsonb_array_elements(jsonb_build_array(v_ot_rules_rate_structure)) AS rate_struct
												CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(rate_struct->'ot_time_calculation') = 'array' THEN rate_struct->'ot_time_calculation' ELSE '[]'::jsonb END) AS calc
											) THEN
												FOR v_multiplier IN
													SELECT calc
													FROM jsonb_array_elements(jsonb_build_array(v_ot_rules_rate_structure)) AS rate_struct
													CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(rate_struct->'ot_time_calculation') = 'array' THEN rate_struct->'ot_time_calculation' ELSE '[]'::jsonb END) AS calc
												LOOP
													EXIT WHEN v_penality_remaning_minutes_calculations_saot <= 0;
													v_penality_limit_minutes_saot := (EXTRACT(EPOCH FROM COALESCE(NULLIF(v_multiplier->>'hours_limit',''),'00:00:00')::time) / 60)::numeric - v_deviations_more_than_times; -- convert hours_limit (HH:MI:SS) to minutes
													v_check_in_penality_applicable_minutes_saot := LEAST(v_penality_remaning_minutes_calculations_saot, v_penality_limit_minutes_saot);
													v_check_in_penality_summary_saot := 'Additionally, a deduction was applied as per the OT configuration, based on the ';
							
													IF v_multiplier->>'pay_on_salary_head' = 'fixed_amount' THEN
														v_head_amount_saot := coalesce((v_multiplier->>'rate_multiplier')::numeric, 0);
														v_penality_remaning_minutes_calculations_saot := v_penality_remaning_minutes_calculations_saot - v_check_in_penality_applicable_minutes_saot;
														v_penality_in_check_in_amount_before_multiplier_saot := v_head_amount_saot * (v_check_in_penality_applicable_minutes_saot / 60); -- BEFORE multiplier
														v_check_in_final_amount_saot := v_check_in_final_amount_saot + v_penality_in_check_in_amount_before_multiplier_saot; -- accumulate final amount (use post-multiplier amount)
							
														v_check_in_penality_summary_saot := COALESCE(v_check_in_penality_summary_saot, '') || format(
															E'fixed amount of ₹%s/Hrs with a %s-minute cap. The usage was %s minutes, yielding ₹%s from the fixed amount. The remaining OT minutes are %s',
															v_head_amount_saot,
															to_char(v_penality_limit_minutes_saot,'FM9999990'),
															to_char(v_check_in_penality_applicable_minutes_saot,'FM999990.00'),
															to_char(v_overtime_amount_before_multiplier,'FM999999990.00'),
															to_char(v_penality_remaning_minutes_calculations_saot,'FM999990.00')
														);
													ELSE
														EXECUTE format('SELECT %I FROM empsalaryregister WHERE appointment_id = $1 AND isactive = ''1''', v_multiplier->>'pay_on_salary_head') INTO v_head_amount_saot USING v_emp_id;
														v_penality_in_check_in_amount_before_multiplier_saot := (v_head_amount_saot / v_emp_salary.month_days::NUMERIC) * (v_check_in_penality_applicable_minutes_saot / v_shift_working_minutes_assigned_after_unpaid_break); -- BEFORE multiplier
														v_penality_in_check_in_amount_after_multiplier_saot := v_penality_in_check_in_amount_before_multiplier_saot * coalesce((v_multiplier->>'rate_multiplier')::numeric, 1); -- AFTER multiplier
														v_check_in_final_amount_saot := v_check_in_final_amount_saot + v_penality_in_check_in_amount_after_multiplier_saot; -- accumulate final amount (use post-multiplier amount)
														v_penality_remaning_minutes_calculations_saot := v_penality_remaning_minutes_calculations_saot - v_check_in_penality_applicable_minutes_saot;

														v_check_in_penality_summary_saot := COALESCE(v_check_in_penality_summary_saot, '') || format(
															E'%s salary of ₹%s, calculated on %s salary setup days with a %sx multiplier and a %s-minute cap. In this case, %s minutes were used, resulting in ((₹%s %s ÷ %s days) × (%s OT minutes ÷ %s shift minutes)) = ₹%s before the multiplier, and ₹%s after applying the %sx multiplier. The remaining OT minutes are %s',
															v_multiplier->>'pay_on_salary_head', v_head_amount_saot,
															v_emp_salary.month_days,
															v_multiplier->>'rate_multiplier',
															to_char(v_penality_remaning_minutes_calculations_saot,'FM9999990'),
															to_char(v_check_in_penality_applicable_minutes_saot,'FM999990.00'),
															v_head_amount_saot, v_multiplier->>'pay_on_salary_head', (v_emp_salary.month_days::NUMERIC), v_check_in_penality_applicable_minutes_saot, v_shift_working_minutes_assigned_after_unpaid_break,
															to_char(v_penality_in_check_in_amount_before_multiplier_saot,'FM999999990.00'),
															to_char(v_penality_in_check_in_amount_after_multiplier_saot,'FM999999990.00'),
															v_multiplier->>'rate_multiplier',
															to_char(v_penality_remaning_minutes_calculations_saot,'FM999990.00')
														);
													END IF;
												END LOOP;
												IF v_check_in_final_amount_saot > 0 THEN
													v_check_in_penality_summary_saot := COALESCE(v_check_in_penality_summary_saot, '') || format(
															E'\n\nFinal Penality Amount is %s',
															v_check_in_final_amount_saot,'FM999990.00');
												END IF;
											END IF;
										END IF;
									END IF;

									-- START - Leave Deduction Penalty
										IF p_customeraccountid = 8613 THEN -- Get all deviations for this customer
											v_leave_grace_max_uses := (SELECT SUM(max_uses) FROM tmp_leave_penalty_rules WHERE max_uses > 0);
											v_leave_grace_used := v_leave_emp_deviations;
										ELSE -- Get only used deviations for another customers
											IF v_penalty_mode = 'strict' THEN
												v_leave_grace_max_uses := (SELECT max_uses FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkin_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC LIMIT 1);
												v_leave_grace_used := (SELECT used_deviations FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkin_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC LIMIT 1);
											ELSE
												v_leave_grace_max_uses := (SELECT SUM(max_uses) FROM tmp_leave_penalty_rules WHERE max_uses > 0 AND end_time >= ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkin_time::time) / 60)::int);
												v_leave_grace_used := (SELECT SUM(used_deviations) FROM tmp_leave_penalty_rules WHERE max_uses > 0 AND end_time >= ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkin_time::time) / 60)::int);
											END IF;
										END IF;

										-- IF v_penalty_as_leave_deduction_enabled = 'Y' AND COALESCE(v_tmp_penalty_rules.used_deviations, 0) >= COALESCE(v_tmp_penalty_rules.max_uses, 0) THEN
										IF v_penalty_as_leave_deduction_enabled = 'Y' AND COALESCE(v_leave_grace_used, 0) >= COALESCE(v_leave_grace_max_uses, 0) THEN
											v_penalty_as_leave_deduction := (SELECT leave_deduction FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkin_time_in_minutes > start_time AND v_deviation_in_checkin_time_in_minutes <= end_time);
											v_penalty_as_leave_deduction_priority := (SELECT leave_priority FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkin_time_in_minutes > start_time AND v_deviation_in_checkin_time_in_minutes <= end_time);
											IF v_penalty_as_leave_deduction = 1.0 THEN
												v_attandance_type := 'AA';
											ELSIF v_penalty_as_leave_deduction = 0.5 THEN
												v_attandance_type := 'HD';
											END IF;
											v_attandance_leave_type := 'AA';
											IF v_penalty_as_leave_deduction_priority IS NOT NULL THEN
												IF EXISTS(SELECT * FROM tmp_candidate_leave_balance WHERE UPPER(typecode) = UPPER(v_penalty_as_leave_deduction_priority::jsonb -> 0 ->> 'leavetypecode') AND prev_bal > 0) THEN
													IF UPPER(v_penalty_as_leave_deduction_priority::jsonb -> 0 ->> 'leave_ctg') = 'PAID' THEN
														v_attandance_leave_type := UPPER(v_penalty_as_leave_deduction_priority::jsonb -> 0 ->> 'leavetypecode');
													END IF;
												END IF;
											END IF;
										END IF;
									-- END - Leave Deduction Penalty

									-- START - Penality (Fixed and Qtrs Deduction) Rules
										-- Fixed Amount Deduction
										IF v_penalty_as_fixed_amount_enabled = 'Y' AND COALESCE(v_tmp_penalty_rules.used_deviations, 0) >= COALESCE(v_tmp_penalty_rules.max_uses, 0) THEN
											v_fixed_amount_penalty_on_checkin := v_tmp_penalty_rules.fixed_amount_deduction;
										END IF;

										-- Per Minute Deduction
										IF v_penalty_as_per_minutes_enabled = 'Y' AND COALESCE(v_tmp_penalty_rules.used_deviations, 0) >= COALESCE(v_tmp_penalty_rules.max_uses, 0) THEN
											v_per_minute_penalty_on_checkin := ((v_deviation_in_checkin_time_in_minutes - v_tmp_penalty_rules.start_time::int) * v_tmp_penalty_rules.per_minute_deduction);
										END IF;

										-- Qtrs (Amount) Deduction
										IF v_penalty_as_qtrs_deduction_enabled = 'Y' AND COALESCE(v_tmp_penalty_rules.used_deviations, 0) >= COALESCE(v_tmp_penalty_rules.max_uses, 0) THEN
	                                        v_penalty_qtrs_deduction := COALESCE(v_tmp_penalty_rules.qtrs_deduction, 0)::NUMERIC;
	                                        v_qtrs_penalty := (CASE WHEN v_penalty_qtrs_deduction < 0 THEN v_one_qtrs_minutes_salary/v_penalty_qtrs_deduction ELSE v_one_qtrs_minutes_salary*v_penalty_qtrs_deduction END);
											v_qtrs_penalty_on_checkin := v_qtrs_penalty;
										END IF;
									-- END - Penality (Fixed and Qtrs Deduction) Rules

									v_penality_on_checkin := COALESCE(v_fixed_amount_penalty_on_checkin, 0) + COALESCE(v_per_minute_penalty_on_checkin, 0) + COALESCE(v_qtrs_penalty_on_checkin, 0) + COALESCE(v_check_in_final_amount_saot, 0);
									IF v_penality_on_checkin > 0 THEN
										v_penality_on_checkin_msg := format(E'The penalty for a %s Minute(s) late in %s mode %s consists of the following:', COALESCE(ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkin_time::time) / 60)::int, 0), v_penalty_mode, COALESCE(v_deviation_type, ''));
										IF COALESCE(v_fixed_amount_penalty_on_checkin, 0) > 0 THEN
										    v_penality_on_checkin_msg := v_penality_on_checkin_msg || format(E'\n• A fixed amount of ₹%s.', COALESCE(v_fixed_amount_penalty_on_checkin, 0));
										END IF;
		
										IF COALESCE(v_per_minute_penalty_on_checkin, 0) > 0 THEN
										    v_penality_on_checkin_msg := v_penality_on_checkin_msg || format(E'\n• A per-minute fine of ₹%s, calculated as ((%s - %s) × ₹%s) = ₹%s.', COALESCE(v_per_minute_penalty_on_checkin, 0), COALESCE(v_deviation_in_checkin_time_in_minutes, 0), COALESCE(v_tmp_penalty_rules.start_time, 0), COALESCE(v_tmp_penalty_rules.per_minute_deduction, 0), COALESCE(v_per_minute_penalty_on_checkin, 0));
										END IF;
										
										IF v_penalty_qtrs_deduction > 0 THEN
										    v_penality_on_checkin_msg := v_penality_on_checkin_msg || format(E'\n• A %s-quarter penalty of ₹%s.', v_penalty_qtrs_deduction, v_qtrs_penalty_on_checkin);
										END IF;
										
										IF v_check_in_penality_summary_saot IS NOT NULL THEN
											v_penality_on_checkin_msg := v_penality_on_checkin_msg || format(E'\n• %s.', v_check_in_penality_summary_saot);
										END IF;
									ELSE
										v_penality_on_checkin_msg := ('Penalty on '||COALESCE(v_deviation_in_checkin_time_in_minutes, 0)||' Minutes Late '||COALESCE(v_deviation_type, '')||' in '||v_penalty_mode||' mode not applied because, before '|| p_att_date ||', the deviations occurred only '||COALESCE(v_emp_deviations, 0)||' times.The penalty will be applied after '||COALESCE(v_tmp_penalty_rules.max_uses, 0)||' occurrence.');
									END IF;
								ELSE
									v_penality_on_checkin_msg := ('Penalty on '||COALESCE(v_deviation_in_checkin_time_in_minutes, 0)||' Minutes Late '||COALESCE(v_deviation_type, '')||' in '||v_penalty_mode||' mode not applied because, before '|| p_att_date ||', the deviations occurred only '||COALESCE(v_emp_deviations, 0)||' times.The penalty will be applied after '||COALESCE(v_tmp_penalty_rules.max_uses, 0)||' occurrence.');
								END IF;
							END IF;
						END IF;
					ELSIF v_deviation_type = 'check-out' THEN
						v_deviation_in_checkout := 0;
						IF ((EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP) / 60) > v_grace_period_in_minutes) AND ((v_LC_EG_enabled_in_app_setting = 'app-setting' AND v_EG_enabled_in_app_setting = 'Y') OR v_LC_EG_enabled_in_app_setting = 'penality-rule') THEN
							v_deviation_in_checkout := 1;
							IF v_emp_deviations > v_grace_period_max_uses THEN
								v_deviation_in_checkout_time := (TO_CHAR((v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP), 'HH24:MI:SS'))::TEXT;
								v_deviation_in_checkout_time_in_minutes := ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkout_time::time) / 60)::int;
								v_penality_remaning_minutes_calculations_saot := v_deviation_in_checkout_time_in_minutes - v_deviations_more_than_times;
								IF v_penalty_mode = 'strict' THEN
									SELECT * INTO v_tmp_penalty_rules
									FROM tmp_penalty_rules
									WHERE v_deviation_in_checkout_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC;

									SELECT att_date INTO v_last_penalty_date
									FROM tbl_monthly_attendance tma
									WHERE tma.isactive = '1' AND tma.emp_code = p_emp_code AND tma.att_date < v_att_date AND tma.deviation_in_checkout = '1'
									AND (COALESCE(NULLIF(earlyhours, ''), '00:00:00')::INTERVAL BETWEEN to_char(make_interval(mins := v_tmp_penalty_rules.start_time), 'HH24:MI:SS')::INTERVAL AND to_char(make_interval(mins := v_tmp_penalty_rules.end_time), 'HH24:MI:SS')::INTERVAL
									AND (latehoursdeduction > 0 OR tma.attendance_type = 'HD'))
									ORDER BY tma.att_date DESC LIMIT 1;

									-- START - Change [1.4] - Multiple Occurrence Penalty Deduction
									IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_after' THEN
										v_penalty_search_to := (v_att_date - INTERVAL '1 DAY')::DATE;
										v_penalty_search_from := GREATEST((v_last_penalty_date + INTERVAL '1 DAY'), (v_att_date - (v_tmp_penalty_rules.max_uses || ' days')::INTERVAL)::DATE);
										SELECT public.usp_calculate_employee_deviations(
											p_action => v_deviation_type::character varying,
											p_customeraccountid => p_customeraccountid::bigint,
											p_emp_code => p_emp_code::bigint,
											p_from_date => TO_CHAR(v_penalty_search_from, 'DD/MM/YYYY')::character varying,
											p_to_date => TO_CHAR(v_penalty_search_to, 'DD/MM/YYYY')::character varying,
											p_start_time => to_char(make_interval(mins := v_tmp_penalty_rules.start_time), 'HH24:MI:SS')::varchar,
											p_end_time => to_char(make_interval(mins := v_tmp_penalty_rules.end_time), 'HH24:MI:SS')::varchar
										) INTO v_emp_deviations;

										UPDATE tmp_penalty_rules SET used_deviations = v_emp_deviations WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
										UPDATE tmp_leave_penalty_rules SET used_deviations = v_emp_deviations, balance_deviations = GREATEST(v_tmp_penalty_rules.max_uses - v_emp_deviations, 0) WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
										-- v_tmp_penalty_rules.used_deviations := v_emp_deviations;
									END IF;
									-- END - Change [1.4] - Multiple Occurrence Penalty Deduction
								ELSE
									SELECT att_date INTO v_last_penalty_date
									FROM tbl_monthly_attendance tma
									WHERE tma.isactive = '1' AND tma.emp_code = p_emp_code AND tma.att_date < v_att_date AND tma.deviation_in_checkout = '1' AND (earlyhoursdeduction > 0 OR tma.attendance_type = 'HD')
									ORDER BY tma.att_date DESC LIMIT 1;
									IF v_emp_deviations > (SELECT SUM(max_uses) FROM tmp_penalty_rules) THEN
										UPDATE tmp_penalty_rules SET used_deviations = v_emp_deviations;
										SELECT * INTO v_tmp_penalty_rules
										FROM tmp_penalty_rules
										WHERE v_deviation_in_checkout_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC;

										-- START - Change [1.4] - Multiple Occurrence Penalty Deduction
										IF v_tmp_penalty_rules.max_uses_mode = 'deviation_multiples_after' THEN
											v_penalty_search_to := (v_att_date - INTERVAL '1 DAY')::DATE;
											v_penalty_search_from := GREATEST((v_last_penalty_date + INTERVAL '1 DAY'), (v_att_date - (v_tmp_penalty_rules.max_uses || ' days')::INTERVAL)::DATE);
											SELECT public.usp_calculate_employee_deviations(
												p_action => v_deviation_type::character varying,
												p_customeraccountid => p_customeraccountid::bigint,
												p_emp_code => p_emp_code::bigint,
												p_from_date => TO_CHAR(v_penalty_search_from, 'DD/MM/YYYY')::character varying,
												p_to_date => TO_CHAR(v_penalty_search_to, 'DD/MM/YYYY')::character varying
											) INTO v_emp_deviations;

											UPDATE tmp_penalty_rules SET used_deviations = v_emp_deviations WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
											UPDATE tmp_leave_penalty_rules SET used_deviations = v_emp_deviations, balance_deviations = GREATEST(v_tmp_penalty_rules.max_uses - v_emp_deviations, 0) WHERE title = v_tmp_penalty_rules.title AND start_time = v_tmp_penalty_rules.start_time AND end_time = v_tmp_penalty_rules.end_time;
											-- v_tmp_penalty_rules.used_deviations := v_emp_deviations;
										END IF;
										-- END - Change [1.4] - Multiple Occurrence Penalty Deduction
									ELSE
										SELECT * INTO v_tmp_penalty_rules FROM tmp_penalty_rules WHERE max_uses = -1;
									END IF;
								END IF;
								IF v_tmp_penalty_rules.exempt_deviation_after_working_hrs_completed = true THEN
									v_is_working_hrs_completed = (CASE WHEN v_no_of_minutes_worked >= v_shift_working_minutes THEN 'Y' ELSE 'N' END);
								END IF;
								IF ((EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP) / 60) > v_grace_period_in_minutes OR v_tmp_penalty_rules.used_deviations > v_tmp_penalty_rules.max_uses) AND v_is_working_hrs_completed = 'N' THEN
									IF v_overtime = 'Y' AND v_penalty_as_ot_config_deduction_enabled = 'Y' THEN
										IF LOWER(v_ot_rules_rate_structure->>'ot_trigger_status') = 'true' THEN
											IF EXISTS (
												SELECT 1
												FROM jsonb_array_elements(jsonb_build_array(v_ot_rules_rate_structure)) AS rate_struct
												CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(rate_struct->'ot_time_calculation') = 'array' THEN rate_struct->'ot_time_calculation' ELSE '[]'::jsonb END) AS calc
											) THEN
												v_check_out_penality_summary_saot := 'Additionally, a deduction was applied as per the OT configuration, based on the ';
												FOR v_multiplier IN
													SELECT calc
													FROM jsonb_array_elements(jsonb_build_array(v_ot_rules_rate_structure)) AS rate_struct
													CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(rate_struct->'ot_time_calculation') = 'array' THEN rate_struct->'ot_time_calculation' ELSE '[]'::jsonb END) AS calc
												LOOP
													EXIT WHEN v_penality_remaning_minutes_calculations_saot <= 0;
													v_penality_limit_minutes_saot := (EXTRACT(EPOCH FROM COALESCE(NULLIF(v_multiplier->>'hours_limit',''),'00:00:00')::time) / 60)::numeric - v_deviations_more_than_times; -- convert hours_limit (HH:MI:SS) to minutes
													v_check_out_penality_applicable_minutes_saot := LEAST(v_penality_remaning_minutes_calculations_saot, v_penality_limit_minutes_saot);

													IF v_multiplier->>'pay_on_salary_head' = 'fixed_amount' THEN
														v_head_amount_saot := coalesce((v_multiplier->>'rate_multiplier')::numeric, 0);
														v_penality_remaning_minutes_calculations_saot := v_penality_remaning_minutes_calculations_saot - v_check_out_penality_applicable_minutes_saot;
														v_penality_in_check_out_amount_before_multiplier_saot := v_head_amount_saot * (v_check_out_penality_applicable_minutes_saot / 60); -- BEFORE multiplier
														v_check_out_final_amount_saot := v_check_out_final_amount_saot + v_penality_in_check_out_amount_before_multiplier_saot; -- accumulate final amount (use post-multiplier amount)
							
														v_check_out_penality_summary_saot := COALESCE(v_check_out_penality_summary_saot, '') || format(
															E'fixed amount of ₹%s/Hrs with a %s-minute cap. The usage was %s minutes, yielding ₹%s from the fixed amount. The remaining minutes are %s.',
															v_head_amount_saot,
															to_char(v_penality_limit_minutes_saot,'FM9999990'),
															to_char(v_check_out_penality_applicable_minutes_saot,'FM999990.00'),
															to_char(v_penality_in_check_out_amount_before_multiplier_saot,'FM999999990.00'),
															to_char(v_penality_remaning_minutes_calculations_saot,'FM999990.00')
														);
													ELSE
														EXECUTE format('SELECT %I FROM empsalaryregister WHERE appointment_id = $1 AND isactive = ''1''', v_multiplier->>'pay_on_salary_head') INTO v_head_amount_saot USING v_emp_id;
														v_penality_in_check_out_amount_before_multiplier_saot := (v_head_amount_saot / v_emp_salary.month_days::NUMERIC) * (v_check_out_penality_applicable_minutes_saot / v_shift_working_minutes_assigned_after_unpaid_break); -- BEFORE multiplier
														v_penality_in_check_out_amount_after_multiplier_saot := v_penality_in_check_out_amount_before_multiplier_saot * coalesce((v_multiplier->>'rate_multiplier')::numeric, 1); -- AFTER multiplier
														v_check_out_final_amount_saot := v_check_out_final_amount_saot + v_penality_in_check_out_amount_after_multiplier_saot; -- accumulate final amount (use post-multiplier amount)
														v_penality_remaning_minutes_calculations_saot := v_penality_remaning_minutes_calculations_saot - v_check_out_penality_applicable_minutes_saot;

														v_check_out_penality_summary_saot := COALESCE(v_check_out_penality_summary_saot, '') || format(
															E'%s salary of ₹%s, calculated on %s salary setup days with a %sx multiplier and a %s-minute cap. In this case, %s minutes were used, resulting in ((₹%s %s ÷ %s days) × (%s OT minutes ÷ %s shift minutes)) = ₹%s before the multiplier, and ₹%s after applying the %sx multiplier. The remaining OT minutes are %s.',
															v_multiplier->>'pay_on_salary_head', v_head_amount_saot,
															v_emp_salary.month_days,
															v_multiplier->>'rate_multiplier',
															to_char(v_penality_remaning_minutes_calculations_saot,'FM9999990'),
															to_char(v_check_out_penality_applicable_minutes_saot,'FM999990.00'),
															v_head_amount_saot, v_multiplier->>'pay_on_salary_head', (v_emp_salary.month_days::NUMERIC), v_check_out_penality_applicable_minutes_saot, v_shift_working_minutes_assigned_after_unpaid_break,
															to_char(v_penality_in_check_out_amount_before_multiplier_saot,'FM999999990.00'),
															to_char(v_penality_in_check_out_amount_after_multiplier_saot,'FM999999990.00'),
															v_multiplier->>'rate_multiplier',
															to_char(v_penality_remaning_minutes_calculations_saot,'FM999990.00')
														);
													END IF;
												END LOOP;
												IF v_check_out_final_amount_saot > 0 THEN
													v_check_out_penality_summary_saot := COALESCE(v_check_out_penality_summary_saot, '') || format(
															E'\n\nFinal Penality Amount is %s',
															v_check_out_final_amount_saot,'FM999990.00');
												END IF;
											END IF;
										END IF;
									END IF;

									-- START - Leave Deduction Penalty
										IF p_customeraccountid = 8613 THEN -- Get all deviations for this customer
											v_leave_grace_used := v_leave_emp_deviations;
											v_leave_grace_max_uses := (SELECT SUM(max_uses) FROM tmp_leave_penalty_rules WHERE max_uses > 0);
										ELSE -- Get only used deviations for another customers
											IF v_penalty_mode = 'strict' THEN
												v_leave_grace_max_uses := (SELECT max_uses FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkout_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC LIMIT 1);
												v_leave_grace_used := (SELECT used_deviations FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkout_time_in_minutes BETWEEN start_time AND end_time ORDER BY start_time ASC LIMIT 1);
											ELSE
												v_leave_grace_used := (SELECT SUM(used_deviations) FROM tmp_leave_penalty_rules WHERE max_uses > 0 AND end_time >= ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkout_time::time) / 60)::int);
												v_leave_grace_max_uses := (SELECT SUM(max_uses) FROM tmp_leave_penalty_rules WHERE max_uses > 0 AND end_time >= ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkout_time::time) / 60)::int);
											END IF;
										END IF;
										IF v_penalty_as_leave_deduction_enabled = 'Y' AND COALESCE(v_leave_grace_used, 0) > COALESCE(v_leave_grace_max_uses, 0) THEN
											v_penalty_as_leave_deduction := (SELECT leave_deduction FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkin_time_in_minutes > start_time AND v_deviation_in_checkin_time_in_minutes <= end_time);
											v_penalty_as_leave_deduction_priority := (SELECT leave_priority FROM tmp_leave_penalty_rules WHERE v_deviation_in_checkin_time_in_minutes > start_time AND v_deviation_in_checkin_time_in_minutes <= end_time);
											IF v_penalty_as_leave_deduction = 1.0 THEN
												v_attandance_type := 'AA';
											ELSIF v_penalty_as_leave_deduction = 0.5 THEN
												v_attandance_type := 'HD';
											END IF;
											v_attandance_leave_type := 'AA';
											IF v_penalty_as_leave_deduction_priority IS NOT NULL THEN
												IF EXISTS(SELECT * FROM tmp_candidate_leave_balance WHERE UPPER(typecode) = UPPER(v_penalty_as_leave_deduction_priority::jsonb -> 0 ->> 'leavetypecode') AND prev_bal > 0) THEN
													IF UPPER(v_penalty_as_leave_deduction_priority::jsonb -> 0 ->> 'leave_ctg') = 'PAID' THEN
														v_attandance_leave_type := UPPER(v_penalty_as_leave_deduction_priority::jsonb -> 0 ->> 'leavetypecode');
													END IF;
												END IF;
											END IF;
										END IF;
									-- END - Leave Deduction Penalty

									-- START - Penality (Fixed and Qtrs Deduction) Rules
										-- Fixed Amount Deduction
										IF v_penalty_as_fixed_amount_enabled = 'Y' AND COALESCE(v_tmp_penalty_rules.used_deviations, 0) >= COALESCE(v_tmp_penalty_rules.max_uses, 0) THEN
											v_fixed_amount_penalty_on_checkout := COALESCE(v_tmp_penalty_rules.fixed_amount_deduction, 0);
										END IF;

										IF v_penalty_as_per_minutes_enabled = 'Y' AND COALESCE(v_tmp_penalty_rules.used_deviations, 0) >= COALESCE(v_tmp_penalty_rules.max_uses, 0) THEN
											v_per_minute_penalty_on_checkout := ((v_deviation_in_checkout_time_in_minutes - v_tmp_penalty_rules.start_time) * v_tmp_penalty_rules.per_minute_deduction);
										END IF;

										-- Qtrs (Amount) Deduction
										IF v_penalty_as_qtrs_deduction_enabled = 'Y' AND COALESCE(v_tmp_penalty_rules.used_deviations, 0) >= COALESCE(v_tmp_penalty_rules.max_uses, 0) THEN
	                                        v_penalty_qtrs_deduction := COALESCE(v_tmp_penalty_rules.qtrs_deduction, 0)::NUMERIC;
	                                        v_qtrs_penalty := (CASE WHEN v_penalty_qtrs_deduction < 0 THEN v_one_qtrs_minutes_salary/v_penalty_qtrs_deduction ELSE v_one_qtrs_minutes_salary*v_penalty_qtrs_deduction END);
											v_qtrs_penalty_on_checkout := v_qtrs_penalty;
										END IF;
									-- END - Penality (Fixed and Qtrs Deduction) Rules

									v_penality_on_checkout := COALESCE(v_fixed_amount_penalty_on_checkout, 0) + COALESCE(v_per_minute_penalty_on_checkout, 0) + COALESCE(v_qtrs_penalty_on_checkout, 0) + COALESCE(v_check_out_final_amount_saot, 0);
									IF v_penality_on_checkout > 0 THEN
										v_penality_on_checkout_msg := format(E'The penalty for a %s Minute(s) late %s consists of the following:', COALESCE(ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkout_time::TIME) / 60)::int, 0), COALESCE(v_deviation_type, ''));
										IF COALESCE(v_fixed_amount_penalty_on_checkout, 0) > 0 THEN
										    v_penality_on_checkout_msg := v_penality_on_checkout_msg || format(E'\n• A fixed amount of ₹%s.', COALESCE(v_fixed_amount_penalty_on_checkout, 0));
										END IF;
		
										IF COALESCE(v_per_minute_penalty_on_checkout, 0) > 0 THEN
										    v_penality_on_checkout_msg := v_penality_on_checkout_msg || format(E'\n• A per-minute fine of ₹%s, calculated as ((%s - %s) × ₹%s) = ₹%s.', COALESCE(v_per_minute_penalty_on_checkout, 0), COALESCE(v_deviation_in_checkout_time_in_minutes, 0), COALESCE(v_tmp_penalty_rules.start_time, 0), COALESCE(v_tmp_penalty_rules.per_minute_deduction, 0), COALESCE(v_per_minute_penalty_on_checkout, 0));
										END IF;
										
										IF v_penalty_qtrs_deduction > 0 THEN
										    v_penality_on_checkout_msg := v_penality_on_checkout_msg || format(E'\n• A %s-quarter penalty of ₹%s.', v_penalty_qtrs_deduction, v_qtrs_penalty_on_checkout);
										END IF;
										
										IF v_check_out_penality_summary_saot IS NOT NULL THEN
											v_penality_on_checkout_msg := v_penality_on_checkout_msg || format(E'\n• %s.', v_check_out_penality_summary_saot);
										END IF;
									ELSE
										v_penality_on_checkout_msg := ('Penalty for early '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_checkout_time_in_minutes, 0)||' minutes) is not applied because deviations are '||COALESCE(v_emp_deviations, 0)||'. The penalty will be deducted only when deviations exceed '||COALESCE(v_tmp_penalty_rules.max_uses, 0)||'.');
									END IF;
								ELSE
									v_penality_on_checkout_msg := ('Penalty for early '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_checkout_time_in_minutes, 0)||' minutes) is not applied because deviations are '||COALESCE(v_emp_deviations, 0)||'. The penalty will be deducted only when deviations exceed '||COALESCE(v_deviations_more_than_times, 0)||'.');
								END IF;
							END IF;
						END IF;
					ELSIF v_deviation_type = 'short-work' THEN
						v_deviation_in_working_hours := 0;
						IF v_no_of_minutes_worked < v_grace_period_in_minutes THEN
							v_deviation_in_working_hours := 1;
							v_deviation_in_working_hours_time := (TO_CHAR(make_interval(mins => (v_grace_period_in_minutes - COALESCE(v_no_of_minutes_worked::int, 0))::int), 'HH24:MI:SS'))::TEXT;
							v_deviation_in_working_hours_time_in_minutes := (ROUND(EXTRACT(EPOCH FROM v_deviation_in_working_hours_time::time) / 60)::int - v_deviations_more_than_times::int);

							IF v_emp_deviations > v_deviations_more_than_times THEN
								v_fixed_amount_penalty_on_working_hours := v_final_fixed_amount_penalty;
								v_per_minute_penalty_on_working_hours := (v_deviation_in_working_hours_time_in_minutes * v_final_per_minute_penalty);
								v_penality_on_working_hours := v_fixed_amount_penalty_on_working_hours + v_per_minute_penalty_on_working_hours;
								v_penality_on_working_hours_msg := ('Penalty for '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_working_hours_time_in_minutes, '')||' minutes) is a fixed amount of ₹'||COALESCE(v_fixed_amount_penalty_on_working_hours, '')||' + per-minute fine of '||(COALESCE(v_per_minute_penalty_on_working_hours, '')||' × ₹'||COALESCE(v_final_per_minute_penalty, ''))||' = ₹'||COALESCE(v_penality_on_working_hours, '')||'.');
							ELSE
								v_penality_on_working_hours_msg := ('Penalty for '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_working_hours_time_in_minutes, '')||' minutes) is not applied because deviations are '||COALESCE(v_emp_deviations, '')||'. The penalty will be deducted only when deviations exceed '||COALESCE(v_deviations_more_than_times, '')||'.');
							END IF;
						END IF;
					ELSIF v_deviation_type = 'monthly-hours' THEN
						IF v_emp_deviations > v_grace_period_in_minutes THEN
							v_emp_deviations_already_deducted = (v_emp_deviations + v_deviation_in_checkin_time_in_minutes) - v_deviations_more_than_times;
						END IF;

						v_deviation_in_checkin := 0;
						-- IF v_deviation_in_checkin_time_in_minutes > 0 THEN
						IF (v_deviation_in_checkin_time_in_minutes > 0) AND ((v_LC_EG_enabled_in_app_setting = 'app-setting' AND v_LC_enabled_in_app_setting = 'Y') OR v_LC_EG_enabled_in_app_setting = 'penality-rule') THEN
							v_is_late_comer := 'Y';
							v_deviation_in_checkin := 1;
							v_deviation_in_checkin_time := (TO_CHAR((v_first_check_in_time::TIMESTAMP - v_shift_start_timing::TIMESTAMP), 'HH24:MI:SS'))::TEXT;
							v_deviation_in_checkin_time_in_minutes := (ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkin_time::time) / 60)::int);

							IF (v_deviation_in_checkin_time_in_minutes + v_emp_deviations) > v_grace_period_in_minutes THEN
								v_deviation_in_checkin_time_in_minutes := ((v_deviation_in_checkin_time_in_minutes + v_emp_deviations) - v_deviations_more_than_times - v_emp_deviations_already_deducted)::INT;
								v_fixed_amount_penalty_on_checkin := v_final_fixed_amount_penalty;
								v_per_minute_penalty_on_checkin := (v_deviation_in_checkin_time_in_minutes * v_final_per_minute_penalty);
								v_qtrs_penalty_on_checkin := v_final_qtrs_penalty;
								v_penality_on_checkin := v_fixed_amount_penalty_on_checkin + v_per_minute_penalty_on_checkin + v_qtrs_penalty_on_checkin;
								v_penality_on_checkin_msg := ('Monthly Penalty for late '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_checkin_time_in_minutes, 0)||' minutes) is a fixed amount of ₹'||COALESCE(v_fixed_amount_penalty_on_checkin, 0)||' + per-minute fine of '||(COALESCE(v_deviation_in_checkin_time_in_minutes, 0)||' × ₹'||COALESCE(v_final_per_minute_penalty, 0))||' = ₹'||COALESCE(v_penality_on_checkin, 0)||'.');
							ELSE
								v_penality_on_checkin_msg := ('Penalty on Late '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_checkin_time_in_minutes, 0)||' Minutes) Not Applied because Deviations are '||COALESCE(v_emp_deviations, 0)||' and penalty will deduction on after '||COALESCE(v_deviations_more_than_times, 0)||'.');
							END IF;
						END IF;

						v_deviation_in_checkout := 0;
						-- IF (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP) / 60) > 0 THEN
						IF ((EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP) / 60) > 0) AND ((v_LC_EG_enabled_in_app_setting = 'app-setting' AND v_EG_enabled_in_app_setting = 'Y') OR v_LC_EG_enabled_in_app_setting = 'penality-rule') THEN
							v_deviation_in_checkout := 1;
							v_deviation_in_checkout_time := (TO_CHAR((v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP), 'HH24:MI:SS'))::TEXT;
							v_deviation_in_checkout_time_in_minutes := ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkout_time::time) / 60)::int;

							IF (v_emp_deviations + v_deviation_in_checkout_time_in_minutes) > v_grace_period_in_minutes THEN
								v_deviation_in_checkout_time_in_minutes := ((v_emp_deviations + v_deviation_in_checkout_time_in_minutes) - v_deviations_more_than_times - v_emp_deviations_already_deducted)::INT;
								v_fixed_amount_penalty_on_checkout := v_final_fixed_amount_penalty;
								v_per_minute_penalty_on_checkout := (v_deviation_in_checkout_time_in_minutes * v_final_per_minute_penalty);
								v_qtrs_penalty_on_checkout := v_final_qtrs_penalty;
								v_penality_on_checkout := v_fixed_amount_penalty_on_checkout + v_per_minute_penalty_on_checkout + v_qtrs_penalty_on_checkout;
								v_penality_on_checkout_msg := ('Monthly Penalty for early '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_checkout_time_in_minutes, 0)||' minutes) is a fixed amount of ₹'||COALESCE(v_fixed_amount_penalty_on_checkout, 0)||' + per-minute fine of '||(COALESCE(v_deviation_in_checkout_time_in_minutes, 0)||' × ₹'||COALESCE(v_final_per_minute_penalty, 0))||' = ₹'||COALESCE(v_penality_on_checkout, 0)||'.');
							ELSE
								v_penality_on_checkout_msg := ('Penalty for early '||COALESCE(v_deviation_type, '')||' ('||COALESCE(v_deviation_in_checkout_time_in_minutes, 0)||' minutes) is not applied because deviations are '||COALESCE(v_emp_deviations, 0)||'. The penalty will be deducted only when deviations exceed '||COALESCE(v_deviations_more_than_times, 0)||'.');
							END IF;
						END IF;

						-- START - Leave Deduction Penalty
						IF (v_deviation_in_checkin = 1 AND (ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkin_time::time) / 60)::int + v_emp_deviations) > v_grace_period_in_minutes) OR (v_deviation_in_checkout = 1 AND (v_emp_deviations + ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkout_time::time) / 60)::int) > v_grace_period_in_minutes) THEN
							v_emp_deviations_till_att_date := (ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkout_time::time) / 60)::int + ROUND(EXTRACT(EPOCH FROM v_deviation_in_checkin_time::time) / 60)::int + v_emp_deviations);
							v_penalty_as_leave_deduction := (SELECT leave_deduction FROM tmp_leave_penalty_rules WHERE v_emp_deviations_till_att_date > start_time AND v_emp_deviations_till_att_date <= end_time);
							v_penalty_as_leave_deduction_priority := (SELECT leave_priority FROM tmp_leave_penalty_rules WHERE v_emp_deviations_till_att_date > start_time AND v_emp_deviations_till_att_date <= end_time);
							IF v_penalty_as_leave_deduction = 1.0 THEN
								v_attandance_type := 'AA';
							ELSIF v_penalty_as_leave_deduction = 0.5 THEN
								v_attandance_type := 'HD';
							END IF;
							IF v_penalty_as_leave_deduction_enabled = 'Y' AND COALESCE(v_emp_deviations_till_att_date, 0) >= COALESCE(v_grace_period_in_minutes, 0) THEN
								v_attandance_leave_type := 'AA';
								IF v_penalty_as_leave_deduction_priority IS NOT NULL THEN
								    FOR v_leave IN SELECT jsonb_array_elements(v_penalty_as_leave_deduction_priority) LOOP
								        SELECT b.typecode INTO v_attandance_leave_type FROM tmp_candidate_leave_balance b WHERE UPPER(b.typecode) = UPPER(v_leave->>'leavetypecode') AND b.prev_bal > 0 LIMIT 1;
										IF v_attandance_leave_type IS NOT NULL THEN EXIT; END IF;
								    END LOOP;
									v_attandance_leave_type := COALESCE(NULLIF(v_attandance_leave_type, ''), 'AA');
									IF v_penalty_as_leave_deduction = 1.0 AND v_attandance_leave_type <> 'AA' THEN
										v_attandance_type := 'LL';
									END IF;
								END IF;
							END IF;
						END IF;
						-- END - Leave Deduction Penalty
					END IF;
				END LOOP;
			END IF;
		END IF;
	-- END - Grace Policy Changes

	IF v_deviation_in_checkout = 1 AND v_deviation_in_checkin = 1 THEN
		v_attandance_category := 'LCEG';
	ELSIF v_deviation_in_checkin = 1 THEN
		v_attandance_category := 'LC';
		IF v_last_check_out_time IS NULL OR COALESCE(v_last_check_out_time::TEXT, '') = '' THEN
			v_attandance_category := 'MPLC';
		END IF;
	ELSIF v_deviation_in_checkout = 1 THEN
		v_attandance_category := 'EG';
	END IF;

	IF v_deviation_in_checkin_time::INTERVAL > '00:00:00' OR v_deviation_in_checkout_time::INTERVAL > '00:00:00' THEN
		v_fore_color := v_tmp_penalty_rules.fore_color;
		v_background_color := v_tmp_penalty_rules.background_color;
	END IF;

	-- START - Response
		OPEN response FOR
			SELECT
			1 status_code,
			'Successfully calculated employee attendance policy.' msg,
			p_emp_code emp_code,
			v_att_date att_date,
			v_shift_id shift_id,
			v_shift_details.attendance_policy_type,
			v_shift_details.attendance_policy_id::BIGINT attendance_policy_id,
			CASE WHEN v_ishourlysetup = 'Y' THEN v_rounded_no_of_minutes_worked ELSE v_no_of_minutes_worked END no_of_minutes_worked,
			CASE WHEN v_ishourlysetup = 'Y' THEN TO_CHAR((v_rounded_no_of_minutes_worked * INTERVAL '1 minute'), 'HH24:MI:SS') ELSE TO_CHAR((v_no_of_minutes_worked * INTERVAL '1 minute'), 'HH24:MI:SS') END no_of_hours_worked,
			v_overtime is_overtime,
			TO_CHAR((v_overtime_minutes * INTERVAL '1 minute'), 'HH24:MI:SS') no_of_overtime_hours_worked,
			v_overtime_final_amount overtime_amount,
			v_overtime_summary overtime_summary,
			v_attandance_type attandance_type,
			v_attandance_category attandance_category,
			v_is_grace_policy_applied grace_policy_applied,
			v_deviation_in_checkin deviation_in_checkin,
			v_deviation_in_checkin_time deviation_in_checkin_time,
			v_penality_on_checkin_msg penality_on_checkin_summary,
			v_penality_on_checkin penality_amount_on_checkin,
			v_deviation_in_checkout deviation_in_checkout,
			v_deviation_in_checkout_time deviation_in_checkout_time,
			v_penality_on_checkout_msg penality_on_checkout_summary,
			v_penality_on_checkout penality_amount_on_checkout,
			v_deviation_in_working_hours deviation_in_working_hours,
			v_deviation_in_working_hours_time deviation_in_working_hours_time,
			v_penality_on_working_hours_msg penality_on_working_hours_msg,
			v_penality_on_working_hours penality_amount_on_working_hours,
			v_penalty_workflow_enabled penalty_workflow_enabled,
			COALESCE(v_leave_template_details.leave_bank_id, 0) leave_bank_id,
			v_attandance_leave_type leave_type,
			v_is_auto_assign_shift is_auto_assign_shift,
			TO_CHAR(v_first_check_in_time, 'HH24:MI:SS') first_check_in_time,
			TO_CHAR(v_last_check_out_time, 'HH24:MI:SS') last_check_out_time,
            v_is_late_comer is_late_comer,
			v_fore_color fore_color,
			v_background_color background_color;
		RETURN response;
	-- END - Response
END;
$BODY$;

ALTER FUNCTION public.calculate_advance_employee_attandance_policy(bigint, bigint, character varying)
    OWNER TO payrollingdb;

