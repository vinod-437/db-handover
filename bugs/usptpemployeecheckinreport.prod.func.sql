-- FUNCTION: public.usptpemployeecheckinreport(text, text, text, bigint, bigint, integer, character varying, character varying, character varying, character varying, text, text, text, integer, integer, text)

-- DROP FUNCTION IF EXISTS public.usptpemployeecheckinreport(text, text, text, bigint, bigint, integer, character varying, character varying, character varying, character varying, text, text, text, integer, integer, text);

CREATE OR REPLACE FUNCTION public.usptpemployeecheckinreport(
	p_action text,
	p_from_date text,
	p_to_date text,
	p_customeraccountid bigint DEFAULT '-9999'::integer,
	p_empcode bigint DEFAULT '-9999'::integer,
	p_geofenceid integer DEFAULT 0,
	p_ou_ids character varying DEFAULT NULL::character varying,
	p_attendance_type character varying DEFAULT 'ALL'::character varying,
	p_report_type character varying DEFAULT NULL::character varying,
	p_marked_type character varying DEFAULT NULL::character varying,
	p_post_offered text DEFAULT ''::text,
	p_posting_department text DEFAULT ''::text,
	p_unitparametername text DEFAULT ''::text,
	p_month integer DEFAULT 0,
	p_year integer DEFAULT 0,
	p_search_keyword text DEFAULT ''::text)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
/*************************************************************************
Version         Date            Change                               Done_by
1.0             21-JULY-2023    INITIAL VERSION                      Siddharth Bansal
1.1             25-JULY-2023    change Response type                 Shiv Kumar
1.2             19-JAN-2024     Add geo fencing details in           Parveen Kumar
                                GetEmployeeTodayAttendance
1.3             15-MAR-2024     'GetAttendanceSummaryByemployer'     chandra mohan
                                Date change date_trunc('month',DATE v_from_date)
2.              23-Mar-2024     Add p_geofenceid changes in 
								GetAttendanceSummaryByemployer 
								and GetAttendanceDetailByemployee    Parveen Kumar
2.1				23-Apr-2024		Change Response for 
								GetAttendanceDetailByemployee		SIDDHARTH BANSAL
								Action
2.2				04-May-2024		TP checkin checkout Detail report  SIDDHARTH BANSAL
								on the basis of first_last_check 
								or every_valid_check
2.3				17-May-2024		TP Check In/Out Detail report for mobile  Parveen Kumar
3.0				05-May-2024		Add Attendance Policy column in response	Parveen Kumar
3.1				28-June-2024	Add attendance_type column in response		Parveen Kumar
3.2				27-July-2024	Add break_total_time, break_pay_type column in response			Parveen Kumar
3.3				03-Aug-2024	    Add OU Id Filter			                Parveen Kumar
3.4				23-Aug-2024		Add jobtype, meeting_name, meeting_feedback column in response		        Parveen Kumar
3.5				03-Sept-2024	Add report type changes (p_report_type)		        Parveen Kumar
3.6				25-Nov-2024		Add meeting_remarks column in response		        Parveen Kumar
3.7				24-Dec-2024		Add p_marked_type Changes		        			Parveen Kumar
3.8				18-Feb-2025		Add 4 new columns in response		        		Parveen Kumar
								early_check_out_amount, early_check_out_time, late_check_in_time, late_check_in_amount
3.9             04-Apr-2025    'GetAttendanceSummaryByemployerEL'     				chandra mohan
4.0             21-Jul-2025    Night Shift Changes     								Parveen Kumar
4.1             04-Aug-2025    OverTime CheckOut Changes							Parveen Kumar
4.2             04-Aug-2025    Add shift duration in response						Parveen Kumar
4.3            20-Aug-2025    Add Multipler Flag Changes							Vinod  Kumar
4.4            14-Sep-2025    add designation check from master tables
4.5            10-Dec-2025    Add check In/Out Lat Long into response				Parveen Kumar
4.6            18-Jan-2026    Add row_id into response								Parveen Kumar
4.7            09-Feb-2026    Dynamic shift_duration based on check-in time			Parveen Kumar [Antigravity]
4.8            11-Feb-2026    Add Auto shift rotation functionality					Parveen Kumar
*************************************************************************/
DECLARE
	v_result refcursor;
	v_from_date DATE;
	v_to_date DATE;
	v_jobtypecode TEXT;

	-- START - Night Shift Changes [4.0]
	v_att_date DATE := (CURRENT_TIMESTAMP + '5 HOURS 30 MINUTES')::DATE;
	v_user_specific_setting record;
	v_shift_start_timing timestamp;
	v_shift_end_timing timestamp;
	v_shift_start_timing_mobile timestamp;
	v_shift_duration INTERVAL;
	v_is_time_exists_between_assigned_att_policy character varying(1) := 'Y';
	-- END - Night Shift Changes [4.0]
	v_auto_shift_rotation character varying(1) := 'Y';
	v_shift_id INT := NULL;

BEGIN
	-- START - OverTime CheckOut Changes [4.1]
		IF EXISTS (SELECT * FROM vw_user_spc_emp WHERE emp_code = p_empcode AND is_active = '1' AND is_night_shift <> 'Y') THEN
			SELECT COALESCE(auto_shift_rotation_yn, 'Y')
			INTO v_auto_shift_rotation 
			FROM tbl_employee_auto_rotation
			WHERE account_id = p_customeraccountid AND emp_code = p_empcode AND status = '1';
			v_auto_shift_rotation := COALESCE(v_auto_shift_rotation, 'Y');
			IF v_auto_shift_rotation = 'N' THEN
				SELECT shift_id INTO v_shift_id
				FROM tbl_employee_shift_roster
				WHERE account_id = p_customeraccountid AND emp_code::BIGINT = p_empcode  AND status = '1' AND roster_date = v_att_date;
			END IF;
			
			IF v_shift_id IS NOT NULL THEN
				SELECT * FROM vw_shifts WHERE shift_id::bigint = v_shift_id AND is_active = '1' LIMIT 1 INTO v_user_specific_setting;
			ELSE
				SELECT * FROM vw_user_spc_emp WHERE emp_code::bigint = p_empcode AND is_active='1' AND is_night_shift <> 'Y' INTO v_user_specific_setting;
			END IF;
			-- START - Shift Timing & Margin
			v_shift_start_timing := ((v_att_date - INTERVAL '1 DAY') + COALESCE(NULLIF(v_user_specific_setting.default_shift_time_from, ''), '00:00:00')::interval)::timestamp;
			v_shift_end_timing := (v_att_date - INTERVAL '1 DAY' + COALESCE(NULLIF(v_user_specific_setting.default_shift_time_to, ''), '00:00:00')::interval)::timestamp;
			v_shift_start_timing_mobile := ((v_att_date - INTERVAL '1 DAY') + COALESCE(NULLIF(v_user_specific_setting.default_shift_time_from, ''), '00:00:00')::interval)::timestamp;
				v_shift_duration := (
						SELECT
							LPAD(FLOOR(total_seconds / 3600)::text, 2, '0') || ':' ||
							LPAD(FLOOR((total_seconds % 3600) / 60)::text, 2, '0') || ':' ||
							LPAD(FLOOR(total_seconds % 60)::text, 2, '0')
						FROM (
							SELECT EXTRACT(
								EPOCH FROM (
									(
										(CURRENT_DATE + COALESCE(NULLIF(v_user_specific_setting.default_shift_time_to, ''), '00:00:00')::time)
										+ CASE WHEN COALESCE(NULLIF(v_user_specific_setting.is_night_shift, ''), 'N') = 'Y' THEN INTERVAL '1 DAY' ELSE INTERVAL '0 DAY' END
										+ CASE WHEN COALESCE(NULLIF(v_user_specific_setting.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_to, ''), '00:00:00')::interval ELSE INTERVAL '0' END
									)
									-
									(
										(CURRENT_DATE + COALESCE(NULLIF(v_user_specific_setting.default_shift_time_from, ''), '00:00:00')::time)
										- CASE WHEN COALESCE(NULLIF(v_user_specific_setting.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_from, ''), '00:00:00')::interval ELSE INTERVAL '0' END
									)
								)
							) AS total_seconds
						) s
					);

			IF COALESCE(NULLIF(v_user_specific_setting.shift_margin, ''), 'N') = 'Y' THEN
				SELECT
					CASE
						WHEN (CURRENT_TIMESTAMP + INTERVAL '5 HOURS 30 MINUTES') BETWEEN (v_shift_start_timing - COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_from, ''), '00:00:00')::interval) AND (v_shift_end_timing + COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_to, ''), '00:00:00')::interval) THEN 'Y'
						ELSE 'N'
					END
				INTO v_is_time_exists_between_assigned_att_policy;
			ELSE
				SELECT
					CASE
						WHEN (CURRENT_TIMESTAMP + INTERVAL '5 HOURS 30 MINUTES') BETWEEN v_shift_start_timing AND v_shift_end_timing THEN 'Y'
						ELSE 'N'
					END
				INTO v_is_time_exists_between_assigned_att_policy;
			END IF;
			-- END - Shift Timing & Margin
			
			IF v_is_time_exists_between_assigned_att_policy = 'Y' AND (CURRENT_TIMESTAMP + INTERVAL '5 HOURS 30 MINUTE')::TIME > '00:00:00'::TIME THEN
				v_att_date := v_att_date - INTERVAL '1 DAY';
			END IF;
		END IF;
	-- END - OverTime CheckOut Changes [4.1]

	if p_from_date='' then
		v_from_date = v_att_date;
	else
		v_from_date=to_date(p_from_date,'dd-mm-yyyy');
	end if;
	if p_to_date='' then
		v_to_date = v_att_date;
	else
		v_to_date=to_date(p_to_date,'dd-mm-yyyy');
	end if;
	
	SELECT string_agg(jobtypecode, ',') INTO v_jobtypecode FROM mst_jobtype
	WHERE jobtypecode <> 'Meeting';

	raise notice 'v_jobtypecode=>%',v_jobtypecode;
	
	if p_customeraccountid= '9413' then
		v_jobtypecode:= v_jobtypecode||',Meeting';
	end if;

	IF p_action = 'GetAttendanceSummaryByemployer_test_old' THEN
		OPEN v_result FOR
			WITH t1 AS
			(
				SELECT op.emp_code,t.att_date,json_agg
				(
					json_build_object
					(
						'row_id', t.id::TEXT,
						'att_date', COALESCE(TO_CHAR(t.att_date,'dd-mm-yyyy'), TO_CHAR(v_from_date::DATE, 'dd-mm-yyyy')), 
						'actual_check_in_time', t.check_in_time, 
						'actual_check_out_time', t.check_out_time, 
						'check_in_time', COALESCE(to_char(t.check_in_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
						'check_out_time', COALESCE(to_char(t.check_out_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
						-- 'no_of_hours_worked', COALESCE(to_char(date_trunc('minute',t.check_out_time) - date_trunc('minute',t.check_in_time),'hh24:mi'),'00:00'), 
						'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0'), 
						'check_in_location', COALESCE(t.check_in_location,''), 
						'check_out_location', COALESCE(t.check_out_location,''), 
						'check_in_image_path', COALESCE(t.check_in_image_path,''), 
						'check_out_image_path', COALESCE(t.check_out_image_path,''),
						'attendance_type', COALESCE(t.attendance_type,''),
						'meeting_name', COALESCE(t.meeting_name,''),
						'meeting_feedback', COALESCE(t.meeting_feedback,''),
						'meeting_remarks', COALESCE(t.meeting_remarks,''),
						'check_in_geofence_id', COALESCE(t.check_in_geofence_id::TEXT, ''),
						'check_in_geofence_id_name', COALESCE((SELECT org_unit_name FROM tbl_org_unit_geofencing WHERE id = t.check_in_geofence_id)::TEXT, ''),
						'check_out_geofence_id', COALESCE(t.check_out_geofence_id::TEXT,''),
						'check_out_geofence_id_name', COALESCE((SELECT org_unit_name FROM tbl_org_unit_geofencing WHERE id = t.check_in_geofence_id)::TEXT, ''),
						'check_in_date', COALESCE(to_char(t.check_in_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','DD-MM-YYYY'),''), 
						'check_out_date', COALESCE(to_char(t.check_out_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','DD-MM-YYYY'),''),
						'approvalappid',coalesce(t.approvalappid,0),
						'isapprovalapproved',coalesce(t.isapprovalapproved,'Y'),
						'app_level',coalesce(ta.level,0),
						-- START - Changes [4.5]
						'check_in_latitude', COALESCE(t.check_in_latitude,''),
						'check_in_longitude', COALESCE(t.check_in_longitude,''),
						'check_out_latitude', COALESCE(t.check_out_latitude,''),
						'check_out_longitude', COALESCE(t.check_out_longitude,'')
						-- END - Changes [4.5]
					) ORDER BY t.id ASC
				) AS check_in_out_details
				FROM openappointments op
				INNER JOIN tbl_attendance t ON t.emp_code=op.emp_code AND t.att_date BETWEEN v_from_date::DATE AND v_to_date::DATE AND t.isactive='1'
				left join tbl_application ta on t.emp_code=ta.emp_code and ta.standardappmoduleid=37 and ta.status=1 and ta.application_id=t.approvalappid
				where op.customeraccountid = p_customeraccountid
				-- Add new Filter Block
				 	AND COALESCE(op.converted, 'N') = 'Y' AND op.appointment_status_id IN (11,14)
					AND op.dateofjoining <= v_to_date::DATE AND (op.dateofrelieveing is null OR op.dateofrelieveing >= v_from_date::DATE)
				 	AND (op.emp_name ILIKE '%'||p_search_keyword||'%' OR COALESCE(op.cjcode, '0') = p_search_keyword OR COALESCE(op.orgempcode, '0') = p_search_keyword)
					AND op.jobtype = ANY (SELECT unnest(string_to_array(CASE WHEN p_report_type = 'Meeting' THEN 'Meeting' ELSE v_jobtypecode END, ',')))
					AND (op.emp_code = p_empcode OR p_empcode = -9999)
				-- Add new Filter Block
				AND (
				COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
				OR EXISTS (
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(op.post_offered)), ',')) AS input_designation
						WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(op.post_offered), ''), ''), ','))
					)
				)

				AND (
				COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
				OR EXISTS (
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(op.posting_department)), ',')) AS input_department
						WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(op.posting_department), ''), ''), ','))
					)
				)
				AND EXISTS
					(
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
						WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
					)
				AND (op.emp_code = p_empcode OR p_empcode = -9999)
				-- SIDDHARTH BANSAL 14/08/2025
		         AND (op.emp_name ILIKE '%'||p_search_keyword||'%' OR COALESCE(op.cjcode, '0') = p_search_keyword OR COALESCE(op.orgempcode, '0') = p_search_keyword)
				--END
				group by op.emp_code,t.att_date
			)

			SELECT 
				CASE WHEN (subquery.emp_code is not null OR tma.emp_code IS NOT NULL) THEN 'Marked' ELSE 'Unmarked' END as marked_status,
				'CheckInCheckOut' table_ref,
				op.emp_code::text, op.emp_name, 
				-- op.post_offered 
				COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered)	designation, op.jobtype,
				 --ADD THIS LINE RIGHT HERE location by chandra mohan 08 july 2025
				(SELECT location FROM tbl_emp_transfer_location_history 
				 WHERE emp_code = op.emp_code AND is_latest = '1' AND isactive = '1' LIMIT 1) AS location,
				--TO_CHAR(subquery.att_date,'dd-mm-yyyy') attendancedate,
		        TO_CHAR(coalesce(subquery.att_date,v_from_date),'dd-mm-yyyy') attendancedate,
				COALESCE((subquery.check_in_out_details->0->>'check_in_time'), '00:00') AS check_in_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_time', '00:00') AS check_out_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'attendance_type', '') AS attendance_type,
				CASE WHEN COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_time', '00:00') = '00:00' THEN 0 ELSE json_array_length(subquery.check_in_out_details) END AS check_in_out_count,
				CASE WHEN emp_cico.total_working_hours_calculation = 'first_last_check' THEN
					CASE WHEN json_array_length(subquery.check_in_out_details) > 1 AND subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					ELSE
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					END
				ELSE
					(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(subquery.check_in_out_details) AS trips(trip))
				END AS no_of_hours_worked,
				COALESCE((subquery.check_in_out_details->0->>'check_in_location'), '') AS check_in_location,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_location'), '') AS check_out_location,
				COALESCE((subquery.check_in_out_details->0->>'check_in_image_path'), '') AS check_in_image_path,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_image_path'), '') AS check_out_image_path,
				nullif(op.dateofjoining,'0001-01-01 BC') dateofjoining,
				NULLIF(tc.document_path,'https://api.contract-jobs.com/crm_api/') AS photopath,
				op.orgempcode, op.cjcode tpcode,
				coalesce(subquery.check_in_out_details,'[{}]')::jsonb check_in_out_details,
				tma.is_overtime is_overtime_applicable, tma.no_of_overtime_hours_worked, tma.deviation_in_checkin, tma.deviation_in_checkout, tma.deviation_in_total_working_hours,
				COALESCE(emp_cico.shift_name, emp_cico.shift_name)||' ['||COALESCE(emp_cico.default_shift_time_from, emp_cico.default_shift_time_from)||'-'||COALESCE(emp_cico.default_shift_time_to, emp_cico.default_shift_time_to)||']'||CASE WHEN COALESCE(tma.is_auto_shift_assign, 'N')='Y' THEN '[Auto Shift]' ELSE '' END AS shift_name,
				COALESCE(emp_cico.is_night_shift, COALESCE(emp_cico.is_night_shift, 'N')) is_night_shift,
				COALESCE(emp_cico.break_total_time, emp_cico.break_total_time) break_total_time,
				nullif(COALESCE(emp_cico.break_pay_type, emp_cico.break_pay_type),'') break_pay_type,
				tma.is_auto_shift_assign is_auto_shift_assign,
				tma.attendance_policy_id attendance_policy_id, op.posting_department department,
				op.assigned_ou_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id IN (select regexp_split_to_table(COALESCE(NULLIF(op.assigned_ou_ids, ''), '0'),',')::int)) assigned_ou_ids_names,
				NULLIF(op.assigned_geofence_ids, '') assigned_geofence_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id IN (select regexp_split_to_table(COALESCE(NULLIF(op.assigned_geofence_ids, ''), '0'),',')::int)) assigned_geofence_ids_names,
				COALESCE((subquery.check_in_out_details->0->>'check_in_date'), '') AS check_in_date,
				COALESCE((subquery.check_in_out_details->0->>'check_out_date'), '') AS check_out_date,
				COALESCE(tma.late_multiplier,'1') late_multiplier,
				COALESCE(tma.early_multiplier,'1') early_multiplier,
				COALESCE(tma.overtime_multiplier,'1') overtime_multiplier,
				(tma.deviation_in_checkin_time) deviation_in_checkin_time,
				(tma.deviation_in_checkout_time) deviation_in_checkout_time,
				(tma.deviation_in_working_hours_time) deviation_in_working_hours_time,
				tma.id as monthlyattendanceid,
				usp_attnname_by_code(tma.att_catagory) att_catagory,
				COALESCE(tma.attendance_type,'') attendance_type_m,
				case when (subquery.check_in_out_details->0->>'app_level')::int<=1 or subquery.check_in_out_details->0->>'approvalappid' ='0' or (subquery.check_in_out_details->0->>'approvalappid'<>'0' and subquery.check_in_out_details->0->>'isapprovalapproved'='N' and (subquery.check_in_out_details->0->>'app_level')::int <=1) then 'Y' else 'N' end as allowedit,
				(subquery.check_in_out_details->0->>'app_level')::int app_level
			FROM openappointments op
			LEFT JOIN t1 AS subquery on op.emp_code=subquery.emp_code
			LEFT JOIN tbl_candidate_documentlist tc ON op.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
			LEFT JOIN vw_user_spc_emp AS emp_cico ON emp_cico.emp_code::bigint = op.emp_code::bigint AND is_active='1'  and emp_cico.customeraccountid=p_customeraccountid
			LEFT JOIN tbl_monthly_attendance AS tma ON tma.emp_code::bigint = subquery.emp_code::bigint AND tma.isactive='1' AND tma.att_date=subquery.att_date
			LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and account_id= op.customeraccountid
			WHERE
				op.customeraccountid=p_customeraccountid AND COALESCE(op.converted, 'N') = 'Y' AND op.appointment_status_id IN (11,14)
				AND op.dateofjoining <= v_to_date::DATE AND (op.dateofrelieveing is null OR op.dateofrelieveing >= v_from_date::DATE)
				AND EXISTS
				(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
				)
				AND 
				(
					p_marked_type = 'All'
					OR (p_marked_type = 'Marked' and (subquery.emp_code IS NOT NULL OR tma.emp_code IS NOT NULL)) 
					OR (p_marked_type = 'Not Marked' and (subquery.emp_code IS NULL and tma.emp_code IS NULL)) 
				)
				AND
				(
					COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
					OR EXISTS (
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(op.post_offered)), ',')) AS input_designation
						WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(op.post_offered), ''), ''), ','))
					)
				)
				AND
				(
					COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
					OR EXISTS (
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(op.posting_department)), ',')) AS input_department
						WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(op.posting_department), ''), ''), ','))
					)
				)
				-- AND EXISTS
				-- 	(
				-- 		SELECT 1
				-- 		FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				-- 		WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
				-- 	)
					-- SIDDHARTH BANSAL 14/08/2025
		         AND (op.emp_name ILIKE '%'||p_search_keyword||'%' OR COALESCE(op.cjcode, '0') = p_search_keyword OR COALESCE(op.orgempcode, '0') = p_search_keyword)
				--END
				AND op.jobtype = ANY (SELECT unnest(string_to_array(CASE WHEN p_report_type = 'Meeting' THEN 'Meeting' ELSE v_jobtypecode END, ',')))
				AND (op.emp_code = p_empcode OR p_empcode = -9999)
			ORDER BY subquery.emp_code ASC;
        RETURN v_result;
	----Chandra mohan New Action 04 apr 2025
	ELSIF p_action = 'GetAttendanceSummaryByemployerEL' THEN
		OPEN v_result FOR
			WITH t1 AS
			(
				SELECT op.emp_code,t.att_date,json_agg
				(
					json_build_object
					(
						'att_date', COALESCE(TO_CHAR(t.att_date,'dd-mm-yyyy'), TO_CHAR(v_from_date::DATE, 'dd-mm-yyyy')), 
						'actual_check_in_time', t.check_in_time, 
						'actual_check_out_time', t.check_out_time, 
						'check_in_time', COALESCE(to_char(t.check_in_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
						'check_out_time', COALESCE(to_char(t.check_out_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
						-- 'no_of_hours_worked', COALESCE(to_char(date_trunc('minute',t.check_out_time) - date_trunc('minute',t.check_in_time),'hh24:mi'),'00:00'), 
						'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0'), 
						'check_in_location', COALESCE(t.check_in_location,''), 
						'check_out_location', COALESCE(t.check_out_location,''), 
						'check_in_image_path', COALESCE(t.check_in_image_path,''), 
						'check_out_image_path', COALESCE(t.check_out_image_path,''),
						'attendance_type', COALESCE(t.attendance_type,''),
						'meeting_name', COALESCE(t.meeting_name,''),
						'meeting_feedback', COALESCE(t.meeting_feedback,''),
						'meeting_remarks', COALESCE(t.meeting_remarks,''),
						'check_in_geofence_id', COALESCE(t.check_in_geofence_id::TEXT, ''),
						'check_in_geofence_id_name', COALESCE((SELECT org_unit_name FROM tbl_org_unit_geofencing WHERE id = t.check_in_geofence_id)::TEXT, ''),
						'check_out_geofence_id', COALESCE(t.check_out_geofence_id::TEXT,''),
						'check_out_geofence_id_name', COALESCE((SELECT org_unit_name FROM tbl_org_unit_geofencing WHERE id = t.check_in_geofence_id)::TEXT, '')
					) ORDER BY t.id ASC
				) AS check_in_out_details
				FROM openappointments op
				INNER JOIN tbl_attendance t ON t.emp_code=op.emp_code AND t.att_date BETWEEN v_from_date::DATE AND v_to_date::DATE AND t.isactive='1'
				where op.customeraccountid = p_customeraccountid and t.emp_code IN (
						SELECT emp_code 
						FROM openappointments 
						WHERE reportingmanager_emp_code =p_empcode::bigint)
				group by op.emp_code,t.att_date
			)

			SELECT 
				CASE WHEN (subquery.emp_code is not null OR tma.emp_code IS NOT NULL) THEN 'Marked' ELSE 'Unmarked' END as marked_status,
				'CheckInCheckOut' table_ref,
				op.emp_code::text, op.emp_name, --op.post_offered 
				COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered) designation, op.jobtype,
				TO_CHAR(subquery.att_date,'dd-mm-yyyy') attendancedate,
				COALESCE((subquery.check_in_out_details->0->>'check_in_time'), '00:00') AS check_in_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_time', '00:00') AS check_out_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'attendance_type', '') AS attendance_type,
				CASE WHEN COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_time', '00:00') = '00:00' THEN 0 ELSE json_array_length(subquery.check_in_out_details) END AS check_in_out_count,
				CASE WHEN emp_cico.total_working_hours_calculation = 'first_last_check' THEN
					CASE WHEN json_array_length(subquery.check_in_out_details) > 1 AND subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					ELSE
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					END
				ELSE
					(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(subquery.check_in_out_details) AS trips(trip))
				END AS no_of_hours_worked,
				COALESCE((subquery.check_in_out_details->0->>'check_in_location'), '') AS check_in_location,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_location'), '') AS check_out_location,
				COALESCE((subquery.check_in_out_details->0->>'check_in_image_path'), '') AS check_in_image_path,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_image_path'), '') AS check_out_image_path,
				op.dateofjoining,
				NULLIF(tc.document_path,'https://api.contract-jobs.com/crm_api/') AS photopath,
				op.orgempcode, op.cjcode tpcode,
				coalesce(subquery.check_in_out_details,'[{}]') check_in_out_details,
				tma.is_overtime is_overtime_applicable, tma.no_of_overtime_hours_worked, tma.deviation_in_checkin, tma.deviation_in_checkout, tma.deviation_in_total_working_hours,
				COALESCE(emp_cico.shift_name, emp_cico.shift_name)||' ['||COALESCE(emp_cico.default_shift_time_from, emp_cico.default_shift_time_from)||'-'||COALESCE(emp_cico.default_shift_time_to, emp_cico.default_shift_time_to)||']'||CASE WHEN COALESCE(tma.is_auto_shift_assign, 'N')='Y' THEN '[Auto Shift]' ELSE '' END AS shift_name,
				COALESCE(emp_cico.is_night_shift, COALESCE(emp_cico.is_night_shift, 'N')) is_night_shift,
				COALESCE(emp_cico.break_total_time, emp_cico.break_total_time) break_total_time,
				COALESCE(emp_cico.break_pay_type, emp_cico.break_pay_type) break_pay_type,
				tma.is_auto_shift_assign is_auto_shift_assign,
				tma.attendance_policy_id attendance_policy_id, op.posting_department department,
				op.assigned_ou_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id IN (select regexp_split_to_table(COALESCE(NULLIF(op.assigned_ou_ids, ''), '0'),',')::int)) assigned_ou_ids_names,
				op.assigned_geofence_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id IN (select regexp_split_to_table(COALESCE(NULLIF(op.assigned_geofence_ids, ''), '0'),',')::int)) assigned_geofence_ids_names,
				COALESCE(tma.late_multiplier,'1') late_multiplier,
				COALESCE(tma.early_multiplier,'1') early_multiplier,
				COALESCE(tma.overtime_multiplier,'1') overtime_multiplier,
					(tma.deviation_in_checkin_time) deviation_in_checkin_time,
				(tma.deviation_in_checkout_time) deviation_in_checkout_time,
				(tma.deviation_in_working_hours_time) deviation_in_working_hours_time,
				usp_attnname_by_code(tma.att_catagory) att_catagory,
				COALESCE(tma.attendance_type,'') attendance_type_m
			FROM openappointments op
			LEFT JOIN t1 AS subquery on op.emp_code=subquery.emp_code
			LEFT JOIN tbl_candidate_documentlist tc ON op.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
			LEFT JOIN vw_user_spc_emp AS emp_cico ON emp_cico.emp_code::bigint = op.emp_code::bigint AND is_active='1'  and emp_cico.customeraccountid=p_customeraccountid
			LEFT JOIN tbl_monthly_attendance AS tma ON tma.emp_code::bigint = subquery.emp_code::bigint AND tma.isactive='1' AND tma.att_date=subquery.att_date
			LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and account_id= op.customeraccountid
			WHERE
				op.customeraccountid=p_customeraccountid AND COALESCE(op.converted, 'N') = 'Y' AND op.appointment_status_id IN (11,14)
				AND op.dateofjoining <= v_to_date::DATE AND (op.dateofrelieveing is null OR op.dateofrelieveing >= v_from_date::DATE)
				AND EXISTS
				(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
				)
				AND 
				(
					p_marked_type = 'All'
					OR (p_marked_type = 'Marked' and (subquery.emp_code IS NOT NULL OR tma.emp_code IS NOT NULL)) 
					OR (p_marked_type = 'Not Marked' and (subquery.emp_code IS NULL and tma.emp_code IS NULL)) 
				)
				AND op.jobtype = ANY (SELECT unnest(string_to_array(CASE WHEN p_report_type = 'Meeting' THEN 'Meeting' ELSE v_jobtypecode END, ',')))
				and op.emp_code IN (
						SELECT emp_code 
						FROM openappointments 
						WHERE reportingmanager_emp_code =p_empcode::bigint)
			ORDER BY subquery.emp_code ASC;
        RETURN v_result;
	----End	
  
	ELSIF p_action = 'GetAttendanceDetailByemployee' THEN
		OPEN v_result FOR
			-- SIDDHARTH BANSAL 24/04/2024
			SELECT
                'CheckInCheckOut' table_ref,
				subquery.emp_code::text, subquery.emp_name, subquery.designation,
				TO_CHAR(subquery.attendancedate,'dd-mm-yyyy') attendancedate,
				COALESCE((subquery.check_in_out_details->0->>'check_in_time'), '00:00') AS check_in_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_time', '00:00') AS check_out_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'attendance_type', '') AS attendance_type,
				CASE WHEN COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_time', '00:00') = '00:00' THEN 0 ELSE json_array_length(subquery.check_in_out_details) END AS check_in_out_count,
				CASE WHEN emp_cico.total_working_hours_calculation = 'after_shift_start_timing' THEN
					CASE WHEN json_array_length(subquery.check_in_out_details) > 1 AND subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
						'00:00:00'
						-- LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - GREATEST((subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp, ((subquery.attendancedate + COALESCE(NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::interval)::TIMESTAMP - INTERVAL '5 HOURS 30 MINUTES')))) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - GREATEST((subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp, ((subquery.attendancedate + COALESCE(NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::interval)::TIMESTAMP - INTERVAL '5 HOURS 30 MINUTES')))) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - GREATEST((subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp, ((subquery.attendancedate + COALESCE(NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::interval)::TIMESTAMP - INTERVAL '5 HOURS 30 MINUTES')))) % 60))::TEXT, 2, '0')
					ELSE
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - GREATEST((subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp, ((subquery.attendancedate + COALESCE(NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::interval)::TIMESTAMP - INTERVAL '5 HOURS 30 MINUTES')))) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - GREATEST((subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp, ((subquery.attendancedate + COALESCE(NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::interval)::TIMESTAMP - INTERVAL '5 HOURS 30 MINUTES')))) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - GREATEST((subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp, ((subquery.attendancedate + COALESCE(NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::interval)::TIMESTAMP - INTERVAL '5 HOURS 30 MINUTES')))) % 60))::TEXT, 2, '0')
					END
				WHEN emp_cico.total_working_hours_calculation = 'first_last_check' THEN
					CASE WHEN json_array_length(subquery.check_in_out_details) > 1 AND subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					ELSE
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					END
				WHEN emp_cico.total_working_hours_calculation = 'first_last_mark_time' THEN
					LPAD(FLOOR(EXTRACT(EPOCH FROM (COALESCE(NULLIF(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time', ''), subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_in_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (COALESCE(NULLIF(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time', ''), subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_in_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (COALESCE(NULLIF(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time', ''), subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_in_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
				ELSE
					(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(subquery.check_in_out_details) AS trips(trip))
				END AS no_of_hours_worked,
				COALESCE((subquery.check_in_out_details->0->>'check_in_location'), '') AS check_in_location,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_location'), '') AS check_out_location,
				COALESCE((subquery.check_in_out_details->0->>'check_in_image_path'), '') AS check_in_image_path,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_image_path'), '') AS check_out_image_path,
				subquery.dateofjoining,
				NULLIF(tc.document_path,'https://api.contract-jobs.com/crm_api/') AS photopath,
				subquery.orgempcode, subquery.tpcode,
				CASE WHEN COALESCE(subquery.geofencingid, 0)<>'0' THEN 'Y' ELSE 'N' END is_eligable_for_geofencing, COALESCE(tougf.isenablegeofencing, 'N') isenablegeofencing,
				COALESCE(subquery.geofencingid,'0') geofencingid, COALESCE(tougf.org_unit_name,'') org_unit_name, COALESCE(tougf.geo_link,'') geo_link,
				COALESCE(tougf.geo_longitude,'0') geo_longitude, COALESCE(tougf.geo_latitude,'0') geo_latitude, COALESCE(tougf.geo_radius,'0') geo_radius,
				subquery.check_in_out_details,
				tma.is_overtime is_overtime_applicable, TO_CHAR(tma.no_of_overtime_hours_worked::INTERVAL, 'HH24:MI') no_of_overtime_hours_worked,
				tma.deviation_in_checkin, tma.deviation_in_checkout, tma.deviation_in_total_working_hours,
				COALESCE(subquery.shift_name, emp_cico.shift_name)||' ['||COALESCE(subquery.default_shift_time_from, emp_cico.default_shift_time_from)||'-'||COALESCE(subquery.default_shift_time_to, emp_cico.default_shift_time_to)||']'||CASE WHEN COALESCE(subquery.is_auto_shift_assign, 'N')='Y' THEN '[Auto Shift]' ELSE '' END AS shift_name,
				COALESCE(subquery.is_night_shift, COALESCE(emp_cico.is_night_shift, 'N')) is_night_shift,
                COALESCE(subquery.break_total_time, emp_cico.break_total_time) break_total_time,
                COALESCE(subquery.break_pay_type, emp_cico.break_pay_type) break_pay_type,
                subquery.is_auto_shift_assign is_auto_shift_assign,
                subquery.attendance_policy_id attendance_policy_id, subquery.department,
				subquery.assigned_ou_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id IN (select regexp_split_to_table(COALESCE(NULLIF(subquery.assigned_ou_ids, ''), '0'),',')::int)) assigned_ou_ids_names,
				-- START - Changes [3.8]
				TO_CHAR(CAST(NULLIF(tma.latehours, '') AS INTERVAL), 'HH24:MI') late_check_in_time, tma.latehoursdeduction late_check_in_amount,
				TO_CHAR(CAST(NULLIF(tma.earlyhours, '') AS INTERVAL), 'HH24:MI') early_check_out_time, tma.earlyhoursdeduction early_check_out_amount,
				-- END - Changes [3.8]
				TO_CHAR(CAST(NULLIF(tma.overtime_hours_approved_by_employer, '') AS INTERVAL), 'HH24:MI') overtime_hours_approved_by_employer, tma.overtime_amount_approved_by_employer overtime_amount_approved_by_employer, -- END - Changes [3.9]
				subquery.assigned_geofence_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id IN (select regexp_split_to_table(COALESCE(NULLIF(subquery.assigned_geofence_ids, ''), '0'),',')::int)) assigned_geofence_ids_names
				,tma.attendance_type as atttype
				,left(tma.firstcheckintime,5) firstcheckintime
				,left(tma.lastcheckouttime,5) lastcheckouttime,
				COALESCE(tma.late_multiplier,'1') late_multiplier,
				COALESCE(tma.early_multiplier,'1') early_multiplier,
				COALESCE(tma.overtime_multiplier,'1') overtime_multiplier,
				(tma.deviation_in_checkin_time) deviation_in_checkin_time,
				(tma.deviation_in_checkout_time) deviation_in_checkout_time,
				(tma.deviation_in_working_hours_time) deviation_in_working_hours_time,
				usp_attnname_by_code(tma.att_catagory) att_catagory,
				COALESCE(tma.attendance_type,'') attendance_type_m,
				tma.id as monthlyattendanceid
			FROM
			(
				SELECT
					op.emp_code, op.emp_name, op.emp_id, 
					-- op.post_offered
					COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered)	designation, COALESCE(op.geofencingid, 0) geofencingid, op.customeraccountid, op.jobtype,
					TO_CHAR(nullif(op.dateofjoining,'0001-01-01 BC'),'dd/mm/yyyy') dateofjoining, t.att_date AS attendancedate, op.orgempcode, op.cjcode tpcode,
					json_agg
					(
						json_build_object
						(
							'row_id', t.id::TEXT,
							'att_date', TO_CHAR(t.att_date,'dd-mm-yyyy'),
							'actual_check_in_time', t.check_in_time, 
							'actual_check_out_time', t.check_out_time, 
							'check_in_time', COALESCE(to_char(t.check_in_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','DD/MM/YYYY HH24:mi:ss'),'00:00'), 
							'check_out_time', COALESCE(to_char(t.check_out_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','DD/MM/YYYY HH24:mi:ss'),'00:00'), 
							-- 'no_of_hours_worked', COALESCE(to_char(date_trunc('minute',t.check_out_time) - date_trunc('minute',t.check_in_time),'hh24:mi'),'00:00'), 
							'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0'),
							'check_in_location', COALESCE(t.check_in_location,''), 
							'check_out_location', COALESCE(t.check_out_location,''), 
							'check_in_image_path', COALESCE(t.check_in_image_path,''), 
							'check_out_image_path', COALESCE(t.check_out_image_path,''),
							'attendance_type', COALESCE(t.attendance_type,''),
							'meeting_name', COALESCE(t.meeting_name,''),
							'meeting_feedback', COALESCE(t.meeting_feedback,''),
							'meeting_remarks', COALESCE(t.meeting_remarks,''),
							'check_in_geofence_id', COALESCE(t.check_in_geofence_id::TEXT, ''),
							'check_in_geofence_id_name', COALESCE((SELECT org_unit_name FROM tbl_org_unit_geofencing WHERE id = t.check_in_geofence_id)::TEXT, ''),
							'check_out_geofence_id', COALESCE(t.check_out_geofence_id::TEXT,''),
							'check_out_geofence_id_name', COALESCE((SELECT org_unit_name FROM tbl_org_unit_geofencing WHERE id = t.check_in_geofence_id)::TEXT, ''),
								-- START - Changes [4.5]
							'check_in_latitude', COALESCE(t.check_in_latitude,'0'),
							'check_in_longitude', COALESCE(t.check_in_longitude,'0'),
							'check_out_latitude', COALESCE(t.check_out_latitude,'0'),
							'check_out_longitude', COALESCE(t.check_out_longitude,'0')
							-- END - Changes [4.5]
						) ORDER BY t.id ASC
					) AS check_in_out_details,
                    COALESCE(tma_sub.is_auto_shift_assign,'') is_auto_shift_assign,
                    COALESCE(tma_sub.attendance_policy_id::TEXT,'') attendance_policy_id,
                    COALESCE(vw_sluw.shift_name,'') shift_name,
                    COALESCE(vw_sluw.default_shift_time_from,'') default_shift_time_from,
                    COALESCE(vw_sluw.default_shift_time_to,'') default_shift_time_to,
                    COALESCE(vw_sluw.is_night_shift,'') is_night_shift,
                    COALESCE(vw_sluw.break_total_time,'') break_total_time,
                    COALESCE(vw_sluw.break_pay_type,'') break_pay_type,
					op.assigned_ou_ids, SPLIT_PART(op.posting_department, '#', 1) department,
					op.assigned_geofence_ids
				FROM openappointments op
				LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and account_id= op.customeraccountid
				LEFT JOIN tbl_attendance t ON t.emp_code=op.emp_code AND t.att_date BETWEEN v_from_date::DATE AND v_to_date::DATE AND t.isactive='1'
					AND COALESCE(t.jobtype, '') = COALESCE(NULLIF(p_report_type, ''), COALESCE(t.jobtype, ''))
					AND UPPER(COALESCE(t.attendance_type, '')) = CASE WHEN UPPER(p_attendance_type) = 'ALL' THEN UPPER(COALESCE(t.attendance_type, '')) ELSE UPPER(p_attendance_type) END
			    LEFT JOIN tbl_monthly_attendance tma_sub ON tma_sub.emp_code::bigint = op.emp_code::bigint AND tma_sub.isactive='1' AND tma_sub.att_date=t.att_date
			    LEFT JOIN vw_shift_list_user_wise AS vw_sluw ON vw_sluw.attendance_policy_id = tma_sub.attendance_policy_id
				WHERE
					op.emp_code=p_empcode AND op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id IN (11,14)
                    AND EXISTS
                    (
                        SELECT 1
                        FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
                        WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
                    )
					-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
				GROUP BY
					op.emp_code, op.emp_name, t.att_date, op.emp_id, 
					-- op.post_offered,
					COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered),	op.geofencingid, op.customeraccountid, op.jobtype,
                    tma_sub.is_auto_shift_assign, tma_sub.attendance_policy_id, vw_sluw.shift_name, vw_sluw.default_shift_time_from, vw_sluw.default_shift_time_to, vw_sluw.is_night_shift, vw_sluw.break_total_time, vw_sluw.break_pay_type,
					op.assigned_ou_ids, op.posting_department, op.assigned_geofence_ids
			) AS subquery
			LEFT JOIN tbl_candidate_documentlist tc ON subquery.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
			LEFT JOIN tbl_org_unit_geofencing tougf ON tougf.isactive='1' AND subquery.customeraccountid=tougf.customeraccountid AND subquery.geofencingid=tougf.id
			LEFT JOIN tbl_monthly_attendance AS tma ON tma.emp_code::bigint = subquery.emp_code::bigint AND tma.isactive='1' AND tma.att_date=subquery.attendancedate
			LEFT JOIN vw_shifts_emp_wise AS emp_cico ON emp_cico.emp_code::bigint = subquery.emp_code::bigint AND is_active='1' AND tma.shift_id = emp_cico.shift_id
			WHERE subquery.attendancedate is not null AND subquery.jobtype = ANY (SELECT unnest(string_to_array(CASE WHEN p_report_type = 'Meeting' THEN 'Meeting' ELSE v_jobtypecode END, ',')))
			ORDER BY subquery.attendancedate DESC;
			-- END
		RETURN v_result;
	ELSIF p_action = 'GetCheckInOuteDetailReportByemployee' THEN
		OPEN v_result FOR
			-- SIDDHARTH BANSAL 24/04/2024
			SELECT
                'CheckInCheckOut' table_ref,
				subquery.emp_code::text, subquery.emp_name, subquery.designation, TO_CHAR(subquery.attendancedate,'dd-mm-yyyy') attendancedate,
				COALESCE((subquery.check_in_out_details->0->>'check_in_time'), '00:00') AS check_in_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_time', '00:00') AS check_out_time,
				COALESCE(subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'attendance_type', '') AS attendance_type,
				CASE WHEN emp_cico.total_working_hours_calculation = 'first_last_check' THEN
					CASE WHEN json_array_length(subquery.check_in_out_details) > 1 AND subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					ELSE
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (subquery.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					END
				ELSE
					(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(subquery.check_in_out_details) AS trips(trip))
				END AS no_of_hours_worked,
				COALESCE((subquery.check_in_out_details->0->>'check_in_location'), '') AS check_in_location,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_location'), '') AS check_out_location,
				COALESCE((subquery.check_in_out_details->0->>'check_in_image_path'), '') AS check_in_image_path,
				COALESCE((subquery.check_in_out_details->(json_array_length(subquery.check_in_out_details) - 1)->>'check_out_image_path'), '') AS check_out_image_path,
				subquery.dateofjoining,
				NULLIF(tc.document_path,'https://api.contract-jobs.com/crm_api/') AS photopath,
				subquery.orgempcode, subquery.tpcode,
				subquery.check_in_out_details attendance_report_details
			FROM
			(
				SELECT
					op.emp_code, op.emp_name, op.emp_id, COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered)
					designation, op.geofencingid, op.customeraccountid, op.jobtype,
					TO_CHAR(nullif(op.dateofjoining,'0001-01-01 BC'),'dd/mm/yyyy') dateofjoining, att_date AS attendancedate, op.orgempcode, op.cjcode tpcode,
					json_agg
					(
						json_build_object
						(
							'att_date', TO_CHAR(att_date,'dd-mm-yyyy'), 
							'actual_check_in_time', t.check_in_time, 
							'actual_check_out_time', t.check_out_time, 
							'check_in_time', COALESCE(to_char(t.check_in_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
							'check_out_time', COALESCE(to_char(t.check_out_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
							-- 'no_of_hours_worked', COALESCE(to_char(date_trunc('minute',t.check_out_time) - date_trunc('minute',t.check_in_time),'hh24:mi'),'00:00'), 
							'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0'),
							'check_in_location', COALESCE(t.check_in_location,''), 
							'check_out_location', COALESCE(t.check_out_location,''), 
							'check_in_image_path', COALESCE(t.check_in_image_path,''), 
							'check_out_image_path', COALESCE(t.check_out_image_path,''),
							'attendance_type', COALESCE(t.attendance_type,''),
							'meeting_name', COALESCE(t.meeting_name,''),
							'meeting_feedback', COALESCE(t.meeting_feedback,''),
							'meeting_remarks', COALESCE(t.meeting_remarks,''),
							-- START - Changes [4.5]
							'check_in_latitude', COALESCE(t.check_in_latitude,'0'),
							'check_in_longitude', COALESCE(t.check_in_longitude,'0'),
							'check_out_latitude', COALESCE(t.check_out_latitude,'0'),
							'check_out_longitude', COALESCE(t.check_out_longitude,'0')
							-- END - Changes [4.5]
						) ORDER BY t.id ASC
					) AS check_in_out_details
				FROM openappointments op
				LEFT JOIN tbl_attendance t ON t.emp_code=op.emp_code AND att_date BETWEEN v_from_date::DATE AND v_to_date::DATE AND t.isactive='1'
				LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and account_id= op.customeraccountid
					AND COALESCE(t.jobtype, '') = COALESCE(NULLIF(p_report_type, ''), COALESCE(t.jobtype, ''))
				    AND UPPER(COALESCE(t.attendance_type, '')) = CASE WHEN UPPER(p_attendance_type) = 'ALL' THEN UPPER(COALESCE(t.attendance_type, '')) ELSE UPPER(p_attendance_type) END
				WHERE
					op.emp_code=p_empcode AND op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id IN (11,14)
                    AND EXISTS
                    (
                        SELECT 1
                        FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
                        WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
                    )
					-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
				GROUP BY op.emp_code, op.emp_name, att_date, op.emp_id
				-- , op.post_offered 
				, COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered)
				, op.geofencingid, op.customeraccountid, op.jobtype
			) AS subquery
			LEFT JOIN tbl_candidate_documentlist tc ON subquery.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
			LEFT JOIN tbl_org_unit_geofencing tougf ON tougf.isactive='1' AND subquery.customeraccountid=tougf.customeraccountid AND subquery.geofencingid=tougf.id
			LEFT JOIN vw_user_spc_emp AS emp_cico ON emp_cico.emp_code::bigint = subquery.emp_code::bigint AND is_active='1'
			WHERE subquery.attendancedate is not null AND subquery.jobtype = ANY (SELECT unnest(string_to_array(CASE WHEN p_report_type = 'Meeting' THEN 'Meeting' ELSE v_jobtypecode END, ',')))
			ORDER BY subquery.attendancedate DESC;
			-- END
		RETURN v_result;
	ELSIF p_action = 'GetAttendanceDetailReportByemployee' THEN
		OPEN v_result FOR
            SELECT
                'Attendance' table_ref,
                oa.emp_code::text, oa.emp_name,
				-- oa.post_offered 
				COALESCE(NULLIF(mtd_designation.designationname, ''), oa.post_offered) 	designation, TO_CHAR(tma.att_date,'dd-mm-yyyy') attendancedate,
                COALESCE(NULLIF(firstcheckintime, ''), '00:00') AS check_in_time,
                COALESCE(NULLIF(lastcheckouttime, ''), '00:00') AS check_out_time,
				CASE
					WHEN tma.attendance_type = 'AA' THEN 'Absent'
					WHEN tma.attendance_type = 'PP' THEN 'Present'
					WHEN tma.attendance_type = 'HD' THEN 'Half day'
					WHEN tma.attendance_type = 'HO' THEN 'Holiday'
					WHEN tma.attendance_type = 'LL' THEN 'Leave'
					WHEN tma.attendance_type = 'WO' THEN 'Weekly Off'
					WHEN tma.attendance_type = 'OD' THEN 'On Duty'
					WHEN tma.attendance_type = 'WFH' THEN 'Work From Home'
					WHEN tma.attendance_type = 'MP' THEN 'Missed Punched'
                    ELSE tma.attendance_type
                END AS attendance_type,
                -- tma.attendance_type AS attendance_type,
                COALESCE(NULLIF(no_of_hours_worked, ''), '00:00') no_of_hours_worked,
                '' AS check_in_location, '' AS check_out_location, '' AS check_in_image_path, '' AS check_out_image_path,
                TO_CHAR(nullif(oa.dateofjoining,'0001-01-01 BC'), 'dd/mm/yyyy') dateofjoining,
                '' AS photopath,
                oa.orgempcode, oa.cjcode tpcode,
                ('[{"att_date": "' || TO_CHAR(tma.att_date, 'dd-mm-yyyy') || '","actual_check_in_time": "","actual_check_out_time": "","check_in_time": "00:00","check_out_time": "00:00","no_of_hours_worked": "00:00","check_in_location": "","check_out_location": "","check_in_image_path": "","check_out_image_path": "","attendance_type": "Business","meeting_name": "","meeting_feedback": "","meeting_remarks": "","check_in_latitude": "0","check_in_longitude": "0","check_out_latitude": "0","check_out_longitude": "0"}]')::JSON attendance_report_details
            FROM tbl_monthly_attendance tma
            INNER JOIN openappointments oa ON oa.emp_code = tma.emp_code
			LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = oa.designation_id and account_id= oa.customeraccountid
            WHERE
                tma.att_date BETWEEN v_from_date::DATE AND v_to_date::DATE AND tma.isactive='1' AND oa.emp_code = p_empcode AND
                oa.customeraccountid = p_customeraccountid AND oa.converted='Y' AND oa.appointment_status_id IN (11,14)
			ORDER BY attendancedate DESC;
		RETURN v_result;
	ELSIF p_action = 'GetEmployeeTodayAttendance' THEN
		-- START - Night Shift Changes [4.0]
			IF EXISTS (SELECT * FROM vw_user_spc_emp WHERE emp_code = p_empcode AND is_active = '1' AND is_night_shift = 'Y') THEN --AND customeraccountid = 5852
				SELECT COALESCE(auto_shift_rotation_yn, 'Y')
				INTO v_auto_shift_rotation 
				FROM tbl_employee_auto_rotation
				WHERE account_id = p_customeraccountid AND emp_code = p_empcode AND status = '1';
				v_auto_shift_rotation := COALESCE(v_auto_shift_rotation, 'Y');
				IF v_auto_shift_rotation = 'N' THEN
					SELECT shift_id INTO v_shift_id
					FROM tbl_employee_shift_roster
					WHERE account_id = p_customeraccountid AND emp_code::BIGINT = p_empcode  AND status = '1' AND roster_date = v_att_date;
				END IF;
				
				IF v_shift_id IS NOT NULL THEN
					SELECT * FROM vw_shifts WHERE shift_id::bigint = v_shift_id AND is_active = '1' LIMIT 1 INTO v_user_specific_setting;
				ELSE
					SELECT * FROM vw_user_spc_emp WHERE emp_code::bigint = p_empcode AND is_active='1' AND is_night_shift = 'Y' INTO v_user_specific_setting;
				END IF;
				-- START - Shift Timing & Margin
				v_shift_start_timing := ((v_att_date - INTERVAL '1 DAY') + v_user_specific_setting.default_shift_time_from::time)::timestamp ;
				v_shift_end_timing := (v_att_date + v_user_specific_setting.default_shift_time_to::time)::timestamp;
				v_shift_start_timing_mobile := ((v_att_date - INTERVAL '1 DAY') + v_user_specific_setting.default_shift_time_from::time)::timestamp;
				v_shift_duration := (
						SELECT
							LPAD(FLOOR(total_seconds / 3600)::text, 2, '0') || ':' ||
							LPAD(FLOOR((total_seconds % 3600) / 60)::text, 2, '0') || ':' ||
							LPAD(FLOOR(total_seconds % 60)::text, 2, '0')
						FROM (
							SELECT EXTRACT(
								EPOCH FROM (
									(
										(CURRENT_DATE + COALESCE(NULLIF(v_user_specific_setting.default_shift_time_to, ''), '00:00:00')::time)
										+ CASE WHEN COALESCE(NULLIF(v_user_specific_setting.is_night_shift, ''), 'N') = 'Y' THEN INTERVAL '1 DAY' ELSE INTERVAL '0 DAY' END
										+ CASE WHEN COALESCE(NULLIF(v_user_specific_setting.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_to, ''), '00:00:00')::interval ELSE INTERVAL '0' END
									)
									-
									(
										(CURRENT_DATE + COALESCE(NULLIF(v_user_specific_setting.default_shift_time_from, ''), '00:00:00')::time)
										- CASE WHEN COALESCE(NULLIF(v_user_specific_setting.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_from, ''), '00:00:00')::interval ELSE INTERVAL '0' END
									)
								)
							) AS total_seconds
						) s
					);
					RAISE NOTICE 'Shift :: % - %', v_shift_start_timing, v_shift_end_timing;
					RAISE NOTICE 'v_shift_duration :: %', v_shift_duration;

				IF COALESCE(NULLIF(v_user_specific_setting.shift_margin, ''), 'N') = 'Y' THEN
					SELECT
						CASE
							WHEN (CURRENT_TIMESTAMP + INTERVAL '5 HOURS 30 MINUTES') BETWEEN (v_shift_start_timing - COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_from, ''), '00:00:00')::interval) AND (v_shift_end_timing + COALESCE(NULLIF(v_user_specific_setting.shift_margin_hours_to, ''), '00:00:00')::interval) THEN 'Y'
							ELSE 'N'
						END
					INTO v_is_time_exists_between_assigned_att_policy;
				ELSE
					SELECT
						CASE
							WHEN (CURRENT_TIMESTAMP + INTERVAL '5 HOURS 30 MINUTES') BETWEEN v_shift_start_timing AND v_shift_end_timing THEN 'Y'
							ELSE 'N'
						END
					INTO v_is_time_exists_between_assigned_att_policy;
				END IF;
				-- END - Shift Timing & Margin
				
				IF v_is_time_exists_between_assigned_att_policy = 'Y' THEN
					v_att_date := v_att_date - INTERVAL '1 DAY';
				END IF;
			END IF;
		-- END - Night Shift Changes [4.0]

		IF p_customeraccountid IN (8801, 4370, 3088) THEN
			OPEN v_result FOR
				SELECT
					'CheckInCheckOut' table_ref,
					op.emp_code::text,op.emp_name,op.post_offered designation,
					COALESCE((check_in_out_detailssss.check_in_out_details->0->>'att_date'), '00:00') AS attendancedate,
					COALESCE((check_in_out_detailssss.check_in_out_details->0->>'check_in_time'), '00:00') AS check_in_time,
					COALESCE(check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'check_out_time', '00:00') AS check_out_time,
					COALESCE(check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'attendance_type', '') AS attendance_type,
					-- (SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(check_in_out_detailssss.check_in_out_details) AS trips(trip)) AS no_of_hours_worked,
					CASE WHEN emp_cico.total_working_hours_calculation = 'first_last_check' THEN
						CASE WHEN json_array_length(check_in_out_detailssss.check_in_out_details) > 1 AND check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
							LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
						ELSE
							LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
						END
					ELSE
						(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(check_in_out_detailssss.check_in_out_details) AS trips(trip))
					END AS no_of_hours_worked,
					COALESCE((check_in_out_detailssss.check_in_out_details->0->>'check_in_location'), '') AS check_in_location,
					COALESCE((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'check_out_location'), '') AS check_out_location,
					COALESCE((check_in_out_detailssss.check_in_out_details->0->>'check_in_image_path'), '') AS check_in_image_path,
					COALESCE((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'check_out_image_path'), '') AS check_out_image_path,
					TO_CHAR(nullif(op.dateofjoining,'0001-01-01 BC'),'dd/mm/yyyy') dateofjoining,
					NULLIF(tc.document_path,'https://api.contract-jobs.com/crm_api/') AS photopath,
					-- CASE WHEN COALESCE(op.geofencingid, 0)<>'0' THEN 'Y' ELSE 'N' END is_eligable_for_geofencing,
					CASE WHEN COALESCE(NULLIF(op.assigned_geofence_ids, ''), NULLIF(op.geofencingid::TEXT, '0'))<>'0' THEN 'Y' ELSE 'N' END is_eligable_for_geofencing,
					CASE WHEN COALESCE(NULLIF(op.assigned_geofence_ids, ''), NULLIF(op.geofencingid::TEXT, '0'))<>'0' THEN 'Y' ELSE 'N' END isenablegeofencing,
					-- COALESCE(tougf.isenablegeofencing, 'N') isenablegeofencing,
					COALESCE(op.geofencingid,'0') geofencingid, COALESCE(tougf.org_unit_name,'') org_unit_name, COALESCE(tougf.geo_link,'') geo_link,
					COALESCE(tougf.geo_longitude,'0') geo_longitude, COALESCE(tougf.geo_latitude,'0') geo_latitude, 
					CASE WHEN emp_cico.is_mobile_check_in_check_out = 'N' THEN '-1' ELSE COALESCE(tougf.geo_radius,'0') END geo_radius,
					check_in_out_detailssss.*,
					ou_geofenc_data.*,
					COALESCE(emp_cico.is_night_shift, 'N') is_night_shift,
					-- START - Dynamic shift_duration based on check-in time [4.7]
					COALESCE(v_shift_start_timing::text, '') AS shift_start_timing,
					COALESCE(v_shift_start_timing::text, '') AS shift_start_timing_mobile,
					COALESCE(
						NULLIF(v_shift_duration::TEXT, ''),
						(
						SELECT
							LPAD(FLOOR(total_seconds / 3600)::text, 2, '0') || ':' ||
							LPAD(FLOOR((total_seconds % 3600) / 60)::text, 2, '0') || ':' ||
							LPAD(FLOOR(total_seconds % 60)::text, 2, '0')
						FROM (
							SELECT EXTRACT(
								EPOCH FROM (
									(
										(CURRENT_DATE + COALESCE(NULLIF(matched_shift.default_shift_time_to, ''), NULLIF(emp_cico.default_shift_time_to, ''), '00:00:00')::time)
										+ CASE WHEN COALESCE(NULLIF(matched_shift.is_night_shift, ''), NULLIF(emp_cico.is_night_shift, ''), 'N') = 'Y' THEN INTERVAL '1 DAY' ELSE INTERVAL '0 DAY' END
										+ CASE WHEN COALESCE(NULLIF(matched_shift.shift_margin, ''), NULLIF(emp_cico.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(matched_shift.shift_margin_hours_to, ''), NULLIF(emp_cico.shift_margin_hours_to, ''), '00:00:00')::interval ELSE INTERVAL '0' END
									)
									-
									(
										(CURRENT_DATE + COALESCE(NULLIF(matched_shift.default_shift_time_from, ''), NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::time)
										- CASE WHEN COALESCE(NULLIF(matched_shift.shift_margin, ''), NULLIF(emp_cico.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(matched_shift.shift_margin_hours_from, ''), NULLIF(emp_cico.shift_margin_hours_from, ''), '00:00:00')::interval ELSE INTERVAL '0' END
									)
								)
							) AS total_seconds
						) s
					)) AS shift_duration,
					COALESCE(NULLIF(v_shift_id, 0), NULLIF(matched_shift.shift_id, 0), NULLIF(emp_cico.shift_id, 0), 0) shift_id
					-- END - Dynamic shift_duration based on check-in time [4.7]
				FROM openappointments op
				LEFT JOIN tbl_candidate_documentlist tc on op.emp_id=tc.candidate_id and tc.document_id=17 and tc.active='Y'
				LEFT JOIN
				(
					SELECT json_agg(trips) ou_geofenc_details
					FROM
					(
						SELECT
							json_build_object
							(
								'geofencingid', COALESCE(id::TEXT, ''),
								'org_unit_name', COALESCE(org_unit_name::TEXT, ''),
								'geo_link', COALESCE(geo_link::TEXT, ''),
								'geo_longitude', COALESCE(geo_longitude::TEXT, ''),
								'geo_latitude', COALESCE(geo_latitude::TEXT, ''),
								'geo_radius', COALESCE(geo_radius::TEXT, '')
							) AS trips
						FROM openappointments op
						INNER JOIN tbl_org_unit_geofencing tougf ON tougf.isactive='1' AND tougf.customeraccountid = p_customeraccountid AND tougf.geo_longitude <> '0' AND tougf.geo_latitude <> '0' AND tougf.id IN (SELECT cast(regexp_split_to_table(COALESCE(NULLIF(op.assigned_geofence_ids, ''), NULLIF(op.geofencingid::TEXT, '0')), ',') as int))
						WHERE op.emp_code=p_empcode AND op.customeraccountid = p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in (11,14)
						GROUP BY tougf.id
						ORDER BY tougf.id ASC
					) ou_geofenc_details
				) ou_geofenc_data ON TRUE
				LEFT JOIN tbl_org_unit_geofencing tougf ON tougf.isactive='1' AND op.customeraccountid=tougf.customeraccountid AND op.geofencingid=tougf.id
				LEFT JOIN vw_user_spc_emp AS emp_cico ON emp_cico.emp_code::bigint = op.emp_code::bigint AND emp_cico.is_active='1'
				-- START - LATERAL JOIN to match shift based on check-in time [4.7]
				LEFT JOIN LATERAL (
					SELECT 
						vw_sew.shift_id, vw_sew.default_shift_time_from, vw_sew.default_shift_time_to, vw_sew.is_night_shift,
						vw_sew.shift_margin, vw_sew.shift_margin_hours_from, vw_sew.shift_margin_hours_to
					FROM (
						SELECT check_in_time::TIMESTAMP AS v_first_check_in_time
						FROM tbl_attendance
						WHERE emp_code = op.emp_code AND att_date = v_att_date AND isactive = '1'
						ORDER BY id ASC LIMIT 1
					) first_checkin
					CROSS JOIN LATERAL (
						SELECT
							shift_id, default_shift_time_from, default_shift_time_to, is_night_shift,
							shift_margin, shift_margin_hours_from, shift_margin_hours_to,
							(v_att_date + default_shift_time_from::interval)::timestamp - COALESCE(NULLIF(shift_margin_hours_from, ''), '00:00:00')::interval AS shift_start_timing,
							((v_att_date + default_shift_time_to::interval)::timestamp + CASE WHEN is_night_shift = 'Y' THEN INTERVAL '1 DAY' ELSE INTERVAL '0 DAY' END)::timestamp AS shift_end_timing,
							COALESCE(first_checkin.v_first_check_in_time + INTERVAL '5 hours 30 minutes', CURRENT_TIMESTAMP + INTERVAL '5 hours 30 minutes') AS in_time
						FROM vw_shifts_emp_wise
						WHERE is_active = '1' AND emp_code::bigint = op.emp_code
					) vw_sew
					WHERE vw_sew.in_time BETWEEN vw_sew.shift_start_timing AND vw_sew.shift_end_timing 
					ORDER BY (vw_sew.in_time - vw_sew.shift_start_timing) ASC 
					LIMIT 1
				) matched_shift ON TRUE
				-- END - LATERAL JOIN to match shift based on check-in time [4.7]
				LEFT JOIN
				(
					SELECT json_agg(trips) check_in_out_details
					FROM
					(
						SELECT
							json_build_object
							(
								'event_id', COALESCE(t.id::TEXT, ''),
								'att_date', TO_CHAR(COALESCE(t.att_date::DATE, v_att_date), 'dd-mm-yyyy'),
								'actual_check_in_time', t.check_in_time, 
								'actual_check_out_time', t.check_out_time, 
								'check_in_time', COALESCE(TO_CHAR(t.check_in_time at time zone 'utc'  at time zone 'Asia/Kolkata','HH24:mi'),'00:00'), 
								'check_out_time', COALESCE(TO_CHAR(t.check_out_time at time zone 'utc'  at time zone 'Asia/Kolkata','HH24:mi'),'00:00'), 
								-- 'no_of_hours_worked', COALESCE(TO_CHAR(date_trunc('minute',t.check_out_time) - date_trunc('minute',t.check_in_time),'hh24:mi'),'00:00'), 
								'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0'),
								'check_in_location', COALESCE(t.check_in_location,''), 
								'check_out_location', COALESCE(t.check_out_location,''), 
								'check_in_image_path', COALESCE(t.check_in_image_path,''), 
								'check_out_image_path', COALESCE(t.check_out_image_path,''),
								'attendance_type', COALESCE(t.attendance_type,'')
							) AS trips
						FROM openappointments op
						LEFT JOIN tbl_attendance t ON t.emp_code=op.emp_code AND att_date = v_att_date AND t.isactive='1'
						LEFT JOIN tbl_candidate_documentlist tc ON op.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
						WHERE op.emp_code = p_empcode AND op.customeraccountid = p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in (11,14)
						GROUP BY t.id
						ORDER BY t.id ASC
					) check_in_out_details
				) check_in_out_detailssss ON TRUE
				WHERE op.emp_code = p_empcode AND op.customeraccountid = p_customeraccountid AND op.converted='Y' AND op.appointment_status_id IN (11,14);
			RETURN v_result;
		ELSE
		OPEN v_result FOR
			SELECT
                'CheckInCheckOut' table_ref,COALESCE(v_shift_start_timing::text, '') AS shift_start_timing,COALESCE(v_shift_start_timing::text, '') AS shift_start_timing_mobile,
				op.emp_code::text,op.emp_name,op.post_offered designation,
				COALESCE((check_in_out_detailssss.check_in_out_details->0->>'att_date'), '00:00') AS attendancedate,
				COALESCE((check_in_out_detailssss.check_in_out_details->0->>'check_in_time'), '00:00') AS check_in_time,
				COALESCE(check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'check_out_time', '00:00') AS check_out_time,
				COALESCE(check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'attendance_type', '') AS attendance_type,
				-- (SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(check_in_out_detailssss.check_in_out_details) AS trips(trip)) AS no_of_hours_worked,
				CASE WHEN emp_cico.total_working_hours_calculation = 'first_last_check' THEN
					CASE WHEN json_array_length(check_in_out_detailssss.check_in_out_details) > 1 AND check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					ELSE
						LPAD(FLOOR(EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (check_in_out_detailssss.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
					END
				ELSE
					(SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(check_in_out_detailssss.check_in_out_details) AS trips(trip))
				END AS no_of_hours_worked,
				COALESCE((check_in_out_detailssss.check_in_out_details->0->>'check_in_location'), '') AS check_in_location,
				COALESCE((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'check_out_location'), '') AS check_out_location,
				COALESCE((check_in_out_detailssss.check_in_out_details->0->>'check_in_image_path'), '') AS check_in_image_path,
				COALESCE((check_in_out_detailssss.check_in_out_details->(json_array_length(check_in_out_detailssss.check_in_out_details) - 1)->>'check_out_image_path'), '') AS check_out_image_path,
				TO_CHAR(nullif(op.dateofjoining,'0001-01-01 BC'),'dd/mm/yyyy') dateofjoining,
				NULLIF(tc.document_path,'https://api.contract-jobs.com/crm_api/') AS photopath,
                -- CASE WHEN COALESCE(op.geofencingid, 0)<>'0' THEN 'Y' ELSE 'N' END is_eligable_for_geofencing,
				CASE WHEN COALESCE(NULLIF(op.assigned_geofence_ids, ''), NULLIF(op.geofencingid::TEXT, '0'))<>'0' THEN 'Y' ELSE 'N' END is_eligable_for_geofencing,
				CASE WHEN COALESCE(NULLIF(op.assigned_geofence_ids, ''), NULLIF(op.geofencingid::TEXT, '0'))<>'0' THEN 'Y' ELSE 'N' END isenablegeofencing,
				-- COALESCE(tougf.isenablegeofencing, 'N') isenablegeofencing,
                COALESCE(op.geofencingid,'0') geofencingid, COALESCE(tougf.org_unit_name,'') org_unit_name, COALESCE(tougf.geo_link,'') geo_link,
				COALESCE(tougf.geo_longitude,'0') geo_longitude, COALESCE(tougf.geo_latitude,'0') geo_latitude, 
				CASE WHEN emp_cico.is_mobile_check_in_check_out = 'N' THEN '-1' ELSE COALESCE(tougf.geo_radius,'0') END geo_radius,
				check_in_out_detailssss.*,
				ou_geofenc_data.*,
                COALESCE(emp_cico.is_night_shift, 'N') is_night_shift,
			    (
			        SELECT
			            LPAD(FLOOR(total_seconds / 3600)::text, 2, '0') || ':' ||
						LPAD(FLOOR((total_seconds % 3600) / 60)::text, 2, '0') || ':' ||
						LPAD(FLOOR(total_seconds % 60)::text, 2, '0')
			        FROM (
			            SELECT EXTRACT(
			                EPOCH FROM (
			                    (
									(CURRENT_DATE + COALESCE(NULLIF(emp_cico.default_shift_time_to, ''), '00:00:00')::time)
									+ CASE WHEN COALESCE(NULLIF(emp_cico.is_night_shift, ''), 'N') = 'Y' THEN INTERVAL '1 DAY' ELSE INTERVAL '0 DAY' END
									+ CASE WHEN COALESCE(NULLIF(emp_cico.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(emp_cico.shift_margin_hours_to, ''), '00:00:00')::interval ELSE INTERVAL '0' END
			                    )
			                    -
			                    (
									(CURRENT_DATE + COALESCE(NULLIF(emp_cico.default_shift_time_from, ''), '00:00:00')::time)
			                     	- CASE WHEN COALESCE(NULLIF(emp_cico.shift_margin, ''), 'N') = 'Y' THEN COALESCE(NULLIF(emp_cico.shift_margin_hours_from, ''), '00:00:00')::interval ELSE INTERVAL '0' END
			                    )
			                )
			            ) AS total_seconds
			        ) s
			    ) AS shift_duration
			FROM openappointments op
			LEFT JOIN tbl_candidate_documentlist tc on op.emp_id=tc.candidate_id and tc.document_id=17 and tc.active='Y'
			LEFT JOIN
			(
				SELECT json_agg(trips) ou_geofenc_details
				FROM
				(
					SELECT
						json_build_object
						(
							'geofencingid', COALESCE(id::TEXT, ''),
							'org_unit_name', COALESCE(org_unit_name::TEXT, ''),
							'geo_link', COALESCE(geo_link::TEXT, ''),
							'geo_longitude', COALESCE(geo_longitude::TEXT, ''),
							'geo_latitude', COALESCE(geo_latitude::TEXT, ''),
							'geo_radius', COALESCE(geo_radius::TEXT, '')
						) AS trips
					FROM openappointments op
					INNER JOIN tbl_org_unit_geofencing tougf ON tougf.isactive='1' AND tougf.customeraccountid = p_customeraccountid AND tougf.geo_longitude <> '0' AND tougf.geo_latitude <> '0' AND tougf.id IN (SELECT cast(regexp_split_to_table(COALESCE(NULLIF(op.assigned_geofence_ids, ''), NULLIF(op.geofencingid::TEXT, '0')), ',') as int))
					WHERE op.emp_code=p_empcode AND op.customeraccountid = p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in (11,14)
					GROUP BY tougf.id
					ORDER BY tougf.id ASC
				) ou_geofenc_details
			) ou_geofenc_data ON TRUE
			LEFT JOIN tbl_org_unit_geofencing tougf ON tougf.isactive='1' AND op.customeraccountid=tougf.customeraccountid AND op.geofencingid=tougf.id
			LEFT JOIN vw_user_spc_emp AS emp_cico ON emp_cico.emp_code::bigint = op.emp_code::bigint AND emp_cico.is_active='1'
			LEFT JOIN
			(
				SELECT json_agg(trips) check_in_out_details
				FROM
				(
					SELECT
						json_build_object
						(
							'event_id', COALESCE(t.id::TEXT, ''),
							'att_date', TO_CHAR(COALESCE(t.att_date::DATE, v_att_date), 'dd-mm-yyyy'),
							'actual_check_in_time', t.check_in_time, 
							'actual_check_out_time', t.check_out_time, 
							'check_in_time', COALESCE(TO_CHAR(t.check_in_time at time zone 'utc'  at time zone 'Asia/Kolkata','HH24:mi'),'00:00'), 
							'check_out_time', COALESCE(TO_CHAR(t.check_out_time at time zone 'utc'  at time zone 'Asia/Kolkata','HH24:mi'),'00:00'), 
							-- 'no_of_hours_worked', COALESCE(TO_CHAR(date_trunc('minute',t.check_out_time) - date_trunc('minute',t.check_in_time),'hh24:mi'),'00:00'), 
							'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0'),
							'check_in_location', COALESCE(t.check_in_location,''), 
							'check_out_location', COALESCE(t.check_out_location,''), 
							'check_in_image_path', COALESCE(t.check_in_image_path,''), 
							'check_out_image_path', COALESCE(t.check_out_image_path,''),
							'attendance_type', COALESCE(t.attendance_type,'')
						) AS trips
					FROM openappointments op
					LEFT JOIN tbl_attendance t ON t.emp_code=op.emp_code AND att_date = v_att_date AND t.isactive='1'
					LEFT JOIN tbl_candidate_documentlist tc ON op.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
					WHERE op.emp_code = p_empcode AND op.customeraccountid = p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in (11,14)
					GROUP BY t.id
					ORDER BY t.id ASC
				) check_in_out_details
			) check_in_out_detailssss ON TRUE
			WHERE op.emp_code = p_empcode AND op.customeraccountid = p_customeraccountid AND op.converted='Y' AND op.appointment_status_id IN (11,14);
		RETURN v_result;
		END IF;
	ELSIF p_action = 'GetDailyAttendanceDetail' THEN
		OPEN v_result FOR
			SELECT
                'CheckInCheckOut' table_ref,
				op.emp_code::text, op.emp_name, 
				
				-- op.post_offered 
				COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered) 	designation,
				TO_CHAR(tma.att_date,'dd-mm-yyyy') attendancedate,
				-- add 5:30  vinod
				--COALESCE(left(tma.firstcheckintime,5), '00:00') AS check_in_time,
				--COALESCE(left(tma.lastcheckouttime,5), '00:00') AS check_out_time,
				
				to_char((to_timestamp(left(nullif(tma.firstcheckintime,''),5),'hh24:mi')  + INTERVAL '5 HOURS 30 MINUTES')::timestamp,'hh24:mi') check_in_time
				,to_char((to_timestamp(left(nullif(tma.lastcheckouttime,''),5),'hh24:mi')  + INTERVAL '5 HOURS 30 MINUTES')::timestamp,'hh24:mi') check_out_time,
				tma.attendance_type AS attendance_type,
				left(tma.no_of_hours_worked,5) as no_of_hours_worked,
				op.dateofjoining,
				NULLIF(tc.document_path,'https://api.contract-jobs.com/crm_api/') AS photopath,
				op.orgempcode, op.cjcode tpcode,
				tma.is_overtime is_overtime_applicable, TO_CHAR(CAST(NULLIF(tma.no_of_overtime_hours_worked, '') AS INTERVAL), 'HH24:MI') no_of_overtime_hours_worked,
				tma.deviation_in_checkin, tma.deviation_in_checkout, tma.deviation_in_total_working_hours,
				--COALESCE(emp_cico.shift_name, emp_cico.shift_name)||' ['||COALESCE(emp_cico.default_shift_time_from, emp_cico.default_shift_time_from)||'-'||COALESCE(emp_cico.default_shift_time_to, emp_cico.default_shift_time_to)||']'||CASE WHEN COALESCE(emp_cico.is_auto_shift_assign, 'N')='Y' THEN '[Auto Shift]' ELSE '' END AS shift_name,
				COALESCE(emp_cico.is_night_shift, COALESCE(emp_cico.is_night_shift, 'N')) is_night_shift,
                COALESCE(emp_cico.break_total_time, emp_cico.break_total_time) break_total_time,
                COALESCE(emp_cico.break_pay_type, emp_cico.break_pay_type) break_pay_type,
                tma.is_auto_shift_assign is_auto_shift_assign,
                tma.attendance_policy_id attendance_policy_id, op.posting_department department,
				op.assigned_ou_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ')
									  from tbl_org_unit_geofencing geo WHERE geo.id IN (select regexp_split_to_table(COALESCE(NULLIF(op.assigned_ou_ids, ''), '0'),',')::int)) assigned_ou_ids_names,
				TO_CHAR(CAST(NULLIF(tma.latehours, '') AS INTERVAL), 'HH24:MI') late_check_in_time, tma.latehoursdeduction late_check_in_amount,
				TO_CHAR(CAST(NULLIF(tma.earlyhours, '') AS INTERVAL), 'HH24:MI') early_check_out_time, tma.earlyhoursdeduction early_check_out_amount,
				TO_CHAR(CAST(NULLIF(tma.overtime_hours_approved_by_employer, '') AS INTERVAL), 'HH24:MI') overtime_hours_approved_by_employer, tma.overtime_amount_approved_by_employer overtime_amount_approved_by_employer,
				leavetype,
				case when tma.multipayoutrequestid=0 then 'Unpaid' else 'Paid' end as paystatus,
				e.salarysetupcriteria,ishourlysetup
				FROM openappointments op
				inner join empsalaryregister e on op.emp_id=e.appointment_id and e.isactive='1'
				LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and account_id= op.customeraccountid
			LEFT JOIN tbl_candidate_documentlist tc ON op.emp_id=tc.candidate_id AND tc.document_id=17 AND tc.active='Y'
			LEFT JOIN vw_user_spc_emp AS emp_cico ON emp_cico.emp_code::bigint = op.emp_code AND is_active='1'
			LEFT JOIN tbl_monthly_attendance AS tma ON tma.emp_code::bigint = op.emp_code::bigint AND tma.isactive='1'
			LEFT JOIN (select distinct emp_code as adv_empcode from tbl_monthly_attendance where emp_code=p_empcode and is_attendance_salary='Salary' and attendance_salary_status='1' and att_date between v_from_date and v_to_date and approval_status='A') adv_attendance
			on adv_attendance.adv_empcode=op.emp_code
			 left join lateral(select distinct emp_code from tbl_monthlysalary where mprmonth=p_month and mpryear=p_year and is_rejected='0' and attendancemode='MPR' and multipayoutrequestid=0) tblsal
			on op.emp_code=tblsal.emp_code
			WHERE op.emp_code=p_empcode
			AND tma.att_date BETWEEN v_from_date::DATE AND v_to_date::DATE AND tma.isactive='1'
			and tblsal.emp_code is null and adv_attendance.adv_empcode is null
			ORDER BY tma.att_date;
			-- END
		RETURN v_result;
	END IF;

	IF p_action = 'GetAttendanceSummaryByemployer' THEN
		OPEN v_result FOR

		WITH filtered_appointments AS (
		    SELECT 
		        op.emp_code,
		        op.emp_name,
		        op.cjcode,
		        op.orgempcode,
		        op.customeraccountid,
		        op.post_offered,
		        op.posting_department,
		        op.assigned_ou_ids,
		        op.geofencingid,
		        op.assigned_geofence_ids,
		        op.dateofjoining,
		        op.designation_id,
		        op.jobtype,
		        op.emp_id
		    FROM openappointments op
		    WHERE 
		        op.customeraccountid = p_customeraccountid
		        AND COALESCE(op.converted, 'N') = 'Y' 
		        AND op.appointment_status_id IN (11,14)
		        AND op.dateofjoining <= v_to_date::DATE 
		        AND (op.dateofrelieveing IS NULL OR op.dateofrelieveing >= v_from_date::DATE)
		        AND (op.emp_code = p_empcode OR p_empcode = -9999)
		        AND (
		            op.emp_name ILIKE '%'||p_search_keyword||'%' 
		            OR COALESCE(op.cjcode, '0') = p_search_keyword 
		            OR COALESCE(op.orgempcode, '0') = p_search_keyword
		        )
		        -- Job Type Filter
		        AND op.jobtype = ANY (
		            SELECT unnest(string_to_array(CASE WHEN p_report_type = 'Meeting' THEN 'Meeting' ELSE v_jobtypecode END, ','))
		        )
		        -- Post Offered Filter
		        AND (
		            COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
		            OR string_to_array(UPPER(op.post_offered), ',') && string_to_array(UPPER(p_post_offered), ',')
		        )
		        -- Department Filter
		        AND (
		            COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
		            OR string_to_array(UPPER(op.posting_department), ',') && string_to_array(UPPER(p_posting_department), ',')            
		        )
		        -- Unit/OU Filter
		        AND (
		            NULLIF(p_unitparametername, '') IS NULL OR
		            string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ',')
		            && string_to_array(p_unitparametername, ',')
		        )
		        -- Secondary OU Check (from original query's second redundant block)
		        AND (
		            NULLIF(p_ou_ids, '') IS NULL OR 
		            string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ',')
		            && string_to_array(p_ou_ids, ',')
		        )
		),
		attendance_details AS (
		    SELECT 
		        t.emp_code,
		        t.att_date,
		        json_agg(
		            json_build_object(
						'row_id', t.id::TEXT,
		                'att_date', COALESCE(TO_CHAR(t.att_date,'dd-mm-yyyy'), TO_CHAR(v_from_date::DATE, 'dd-mm-yyyy')), 
		                'actual_check_in_time', t.check_in_time, 
		                'actual_check_out_time', t.check_out_time, 
		                'check_in_time', COALESCE(to_char(t.check_in_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
		                'check_out_time', COALESCE(to_char(t.check_out_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','HH24:mi'),'00:00'), 
		                'no_of_hours_worked', LPAD(FLOOR(EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM (t.check_out_time::timestamp - t.check_in_time::timestamp)) % 60))::TEXT, 2, '0'), 
		                'check_in_location', COALESCE(t.check_in_location,''), 
		                'check_out_location', COALESCE(t.check_out_location,''), 
		                'check_in_image_path', COALESCE(t.check_in_image_path,''), 
		                'check_out_image_path', COALESCE(t.check_out_image_path,''),
		                'attendance_type', COALESCE(t.attendance_type,''),
		                'meeting_name', COALESCE(t.meeting_name,''),
		                'meeting_feedback', COALESCE(t.meeting_feedback,''),
		                'meeting_remarks', COALESCE(t.meeting_remarks,''),
		                'check_in_geofence_id', COALESCE(t.check_in_geofence_id::TEXT, ''),
		                'check_in_geofence_id_name', COALESCE(geo_in.org_unit_name::TEXT, ''),
		                'check_out_geofence_id', COALESCE(t.check_out_geofence_id::TEXT,''),
		                'check_out_geofence_id_name', COALESCE(geo_out.org_unit_name::TEXT, ''),
		                'check_in_date', COALESCE(to_char(t.check_in_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','DD-MM-YYYY'),''), 
		                'check_out_date', COALESCE(to_char(t.check_out_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata','DD-MM-YYYY'),''),
		                'approvalappid', COALESCE(t.approvalappid,0),
		                'isapprovalapproved', COALESCE(t.isapprovalapproved,'Y'),
		                'app_level', COALESCE(ta.level,0),
		                'check_in_latitude', COALESCE(t.check_in_latitude,''),
		                'check_in_longitude', COALESCE(t.check_in_longitude,''),
		                'check_out_latitude', COALESCE(t.check_out_latitude,''),
		                'check_out_longitude', COALESCE(t.check_out_longitude,'')
		            ) ORDER BY t.id ASC
		        ) AS check_in_out_details
		    FROM filtered_appointments fa
		    JOIN tbl_attendance t ON t.emp_code = fa.emp_code 
		        AND t.att_date BETWEEN v_from_date::DATE AND v_to_date::DATE 
		        AND t.isactive = '1'
		    LEFT JOIN tbl_application ta ON t.emp_code = ta.emp_code 
		        AND ta.standardappmoduleid = 37 
		        AND ta.status = 1 
		        AND ta.application_id = t.approvalappid
		    LEFT JOIN tbl_org_unit_geofencing geo_in ON t.check_in_geofence_id = geo_in.id
		    LEFT JOIN tbl_org_unit_geofencing geo_out ON t.check_out_geofence_id = geo_out.id
		    GROUP BY t.emp_code, t.att_date
		)
		SELECT 
		    CASE 
		        WHEN (ad.emp_code IS NOT NULL OR tma.emp_code IS NOT NULL) THEN 'Marked' 
		        ELSE 'Unmarked' 
		    END as marked_status,
		    'CheckInCheckOut' as table_ref,
		    op.emp_code::text, 
		    op.emp_name, 
		    COALESCE(NULLIF(mtd.designationname, ''), op.post_offered) as designation, 
		    op.jobtype,
		    loc.location, -- Retrieved from LATERAL JOIN
		    TO_CHAR(COALESCE(ad.att_date, v_from_date), 'dd-mm-yyyy') as attendancedate,
		    COALESCE((ad.check_in_out_details->0->>'check_in_time'), '00:00') AS check_in_time,
		    COALESCE(ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'check_out_time', '00:00') AS check_out_time,
		    COALESCE(ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'attendance_type', '') AS attendance_type,
		    CASE 
		        WHEN COALESCE(ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'check_out_time', '00:00') = '00:00' THEN 0 
		        ELSE json_array_length(ad.check_in_out_details) 
		    END AS check_in_out_count,
		    CASE 
		        WHEN emp_cico.total_working_hours_calculation = 'first_last_check' THEN
		            CASE 
		                WHEN json_array_length(ad.check_in_out_details) > 1 AND ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'actual_check_out_time' IS NULL THEN
		                    LPAD(FLOOR(EXTRACT(EPOCH FROM ((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (ad.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (ad.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 2)->>'actual_check_out_time')::timestamp - (ad.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
		                ELSE
		                    LPAD(FLOOR(EXTRACT(EPOCH FROM ((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (ad.check_in_out_details->0->>'actual_check_in_time')::timestamp)) / 3600)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (ad.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 3600) / 60)::TEXT, 2, '0') || ':' || LPAD(FLOOR((EXTRACT(EPOCH FROM ((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'actual_check_out_time')::timestamp - (ad.check_in_out_details->0->>'actual_check_in_time')::timestamp)) % 60))::TEXT, 2, '0')
		            END
		        ELSE
		            (SELECT to_char(SUM((trip->>'no_of_hours_worked')::interval), 'HH24:MI') FROM json_array_elements(ad.check_in_out_details) AS trips(trip))
		    END AS no_of_hours_worked,
		    COALESCE((ad.check_in_out_details->0->>'check_in_location'), '') AS check_in_location,
		    COALESCE((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'check_out_location'), '') AS check_out_location,
		    COALESCE((ad.check_in_out_details->0->>'check_in_image_path'), '') AS check_in_image_path,
		    COALESCE((ad.check_in_out_details->(json_array_length(ad.check_in_out_details) - 1)->>'check_out_image_path'), '') AS check_out_image_path,
		    NULLIF(op.dateofjoining, '0001-01-01 BC') as dateofjoining,
		    NULLIF(tc.document_path, 'https://api.contract-jobs.com/crm_api/') AS photopath,
		    op.orgempcode, 
		    op.cjcode AS tpcode,
		    COALESCE(ad.check_in_out_details, '[{}]')::jsonb as check_in_out_details,
		    tma.is_overtime as is_overtime_applicable, 
		    tma.no_of_overtime_hours_worked, 
		    tma.deviation_in_checkin, 
		    tma.deviation_in_checkout, 
		    tma.deviation_in_total_working_hours,
		    COALESCE(emp_cico.shift_name, emp_cico.shift_name)||' ['||COALESCE(emp_cico.default_shift_time_from, emp_cico.default_shift_time_from)||'-'||COALESCE(emp_cico.default_shift_time_to, emp_cico.default_shift_time_to)||']'||CASE WHEN COALESCE(tma.is_auto_shift_assign, 'N')='Y' THEN '[Auto Shift]' ELSE '' END AS shift_name,
		    COALESCE(emp_cico.is_night_shift, 'N') as is_night_shift,
		    emp_cico.break_total_time,
		    NULLIF(emp_cico.break_pay_type, '') as break_pay_type,
		    tma.is_auto_shift_assign,
		    tma.attendance_policy_id, 
		    op.posting_department as department,
		    op.assigned_ou_ids, 
		    ou_names.assigned_ou_ids_names, -- Retrieved from LATERAL JOIN
		    NULLIF(op.assigned_geofence_ids, '') as assigned_geofence_ids, 
		    geo_names.assigned_geofence_ids_names, -- Retrieved from LATERAL JOIN
		    COALESCE((ad.check_in_out_details->0->>'check_in_date'), '') AS check_in_date,
		    COALESCE((ad.check_in_out_details->0->>'check_out_date'), '') AS check_out_date,
		    COALESCE(tma.late_multiplier, '1') as late_multiplier,
		    COALESCE(tma.early_multiplier, '1') as early_multiplier,
		    COALESCE(tma.overtime_multiplier, '1') as overtime_multiplier,
		    tma.deviation_in_checkin_time,
		    tma.deviation_in_checkout_time,
		    tma.deviation_in_working_hours_time,
		    tma.id as monthlyattendanceid,
		    usp_attnname_by_code(tma.att_catagory) as att_catagory,
		    COALESCE(tma.attendance_type, '') as attendance_type_m,
		    CASE 
		        WHEN (ad.check_in_out_details->0->>'app_level')::int <= 1 
		          OR ad.check_in_out_details->0->>'approvalappid' = '0' 
		          OR (ad.check_in_out_details->0->>'approvalappid' <> '0' 
		              AND ad.check_in_out_details->0->>'isapprovalapproved' = 'N' 
		              AND (ad.check_in_out_details->0->>'app_level')::int <= 1) 
		        THEN 'Y' 
		        ELSE 'N' 
		    END as allowedit,
		    (ad.check_in_out_details->0->>'app_level')::int as app_level
		FROM filtered_appointments op
		LEFT JOIN attendance_details ad ON op.emp_code = ad.emp_code
		LEFT JOIN tbl_candidate_documentlist tc ON op.emp_id = tc.candidate_id AND tc.document_id = 17 AND tc.active = 'Y'
		LEFT JOIN vw_user_spc_emp emp_cico ON emp_cico.emp_code::bigint = op.emp_code::bigint AND emp_cico.is_active = '1' AND emp_cico.customeraccountid = op.customeraccountid
		LEFT JOIN tbl_monthly_attendance tma ON tma.emp_code::bigint = op.emp_code::bigint AND tma.isactive = '1' AND tma.att_date = ad.att_date
		LEFT JOIN mst_tp_designations mtd ON mtd.dsignationid = op.designation_id AND mtd.account_id = op.customeraccountid
		-- LATERAL JOIN for Location
		LEFT JOIN LATERAL (
		    SELECT location 
		    FROM tbl_emp_transfer_location_history 
		    WHERE emp_code = op.emp_code AND is_latest = '1' AND isactive = '1' 
		    LIMIT 1
		) loc ON TRUE
		-- LATERAL JOIN for Assigned OU Names
		LEFT JOIN LATERAL (
		    SELECT STRING_AGG(geo.org_unit_name::TEXT, ', ') as assigned_ou_ids_names
		    FROM tbl_org_unit_geofencing geo 
		    WHERE geo.id IN (SELECT regexp_split_to_table(COALESCE(NULLIF(op.assigned_ou_ids, ''), '0'), ',')::int)
		) ou_names ON TRUE
		-- LATERAL JOIN for Assigned Geofence Names
		LEFT JOIN LATERAL (
		    SELECT STRING_AGG(geo.org_unit_name::TEXT, ', ') as assigned_geofence_ids_names
		    FROM tbl_org_unit_geofencing geo 
		    WHERE geo.id IN (SELECT regexp_split_to_table(COALESCE(NULLIF(op.assigned_geofence_ids, ''), '0'), ',')::int)
		) geo_names ON TRUE
		WHERE
		    (
		        p_marked_type = 'All'
		        OR (p_marked_type = 'Marked' AND (ad.emp_code IS NOT NULL OR tma.emp_code IS NOT NULL)) 
		        OR (p_marked_type = 'Not Marked' AND (ad.emp_code IS NULL AND tma.emp_code IS NULL)) 
		    )
		ORDER BY ad.emp_code ASC;
        RETURN v_result;
	END IF;

END;
$BODY$;

ALTER FUNCTION public.usptpemployeecheckinreport(text, text, text, bigint, bigint, integer, character varying, character varying, character varying, character varying, text, text, text, integer, integer, text)
    OWNER TO payrollingdb;

