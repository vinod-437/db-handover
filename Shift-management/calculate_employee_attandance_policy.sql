-- FUNCTION: public.calculate_employee_attandance_policy(bigint, bigint, character varying)

-- DROP FUNCTION IF EXISTS public.calculate_employee_attandance_policy(bigint, bigint, character varying);

CREATE OR REPLACE FUNCTION public.calculate_employee_attandance_policy(
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
1.0		|	29-May-2024	|	Parveen Kumar	|	Initial Version
2.0		|	21-Jun-2025	|	Parveen Kumar	|	Grace Policy Calculations
2.1		|	17-Jul-2025	|	Parveen Kumar	|	Apply Break Policy Changes (Paid/Unpaid)
2.2		|	18-Aug-2025	|	Parveen Kumar	|	Auto Shift Rotation and Auto Assign Changes
2.3		|	30-Sep-2025	|	Parveen Kumar	|	Add LC (Late Coming) and EG (Early Going) Changes
**************************************************************************************************/
DECLARE
	response refcursor;
	v_att_date DATE;
	v_user_specific_setting record;
	v_assigned_shift record;

	v_shift_start_timing timestamp;
	v_shift_end_timing timestamp;
	v_shift_working_minutes double precision := 0;
	v_shift_working_minutes_assigned double precision := 0;
	v_first_check_in_time_and_shift_minutes_diff double precision := 0;
	v_last_check_out_time_and_shift_minutes_diff double precision := 0;

	v_first_check_in_time TIMESTAMP;
	v_last_check_out_time TIMESTAMP;
	v_no_of_hours_worked TEXT;
	v_no_of_minutes_worked double precision := 0;
	v_attandance_type TEXT := 'PP';
	/*****************|************************|
	| Attendance Type | Attendance Description |
	|-----------------|------------------------|
	| 		WFH		  | Work From Home		   |
	| 		AA		  | Absent				   |
	| 		PP		  | Present				   |
	| 		LL		  | Leave				   |
	| 		HD		  | Half day			   |
	| 		HO		  | Holiday				   |
	| 		WO		  | Weekly-Off			   |
	| 		OD		  | On-Duty				   |
	| 		MP		  | Missed Punch		   |
	******************************************/
	v_attandance_category TEXT := NULL; -- MP Sub Category
	/*****************|************************|
	| Attendance Cat. | Attendance Description |
	|-----------------|------------------------|
	| 		SP		  | Single Punch		   |
	| 		WO		  | Weekly-Off			   |
	| 		HO		  | Holiday				   |
	| 		DE		  | Deviation			   |
	| 		MP		  | Missed Punch		   |
	********************************************/
	v_attandance_leave_type TEXT := NULL;

	v_grace_period_JSON JSONB;
	v_is_grace_policy_applied TEXT := 'N';

	row_data jsonb;

	v_deviation_in_checkin INT := 0;
	v_deviation_in_checkin_time TEXT := '00:00:00';
	v_deviation_in_checkout INT := 0;
	v_deviation_in_checkout_time TEXT := '00:00:00';
	v_deviation_in_working_hours INT := 0;
	v_deviation_in_working_hours_time TEXT := '00:00:00';
	v_is_late_comer character varying(1) := 'N';

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

	/******| START - Need to remove after testing completed |*****/
	v_attendance_policy_type_assigned text := NULL;
	v_attendance_policy_id_assigned text := NULL;
	v_attendance_policy_type_auto text := NULL;
	v_attendance_policy_id_auto text := NULL;
	v_shift_start_timing_auto timestamp;
	v_shift_end_timing_auto timestamp;
	v_shift_working_minutes_auto double precision := 0;
	/******| END - Need to remove after testing completed |*****/

    v_rounded_check_out TIMESTAMP;
    v_rounded_check_in TIMESTAMP;
    v_rounded_no_of_hours_worked TEXT;
	v_rounded_no_of_minutes_worked double precision := 0;

	-- START - Grace Policy Calculations
		v_total_deviation_checkin INT := 0;
		v_total_deviation_checkout INT := 0;
		v_deviation_in_total_working_hours NUMERIC := 0;
		v_leave_deduction_days NUMERIC := 0;
		v_deviations_more_than_period TEXT;
		v_deviations_frequency TEXT;
		v_deviations_more_than_times INT := 0;
		v_leave_deduction_reason jsonb;
		v_deduction_row_data INT;
	-- END - Grace Policy Calculations

	v_ishourlysetup TEXT;
	v_total_working_hours_calculation TEXT;

	-- START - Break Policy Changes [2.1]
	v_total_break_paid INTERVAL := INTERVAL '0 minutes';
	v_total_break_unpaid INTERVAL := INTERVAL '0 minutes';
	v_break_record JSONB;
	v_break_duration_text TEXT;
	v_break_duration INTERVAL;
	v_break_paid_flag TEXT;
	-- END - Break Policy Changes [2.1]

	-- START - Shift Rotation [2.1]
	v_shift_id INT;
	-- END - Shift Rotation [2.1]

BEGIN
	IF p_att_date IS NULL THEN
		v_att_date = CURRENT_DATE;
	ELSE
		v_att_date = TO_DATE(p_att_date, 'dd/mm/yyyy');
	END IF;

	-- START - Get Check-In/Out Time and Total No of Hours Worked
		SELECT
			op.emp_id, (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp actual_check_in_time,
			CASE WHEN json_array_length(check_in_out_data.check_in_out_details) > 1 AND check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
				(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp
			ELSE
				(check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp
			END 
			actual_check_out_time,
			CASE WHEN emp_spec.total_working_hours_calculation = 'first_last_check' THEN
				CASE WHEN json_array_length(check_in_out_data.check_in_out_details) > 1 AND check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
					LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
				ELSE
					LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_data.check_in_out_details->(json_array_length(check_in_out_data.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_data.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
				END
			ELSE
				(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(check_in_out_data.check_in_out_details) AS trips(trip))
			END AS no_of_hours_worked,
			COALESCE(NULLIF(esr.ishourlysetup, ''), 'N') ishourlysetup,
			emp_spec.total_working_hours_calculation
		FROM openappointments op
		LEFT JOIN vw_user_spc_emp AS emp_spec ON emp_spec.emp_code::bigint = op.emp_code::bigint AND emp_spec.is_active='1'
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
				LEFT JOIN tbl_attendance t ON t.emp_code=op.emp_code AND att_date = v_att_date AND t.isactive='1'
				LEFT JOIN tbl_candidate_documentlist tc ON op.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
				WHERE op.emp_code=p_emp_code AND op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in (11,14)
				GROUP BY t.id
				ORDER BY t.id ASC
			) check_in_out_details
		) check_in_out_data ON TRUE
		LEFT JOIN empsalaryregister esr ON esr.appointment_id = op.emp_id AND esr.isactive = '1'
		WHERE op.emp_code=p_emp_code AND op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id IN (11,14)
		INTO v_emp_id, v_first_check_in_time, v_last_check_out_time, v_no_of_hours_worked, v_ishourlysetup, v_total_working_hours_calculation;
		-- RAISE NOTICE 'v_emp_id [%]', v_emp_id;
		-- RAISE NOTICE 'v_first_check_in_time [%]', v_first_check_in_time;
		-- RAISE NOTICE 'v_last_check_out_time [%]', v_last_check_out_time;
		-- RAISE NOTICE 'v_no_of_hours_worked [%]', v_no_of_hours_worked;
		-- RAISE NOTICE 'v_ishourlysetup [%]', v_ishourlysetup;

		v_no_of_hours_worked := (CASE WHEN v_no_of_hours_worked LIKE '-%' THEN '00:00:00' ELSE v_no_of_hours_worked END);
		v_no_of_minutes_worked := CEIL(EXTRACT(EPOCH FROM v_no_of_hours_worked::INTERVAL)/60);

		-- RAISE NOTICE 'v_no_of_minutes_worked [%]', v_no_of_minutes_worked;
	-- END - Get Check-In/Out Time and Total No of Hours Worked
	IF v_last_check_out_time IS NULL OR COALESCE(v_last_check_out_time::TEXT, '') = '' THEN
		-- v_attandance_type := 'MP';
		-- v_attandance_category := 'SP';
		v_attandance_category := 'MP';
	END IF;

	-- START - Extrat Month and Year from v_att_date
		SELECT EXTRACT('MONTH' FROM v_att_date), EXTRACT('YEAR' FROM v_att_date) INTO v_month, v_year;
	-- START - Extrat Month and Year from v_att_date

	IF EXISTS (SELECT 1 FROM tbl_employee_shift_roster WHERE account_id = p_customeraccountid AND emp_code::BIGINT = p_emp_code  AND status = '1' AND roster_date = v_att_date) THEN
		SELECT shift_id
		INTO v_shift_id
		FROM tbl_employee_shift_roster
		WHERE account_id = p_customeraccountid AND emp_code::BIGINT = p_emp_code  AND status = '1' AND roster_date = v_att_date;
		SELECT * FROM vw_user_spc_emp WHERE shift_id::bigint = v_shift_id AND is_active = '1' LIMIT 1 INTO v_user_specific_setting;
		-- RAISE NOTICE 'Applied Shift Rotation';
	END IF;

	IF v_user_specific_setting IS NULL THEN
		SELECT * FROM vw_user_spc_emp WHERE emp_code::bigint = p_emp_code AND is_active = '1' INTO v_user_specific_setting;
		SELECT v_user_specific_setting.shift_id INTO v_shift_id;
	END IF;

	-- SELECT * FROM vw_user_spc_emp WHERE emp_code::bigint = p_emp_code AND is_active='1' INTO v_user_specific_setting;
	SELECT * FROM vw_user_spc_emp WHERE emp_code::bigint = p_emp_code AND is_active='1' INTO v_assigned_shift;

	-- START - Break Policy Changes [2.1]
		-- Check if break_total_time is not null or empty
		IF NULLIF(v_user_specific_setting.break_total_time, '') IS NOT NULL AND v_user_specific_setting.break_total_time <> '[]' THEN
			-- Loop through JSONB array of break_total_time (CAST to jsonb)
			FOR v_break_record IN 
				SELECT * 
				FROM jsonb_array_elements(v_user_specific_setting.break_total_time::jsonb)
			LOOP
				v_break_duration_text := v_break_record->>'break_type_duration';
				v_break_paid_flag     := v_break_record->>'break_type_paid_unpaid';
				RAISE NOTICE 'break_duration_text - %', v_break_duration_text;
				RAISE NOTICE 'break_paid_flag - %', v_break_paid_flag;
	
				-- Convert string like '10 Minutes' to interval
				v_break_duration := 
					CASE 
						WHEN v_break_duration_text ~* '^\d+\s+minute' THEN 
							(regexp_replace(v_break_duration_text, '[^\d]', '', 'g') || ' minutes')::interval
						WHEN v_break_duration_text ~* '^\d+\s+second' THEN 
							(regexp_replace(v_break_duration_text, '[^\d]', '', 'g') || ' seconds')::interval
						WHEN v_break_duration_text ~* '^\d+\s+hour' THEN 
							(regexp_replace(v_break_duration_text, '[^\d]', '', 'g') || ' hours')::interval
						ELSE interval '0 minutes'
					END;
	
				-- Accumulate based on paid/unpaid
				IF v_break_paid_flag = 'Unpaid' THEN
					v_total_break_unpaid := v_total_break_unpaid + v_break_duration;
				ELSIF v_break_paid_flag = 'Paid' THEN
					v_total_break_paid := v_total_break_paid + v_break_duration;
				END IF;
			END LOOP;
		END IF;
	-- END - Break Policy Changes [2.1]

	-- START - Default Shift Timing
		v_shift_start_timing := (v_att_date + v_user_specific_setting.default_shift_time_from::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
		IF v_user_specific_setting.is_night_shift = 'Y' THEN
			--RAISE NOTICE 'Adding 1 Day in Default Shift - %', v_att_date;
			v_shift_end_timing := ((v_att_date + INTERVAL '1 DAY') + v_user_specific_setting.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
		ELSE
			v_shift_end_timing := (v_att_date + v_user_specific_setting.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
		END IF;
		v_shift_working_minutes := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_shift_start_timing::TIMESTAMP - v_total_break_unpaid) / 60);
		v_shift_working_minutes_assigned := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_shift_start_timing::TIMESTAMP - v_total_break_unpaid) / 60);
	-- END - Default Shift Timing

	-- START - Check whether the employee's check-in time is within the assigned attendance policy; if not, then the system should automatically assign a shift.
		-- RAISE NOTICE 'v_user_specific_setting.shift_margin [%]', v_user_specific_setting.shift_margin;
		IF COALESCE(NULLIF(v_user_specific_setting.shift_margin, ''), 'N') = 'Y' THEN
			SELECT CASE WHEN v_first_check_in_time::timestamp BETWEEN (v_shift_start_timing - v_user_specific_setting.shift_margin_hours_from::interval) AND (v_shift_end_timing + v_user_specific_setting.shift_margin_hours_to::interval) THEN 'Y' ELSE 'N' END INTO v_is_time_exists_between_assigned_att_policy;
		ELSE
			SELECT CASE WHEN v_first_check_in_time::timestamp BETWEEN v_shift_start_timing AND v_shift_end_timing THEN 'Y' ELSE 'N' END INTO v_is_time_exists_between_assigned_att_policy;
		END IF;
		-- RAISE NOTICE 'v_att_date - %', v_att_date;
		-- RAISE NOTICE 'Night Shift - %', v_user_specific_setting.is_night_shift;
		-- RAISE NOTICE 'Check-In Time - % Check-In Time - %', (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES'), (v_last_check_out_time + INTERVAL '5 HOURS 30 MINUTES');
		-- RAISE NOTICE 'Attendance Policy - %', v_user_specific_setting.attendance_policy_type||' [ '||v_user_specific_setting.attendance_policy_id||' ]';
		-- RAISE NOTICE 'Shift Timing - %', (v_shift_start_timing + INTERVAL '5 HOURS 30 MINUTES')||' - '||(v_shift_end_timing + INTERVAL '5 HOURS 30 MINUTES');
		-- RAISE NOTICE 'Shift Margin - % || Shift Margin(Start) - % || Shift Margin(Last) - %', v_user_specific_setting.shift_margin, v_user_specific_setting.shift_margin_hours_from, v_user_specific_setting.shift_margin_hours_to;
		-- RAISE NOTICE 'Shift Timing After Margin - %', ((v_shift_start_timing + INTERVAL '5 HOURS 30 MINUTES') - v_user_specific_setting.shift_margin_hours_from::interval||' - '||(v_shift_end_timing + INTERVAL '5 HOURS 30 MINUTES') + v_user_specific_setting.shift_margin_hours_to::interval);
		-- RAISE NOTICE 'v_is_time_exists_between_assigned_att_policy - % ', v_is_time_exists_between_assigned_att_policy;

		SELECT COALESCE(auto_shift_rotation_yn, 'Y')
		INTO v_auto_shift_rotation 
		FROM tbl_employee_auto_rotation
		WHERE account_id = p_customeraccountid AND emp_code = p_emp_code AND status = '1';
		-- RAISE NOTICE 'Auto Shift Rotation [%]', v_auto_shift_rotation;

		IF v_is_time_exists_between_assigned_att_policy = 'N' AND p_customeraccountid NOT IN (6878, 6872)  AND v_auto_shift_rotation = 'Y' THEN
			-- START - Get employer auto shift (latest)
				IF NOT EXISTS (SELECT * FROM vw_shift_list_user_wise WHERE customeraccountid = p_customeraccountid AND is_active='1' AND v_first_check_in_time::timestamp BETWEEN ((v_att_date + vw_shift_list_user_wise.default_shift_time_from::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES' - vw_shift_list_user_wise.shift_margin_hours_from::interval) AND CASE WHEN vw_shift_list_user_wise.is_night_shift = 'Y' THEN ((v_att_date + INTERVAL '1 DAY') + vw_shift_list_user_wise.default_shift_time_to::time + vw_shift_list_user_wise.shift_margin_hours_to::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' ELSE (v_att_date + vw_shift_list_user_wise.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES' + vw_shift_list_user_wise.shift_margin_hours_to::interval END ORDER BY shift_id DESC LIMIT 1) THEN
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
						v_overtime is_overtime,
						TO_CHAR((v_overtime_minutes * INTERVAL '1 minute'), 'HH24:MI:SS') no_of_overtime_hours_worked,
						v_attandance_type attandance_type,
						v_attandance_category attandance_category,
						v_is_grace_policy_applied grace_policy_applied,
						v_deviation_in_checkin deviation_in_checkin,
						v_deviation_in_checkin_time deviation_in_checkin_time,
						v_deviation_in_checkout deviation_in_checkout,
						v_deviation_in_checkout_time deviation_in_checkout_time,
						v_deviation_in_working_hours deviation_in_working_hours,
						v_deviation_in_working_hours_time deviation_in_working_hours_time,
						0::bigint leave_bank_id,
						v_attandance_leave_type leave_type,
						v_is_auto_assign_shift is_auto_assign_shift,
						TO_CHAR(v_first_check_in_time, 'HH24:MI:SS') first_check_in_time,
						TO_CHAR(v_last_check_out_time, 'HH24:MI:SS') last_check_out_time,
                        v_is_late_comer is_late_comer;
					RETURN response;
				END IF;

				v_user_specific_setting := NULL;
				-- SELECT * FROM vw_shift_list_user_wise WHERE customeraccountid = p_customeraccountid AND is_active='1' AND v_first_check_in_time::timestamp BETWEEN (v_att_date + vw_shift_list_user_wise.default_shift_time_from::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES' AND CASE WHEN vw_shift_list_user_wise.is_night_shift = 'Y' THEN ((v_att_date + INTERVAL '1 DAY') + vw_shift_list_user_wise.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES' ELSE (v_att_date + vw_shift_list_user_wise.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES' END ORDER BY shift_id DESC LIMIT 1
				SELECT * FROM vw_shift_list_user_wise WHERE customeraccountid = p_customeraccountid AND is_active='1' AND v_first_check_in_time::timestamp BETWEEN ((v_att_date + vw_shift_list_user_wise.default_shift_time_from::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES' - vw_shift_list_user_wise.shift_margin_hours_from::interval) AND CASE WHEN vw_shift_list_user_wise.is_night_shift = 'Y' THEN ((v_att_date + INTERVAL '1 DAY') + vw_shift_list_user_wise.default_shift_time_to::time + vw_shift_list_user_wise.shift_margin_hours_to::interval)::timestamp - INTERVAL '5 HOUR 30 MINUTES' ELSE (v_att_date + vw_shift_list_user_wise.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES' + vw_shift_list_user_wise.shift_margin_hours_to::interval END ORDER BY shift_id DESC LIMIT 1
				INTO v_user_specific_setting;
				-- RAISE NOTICE 'v_user_specific_setting - % ', v_user_specific_setting;

				v_is_auto_assign_shift := 'Y';
				v_shift_start_timing := (v_att_date + v_user_specific_setting.default_shift_time_from::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
				IF v_user_specific_setting.is_night_shift = 'Y' THEN
					v_shift_end_timing := ((v_att_date + INTERVAL '1 DAY') + v_user_specific_setting.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
				ELSE
					v_shift_end_timing := (v_att_date + v_user_specific_setting.default_shift_time_to::time)::timestamp - INTERVAL '5 HOUR 30 MINUTES';
				END IF;
				v_shift_working_minutes := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_shift_start_timing::TIMESTAMP - v_total_break_unpaid) / 60);
			-- END - Get employer auto shift (latest)
		END IF;
	-- END - Check whether the employee's check-in time is within the assigned attendance policy; if not, then the system should automatically assign a shift.

	-- START - Round Off Calculations
		-- RAISE NOTICE 'is round off? - %', v_user_specific_setting.is_round_off;
		IF v_user_specific_setting.is_round_off = 'Y' THEN
			v_first_check_in_time_and_shift_minutes_diff := (EXTRACT(EPOCH FROM v_first_check_in_time::TIMESTAMP - v_shift_start_timing::TIMESTAMP) / 60);
			IF v_first_check_in_time_and_shift_minutes_diff > 0 AND v_first_check_in_time_and_shift_minutes_diff <= COALESCE(v_user_specific_setting.first_checkin, 0) THEN
				v_first_check_in_time := v_shift_start_timing;
				v_no_of_minutes_worked := v_no_of_minutes_worked + v_first_check_in_time_and_shift_minutes_diff;
			END IF;

			v_last_check_out_time_and_shift_minutes_diff := (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP) / 60);
			IF v_last_check_out_time_and_shift_minutes_diff > 0 AND v_last_check_out_time_and_shift_minutes_diff <= COALESCE(v_user_specific_setting.last_check_out, 0) THEN
				v_last_check_out_time := v_shift_end_timing;
				v_no_of_minutes_worked := v_no_of_minutes_worked + v_last_check_out_time_and_shift_minutes_diff;
			END IF;
			
			-- RAISE NOTICE 'v_no_of_minutes_worked [%]', v_no_of_minutes_worked;

			v_no_of_minutes_worked := CEIL(v_no_of_minutes_worked);
			-- IF FLOOR(EXTRACT(EPOCH FROM v_last_check_out_time - v_first_check_in_time) / 60) < v_no_of_hours_worked THEN
			-- 	Working hours is less than roundoff working hours
			-- END IF;
		END IF;
	-- END - Round Off Calculations

	-- RAISE NOTICE 'minimum_working_hours_required_for_day : %', v_user_specific_setting.minimum_working_hours_required_for_day;
	-- RAISE NOTICE 'manual_input_shift_hours : %', v_user_specific_setting.manual_input_shift_hours;
	-- START - Min/Max working hours Calculations
		IF v_user_specific_setting.minimum_working_hours_required_for_day = 'Strict' THEN
			IF v_user_specific_setting.manual_input_shift_hours = 'manual_input' THEN
				v_full_day_min_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.full_day_time::INTERVAL)/60;
				v_half_day_min_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.half_day_time::INTERVAL)/60;
			ELSIF v_user_specific_setting.manual_input_shift_hours = 'shift_hours' OR v_user_specific_setting.manual_input_shift_hours = 'shift_hrs' THEN
				v_full_day_min_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.default_shift_full_hours::INTERVAL)/60;
				v_half_day_min_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.default_shift_half_hours::INTERVAL)/60;
			END IF;

			IF COALESCE(v_user_specific_setting.is_max_hours_required, 'N') = 'Y' THEN
				v_half_day_max_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.max_half_day_time::INTERVAL)/60;
				v_full_day_max_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.max_full_day_time::INTERVAL)/60;
			END IF;
			-- RAISE NOTICE 'v_half_day_min_minutes % v_full_day_min_minutes=%', v_half_day_min_minutes,v_full_day_min_minutes;
			-- RAISE NOTICE 'v_no_of_minutes_worked % v_full_day_min_minutes=%', v_no_of_minutes_worked,v_full_day_min_minutes;
			RAISE NOTICE 'v_attandance_type %', v_attandance_type;
			RAISE NOTICE 'v_no_of_minutes_worked %', v_no_of_minutes_worked;
			RAISE NOTICE 'v_half_day_min_minutes %', v_half_day_min_minutes;
			IF v_no_of_minutes_worked <= 0 THEN
				-- v_attandance_type := 'MP';
			 	v_attandance_type := 'PP';  -- as per discussed with Yatin Sir on dated 30/12/2025
				v_attandance_category := 'MP';
			ELSIF v_no_of_minutes_worked < v_half_day_min_minutes THEN
				-- v_attandance_type := 'MP';
				v_attandance_type := 'PP';
				-- v_attandance_category := 'DE';
				v_attandance_category := 'MP';
			ELSIF v_no_of_minutes_worked < v_full_day_min_minutes THEN
				v_attandance_type := 'HD';
			ELSIF v_no_of_minutes_worked > v_full_day_min_minutes THEN
				v_attandance_type := 'PP';
			END IF;
			RAISE NOTICE 'v_attandance_type %', v_attandance_type;
		END IF;

		IF v_user_specific_setting.minimum_working_hours_required_for_day = 'Lenient' THEN
			IF v_user_specific_setting.manual_input_shift_hours = 'manual_input_len' THEN
				v_per_day_min_minutes := EXTRACT(EPOCH FROM COALESCE(NULLIF(v_user_specific_setting.per_day_time, ''), '00:00:00')::INTERVAL)/60;
			ELSIF v_user_specific_setting.manual_input_shift_hours = 'shift_hours_len' THEN
				v_per_day_min_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.default_shift_full_hours::INTERVAL)/60;
			END IF;

			IF COALESCE(v_user_specific_setting.is_max_hours_required, 'N') = 'Y' THEN
				v_per_day_max_minutes := EXTRACT(EPOCH FROM COALESCE(NULLIF(v_user_specific_setting.max_hours_per_day_time, ''), '00:00:00')::INTERVAL)/60;
			END IF;

			-- IF v_no_of_minutes_worked > v_per_day_min_minutes THEN
				v_attandance_type := 'PP';
			-- ELSE
			-- 	v_attandance_type := 'MP';
			-- 	v_attandance_category := 'DE';
			-- END IF;
		END IF;
	-- END - Min/Max working hours Calculations

	-- START - Overtime Calculations
		IF p_customeraccountid = 6969 THEN -- High-Flow Client
			v_overtime := COALESCE(v_assigned_shift.show_overtime_deviation, 'N'); -- Special Permission for Overtime calclation as per the assigned Shift
		ELSE
			v_overtime := COALESCE(v_user_specific_setting.show_overtime_deviation, 'N');
		END IF;

		-- RAISE NOTICE 'v_no_of_minutes_worked [%]', v_no_of_minutes_worked;
		-- RAISE NOTICE 'v_overtime [%]', v_overtime;
		IF v_overtime = 'Y' THEN
			-- RAISE NOTICE 'v_no_of_minutes_worked [%]', (v_no_of_minutes_worked);
			-- RAISE NOTICE 'v_shift_working_minutes [%]', (v_shift_working_minutes);
			-- RAISE NOTICE 'v_shift_working_minutes_assigned [%]', (v_shift_working_minutes_assigned);
			IF ((v_no_of_minutes_worked - v_shift_working_minutes) > 0 OR (v_no_of_minutes_worked - v_shift_working_minutes_assigned) > 0) OR (v_ishourlysetup = 'Y' AND v_no_of_minutes_worked > 0) THEN
				-- IF p_customeraccountid = 6969 THEN  -- Customeraccount Highflow dailywages rate formula
					-- Apply rounding to check-in time
					-- RAISE NOTICE 'v_first_check_in_time [%]', (v_first_check_in_time);
					-- RAISE NOTICE 'v_first_check_in_time [%]', (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES');
					v_rounded_check_in := DATE_TRUNC('hour', (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES')) +
						CASE 
							WHEN EXTRACT(MINUTE FROM (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES')) < 15 THEN INTERVAL '0 minutes'
							WHEN EXTRACT(MINUTE FROM (v_first_check_in_time + INTERVAL '5 HOURS 30 MINUTES')) < 30 THEN INTERVAL '30 minutes'
							ELSE INTERVAL '1 hour'
						END;
					RAISE NOTICE 'v_rounded_check_in [%]', (v_rounded_check_in);
			
					-- Apply rounding to check-out time
					v_rounded_check_out := DATE_TRUNC('hour', (v_last_check_out_time + INTERVAL '5 HOURS 30 MINUTES')) +
						CASE 
							WHEN EXTRACT(MINUTE FROM (v_last_check_out_time + INTERVAL '5 HOURS 30 MINUTES')) < 15 THEN INTERVAL '0 minutes'
							WHEN EXTRACT(MINUTE FROM (v_last_check_out_time + INTERVAL '5 HOURS 30 MINUTES')) < 59 THEN INTERVAL '30 minutes'
							ELSE INTERVAL '1 hour'
						END;
					RAISE NOTICE 'v_rounded_check_out [%]', (v_rounded_check_out);
			
					-- Calculate the duration
					v_rounded_no_of_hours_worked := 
						LPAD(FLOOR(EXTRACT(EPOCH FROM (v_rounded_check_out - v_rounded_check_in)) / 3600)::TEXT, 2, '0') || ':' ||
						LPAD(FLOOR((EXTRACT(EPOCH FROM (v_rounded_check_out - v_rounded_check_in)) % 3600) / 60)::TEXT, 2, '0') || ':' ||
						LPAD(FLOOR((EXTRACT(EPOCH FROM (v_rounded_check_out - v_rounded_check_in)) % 60))::TEXT, 2, '0');
					RAISE NOTICE 'v_rounded_no_of_hours_worked [%]', v_rounded_no_of_hours_worked;

					-- v_rounded_no_of_minutes_worked := EXTRACT(EPOCH FROM (v_rounded_no_of_hours_worked::INTERVAL - INTERVAL '30 MINUTES'))/60; -- 30 Minutes minus from total working time because of lunch time of Hi-Flow Client
					v_rounded_no_of_minutes_worked := EXTRACT(EPOCH FROM (v_rounded_no_of_hours_worked::INTERVAL - v_total_break_unpaid))/60; -- 30 Minutes minus from total working time because of lunch time of Hi-Flow Client
					-- RAISE NOTICE 'v_rounded_no_of_hours_worked [%]', v_rounded_no_of_hours_worked;
					-- RAISE NOTICE 'v_rounded_check_in [%]', v_rounded_check_in;
					-- RAISE NOTICE 'v_rounded_check_out [%]', v_rounded_check_out;
					-- RAISE NOTICE 'v_total_break_unpaid [%]', v_total_break_unpaid;
					RAISE NOTICE 'v_rounded_no_of_minutes_worked [%]', v_rounded_no_of_minutes_worked;
					RAISE NOTICE 'v_total_working_hours_calculation [%]', v_total_working_hours_calculation;
					IF v_total_working_hours_calculation = 'every_valid_check' THEN
						v_overtime_minutes := v_no_of_minutes_worked - v_shift_working_minutes_assigned;
					ELSE
						v_overtime_minutes := v_rounded_no_of_minutes_worked - v_shift_working_minutes_assigned;
					END IF;
					RAISE NOTICE 'v_overtime_minutes [%]', v_overtime_minutes;
					IF v_overtime_minutes < 0 THEN
						v_overtime_minutes = 0;
					END IF;
					RAISE NOTICE 'v_overtime_minutes [%]', v_overtime_minutes;
				-- ELSE
				-- 	v_overtime_minutes := v_no_of_minutes_worked - v_shift_working_minutes;
				-- 	--RAISE NOTICE 'v_overtime_minutes [%]', v_overtime_minutes;
				-- END IF;
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
			p_emp_id => v_emp_id::text
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
				-- START - Change [1.1]
				IF NULLIF(v_user_specific_setting.rule_txt, '') IS NOT NULL THEN
					IF EXISTS(SELECT * FROM tmp_candidate_leave_balance WHERE UPPER(typecode) = UPPER(v_user_specific_setting.rule_txt::jsonb -> 0 -> 'deductLeaveReason' -> 0 ->> 'leavetypecode') AND prev_bal > 0) THEN
						IF UPPER(v_user_specific_setting.rule_txt::jsonb -> 0 -> 'deductLeaveReason' -> 0 ->> 'leave_ctg') = 'PAID' THEN
							v_attandance_leave_type := UPPER(v_user_specific_setting.rule_txt::jsonb -> 0 -> 'deductLeaveReason' -> 0 ->> 'leavetypecode');
						END IF;
					END IF;
				END IF;
				-- END - Change [1.1]

				IF p_customeraccountid = 5852 THEN
					v_attandance_leave_type := 'AA';
				END IF;
			END IF;
		END IF;
	-- START - Leave Details

	-- START - Grace Policy Changes
	-- RAISE NOTICE 'is grace policy applied : %', COALESCE(v_user_specific_setting.enable_grace_period, 'N');
	-- START - Grace Policy Changes
		v_is_grace_policy_applied := COALESCE(v_user_specific_setting.enable_grace_period, 'N');
		IF v_is_grace_policy_applied = 'Y' THEN
			IF v_user_specific_setting.rule_txt IS NOT NULL OR v_user_specific_setting.rule_txt <> '' THEN
				-- START - Get All Daviation of this month
					SELECT -- tma.emp_code, MAX(oa.emp_name) emp_name, MIN(att_date) min_date, MAX(att_date) max_date, COUNT(tma.*) total_records,
						SUM(COALESCE(tma.deviation_in_checkin, '0')::INT), SUM(COALESCE(tma.deviation_in_checkout, '0')::INT), SUM(COALESCE(tma.deviation_in_total_working_hours, '0')::INT)
					INTO v_total_deviation_checkin, v_total_deviation_checkout, v_deviation_in_total_working_hours
					FROM tbl_monthly_attendance tma
					INNER JOIN openappointments oa ON oa.emp_code = tma.emp_code AND oa.customeraccountid = p_customeraccountid
					WHERE tma.isactive = '1' AND tma.att_date BETWEEN (DATE_TRUNC('month', v_att_date))::DATE AND v_att_date AND tma.emp_code = p_emp_code
					GROUP BY tma.emp_code;
				-- END - Get All Daviation of this month
				-- RAISE NOTICE 'v_total_deviation_checkin [%]', v_total_deviation_checkin;
				-- RAISE NOTICE 'v_user_specific_setting.rule_txt [%]', v_user_specific_setting.rule_txt;

				SELECT v_user_specific_setting.rule_txt::jsonb INTO v_grace_period_JSON;
				FOR row_data IN SELECT * FROM jsonb_array_elements(v_grace_period_JSON) LOOP
					-- RAISE NOTICE 'firstCheckInLateBy : %', row_data;
					-- RAISE NOTICE 'firstCheckInLateBy : %', row_data->>'firstCheckInLateBy';
					/*
						[
							{
								"firstCheckInLateBy": true,
								"firstCheckInLateTime": "1",
								"lastCheckOutEarlyBy": false,
								"lastCheckOutEarlyTime": "",
								"workingHoursLessBy": false,
								"workingHoursLessTime": "",
								"deviationsMoreThanTimes": "3",
								"deviationsMoreThanPeriod": "month",
								"deviationsMultiplesOf": "",
								"deviationsMultiplesOfPeriod": "",
								"deductLeaveBalanceDays": "",
								"deductLeaveReasonTypes": null,
								"deviationsRadio": "deviation_more_than",
								"deductLeaveBalance": "0.5",
								"firstCheckinR2": false,
								"firstCheckinR2LateTime": "",
								"deductLeaveReason": [
									{
										"leave_id": 7,
										"leave_type": "Casual leave",
										"el_sn": 5,
										"leave_ctg": "Paid",
										"leavetypecode": "CL"
									}
								]
							}
						]
					*/

					v_leave_deduction_days := (COALESCE(NULLIF((row_data->>'deductLeaveBalance'), ''), '0'))::NUMERIC;
					v_deviations_more_than_times := (COALESCE(NULLIF((row_data->>'deviationsMoreThanTimes'), ''), '0'))::NUMERIC;
					v_deviations_more_than_period := (row_data->>'deviationsMoreThanPeriod'); -- Weekly, Monthly, Pay Period
					v_deviations_frequency := (row_data->>'deviationsRadio'); -- deviation_more_than, deviation_multiples_of

					-- RAISE NOTICE 'v_leave_deduction_days [%]', v_leave_deduction_days;
					-- RAISE NOTICE 'v_deviations_more_than_times [%]', v_deviations_more_than_times;
					-- RAISE NOTICE 'v_deviations_more_than_period [%]', v_deviations_more_than_period;
					-- RAISE NOTICE 'v_deviations_frequency [%]', v_deviations_frequency;
					-- RAISE NOTICE 'firstCheckInLateBy [%]', (row_data->>'firstCheckInLateBy');

					IF (row_data->>'firstCheckInLateBy')::boolean = TRUE THEN
						v_deviation_in_checkin := 0;
						IF (EXTRACT(EPOCH FROM v_first_check_in_time::TIMESTAMP - v_shift_start_timing::TIMESTAMP) / 60) > COALESCE((row_data->>'firstCheckInLateTime')::int, 0) THEN
							v_deviation_in_checkin := 1;
							v_deviation_in_checkin_time := (TO_CHAR((v_first_check_in_time::TIMESTAMP - v_shift_start_timing::TIMESTAMP), 'HH24:MI:SS'))::TEXT;
							v_is_late_comer := 'Y';

							-- RAISE NOTICE 'v_total_deviation_checkin [%]', v_total_deviation_checkin;
							-- RAISE NOTICE 'v_deviations_more_than_times [%]', v_deviations_more_than_times;
							-- RAISE NOTICE 'v_deviations_more_than_period [%]', v_deviations_more_than_period;
							-- RAISE NOTICE 'v_deviations_frequency [%]', v_deviations_frequency;
							-- RAISE NOTICE 'deductLeaveReason [%]', (row_data->'deductLeaveReason');
							IF v_total_deviation_checkin > v_deviations_more_than_times AND v_deviations_more_than_period = 'month' AND v_deviations_frequency = 'deviation_more_than' AND COALESCE(v_last_check_out_time::TEXT, '') <> '' THEN
								IF jsonb_typeof(row_data->'deductLeaveReason') = 'array' THEN
									FOR v_deduction_row_data IN 0 .. jsonb_array_length(row_data->'deductLeaveReason') - 1 LOOP
										v_leave_deduction_reason := (row_data->>'deductLeaveReason')::JSONB->v_deduction_row_data;
										-- RAISE NOTICE 'v_leave_deduction_reason [%]', v_leave_deduction_reason;
										IF v_leave_deduction_reason ? 'leavetypecode' AND v_leave_deduction_reason ? 'leave_ctg' THEN
											IF EXISTS (SELECT 1 FROM tmp_candidate_leave_balance WHERE UPPER(typecode) = UPPER(v_leave_deduction_reason ->> 'leavetypecode') AND prev_bal > 0) THEN
												IF v_leave_deduction_days = 1 THEN
													v_attandance_type := 'LL';
													v_attandance_category := NULL;
												ELSE
													v_attandance_type := 'HD';
													v_attandance_category := NULL;
												END IF;
												-- RAISE NOTICE 'v_attandance_type Check IN [%]', v_attandance_type;

												IF UPPER(v_leave_deduction_reason ->> 'leave_ctg') = 'PAID' THEN
													v_attandance_leave_type := UPPER(v_leave_deduction_reason ->> 'leavetypecode');
												ELSE
													v_attandance_leave_type := 'AA';
												END IF;
												-- RAISE NOTICE 'v_attandance_type [%]', v_attandance_type;
												-- RAISE NOTICE 'v_attandance_category [%]', v_attandance_category;
												-- RAISE NOTICE 'v_attandance_leave_type [%]', v_attandance_leave_type;
											ELSE
												IF v_leave_deduction_days = 1 THEN
													v_attandance_type := 'LL';
												ELSE
													v_attandance_type := 'HD';
												END IF;
												v_attandance_category := NULL;
												v_attandance_leave_type := 'AA';
											END IF;
										END IF;
									END LOOP;
								END IF;
							END IF;
						END IF;
					END IF;

					IF (row_data->>'lastCheckOutEarlyBy')::boolean = TRUE THEN
						v_deviation_in_checkout := 0;
						IF (EXTRACT(EPOCH FROM v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP) / 60) > COALESCE((row_data->>'lastCheckOutEarlyTime')::int, 0) THEN
							v_deviation_in_checkout := 1;
							v_deviation_in_checkout_time := (TO_CHAR((v_shift_end_timing::TIMESTAMP - v_last_check_out_time::TIMESTAMP), 'HH24:MI:SS'))::TEXT;

							IF v_total_deviation_checkout > v_deviations_more_than_times AND v_deviations_more_than_period = 'month' AND v_deviations_frequency = 'deviation_more_than' AND COALESCE(v_last_check_out_time::TEXT, '') <> '' THEN
								IF jsonb_typeof(row_data->'deductLeaveReason') = 'array' THEN
									FOR v_deduction_row_data IN 0 .. jsonb_array_length(row_data->'deductLeaveReason') - 1 LOOP
										v_leave_deduction_reason := (row_data->>'deductLeaveReason')::JSONB->v_deduction_row_data;
										IF v_leave_deduction_reason ? 'leavetypecode' AND v_leave_deduction_reason ? 'leave_ctg' THEN
											IF EXISTS (SELECT 1 FROM tmp_candidate_leave_balance WHERE UPPER(typecode) = UPPER(v_leave_deduction_reason ->> 'leavetypecode') AND prev_bal > 0) THEN
												IF v_leave_deduction_days = 1 THEN
													v_attandance_type := 'LL';
													v_attandance_category := NULL;
												ELSE
													v_attandance_type := 'HD';
													v_attandance_category := NULL;
												END IF;

												IF UPPER(v_leave_deduction_reason ->> 'leave_ctg') = 'PAID' THEN
													v_attandance_leave_type := UPPER(v_leave_deduction_reason ->> 'leavetypecode');
												ELSE
													v_attandance_leave_type := 'AA';
												END IF;
											END IF;
										END IF;
									END LOOP;
								END IF;
							END IF;
						END IF;
					END IF;

					-- RAISE NOTICE 'workingHoursLessBy : %', row_data->>'workingHoursLessBy';
					IF (row_data->>'workingHoursLessBy')::boolean = TRUE THEN
						v_deviation_in_working_hours := 0;
						-- RAISE NOTICE 'workingHoursLessTime : %', row_data->>'workingHoursLessTime';
						IF v_no_of_minutes_worked < COALESCE((row_data->>'workingHoursLessTime')::int, 0) THEN
							v_deviation_in_working_hours := 1;
							v_deviation_in_working_hours_time := (TO_CHAR(make_interval(mins => COALESCE((row_data->>'workingHoursLessTime')::int, 0) - COALESCE(v_no_of_minutes_worked::int, 0)), 'HH24:MI:SS'))::TEXT;
						END IF;
					END IF;
				END LOOP;
			END IF;
		END IF;
	-- END - Grace Policy Changes

	-- START - Changes [2.3]
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
	-- END - Changes [2.3]

	-- START - Response
		OPEN response FOR
			SELECT
			1 status_code,
			'Successfully calculated employee attendance policy.' msg,
			p_emp_code emp_code,
			v_att_date att_date,
			v_shift_id shift_id,
			v_user_specific_setting.attendance_policy_type,
			v_user_specific_setting.attendance_policy_id,
			CASE WHEN v_ishourlysetup = 'Y' AND p_customeraccountid = 6969 THEN v_rounded_no_of_minutes_worked ELSE v_no_of_minutes_worked END no_of_minutes_worked,
			CASE WHEN v_ishourlysetup = 'Y' AND p_customeraccountid = 6969 THEN TO_CHAR((v_rounded_no_of_minutes_worked * INTERVAL '1 minute'), 'HH24:MI:SS') ELSE TO_CHAR((v_no_of_minutes_worked * INTERVAL '1 minute'), 'HH24:MI:SS') END no_of_hours_worked,
			-- v_rounded_no_of_minutes_worked no_of_minutes_worked,
			-- TO_CHAR((v_rounded_no_of_minutes_worked * INTERVAL '1 minute'), 'HH24:MI:SS') no_of_hours_worked,
			-- v_no_of_minutes_worked no_of_minutes_worked,
			-- TO_CHAR((v_no_of_minutes_worked * INTERVAL '1 minute'), 'HH24:MI:SS') no_of_hours_worked,
			v_overtime is_overtime,
			TO_CHAR((v_overtime_minutes * INTERVAL '1 minute'), 'HH24:MI:SS') no_of_overtime_hours_worked,
			v_attandance_type attandance_type,
			v_attandance_category attandance_category,
			v_is_grace_policy_applied grace_policy_applied,
			v_deviation_in_checkin deviation_in_checkin,
			v_deviation_in_checkin_time deviation_in_checkin_time,
			v_deviation_in_checkout deviation_in_checkout,
			v_deviation_in_checkout_time deviation_in_checkout_time,
			v_deviation_in_working_hours deviation_in_working_hours,
			v_deviation_in_working_hours_time deviation_in_working_hours_time,
			COALESCE(v_leave_template_details.leave_bank_id, 0) leave_bank_id,
			v_attandance_leave_type leave_type,
			v_is_auto_assign_shift is_auto_assign_shift,
			TO_CHAR(v_first_check_in_time, 'HH24:MI:SS') first_check_in_time,
			TO_CHAR(v_last_check_out_time, 'HH24:MI:SS') last_check_out_time,
            v_is_late_comer is_late_comer;
		RETURN response;
	-- END - Response
END;
$BODY$;

ALTER FUNCTION public.calculate_employee_attandance_policy(bigint, bigint, character varying)
    OWNER TO payrollingdb;

