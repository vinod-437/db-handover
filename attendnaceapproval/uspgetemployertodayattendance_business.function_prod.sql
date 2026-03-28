-- FUNCTION: public.uspgetemployertodayattendance_business(character varying, bigint, text, text, text, integer, text, character varying, integer, integer, character varying, text, text, text, text, integer, integer, character varying, integer, integer)

-- DROP FUNCTION IF EXISTS public.uspgetemployertodayattendance_business(character varying, bigint, text, text, text, integer, text, character varying, integer, integer, character varying, text, text, text, text, integer, integer, character varying, integer, integer);

CREATE OR REPLACE FUNCTION public.uspgetemployertodayattendance_business(
	p_action character varying,
	p_customeraccountid bigint,
	p_attdate text DEFAULT ''::text,
	p_empname text DEFAULT ''::text,
	p_approvalstatus text DEFAULT ''::text,
	p_geofenceid integer DEFAULT 0,
	p_attendancesource text DEFAULT 'all'::text,
	p_ou_ids character varying DEFAULT NULL::character varying,
	p_page_no integer DEFAULT 1,
	p_page_limit integer DEFAULT 10,
	p_status character varying DEFAULT NULL::character varying,
	p_post_offered text DEFAULT 'All'::text,
	p_posting_department text DEFAULT 'All'::text,
	p_unitparametername text DEFAULT ''::text,
	p_att_purpose text DEFAULT 'Attendance'::text,
	p_year integer DEFAULT 0,
	p_month integer DEFAULT 0,
	p_month_direction character varying DEFAULT 'N'::character varying,
	p_month_start_day integer DEFAULT 0,
	p_month_end_day integer DEFAULT 0)
    RETURNS SETOF refcursor 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
/*******|***************************|***************************|***************************************************************|
Version |			Done By			|			Date			|	Change
********|***************************|***************************|***************************************************************|
1.0		| Parveen Kumar 			| 29-April-2023 			| Initial - Replica of uspgetemployertodayattendance Procedure
2.0		| Parveen Kumar 			| 09-April-2024 			| Add salary_days_opted, 
																| marked_attendance_paid_days, marked_attendance_leave_taken
2.1		| Parveen Kumar 			| 24-July-2024 	    		| Add assigned_ou_ids filter
3.0		| Parveen Kumar 			| 30-July-2024 	    		| Add p_page_no and p_page_limit filter
3.1     |Siddharth Bansal           |27-Dec-2024				| Joined with holiday Table and give holiday_state_name
3.2     |Shiv Kumar		            |15-Feb-2025				| Cross Month
3.3		| Parveen Kumar				|26-Feb-2025 				| add v_payout_with_attendance in response
3.4     | Parveen Kumar		        |04-March-2025				| Cross Month Start date and end date changes
3.5		| Siddharth Bansal		    |13-March-2025				| Join with tbl_monthlysalary and payment advice
3.6		| Parveen Kumar		    	|22-March-2025				| Add assigned_ou_ids, assigned_ou_ids_name, assigned_geofence_ids and assigned_geofence_ids_name in response
3.6		| SIDDHARTH BANSAL		   	|26-March-2025				| Add salary/Attendance details and filter for att Purpose in Response
3.7		| Shiv Kumar			   	|18-Jun-2025				| change OU Filter Condition
3.8		| Vinod Kumar			   	|24-Jun-2025				| change cross month
3.9		| Shiv Kumar			   	|19-Jul-2025				| cross month and multipayout employees
3.10	| Vinod Kumar			   	|11-Oct-2025				| Add MP/DE/SP Count from  att_Catgeory column
********************************************************************************************************************************/
DECLARE
	v_rfc1 refcursor;
	v_rfc2 refcursor;
	v_resultset1 json;
	v_resultset2 json;
	v_isattendancerequired varchar(30);
	v_payout_settings varchar(30);
	v_monthdays int;
	v_month int;
	v_year int;
	v_payout_mode_type text;
	v_tbl_account tbl_account%rowtype;
	v_rec_payrolldates record;
	v_payout_with_attendance varchar(10); -- Change [3.3]
	v_isbackward varchar(1):='N';
	v_nextmonthdays int:=0;
	v_att_date date;
	v_ou_ids_arr text[];
	v_unitparametername_arr text[];
	v_post_offered_arr text[];
	v_posting_department_arr text[];

BEGIN
	v_att_date:=CASE WHEN nullif(p_attdate,'') IS NULL THEN current_date ELSE to_date(p_attdate,'dd-mm-yyyy') END;
	v_ou_ids_arr := string_to_array(NULLIF(p_ou_ids, ''), ',');
	v_unitparametername_arr := string_to_array(NULLIF(p_unitparametername, ''), ',');
	v_post_offered_arr := string_to_array(lower(p_post_offered), ',');
	v_posting_department_arr := string_to_array(lower(p_posting_department), ',');
	IF p_action='GetEmployeerTodayAttendance' THEN
	
		SELECT * FROM tbl_account WHERE id=p_customeraccountid INTO v_tbl_account;
		v_payout_mode_type:=v_tbl_account.payout_mode_type;
		--SELECT payout_mode_type FROM tbl_account WHERE id = p_customeraccountid INTO v_payout_mode_type;
		SELECT payout_with_attendance INTO v_payout_with_attendance FROM tbl_employerpayoutdate WHERE customeracountid = p_customeraccountid AND isactive = '1' ORDER BY id DESC LIMIT 1; -- Change [3.3]

		v_month:=extract('month' FROM v_att_date)::int;
		v_year:=extract('year' FROM v_att_date)::int;
		v_monthdays:=extract ('day' FROM make_date(v_year::int, v_month::int, 1)+interval '1 month -1 day')::int;

		/**********************Cross month 14-Feb-2024 starts(Change 3.2)***************************************************/
		-- select  (make_date(v_year::int, v_month::int,month_start_day)- interval '1 month')::date start_dt
		-- , make_date(v_year::int, v_month::int,month_end_day)::date  end_dt
		-- Change - START [3.3]
			select null::date start_dt,null::date end_dt,null::int month_start_day,null::text month_direction into v_rec_payrolldates;
			if coalesce(p_month_direction,'N')='N' then
				v_rec_payrolldates.start_dt:=make_date(v_year::int, v_month::int,1);
				v_rec_payrolldates.end_dt:=(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date;
				v_rec_payrolldates.month_start_day:=1;
				v_rec_payrolldates.month_direction:='N';
			else
			v_month=p_month;
			v_year:=p_year;
		SELECT 
			-- added by vinod dated. 23.06.2025
			CASE WHEN p_month_direction='F' THEN make_date(v_year::int, v_month::int,p_month_start_day)::date
								ELSE (make_date(v_year::int, v_month::int,p_month_start_day)- interval '1 month') END start_dt,
						 CASE WHEN p_month_direction='F' THEN (make_date(v_year::int, v_month::int,p_month_end_day)+ interval '1 month')::date 
						 ELSE make_date(v_year::int, v_month::int,p_month_end_day)::date  END  end_dt
				,p_month_start_day as month_start_day,p_month_direction as month_direction
			-- added closed 23.06.2025
			/* make_date(v_year::int, v_month::int, month_start_day)::date start_dt,
			(make_date(v_year::int, v_month::int, month_end_day) + INTERVAL '1 month')::date end_dt
			*/
		-- Change - END [3.3]
		into v_rec_payrolldates;
		end if;
		--Raise Notice 'v_rec_payrolldates.start_dt=%,v_rec_payrolldates.end_dt=%',v_rec_payrolldates.start_dt,v_rec_payrolldates.end_dt;
		/**********************Cross month 14-Feb-2024 ends***************************************************/	

		if coalesce(v_rec_payrolldates.month_start_day,0)>1 and coalesce(v_rec_payrolldates.month_direction,'N')='B' then
			v_nextmonthdays:=v_monthdays;
			v_monthdays:=date_part('day',make_date(v_year,v_month,1) - INTERVAL '1 DAY');
			--v_isbackward:='Y';
		end if;
-- Removed tblouemployees CTE for performance

		SELECT max(coalesce(isattendancerequired,'Y')) INTO v_isattendancerequired
		FROM empsalaryregister e 
		INNER JOIN openappointments op ON e.appointment_id=op.emp_id
			AND ( v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op.assigned_ou_ids, ''), ',') )
            -- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
		WHERE
			op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in (11,14)
			AND (op.dateofrelieveing is null or dateofrelieveing>=make_date(v_year, v_month, 1))
			AND v_att_date BETWEEN effectivefrom AND coalesce(effectiveto,v_att_date);

		v_isattendancerequired:=CASE WHEN coalesce(v_isattendancerequired,'Y')='N' then 'Manual' ELSE 'Auto' END;

/*		SELECT CASE WHEN ta.leavetemplateapplicableon='Employer' then ta.payout_settings ELSE v_isattendancerequired END
		FROM tbl_account ta
		WHERE id=p_customeraccountid
		INTO v_payout_settings;*/
		v_payout_settings:=CASE WHEN v_tbl_account.leavetemplateapplicableon='Employer' then v_tbl_account.payout_settings ELSE v_isattendancerequired END;

-- Removed tblouemployees CTE for performance
/*************Added for Change 3.9 starts*****************/			
with tblmultipayout as(
							SELECT DISTINCT emp_code as taa2_emp_code
							FROM tbl_monthly_attendance
							where tbl_monthly_attendance.customeraccountid = p_customeraccountid
								and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
								and (isactive='1' or attendance_salary_status='1')
								and approval_status='A'
								and multipayoutrequestid<>0
								) 							
								
/*************Added for Change 3.9 ends*****************/	
		SELECT --array_to_json(array_agg(
			row_to_json(X)
		--))  
		INTO v_resultset1 FROM
		(
			SELECT 
				v_tbl_account.tds_enablestatus,
				count(distinct op.emp_code) AS total_att,
				count(CASE WHEN attendance_type in ('PP','HD','WFH','OD') then 1 ELSE null END ) AS present_att,
				count(CASE WHEN attendance_type ='AA' then 1 ELSE null END ) AS absent_att,
				count(CASE WHEN attendance_type ='LL' then 1 ELSE null END ) AS Leave_att,
				v_payout_settings AS payout_settings,
				coalesce(count(distinct tmf.emp_code),0) AS workreportcount
			FROM openappointments op 
			left join empsalaryregister e on e.appointment_id=op.emp_id and e.isactive='1' and  COALESCE(e.salarysetupcriteria,'')<>'PieceRate'
			LEFT JOIN public.tbl_monthly_attendance ta ON ta.emp_code=op.emp_code AND ta.att_date=v_att_date
-- 			AND ta.isactive='1'
			AND 
			(
				(ta.isactive = '1' AND p_att_purpose = 'Attendance' AND ta.attendance_salary_status = '0' AND ta.is_attendance_salary = p_att_purpose)  
				OR  
				(ta.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta.isactive = '0' AND ta.is_attendance_salary = p_att_purpose)
			)
			LEFT JOIN tbl_monthwise_flexi_attendance tmf ON op.emp_code=tmf.emp_code AND tmf.attendanceyear=v_year AND tmf.attendancemonth=v_month AND tmf.isactive='1'
			LEFT JOIN
			(
				SELECT
					ta2.emp_code ecode, count(*) marked_attendance, count(CASE WHEN approval_status='A' then 1 ELSE null END) AS approved_attendance,
							count(CASE WHEN approval_status='P' then 1 ELSE null END) AS unapproved_attendance,
					SUM(CASE WHEN attendance_type IN ('PP','HO','WO','WFH','OD') THEN 1.0 WHEN attendance_type in ('HD') THEN 0.5 END) attendance_paid_days,
					SUM(CASE WHEN attendance_type  ='LL' THEN 1 WHEN attendance_type='HD' AND NULLIF(leavetype,'') IS NOT NULL AND NULLIF(leavetype,'')<>'AA' THEN 0.5 ELSE 0.0 END) attendance_leave_taken
				FROM tbl_monthly_attendance ta2
				INNER JOIN openappointments op2 ON ta2.emp_code=op2.emp_code 
-- 				AND ta2.isactive='1'
				AND 
				(
					(ta2.isactive = '1' AND p_att_purpose = 'Attendance' AND ta2.attendance_salary_status = '0' AND ta2.is_attendance_salary = p_att_purpose)  
					OR  
					(ta2.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta2.isactive = '0' AND ta2.is_attendance_salary = p_att_purpose)
				)
				WHERE 
					op2.customeraccountid=p_customeraccountid 
					and ta2.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
					AND ( v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op2.assigned_ou_ids, ''), ',') )
					-- AND COALESCE(op2.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op2.geofencingid, 0) ELSE p_geofenceid END
				GROUP BY ta2.emp_code
			) tblmonatt ON op.emp_code=tblmonatt.ecode
			left join tblmultipayout  on tblmultipayout.taa2_emp_code=op.emp_code
			/*****************************************************/
			
			WHERE  (e.id is not null or v_payout_mode_type='attendance' )  and
				op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in(11,14)
				AND (op.dateofjoining <= v_att_date)
				AND (op.dateofrelieveing is null or dateofrelieveing>=make_date(v_year, v_month, 1))
				-- SIDDHARTH BANSAL 05/11/2024
-- 				AND (LOWER(p_post_offered) = 'all' OR LOWER(op.post_offered) = LOWER(p_post_offered))
-- 				AND (LOWER(p_posting_department) = 'all' OR LOWER((string_to_array(op.posting_department,'#'))[1]::varchar) = LOWER(p_posting_department))
			    AND (lower(p_post_offered) = 'all' OR lower(op.post_offered) = ANY (v_post_offered_arr))
                AND (lower(p_posting_department) = 'all' OR lower((string_to_array(op.posting_department, '#'))[1]::varchar) = ANY (v_posting_department_arr))
				AND (v_unitparametername_arr IS NULL OR v_unitparametername_arr && string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
                AND (v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op.assigned_ou_ids, ''), ','))
				-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
				AND
				(
					nullif(p_empname,'') is null or
					op.emp_name ILIKE '%'||COALESCE(nullif(p_empname,''), op.emp_name)||'%' OR
					op.mobile ILIKE '%'||COALESCE(nullif(p_empname,''), op.mobile)||'%' OR
					op.orgempcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.orgempcode)||'%' OR
					op.cjcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.cjcode)||'%'
				)
-- 				AND 
-- 				(
-- 					(ta.isactive = '1' AND p_att_purpose = 'Attendance' AND ta.attendance_salary_status = '0' AND ta.is_attendance_salary = p_att_purpose)  
-- 					OR  
-- 					(ta.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta.isactive = '0' AND ta.is_attendance_salary = p_att_purpose)
-- 				)
				AND (coalesce(nullif(p_status,''),'All')='All'
					 or(p_status = 'Verified' and  COALESCE(tblmonatt.approved_attendance, 0) > 0  and coalesce(tblmonatt.unapproved_attendance,0)=0)
					 or(p_status = 'Marked' and COALESCE(tblmonatt.marked_attendance, 0) > 0 AND COALESCE(tblmonatt.unapproved_attendance, 0) > 0)
					 or(p_status = 'UnMarked' and COALESCE(tblmonatt.marked_attendance,0) = 0 /*AND COALESCE(tblmonatt.approved_attendance, 0) = 0*/)
					)
				AND COALESCE(NULLIF(op.jobtype, ''), '') <> 'Unit Parameter'
		) AS X;

		-- Removed tblouemployees CTE for performance
			/*************Added for Change 3.9 starts*****************/			
			with tblmultipayout as(
										SELECT DISTINCT emp_code as taa2_emp_code
										FROM tbl_monthly_attendance
										where tbl_monthly_attendance.customeraccountid = p_customeraccountid
											and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
											and (isactive='1' or attendance_salary_status='1')
											and approval_status='A'
											and multipayoutrequestid<>0
											)
			,tbladvattendance as(
							SELECT DISTINCT emp_code as adv_emp_code
							FROM tbl_monthly_attendance
							where tbl_monthly_attendance.customeraccountid = p_customeraccountid
								and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
								and is_attendance_salary='Salary'
								and attendance_salary_status='1'
								and approval_status='A'
								) 
											
			/*************Added for Change 3.9 starts*****************/		

		SELECT array_to_json(
			array_agg(row_to_json(X))
		)
		INTO v_resultset2 FROM
		(
			SELECT
				op.emp_code,op.emp_name, coalesce(ta.approval_status,'N') approval_status, COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered)  emp_designation,
				coalesce(ta.marked_by_usertype,'') marked_by_usertype,
				case when tmf.emp_code is not null then 'WRP' ELSE coalesce(ta.attendance_type,'') END attendance_type,
				coalesce(nullif(tcd.document_path,'https://api.contract-jobs.com/crm_api/'),'') photopath,op.mobile,to_char(op.dateofbirth,'dd/mm/yyyy') dateofbirth,
				to_char(op.dateofjoining,'dd/mm/yyyy') dateofjoining,
				CASE WHEN e.timecriteria<>'Full Time'  then '' when coalesce(attendance_type,'AA') ='AA' then 'Abesnt' when ta.attendance_type in ('PP','HD','WFH','OD') then 'Present'  when attendance_type ='LL' then 'Leave' when attendance_type ='HO' then 'Holiday' END AS today_status,
				coalesce(tblmonatt.marked_attendance,0)||' Days' marked_attendance,
				CASE WHEN e.timecriteria='Full Time' then coalesce(tblmonatt.approved_attendance,0)||' Days' ELSE coalesce(tmf.salarydays::numeric(18,1),0)||' Days' END approved_attendance,
				coalesce(to_char(op.dateofrelieveing,'dd/mm/yyyy'),'') dateofrelieveing,
				CASE WHEN v_payout_mode_type='attendance' then 'Full Time' ELSE coalesce(nullif(e.timecriteria,''),'Full Time') END time_criteria, op.js_id::text js_id,
				COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered) post_offered, op.job_state stateName, e.salaryinhand::numeric(18)::text salaryinhand, e.ctc::text ctc,
				CASE WHEN coalesce(tblcmsd.empcode::bigint) is not null then 'Locked' ELSE 'Not Locked' END AS lockstatus,
				COALESCE(v_payout_with_attendance, 'PWA') AS payout_with_attendance, -- Change [3.3]
				ceiling(e.salaryinhand/e.salarydays) AS minperdayinhand, ceiling((e.salaryinhand/e.salarydays)/v_monthdays) AS maxperdayinhand,
				coalesce(e.salarydays,0)::text salarydays, (coalesce(tmf.inhandsalary,0)::numeric(18))::text salaryamount,
				CASE WHEN NULLIF(op.orgempcode, '') IS NULL THEN op.cjcode ELSE op.orgempcode END orgempcode, op.cjcode tp_code, tblvouchers.voucherdetails, leavedetails.*,
				CASE when pa.emp_code is null and tbl.emp_code is null  then 'N' WHEN COALESCE(tblmonatt.approved_attendance,0)>0 and coalesce(tblmonatt.unapproved_attendance,0)=0 THEN 'Y' ELSE 'N' END monthly_att_approval_status,
				e.salaryindaysopted salary_days_opted, coalesce(tblmonatt.attendance_paid_days, 0)::TEXT marked_attendance_paid_days,
				coalesce(tblmonatt.attendance_leave_taken, 0)::TEXT marked_attendance_leave_taken,
                COALESCE(ta.attendance_policy_id::TEXT, '') attendance_policy_id, COALESCE(ta.attendance_policy_type::TEXT, '') attendance_policy_type,
                COALESCE(ta.no_of_hours_worked::TEXT, '') no_of_hours_worked, COALESCE(ta.is_overtime::TEXT, '') is_overtime,
                COALESCE(ta.no_of_overtime_hours_worked::TEXT, '') no_of_overtime_hours_worked, COALESCE(ta.deviation_in_checkin::TEXT, '') deviation_in_checkin,
                COALESCE(ta.deviation_in_checkout::TEXT, '') deviation_in_checkout, COALESCE(ta.deviation_in_total_working_hours::TEXT, '') deviation_in_total_working_hours
				,(string_to_array(op.posting_department,'#'))[1]::varchar posting_department,COALESCE(eho.holiday_state_name::TEXT,'') holiday_state_name
				,(select string_agg(ton.org_unit_name,', ') 
							  from public.tbl_org_unit_geofencing ton 
							  where ton.id = ANY(string_to_array(op.assigned_ou_ids, ',')::int[])
							 ) as assignedous
			,e.taxes as tds
			,e.tdsmode
				,case when edl.emp_code is null then 'N' else 'Y' end as deviationpaystatus,COALESCE(pa.advicelockstatus,'Unlocked') as advicelockstatus,
				CASE WHEN tbl.emp_code IS NULL THEN 'Unlocked' ELSE 'Locked' END AS Payoutlockstatus,
				-- START - Change [3.6]
				op.assigned_ou_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id = ANY(string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), '0'), ',')::int[])) assignedous,
				op.assigned_geofence_ids, (select STRING_AGG(geo.org_unit_name::TEXT||CASE WHEN COALESCE(isenablegeofencing, 'N') = 'N' THEN ' [Disabled]' ELSE '' END, ', ') from tbl_org_unit_geofencing geo WHERE COALESCE(isenablegeofencing, 'N') = 'Y' AND geo.id = ANY(string_to_array(COALESCE(NULLIF(op.assigned_geofence_ids, ''), '0'), ',')::int[])) assigned_geofence_ids_name
			,ta.attendance_salary_status,COALESCE(ta.is_attendance_salary,p_att_purpose)is_attendance_salary,ta.isactive
				-- END - Change [3.6]
			,ta.payout_frequencytype
			,coalesce(multipayoutcount,0) multipayoutcount
			,case when tbladvattendance.adv_emp_code is not null then 'Y' else 'N' end as advattexists

			FROM openappointments op
			left join empsalaryregister es on es.appointment_id=op.emp_id and es.isactive='1' and COALESCE(es.salarysetupcriteria,'')<>'PieceRate'
			left join tbl_empl_holiday_state_mapping eho on eho.tp_account_id= op.customeraccountid and eho.emp_code= op.emp_code and eho.status = '1'
			LEFT JOIN tbl_monthly_attendance ta ON ta.emp_code=op.emp_code 
			
-- 			AND ta.isactive='1' 
			AND 
				(
					(ta.isactive = '1' AND p_att_purpose = 'Attendance' AND ta.attendance_salary_status = '0' AND ta.is_attendance_salary = p_att_purpose)  
					OR  
					(ta.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta.isactive = '0' AND ta.is_attendance_salary = p_att_purpose)
				)
			AND ta.att_date=v_att_date AND ta.approval_status=CASE WHEN nullif(p_approvalstatus,'') IS NULL THEN ta.approval_status ELSE p_approvalstatus END
			LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and account_id= op.customeraccountid
			LEFT JOIN tbl_candidate_documentlist tcd ON op.emp_id = tcd.candidate_id AND tcd.document_id = 17 AND tcd.active = 'Y'
			LEFT JOIN tbl_monthwise_flexi_attendance tmf ON op.emp_code=tmf.emp_code AND tmf.attendancemonth = v_month AND tmf.attendanceyear = v_year AND tmf.isactive='1'
			left join employee_deviation_lock edl on op.emp_code=edl.emp_code and edl.isactive='1' and edl.locyear=v_year and edl.locmonth=v_month
-- 			LEFT JOIN paymentadvice pa on pa.customeraccountid=op.customeraccountid and pa.emp_id = op.emp_id and pa.mprmonth = EXTRACT(MONTH FROM att_date) AND pa.mpryear = EXTRACT(YEAR FROM att_date) -- SIDDHARTH 
			LEFT JOIN (
			SELECT DISTINCT emp_code,advicelockstatus
			FROM paymentadvice
			WHERE paiddays > 0
			  AND attendancemode = 'MPR' and paymentadvice.customeraccountid = p_customeraccountid
				AND paymentadvice.mpryear = v_year AND paymentadvice.mprmonth = v_month
			ORDER BY emp_code DESC
		) pa ON pa.emp_code = op.emp_code
			LEFT JOIN (
				SELECT DISTINCT emp_code
				FROM tbl_monthlysalary
				  where paiddays > 0
				  AND attendancemode = 'MPR'
				  AND is_rejected = '0'
				and tbl_monthlysalary.mpryear = v_year AND tbl_monthlysalary.mprmonth = v_month
				ORDER BY emp_code DESC
			) tbl ON tbl.emp_code = op.emp_code 
			LEFT JOIN
			(
				SELECT
					ta2.emp_code ecode, count(*) marked_attendance, count(CASE WHEN approval_status='A' then 1 ELSE null END) AS approved_attendance,
					count(CASE WHEN approval_status='P' then 1 ELSE null END) AS unapproved_attendance,
					SUM(CASE WHEN attendance_type IN ('PP','HO','WO','WFH','OD') THEN 1.0 WHEN attendance_type in ('HD') THEN 0.5 END) attendance_paid_days,
					SUM(CASE WHEN attendance_type  ='LL' THEN 1 WHEN attendance_type='HD' AND NULLIF(leavetype,'') IS NOT NULL AND NULLIF(leavetype,'')<>'AA' THEN 0.5 ELSE 0.0 END) attendance_leave_taken
					,SUM(CASE WHEN multipayoutrequestid>0 THEN 1.0 else 0.0 END) multipayoutcount

				FROM tbl_monthly_attendance ta2
				INNER JOIN openappointments op2 ON ta2.emp_code=op2.emp_code
-- 				AND ta2.isactive='1'
				AND 
				(
					(ta2.isactive = '1' AND p_att_purpose = 'Attendance' AND ta2.attendance_salary_status = '0' AND ta2.is_attendance_salary = p_att_purpose)  
					OR  
					(ta2.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta2.isactive = '0' AND ta2.is_attendance_salary = p_att_purpose)
				)
			/*****************************************************/
		     left join tblouemployees on tblouemployees.ou_emp_code=op2.emp_code
			/*****************************************************/
				WHERE
					op2.customeraccountid=p_customeraccountid 
					and ta2.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
				--AND date_trunc('month',att_date)=date_trunc('month',to_date(p_attdate,'dd-mm-yyyy'))
					AND 
					( NULLIF(p_ou_ids, '') is null or tblouemployees.ou_emp_code is not null	
					/*	EXISTS
					(
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op2.assigned_ou_ids, ''), COALESCE(NULLIF(op2.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
						WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op2.assigned_ou_ids, ''), COALESCE(NULLIF(op2.geofencingid::TEXT, ''), '0')), ','))
					)*/
					)
					-- AND COALESCE(op2.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op2.geofencingid, 0) ELSE p_geofenceid END
				GROUP BY ta2.emp_code
			) tblmonatt ON op.emp_code=tblmonatt.ecode
			LEFT JOIN empsalaryregister e ON op.emp_id=e.appointment_id AND e.isactive='1'
			LEFT JOIN
			(
				SELECT distinct empcode
				FROM cmsdownloadedwages 
				WHERE mprmonth = v_month AND mpryear = v_year 
				AND isactive='1' AND attendancemode='MPR' --<>'Ledger'
			) tblcmsd ON op.emp_code = tblcmsd.empcode::bigint
			LEFT JOIN
			(
				SELECT tbl_employeeledger.emp_code,string_agg(mst_otherduction.deduction_name||':'||trunc(amount*(CASE WHEN mst_otherduction.masterledgername='Deduction' then -1 ELSE 1 END))::text||':'||tbl_employeeledger.remarks,'<br/>') AS voucherdetails
				FROM public.tbl_employeeledger 
				INNER JOIN mst_otherduction ON tbl_employeeledger.headid=mst_otherduction.id
				INNER JOIN openappointments op ON tbl_employeeledger.emp_code=op.emp_code AND op.customeraccountid=p_customeraccountid
				/*****************************************************/
				 left join tblouemployees on tblouemployees.ou_emp_code=op.emp_code
				/*****************************************************/
				WHERE
                    processmonth=v_month AND processyear=v_year AND tbl_employeeledger.isactive='1' AND headid<>6
                    AND 
					
					( NULLIF(p_ou_ids, '') is null or tblouemployees.ou_emp_code is not null
					
					/*EXISTS
					(
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
						WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
					)*/
					)
					-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
				GROUP BY tbl_employeeledger.emp_code
			) tblvouchers ON tblvouchers.emp_code=op.emp_code
			LEFT JOIN
			(
				SELECT * FROM get_leave_balance_by_account(p_account_id=>p_customeraccountid::text,p_att_month=>v_month::text,p_att_year=>v_year::text)
			) AS leavedetails ON op.emp_id=leavedetails.emp_id
			/*****************************************************/
		     left join tblouemployees on tblouemployees.ou_emp_code=op.emp_code
			 left join tblmultipayout on op.emp_code=tblmultipayout.taa2_emp_code --change 3.9
			 left join tbladvattendance  on tbladvattendance.adv_emp_code=op.emp_code											/*****************************************************/
			WHERE (es.id is not null or v_payout_mode_type='attendance' )  and
				op.customeraccountid=p_customeraccountid
				AND op.converted='Y' AND op.appointment_status_id in(11,14)
				AND (op.dateofjoining <= v_att_date)
				AND (op.dateofrelieveing is null or dateofrelieveing>=make_date(v_year, v_month, 1))
				AND (
					op.emp_name ILIKE '%'||COALESCE(nullif(p_empname,''), op.emp_name)||'%' OR
					op.mobile ILIKE '%'||COALESCE(nullif(p_empname,''), op.mobile)||'%' OR
					op.orgempcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.orgempcode)||'%' OR
					op.cjcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.cjcode)||'%'
				)
-- 			AND 
-- 				(
-- 					(ta.isactive = '1' AND p_att_purpose = 'Attendance' AND ta.attendance_salary_status = '0' AND ta.is_attendance_salary = p_att_purpose)  
-- 					OR  
-- 					(ta.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta.isactive = '0' AND ta.is_attendance_salary = p_att_purpose)
-- 				)
-- 				-- SIDDHARTH BANSAL 18/10/2024
-- 				AND (LOWER(p_post_offered) = 'all' OR LOWER(op.post_offered) = LOWER(p_post_offered))
-- 				AND (LOWER(p_posting_department) = 'all' OR LOWER((string_to_array(op.posting_department,'#'))[1]::varchar) = LOWER(p_posting_department))
-- 				--END
			  	-- SIDDHARTH BANSAL 05/11/2024
				AND (lower(p_post_offered) = 'all' OR lower(op.post_offered) = ANY (string_to_array(lower(p_post_offered), ',')))
                AND (lower(p_posting_department) = 'all' OR lower((string_to_array(op.posting_department, '#'))[1]::varchar) = ANY (string_to_array(lower(p_posting_department), ',')))
				AND
					( 	NULLIF(p_unitparametername, '') is null or  
					
					EXISTS
				(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
				))
				AND 
				( 
				NULLIF(p_ou_ids, '') is null or tblouemployees.ou_emp_code is not null
				/*EXISTS
				(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
				)*/
				)
				-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
				AND (p_attendancesource = 'all' 
					 or (
						 p_attendancesource = 'bulkexcel'
						 AND op.emp_code IN (select t3.emp_code from tbl_monthly_attendance t3
											WHERE t3.customeraccountid=p_customeraccountid 
											 --AND date_trunc('month', t3.att_date) = make_date(v_year,v_month,1)
											and t3.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
											-- and t3.isactive='1'
											AND 
											(
												(t3.isactive = '1' AND p_att_purpose = 'Attendance' AND t3.attendance_salary_status = '0' AND t3.is_attendance_salary = p_att_purpose)  
												OR  
												(t3.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND t3.isactive = '0' AND t3.is_attendance_salary = p_att_purpose)
											)
											 AND t3.attendancesource = 'bulkexcel'
				)))
				AND (coalesce(nullif(p_status,''),'All')='All'
					 or(p_status = 'Verified' and  COALESCE(tblmonatt.approved_attendance, 0) > 0  and coalesce(tblmonatt.unapproved_attendance,0)=0)
					 or(p_status = 'Marked' and COALESCE(tblmonatt.marked_attendance, 0) > 0 AND COALESCE(tblmonatt.unapproved_attendance, 0) > 0)
					 or(p_status = 'UnMarked' and COALESCE(tblmonatt.marked_attendance,0) = 0 /*AND COALESCE(tblmonatt.approved_attendance, 0) = 0*/)
					)
				AND COALESCE(NULLIF(op.jobtype, ''), '') <> 'Unit Parameter'
				ORDER BY op.emp_name, coalesce(op.orgempcode,'')
				LIMIT p_page_limit OFFSET p_page_limit * (p_page_no - 1)
		) AS X;
		OPEN v_rfc1 FOR
			SELECT v_resultset1 AS attendncesummary, v_resultset2 AS attendancedetail, v_payout_settings payout_settings;
		RETURN NEXT v_rfc1;
	END IF;

	IF p_action='GetEmployeerTodayRequiredAttendance' THEN	
		SELECT * FROM tbl_account WHERE id=p_customeraccountid INTO v_tbl_account;
		v_payout_mode_type:=v_tbl_account.payout_mode_type;
		SELECT payout_with_attendance INTO v_payout_with_attendance FROM tbl_employerpayoutdate WHERE customeracountid = p_customeraccountid AND isactive = '1' ORDER BY id DESC LIMIT 1; -- Change [3.3]

		v_month:=extract('month' FROM v_att_date)::int;
		v_year:=extract('year' FROM v_att_date)::int;
		v_monthdays:=extract ('day' FROM make_date(v_year::int, v_month::int, 1)+interval '1 month -1 day')::int;

		select null::date start_dt,null::date end_dt,null::int month_start_day,null::text month_direction into v_rec_payrolldates;
			if coalesce(p_month_direction,'N')='N' then
				v_rec_payrolldates.start_dt:=make_date(v_year::int, v_month::int,1);
				v_rec_payrolldates.end_dt:=(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date;
				v_rec_payrolldates.month_start_day:=1;
				v_rec_payrolldates.month_direction:='N';
			else
			v_month=p_month;
			v_year:=p_year;
		SELECT
			-- added by vinod dated. 23.06.2025
			CASE WHEN p_month_direction='F' THEN make_date(v_year::int, v_month::int,p_month_start_day)::date
								ELSE (make_date(v_year::int, v_month::int,p_month_start_day)- interval '1 month') END start_dt,
						 CASE WHEN p_month_direction='F' THEN (make_date(v_year::int, v_month::int,p_month_end_day)+ interval '1 month')::date 
						 ELSE make_date(v_year::int, v_month::int,p_month_end_day)::date  END  end_dt
				,p_month_start_day as month_start_day,p_month_direction as month_direction
			-- added closed 23.06.2025
			/* make_date(v_year::int, v_month::int, month_start_day)::date start_dt,
			(make_date(v_year::int, v_month::int, month_end_day) + INTERVAL '1 month')::date end_dt
			*/
		-- Change - END [3.3]
		into v_rec_payrolldates;
		end if;
		--Raise Notice 'v_rec_payrolldates.start_dt=%,v_rec_payrolldates.end_dt=%',v_rec_payrolldates.start_dt,v_rec_payrolldates.end_dt;
		/**********************Cross month 14-Feb-2024 ends***************************************************/	

		if coalesce(v_rec_payrolldates.month_start_day,0)>1 and coalesce(v_rec_payrolldates.month_direction,'N')='B' then
			v_nextmonthdays:=v_monthdays;
			v_monthdays:=date_part('day',make_date(v_year,v_month,1) - INTERVAL '1 DAY');
			--v_isbackward:='Y';
		end if;
		/**********************Cross month 14-Feb-2024 ends***************************************************/	

		SELECT max(coalesce(isattendancerequired,'Y')) INTO v_isattendancerequired
		FROM empsalaryregister e 
		INNER JOIN openappointments op ON e.appointment_id=op.emp_id
	  /*
			AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
			)
*/
		WHERE
			op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in (11,14)
			AND (op.dateofrelieveing is null or dateofrelieveing>=make_date(v_year, v_month, 1))
			AND v_att_date BETWEEN effectivefrom AND coalesce(effectiveto,v_att_date);

		v_isattendancerequired:=CASE WHEN coalesce(v_isattendancerequired,'Y')='N' then 'Manual' ELSE 'Auto' END;

		v_payout_settings:=CASE WHEN v_tbl_account.leavetemplateapplicableon='Employer' then v_tbl_account.payout_settings ELSE v_isattendancerequired END;

-- Removed tblouemployees CTE for performance
		SELECT 
			row_to_json(X)
		INTO v_resultset1 FROM
		(
			SELECT 
				v_tbl_account.tds_enablestatus,
				count(distinct op.emp_code) AS total_att,
				count(CASE WHEN attendance_type in ('PP','HD','WFH','OD') then 1 ELSE null END ) AS present_att,
				count(CASE WHEN attendance_type ='AA' then 1 ELSE null END ) AS absent_att,
				count(CASE WHEN attendance_type ='LL' then 1 ELSE null END ) AS Leave_att,
				v_payout_settings AS payout_settings,
				coalesce(count(distinct tmf.emp_code),0) AS workreportcount
			FROM openappointments op 
			LEFT JOIN public.tbl_monthly_attendance ta ON ta.emp_code=op.emp_code AND ta.att_date=v_att_date
			AND 
			(
				(ta.isactive = '1' AND p_att_purpose = 'Attendance' AND ta.attendance_salary_status = '0' AND ta.is_attendance_salary = p_att_purpose)  
				OR  
				(ta.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta.isactive = '0' AND ta.is_attendance_salary = p_att_purpose)
			)
			LEFT JOIN tbl_monthwise_flexi_attendance tmf ON op.emp_code=tmf.emp_code AND tmf.attendanceyear=v_year AND tmf.attendancemonth=v_month AND tmf.isactive='1'
			LEFT JOIN
			(
				SELECT
					ta2.emp_code ecode, count(*) marked_attendance, count(CASE WHEN approval_status='A' then 1 ELSE null END) AS approved_attendance,
							count(CASE WHEN approval_status='P' then 1 ELSE null END) AS unapproved_attendance,
					SUM(CASE WHEN attendance_type IN ('PP','HO','WO','WFH','OD') THEN 1.0 WHEN attendance_type in ('HD') THEN 0.5 END) attendance_paid_days,
					SUM(CASE WHEN attendance_type  ='LL' THEN 1 WHEN attendance_type='HD' AND NULLIF(leavetype,'') IS NOT NULL AND NULLIF(leavetype,'')<>'AA' THEN 0.5 ELSE 0.0 END) attendance_leave_taken
				FROM tbl_monthly_attendance ta2
				INNER JOIN openappointments op2 ON ta2.emp_code=op2.emp_code 
				AND 
				(
					(ta2.isactive = '1' AND p_att_purpose = 'Attendance' AND ta2.attendance_salary_status = '0' AND ta2.is_attendance_salary = p_att_purpose)  
					OR  
					(ta2.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta2.isactive = '0' AND ta2.is_attendance_salary = p_att_purpose)
				)
				
				WHERE
					op2.customeraccountid=p_customeraccountid 
					and ta2.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
					AND ( v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op2.assigned_ou_ids, ''), ',') )
				GROUP BY ta2.emp_code
			) tblmonatt ON op.emp_code=tblmonatt.ecode
				left join(
							SELECT tbl_monthly_attendance.emp_code taa_empcode
							FROM tbl_monthly_attendance inner join openappointments op 
							on tbl_monthly_attendance.emp_code=op.emp_code
							and op.customeraccountid = p_customeraccountid
							where tbl_monthly_attendance.customeraccountid = p_customeraccountid
								and att_date between greatest(v_rec_payrolldates.start_dt,op.dateofjoining) and least(v_rec_payrolldates.end_dt,coalesce(op.dateofrelieveing,v_rec_payrolldates.end_dt))
								and attendance_salary_status='1'
								and lower(is_attendance_salary)='salary'
					group by tbl_monthly_attendance.emp_code
					)tmpsalary_att
					on op.emp_code=tmpsalary_att.taa_empcode
			/*****************************************************/	
			WHERE 
				op.customeraccountid=p_customeraccountid AND op.converted='Y' AND op.appointment_status_id in(11,14)
				AND (op.dateofjoining <= v_att_date)
				AND (op.dateofrelieveing is null or dateofrelieveing>=make_date(v_year, v_month, 1))
				AND (lower(p_post_offered) = 'all' OR lower(op.post_offered) = ANY (v_post_offered_arr))
                AND (lower(p_posting_department) = 'all' OR lower((string_to_array(op.posting_department, '#'))[1]::varchar) = ANY (v_posting_department_arr))
				AND (v_unitparametername_arr IS NULL OR v_unitparametername_arr && string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
                AND (v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op.assigned_ou_ids, ''), ','))
				AND
				(	nullif(p_empname,'') is null or
					op.emp_name ILIKE '%'||COALESCE(nullif(p_empname,''), op.emp_name)||'%' OR
					op.mobile ILIKE '%'||COALESCE(nullif(p_empname,''), op.mobile)||'%' OR
					op.orgempcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.orgempcode)||'%' OR
					op.cjcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.cjcode)||'%'
				)
				AND (coalesce(nullif(p_status,''),'All')='All'
					 or(p_status = 'Verified' and  COALESCE(tblmonatt.approved_attendance, 0) > 0  and coalesce(tblmonatt.unapproved_attendance,0)=0)
					 or(p_status = 'Marked' and COALESCE(tblmonatt.marked_attendance, 0) > 0 AND COALESCE(tblmonatt.unapproved_attendance, 0) > 0)
					 or(p_status = 'UnMarked' and COALESCE(tblmonatt.marked_attendance,0) = 0 /*AND COALESCE(tblmonatt.approved_attendance, 0) = 0*/)
					)
				AND COALESCE(NULLIF(op.jobtype, ''), '') <> 'Unit Parameter'
				and not (p_att_purpose = 'Attendance' and tmpsalary_att.taa_empcode is not null)

		) AS X;
RAISE NOTICE 'TEST 1';
-- Removed tblouemployees CTE for performance
		SELECT array_to_json(
			array_agg(row_to_json(X))
		)
		INTO v_resultset2 FROM
		(
		 -- op.post_offered
			SELECT
				op.emp_code,op.emp_name, COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered)  emp_designation,
				case when tmf.emp_code is not null then 'WRP' ELSE coalesce(ta.attendance_type,'') END attendance_type,
				coalesce(nullif(tcd.document_path,'http://1akal.in/crm_api/'),'') photopath,
				op.mobile,to_char(op.dateofbirth,'dd/mm/yyyy') dateofbirth,
				to_char(op.dateofjoining,'dd/mm/yyyy') dateofjoining,
				coalesce(to_char(op.dateofrelieveing,'dd/mm/yyyy'),'') dateofrelieveing,
				CASE WHEN v_payout_mode_type='attendance' then 'Full Time' ELSE coalesce(nullif(e.timecriteria,''),'Full Time') END time_criteria, op.js_id::text js_id,
				COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered) post_offered, op.job_state stateName,
				CASE WHEN coalesce(tblcmsd.empcode::bigint) is not null then 'Locked' ELSE 'Not Locked' END AS lockstatus,
				COALESCE(v_payout_with_attendance, 'PWA') AS payout_with_attendance, -- Change [3.3]
				coalesce(e.salarydays,0)::text salarydays,
				op.orgempcode, op.cjcode tp_code, tblvouchers.voucherdetails,
				leavedetails.template_name,leavedetails.comp_off_txt,leavedetails.balance_txt,
				leavedetails.leave_bank_id,
				op.emp_id,op.customeraccountid as account_id,
				e.salaryindaysopted salary_days_opted,
				CASE WHEN COALESCE(tblmonatt.approved_attendance,0)>0 and coalesce(tblmonatt.unapproved_attendance,0)=0 THEN 'Y' ELSE 'N' END monthly_att_approval_status,
				--e.salaryindaysopted salary_days_opted,
				coalesce(tblmonatt.attendance_paid_days, 0)::TEXT marked_attendance_paid_days,
				coalesce(tblmonatt.attendance_leave_taken, 0)::TEXT marked_attendance_leave_taken,
				CASE WHEN e.timecriteria='Full Time' then coalesce(tblmonatt.approved_attendance,0)||' Days' ELSE coalesce(tmf.salarydays::numeric(18,1),0)||' Days' END approved_attendance,
                --COALESCE(ta.attendance_policy_id::TEXT, '') attendance_policy_id, COALESCE(ta.attendance_policy_type::TEXT, '') attendance_policy_type,
                --OALESCE(ta.no_of_hours_worked::TEXT, '') no_of_hours_worked, COALESCE(ta.is_overtime::TEXT, '') is_overtime,
                --COALESCE(ta.no_of_overtime_hours_worked::TEXT, '') no_of_overtime_hours_worked, COALESCE(ta.deviation_in_checkin::TEXT, '') deviation_in_checkin,
                --COALESCE(ta.deviation_in_checkout::TEXT, '') deviation_in_checkout,
				--COALESCE(ta.deviation_in_total_working_hours::TEXT, '') deviation_in_total_working_hours,
				(string_to_array(op.posting_department,'#'))[1]::varchar posting_department,COALESCE(eho.holiday_state_name::TEXT,'') holiday_state_name
				,case when edl.emp_code is null then 'N' else 'Y' end as deviationpaystatus,COALESCE(pa.advicelockstatus,'Unlocked') as advicelockstatus,
				CASE WHEN tbl.emp_code IS NULL THEN 'Unlocked' ELSE 'Locked' END AS Payoutlockstatus,
				-- START - Change [3.6]
				op.assigned_ou_ids, (select STRING_AGG(geo.org_unit_name::TEXT, ', ') from tbl_org_unit_geofencing geo WHERE geo.id = ANY(string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), '0'), ',')::int[])) assignedous,
				op.assigned_geofence_ids, (select STRING_AGG(geo.org_unit_name::TEXT||CASE WHEN COALESCE(isenablegeofencing, 'N') = 'N' THEN ' [Disabled]' ELSE '' END, ', ') from tbl_org_unit_geofencing geo WHERE COALESCE(isenablegeofencing, 'N') = 'Y' AND geo.id = ANY(string_to_array(COALESCE(NULLIF(op.assigned_geofence_ids, ''), '0'), ',')::int[])) assigned_geofence_ids_name
				,ta.attendance_salary_status,
				COALESCE(ta.is_attendance_salary,p_att_purpose)is_attendance_salary--,ta.isactive
				,mispunch_days,swl_days
			,greatest(0,(case when e.salaryindaysopted='Y' then e.salarydays else v_monthdays end)-coalesce(attendance_paid_days,0)-coalesce(attendance_leave_taken,0)) absent_days
			,coalesce(attendance_paid_days,0)+coalesce(attendance_leave_taken,0) total_paid_days
			,coalesce(absentmarkeddays_days,0) absentmarkeddays_days
			,coalesce(multipayoutcount,0) multipayoutcount
			FROM openappointments op
			left join tbl_empl_holiday_state_mapping eho on eho.tp_account_id= op.customeraccountid and eho.emp_code= op.emp_code and eho.status = '1'
			LEFT JOIN tbl_monthly_attendance ta ON ta.emp_code=op.emp_code 
			AND 
				(
					(ta.isactive = '1' AND p_att_purpose = 'Attendance' AND ta.attendance_salary_status = '0' AND ta.is_attendance_salary = p_att_purpose)  
					OR  
					(ta.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta.isactive = '0' AND ta.is_attendance_salary = p_att_purpose)
				)
			AND ta.att_date=v_att_date AND ta.approval_status=CASE WHEN nullif(p_approvalstatus,'') IS NULL THEN ta.approval_status ELSE p_approvalstatus END
			LEFT JOIN tbl_candidate_documentlist tcd ON op.emp_id = tcd.candidate_id AND tcd.document_id = 17 AND tcd.active = 'Y'
			LEFT JOIN tbl_monthwise_flexi_attendance tmf ON op.emp_code=tmf.emp_code AND tmf.attendancemonth = v_month AND tmf.attendanceyear = v_year AND tmf.isactive='1'
			left join employee_deviation_lock edl on op.emp_code=edl.emp_code and edl.isactive='1' and edl.locyear=v_year and edl.locmonth=v_month
			LEFT JOIN (
			SELECT DISTINCT emp_code,advicelockstatus
			FROM paymentadvice
			WHERE paiddays > 0
			  AND attendancemode = 'MPR' and paymentadvice.customeraccountid = p_customeraccountid
				AND paymentadvice.mpryear = v_year AND paymentadvice.mprmonth = v_month
			ORDER BY emp_code DESC
		) pa ON pa.emp_code = op.emp_code
			LEFT JOIN(
				SELECT DISTINCT emp_code
				FROM tbl_monthlysalary
				  where paiddays > 0
				  AND attendancemode = 'MPR'
				  AND is_rejected = '0'
				and tbl_monthlysalary.mpryear = v_year AND tbl_monthlysalary.mprmonth = v_month
				ORDER BY emp_code DESC
			) tbl ON tbl.emp_code = op.emp_code 
			LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and mtd_designation.account_id= op.customeraccountid
			LEFT JOIN
			(
				SELECT
					ta2.emp_code ecode, count(*) marked_attendance, count(CASE WHEN approval_status='A' then 1 ELSE null END) AS approved_attendance,
					count(CASE WHEN approval_status='P' then 1 ELSE null END) AS unapproved_attendance,
					SUM(CASE WHEN attendance_type IN ('PP','HO','WO','WFH','OD','TR','ASL') THEN 1.0 WHEN attendance_type in ('HD') THEN 0.5 END) attendance_paid_days,
					SUM(case when attendance_type  ='LL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 1 when attendance_type='HD' and nullif(leavetype,'') is not null and nullif(leavetype,'')<>'AA' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 when attendance_type  ='HL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 else 0.0 end) attendance_leave_taken
				--,SUM(CASE WHEN attendance_type IN ('MP') THEN 1.0 else 0.0 END) mispunch_days
				,SUM(CASE WHEN attendance_type IN ('MP') OR att_catagory in ('SP','DE','MP') THEN 1.0 else 0.0 END) mispunch_days
				,SUM(CASE WHEN attendance_type IN ('SWL') THEN 1.0 else 0 END) swl_days
				,SUM(CASE WHEN attendance_type IN ('AA') THEN 1.0 else 0.0 END) absentmarkeddays_days

				,SUM(CASE WHEN multipayoutrequestid>0 THEN 1.0 else 0.0 END) multipayoutcount
				FROM tbl_monthly_attendance ta2
				INNER JOIN openappointments op2 ON ta2.emp_code=op2.emp_code
				AND 
				(
					(ta2.isactive = '1' AND p_att_purpose = 'Attendance' AND ta2.attendance_salary_status = '0' AND ta2.is_attendance_salary = p_att_purpose)  
					OR  
					(ta2.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND ta2.isactive = '0' AND ta2.is_attendance_salary = p_att_purpose)
				)
			/*****************************************************/
			/*****************************************************/
			
			

				WHERE
					op2.customeraccountid=p_customeraccountid 
					and ta2.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt	 								   
					AND ( v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op2.assigned_ou_ids, ''), ',') )
				GROUP BY ta2.emp_code
			) tblmonatt ON op.emp_code=tblmonatt.ecode
			LEFT JOIN empsalaryregister e ON op.emp_id=e.appointment_id AND e.isactive='1'
			LEFT JOIN
			(
				SELECT distinct empcode
				FROM cmsdownloadedwages 
				WHERE mprmonth = v_month AND mpryear = v_year 
				AND isactive='1' AND attendancemode='MPR' --<>'Ledger'
			) tblcmsd ON op.emp_code = tblcmsd.empcode::bigint
			LEFT JOIN
			(
				SELECT tbl_employeeledger.emp_code,string_agg(mst_otherduction.deduction_name||':'||trunc(amount*(CASE WHEN mst_otherduction.masterledgername='Deduction' then -1 ELSE 1 END))::text||':'||tbl_employeeledger.remarks,'<br/>') AS voucherdetails
				FROM public.tbl_employeeledger 
				INNER JOIN mst_otherduction ON tbl_employeeledger.headid=mst_otherduction.id
				INNER JOIN openappointments op ON tbl_employeeledger.emp_code=op.emp_code AND op.customeraccountid=p_customeraccountid
				WHERE
                    processmonth=v_month AND processyear=v_year AND tbl_employeeledger.isactive='1' AND headid<>6									   
                    AND ( v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op.assigned_ou_ids, ''), ',') )
				GROUP BY tbl_employeeledger.emp_code
			) tblvouchers ON tblvouchers.emp_code=op.emp_code
			LEFT JOIN
			(
				SELECT * FROM get_leave_balance_by_account(p_account_id=>p_customeraccountid::text,p_att_month=>v_month::text,p_att_year=>v_year::text)
			) AS leavedetails ON op.emp_id=leavedetails.emp_id
			/*****************************************************/
				left join(
							SELECT tbl_monthly_attendance.emp_code taa_empcode
							FROM tbl_monthly_attendance inner join openappointments op 
							on tbl_monthly_attendance.emp_code=op.emp_code
							and op.customeraccountid = p_customeraccountid
							where tbl_monthly_attendance.customeraccountid = p_customeraccountid
								and att_date between greatest(v_rec_payrolldates.start_dt,op.dateofjoining) and least(v_rec_payrolldates.end_dt,coalesce(op.dateofrelieveing,v_rec_payrolldates.end_dt))
								and attendance_salary_status='1'
								and lower(is_attendance_salary)='salary'
					group by tbl_monthly_attendance.emp_code
					)tmpsalary_att
					on op.emp_code=tmpsalary_att.taa_empcode
			/*****************************************************/
			WHERE
				op.customeraccountid=p_customeraccountid
				AND op.converted='Y' AND op.appointment_status_id in(11,14)
				AND (op.dateofjoining <= v_att_date)
				AND (op.dateofrelieveing is null or dateofrelieveing>=make_date(v_year, v_month, 1))
				AND (nullif(p_empname,'') is null or
					op.emp_name ILIKE '%'||COALESCE(nullif(p_empname,''), op.emp_name)||'%' OR
					op.mobile ILIKE '%'||COALESCE(nullif(p_empname,''), op.mobile)||'%' OR
					op.orgempcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.orgempcode)||'%' OR
					op.cjcode ILIKE '%'||COALESCE(nullif(p_empname,''), op.cjcode)||'%'
				)
				AND (lower(p_post_offered) = 'all' OR lower(op.post_offered) = ANY (v_post_offered_arr))
                AND (lower(p_posting_department) = 'all' OR lower((string_to_array(op.posting_department, '#'))[1]::varchar) = ANY (v_posting_department_arr))

				AND 
			(
				NULLIF(p_unitparametername, '') is null
				 or v_unitparametername_arr && string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ',')
			 )
									
				AND (v_ou_ids_arr IS NULL OR v_ou_ids_arr && string_to_array(NULLIF(op.assigned_ou_ids, ''), ','))
				AND (p_attendancesource = 'all' 
					 or (
						 p_attendancesource = 'bulkexcel'
						 AND op.emp_code IN (select t3.emp_code from tbl_monthly_attendance t3
											WHERE t3.customeraccountid=p_customeraccountid 
											and t3.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
											AND 
											(
												(t3.isactive = '1' AND p_att_purpose = 'Attendance' AND t3.attendance_salary_status = '0' AND t3.is_attendance_salary = p_att_purpose)  
												OR  
												(t3.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND t3.isactive = '0' AND t3.is_attendance_salary = p_att_purpose)
											)
											 AND t3.attendancesource = 'bulkexcel'
				)))
				AND (coalesce(nullif(p_status,''),'All')='All'
					 or(p_status = 'Verified' and  COALESCE(tblmonatt.approved_attendance, 0) > 0  and coalesce(tblmonatt.unapproved_attendance,0)=0)
					 or(p_status = 'Marked' and COALESCE(tblmonatt.marked_attendance, 0) > 0 AND COALESCE(tblmonatt.unapproved_attendance, 0) > 0)
					 or(p_status = 'UnMarked' and COALESCE(tblmonatt.marked_attendance,0) = 0 /*AND COALESCE(tblmonatt.approved_attendance, 0) = 0*/)
					)
				AND COALESCE(NULLIF(op.jobtype, ''), '') <> 'Unit Parameter'
			and not (p_att_purpose = 'Attendance' and tmpsalary_att.taa_empcode is not null)
				ORDER BY op.emp_name, coalesce(op.orgempcode,'')
				LIMIT p_page_limit OFFSET p_page_limit * (p_page_no - 1)
		) AS X;
RAISE NOTICE 'TEST 2';
		OPEN v_rfc1 FOR
			SELECT v_resultset1 AS attendncesummary, v_resultset2 AS attendancedetail, v_payout_settings payout_settings;
		RETURN NEXT v_rfc1;
	END IF;
END;
$BODY$;

ALTER FUNCTION public.uspgetemployertodayattendance_business(character varying, bigint, text, text, text, integer, text, character varying, integer, integer, character varying, text, text, text, text, integer, integer, character varying, integer, integer)
    OWNER TO payrollingdb;

ALTER FUNCTION public.uspgetemployertodayattendance_business(character varying, bigint, text, text, text, integer, text, character varying, integer, integer, character varying, text, text, text, text, integer, integer, character varying, integer, integer)
    SET plan_cache_mode = force_custom_plan;

