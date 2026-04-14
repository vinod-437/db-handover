CREATE OR REPLACE FUNCTION public.usp_approve_reject_missed_punch_att(p_action text, p_customeraccountid bigint, p_emp_code bigint, p_att_date text, p_att_status text, p_modified_by_user text, p_modified_by_ip text, p_remarks text DEFAULT NULL::text)
 RETURNS refcursor
 LANGUAGE plpgsql
AS $function$
/********|****************|********************|*****************************
|VERSION |  DATE          | CHANGE BY          |CHANGE
|********|****************|********************|*****************************
|1.0     |  15-FEB-2025   | Parveen Kumar      |Initial Version
|2.0     |  21-JUN-2025   | Vinod   Kumar      |remove Error for Mutliple row
****************************************************************************/
DECLARE
	response refcursor;
    v_attid BIGINT;
	v_empid int;
	v_timecriteria varchar(30);
	v_payout_mode_type text;
	v_check_in_time text;
	v_check_out_time text;
    v_att_date DATE;
    v_att_policy_type character varying(100);
    v_att_policy_id bigint;

	v_att_policy refcursor;
	v_rec record;
	v_is_policy_applied character varying(100) := 'N';

    -- START [1.1]
    v_alert_js_id bigint;
    v_alert_customeraccountid int;
    v_alert_emp_name character varying(100);
    v_alert_org_emp_code_or_tp_code character varying(50);
    -- END [1.1]
	v_is_late_comer character varying(1) := 'N';
    v_employee_alert_msg character varying(500);
    v_employer_alert_msg character varying(500);

BEGIN
    IF EXISTS (SELECT * FROM vw_user_spc_emp WHERE emp_code::bigint=p_emp_code AND is_active='1') THEN
        v_is_policy_applied := 'Y';
    END IF;

	IF NOT EXISTS(SELECT * FROM tbl_account WHERE id = p_customeraccountid AND status = '1') THEN
		OPEN response FOR
			SELECT -1 AS status, 'Employer not exists/active.' msg;
		RETURN response;
	END IF;

	IF NOT EXISTS(SELECT * FROM openappointments WHERE emp_code = p_emp_code AND customeraccountid = p_customeraccountid AND appointment_status_id='11' AND COALESCE(converted, 'N')='Y' AND COALESCE(dateofrelieveing, CURRENT_DATE)::date <= CURRENT_DATE::date) THEN
		OPEN response FOR
			SELECT -1 AS status, 'Employee not exists/active.' msg;
		RETURN response;
	END IF;

    SELECT payout_mode_type FROM tbl_account WHERE id=p_customeraccountid INTO v_payout_mode_type;
    SELECT emp_id, emp_name, COALESCE(NULLIF(orgempcode, ''), cjcode), js_id, customeraccountid, jobtype FROM openappointments WHERE emp_code=p_emp_code AND customeraccountid=p_customeraccountid INTO v_empid, v_alert_emp_name, v_alert_org_emp_code_or_tp_code, v_alert_js_id, v_alert_customeraccountid;
    SELECT COALESCE(timecriteria, '') FROM empsalaryregister WHERE appointment_id=v_empid AND isactive='1' AND effectivefrom<=CURRENT_DATE ORDER BY id DESC LIMIT 1 INTO v_timecriteria;
    SELECT COALESCE(attendance_policy_type, NULL), COALESCE(attendance_policy_id, NULL) FROM vw_user_spc_emp WHERE emp_code=p_emp_code AND is_active=true INTO v_att_policy_type, v_att_policy_id;

    v_att_date = TO_DATE(p_att_date, 'dd/mm/yyyy');
    IF p_action = 'ApproveMissedPunch' THEN
        IF EXISTS (SELECT * FROM tbl_attendance WHERE isactive = '1' AND emp_code = p_emp_code AND att_date = v_att_date AND is_mis_punch = 'Y' AND mis_punch_approval_status = 'A') THEN
            OPEN response FOR
                SELECT -1 AS status, 'Missed Punch attendance already approved.' msg;
            RETURN response;
        END IF;

        IF NOT EXISTS (SELECT * FROM tbl_attendance WHERE isactive = '1' AND emp_code = p_emp_code AND att_date = v_att_date AND is_mis_punch = 'Y' AND mis_punch_approval_status = 'P') THEN
            OPEN response FOR
                SELECT -1 AS status, 'Pending Missed Punch attendance not found for update.' msg;
            RETURN response;
        END IF;

      /* IF NOT EXISTS (SELECT * FROM tbl_monthly_attendance WHERE emp_code=p_emp_code AND customeraccountid = p_customeraccountid 
		AND att_date = v_att_date::DATE AND isactive = '1' AND attendance_type = 'MP' AND att_catagory in ('SP','DE') ) THEN
         */   

        IF NOT EXISTS (SELECT * FROM tbl_monthly_attendance WHERE emp_code=p_emp_code AND customeraccountid = p_customeraccountid AND att_date = v_att_date::DATE AND isactive = '1' AND (attendance_type = 'MP' OR att_catagory IN ('MP', 'DE', 'SP', 'LC', 'EG', 'LCEG'))) THEN
            OPEN response FOR
                SELECT -1 AS status, 'Missed Punch attendance not found for update.' msg;
            RETURN response;
        END IF;

        UPDATE tbl_attendance
        SET
            is_mis_punch = 'Y',
            mis_punch_approval_status = 'A',
            mis_punch_approved_by = p_modified_by_user,
            mis_punch_approved_by_ip = p_modified_by_ip,
            mis_punch_approved_on = CURRENT_TIMESTAMP,
            modifiedbyuser = p_modified_by_user,
            modifiedon = CURRENT_TIMESTAMP,
            modifiedbyip = p_modified_by_ip,
			remarks = p_remarks
        WHERE emp_code = p_emp_code AND att_date = v_att_date AND isactive = '1';
       -- RETURNING id INTO v_attid;
		-- added on this by vinod
		SELECT id INTO v_attid FROM tbl_attendance WHERE emp_code = p_emp_code::bigint   AND att_date = v_att_date
		AND isactive = '1' ORDER BY id  LIMIT 1;
		-- end 

        IF v_attid IS NOT NULL THEN
            IF v_is_policy_applied = 'Y' THEN
                SELECT public.calculate_employee_attandance_policy
                (
                    p_customeraccountid => p_customeraccountid,
                    p_emp_code => p_emp_code,
                    p_att_date => p_att_date
                ) INTO v_att_policy;
                FETCH v_att_policy INTO v_rec;

                UPDATE tbl_monthly_attendance
                SET
                    attendance_type = v_rec.attandance_type, approval_status = 'A',
                    modifiedbyuser = p_modified_by_user, modifiedon = CURRENT_TIMESTAMP, modifiedbyip = p_modified_by_ip,
                    attendance_policy_id = v_rec.attendance_policy_id, attendance_policy_type = v_rec.attendance_policy_type, no_of_hours_worked = v_rec.no_of_hours_worked, 
                    is_overtime = v_rec.is_overtime, no_of_overtime_hours_worked = v_rec.no_of_overtime_hours_worked, 
                    deviation_in_checkin = v_rec.deviation_in_checkin, deviation_in_checkout = v_rec.deviation_in_checkout, deviation_in_total_working_hours = v_rec.deviation_in_working_hours,
                    leavebankid = v_rec.leave_bank_id, leavetype = v_rec.leave_type,
                    att_catagory = v_rec.attandance_category, is_auto_shift_assign = v_rec.is_auto_assign_shift,
                    firstcheckintime = v_rec.first_check_in_time, lastcheckouttime = v_rec.last_check_out_time,
                    was_mis_punch = '1',
                    mis_punch_approval_status = 'A', mis_punch_approved_by = p_modified_by_user,  mis_punch_approved_by_ip = p_modified_by_ip, mis_punch_approved_on = CURRENT_TIMESTAMP,
					remarks = p_remarks
                WHERE emp_code=p_emp_code AND customeraccountid=p_customeraccountid AND att_date=v_att_date AND isactive='1' AND (v_timecriteria='Full Time' OR v_payout_mode_type='attendance');
            ELSE
                SELECT check_in_time, check_out_time FROM tbl_attendance
                WHERE isactive = '1' AND emp_code = p_emp_code AND att_date = v_att_date AND is_mis_punch = 'Y' AND mis_punch_approval_status = 'P'
                INTO v_check_in_time, v_check_out_time;

                UPDATE tbl_monthly_attendance
                SET
                    attendance_type = 'PP', approval_status = 'A',
                    modifiedbyuser = p_modified_by_user, modifiedon = CURRENT_TIMESTAMP, modifiedbyip = p_modified_by_ip,
                    attendance_policy_id = NULL,  attendance_policy_type = NULL, no_of_hours_worked = NULL, 
                    is_overtime = 'N', no_of_overtime_hours_worked = NULL, 
                    deviation_in_checkin = 0, deviation_in_checkout = 0, deviation_in_total_working_hours = 0,
                    leavebankid = 0, leavetype = NULL,
                    att_catagory = NULL, is_auto_shift_assign = 'N',
                    firstcheckintime = v_check_in_time, lastcheckouttime = v_check_out_time,
                    was_mis_punch = '1',
                    mis_punch_approval_status = 'A', mis_punch_approved_by = p_modified_by_user, mis_punch_approved_by_ip = p_modified_by_ip, mis_punch_approved_on = CURRENT_TIMESTAMP,
					remarks = p_remarks
                WHERE emp_code=p_emp_code AND customeraccountid=p_customeraccountid AND att_date=v_att_date AND isactive='1' AND (v_timecriteria='Full Time' OR v_payout_mode_type='attendance');
			END IF;

            /*
            -- START Alert
                v_employer_alert_msg := v_alert_emp_name||' ('||v_alert_org_emp_code_or_tp_code||') updated their missed punch attendance check-in ('||COALESCE(TO_CHAR((p_check_in_time::TIMESTAMP),'HH24:mi'),'00:00')||') and check-out ('||COALESCE(TO_CHAR((p_check_out_time::TIMESTAMP),'HH24:mi'),'00:00')||') for '||p_att_date||' on '||TO_CHAR(CURRENT_DATE, 'dd/mm/yyyy')||' at '||TO_CHAR(CURRENT_TIMESTAMP + INTERVAL '5 HOURS 30 MINUTE', 'HH24:MI:SS')||'.';
                PERFORM usppopulatetpalerts
                (
                    p_action => 'PopulateAlert'::character varying,
                    p_js_id => v_alert_js_id::bigint,
                    p_customeraccountid => v_alert_customeraccountid::integer,
                    p_alertusertype => 'Employer'::character varying,
                    p_alerttypeid => 20::integer,
                    p_alertmessage => v_employer_alert_msg
                );

                v_employee_alert_msg := 'Missed punch attendance updated: Check-in ('||COALESCE(TO_CHAR((p_check_in_time::TIMESTAMP),'HH24:mi'),'00:00')||') and check-out ('||COALESCE(TO_CHAR((p_check_out_time::TIMESTAMP),'HH24:mi'),'00:00')||') for '||p_att_date||', updated on '||TO_CHAR(CURRENT_DATE, 'dd/mm/yyyy')||' at '||TO_CHAR(CURRENT_TIMESTAMP + INTERVAL '5 HOURS 30 MINUTE', 'HH24:MI:SS')||'.';
                PERFORM usppopulatetpalerts
                (
                    p_action => 'PopulateAlert'::character varying,
                    p_js_id => v_alert_js_id::bigint,
                    p_customeraccountid => v_alert_customeraccountid::integer,
                    p_alertusertype => 'Employee'::character varying,
                    p_alerttypeid => 21::integer,
                    p_alertmessage => v_employee_alert_msg
                );
            -- END Alert
            */

            OPEN response FOR
                SELECT 1 AS status, 'Missed Punch approved successfully.' msg;
            RETURN response;
        ELSE
            OPEN response FOR
                SELECT -1 AS status, 'Unable to approve missed punch attendance.' msg;
            RETURN response;
        END IF;
    ELSIF p_action = 'RejectMissedPunch' THEN
        IF EXISTS (SELECT * FROM tbl_attendance WHERE isactive = '1' AND emp_code = p_emp_code AND att_date = v_att_date AND is_mis_punch = 'Y' AND mis_punch_approval_status = 'A') THEN
            OPEN response FOR
                SELECT -1 AS status, 'Missed punch attendance is already approved and cannot be rejected.' msg;
            RETURN response;
        END IF;

        UPDATE tbl_attendance
        SET
            isactive = '0',
            is_mis_punch = 'Y',
            mis_punch_approval_status = 'R', mis_punch_approved_by = p_modified_by_user, mis_punch_approved_by_ip = p_modified_by_ip, mis_punch_approved_on = CURRENT_TIMESTAMP,
            modifiedbyuser = p_modified_by_user, modifiedon = CURRENT_TIMESTAMP, modifiedbyip = p_modified_by_ip,
			remarks = p_remarks
        WHERE emp_code = p_emp_code AND att_date = v_att_date AND isactive = '1'
        RETURNING id INTO v_attid;

        IF v_attid IS NOT NULL THEN
            UPDATE tbl_monthly_attendance
            SET
                isactive = '0',
                was_mis_punch = '1',
                mis_punch_approval_status = 'R', mis_punch_approved_by = p_modified_by_user, mis_punch_approved_by_ip = p_modified_by_ip, mis_punch_approved_on = CURRENT_TIMESTAMP,
                modifiedbyuser = p_modified_by_user, modifiedon = CURRENT_TIMESTAMP, modifiedbyip = p_modified_by_ip,
				remarks = p_remarks
            WHERE emp_code=p_emp_code AND customeraccountid=p_customeraccountid AND att_date=v_att_date AND isactive='1' AND (v_timecriteria='Full Time' OR v_payout_mode_type='attendance');

            OPEN response FOR
                SELECT 1 AS status, 'Missed Punch rejected successfully.' msg;
            RETURN response;
        ELSE
            OPEN response FOR
                SELECT -1 AS status, 'Unable to reject missed punch attendance.' msg;
            RETURN response;
        END IF;
    ELSE
        OPEN response FOR
            SELECT -1 AS status, 'Invalid operation.' msg;
        RETURN response;
    END IF;

    EXCEPTION WHEN others THEN 
    OPEN response FOR
        SELECT -1 status, 'An error occurred: ' || SQLERRM msg;
    RETURN response;
END;
$function$
