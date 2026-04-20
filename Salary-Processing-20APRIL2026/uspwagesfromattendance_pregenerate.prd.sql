-- FUNCTION: public.uspwagesfromattendance_pregenerate(character varying, bigint, bigint, character varying, integer, integer, character varying, numeric, bigint)

-- DROP FUNCTION IF EXISTS public.uspwagesfromattendance_pregenerate(character varying, bigint, bigint, character varying, integer, integer, character varying, numeric, bigint);

CREATE OR REPLACE FUNCTION public.uspwagesfromattendance_pregenerate(
	p_action character varying,
	p_emp_code bigint,
	p_createdby bigint,
	p_createdbyip character varying,
	p_month integer,
	p_year integer,
	p_salmode character varying DEFAULT 'Actual'::character varying,
	p_paiddays numeric DEFAULT 0.0,
	p_multipayoutrequestid bigint DEFAULT 0)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
	v_isattendancerequired varchar(1);
	v_monthdays double precision;
	v_paiddays double precision;
	v_leavetaken double precision;
	v_rfc refcursor;
	v_isattendancerequiredemployee varchar(30);
	v_isattendancerequiredemployer varchar(30);
	v_currentmonthstartdate varchar(12);
	v_currentmonthenddate varchar(12);
	v_joiningdayspast int:=0;
	v_relievingdays int:=0;
	v_doj date;
	v_dor date;
	v_rec_payrolldates record;
	v_customeraccountid bigint;
	v_rec_attendance record;
	v_advice_attendancerecord text;
	v_default_shift_full_hours text;
	v_working_minutes numeric(10,2);
	v_shift_minutes numeric(10,2);
	v_advance_or_current text:='Current';
	
	v_user_specific_setting record;
	v_working_leaves numeric(10,2);

	-- START - Get Break Details
	v_total_break_paid INTERVAL := INTERVAL '0 minutes';
	v_total_break_unpaid INTERVAL := INTERVAL '0 minutes';
	v_break_record JSONB;
	v_break_duration_text TEXT;
	v_break_duration INTERVAL;
	v_break_paid_flag TEXT;
	-- END - Get Break Details
	v_monthpresentdays  numeric(10,2);
	v_fullmonthincentive numeric:=0.0;
	v_empsalaryregister empsalaryregister%rowtype;

BEGIN
/*************************************************************************
Version Date			Change								Done_by
1.0						Initial Version						Shiv Kumar
1.1		10-Apr-2023		Attendance required on the basis	Shiv Kumar
						of Payment mode Manual/Auto
1.2		04-Sep-2024		Change hrgenerated as per month		Shiv Kumar
1.3		14-Feb-2025		Cross Month Attendance				Shiv Kumar
1.4		04-March-2025	Cross Month Start date and end date changes				Parveen Kumar
1.5		05-May-2025		Payment Advice directly to Salary	Shiv Kumar
1.6		07-May-2025		Ignore Attendance before DOJ and 	Shiv Kumar
						After Date of relieveing
1.7		28-May-2025		Tax calculation as a rule			Shiv Kumar
1.8		27-Jun-2025		Change Hourly Calculation			Shiv Kumar
1.9		30-Aug-2025		Multipayout for both hourly and 	Shiv Kumar
						monthly setup
1.10	10-Nov-2025		Full Month Attendance Incentive		Shiv Kumar
1.11	21-Nov-2025		Add Advance Shift Changes to get the shift timing		Parveen Kumar
1.12	21-Nov-2025		As per verbal discussion with Yatin Sir 		Shiv Kumar
						If Hourly setup and Holiday or PP then One Day salary Added
						and setting is for all employers
1.13	02-Dec-2025		Add flexiblemonthdays					Shiv Kumar
1.14	20-Mar-2026		Add customeraccountid check 
						to monthly Attendance					Antigravity [Vinod]
*************************************************************************/
-- STEP 1: Verify geofencing rules - Exit entirely if employee belongs to an "Attendance Leave Only" org unit
if not EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array((select COALESCE(COALESCE(NULLIF(op.assigned_ou_ids, ''),'0')) from openappointments op where op.emp_code=p_emp_code), ',')) AS input_ou_ids
		WHERE input_ou_ids::bigint in (select id from tbl_org_unit_geofencing where is_attendance_leave_only='Y')
		) then
	
	v_currentmonthstartdate:=(p_year::text||'-'||lpad(p_month::text,2,'0')||'-01');
	v_currentmonthenddate:=to_char((v_currentmonthstartdate::date+interval '1 month'-interval '1 day'),'yyyy-mm-dd');
	
	select dateofjoining,dateofrelieveing,customeraccountid from openappointments where emp_code=p_emp_code into v_doj,v_dor,v_customeraccountid;
v_monthdays:=date_part('day',DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');

/**********************change 1.35 starts***************************************************/
-- select  (make_date(p_year::int, p_month::int,month_start_day)- interval '1 month')::date start_dt
-- , make_date(p_year::int, p_month::int,month_end_day)::date  end_dt
-- Change - START [1.4]
-- STEP 2: Fetch and align Custom Payroll Date Cycles defined by customer account (e.g. 26th to 25th)
SELECT

-- added by vinod dated. 23.06.2025
		CASE WHEN month_direction='F' THEN make_date(p_year::int, p_month::int,month_start_day)::date
		ELSE (make_date(p_year::int, p_month::int,month_start_day)- interval '1 month') END start_dt,
		CASE WHEN month_direction='F' THEN (make_date(p_year::int, p_month::int,month_end_day)+ interval '1 month')::date 
		ELSE make_date(p_year::int, p_month::int,month_end_day)::date  END end_dt
		-- vinod end   23.06.2025
		
	/* make_date(p_year::int, p_month::int, month_start_day)::date start_dt,
	(make_date(p_year::int, p_month::int, month_end_day) + INTERVAL '1 month')::date end_dt*/
-- Change - END [1.4]
into v_rec_payrolldates
from mst_account_custom_month_settings 
where account_id= v_customeraccountid and status='1'  AND month_start_day <>0;
v_rec_payrolldates.start_dt:=coalesce(v_rec_payrolldates.start_dt,make_date(p_year::int, p_month::int,1));
v_rec_payrolldates.end_dt:=coalesce(v_rec_payrolldates.end_dt,(make_date(p_year::int, p_month::int,1)+ interval '1 month -1 day')::date);
--Raise Notice 'v_rec_payrolldates.start_dt=%,v_rec_payrolldates.end_dt=%',v_rec_payrolldates.start_dt,v_rec_payrolldates.end_dt;
/**********************change 1.35 ends***************************************************/	
	-- STEP 3: Adjust attendance bounds for mid-month Joiners (DOJ) and Leavers (DOR)
	if (to_char(v_doj,'mmyyyy'))=(lpad(p_month::text,2,'0')||p_year::text) then
			v_joiningdayspast:=(to_char(v_doj,'dd')::int)-1;
	end if;
	v_joiningdayspast:=coalesce(v_joiningdayspast,0);
	
	if (to_char(v_dor,'mmyyyy'))=(lpad(p_month::text,2,'0')||p_year::text) then
			v_relievingdays:=(extract ('day' from v_currentmonthenddate::date)::int-extract('day' from v_dor)::int);
	end if;
	v_relievingdays:=coalesce(v_relievingdays,0);

		if p_action='GenerateWages_pregenerate' then

		select case when ta.leavetemplateapplicableon='Employer' then ta.payout_settings else 'Manual' end
		from tbl_account ta where ta.id=(select customeraccountid from openappointments where emp_code=p_emp_code)
		into v_isattendancerequiredemployer;

		select e.* --isattendancerequired
		FROM empsalaryregister e inner join openappointments op
					on e.appointment_id=op.emp_id and op.emp_code=p_emp_code
					where op.converted='Y' and op.appointment_status_id=11		
					and (op.dateofrelieveing is null or dateofrelieveing>=v_currentmonthstartdate::date)
					and  v_currentmonthenddate::date between effectivefrom and coalesce(effectiveto,v_currentmonthenddate::date)
					order by e.id desc limit 1
		 into v_empsalaryregister; --v_isattendancerequiredemployee;
	v_isattendancerequiredemployee:=v_empsalaryregister.isattendancerequired;
	
/***********************Check Approved and unapproved attendance*********************/	
	-- STEP 4: Poll `tbl_monthly_attendance` to segregate approved and unapproved logs within processing dates
	if exists(select 1 from tbl_monthly_attendance 
		where customeraccountid=v_customeraccountid and emp_code=p_emp_code and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
		and attendance_salary_status='1' and is_attendance_salary='Salary' and approval_status='A'
		and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)) then 
	select count(case when approval_status='A' then 1 else null end) as approved_attendance,
		count(case when coalesce(approval_status,'')<>'A' then 1 else null end) as unapproved_attendance	
					from tbl_monthly_attendance 
					where customeraccountid=v_customeraccountid and emp_code=p_emp_code
					and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
					--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
					and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
					and attendance_salary_status='1'
					and lower(is_attendance_salary)='salary' 
into v_rec_attendance;

else
select count(case when approval_status='A' then 1 else null end) as approved_attendance,
		count(case when coalesce(approval_status,'')<>'A' then 1 else null end) as unapproved_attendance	
					from tbl_monthly_attendance 
					where customeraccountid=v_customeraccountid and emp_code=p_emp_code
						and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
					--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
					and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
					and isactive='1'
into v_rec_attendance;				
		
end if;

/***********************Check Approved and unapproved attendance ends here*********************/	
		if p_salmode='Provisional' then
			v_paiddays:=p_paiddays;
			v_leavetaken:=0;
			v_advance_or_current:='Current';
		else	/****************Attendance Not Required Block************************************/  			
			-- STEP 5: Auto/Fixed Mode - bypass detailed attendance matching; assign full month days directly minus join/leave offsets
			if v_isattendancerequiredemployer='Auto' or v_isattendancerequiredemployee='N' then 
				select (case when e.salaryindaysopted='Y' then e.salarydays else v_monthdays end) as salarydays
					FROM empsalaryregister e inner join openappointments op
					on e.appointment_id=op.emp_id and op.emp_code=p_emp_code
					where op.converted='Y' and op.appointment_status_id=11		
					and (op.dateofrelieveing is null or dateofrelieveing>=v_currentmonthstartdate::date)
					and  v_currentmonthenddate::date between effectivefrom and coalesce(effectiveto,v_currentmonthenddate::date)
					order by e.id desc limit 1
					into v_paiddays;
					
					v_paiddays:=coalesce(v_paiddays-coalesce(v_joiningdayspast,0),0)-v_relievingdays;
					v_leavetaken:=0;
			else
			
			/****************Hourly Setup Block************************************/  
			-- STEP 6: Hourly Setup - calculate rigorous base shift durations fetching dynamic break policies and settings
			if exists(select * from openappointments op inner join empsalaryregister e on op.emp_id=e.appointment_id and op.emp_code=p_emp_code and e.ishourlysetup='Y' and e.isactive='1') then
			    -- select default_shift_full_hours from vw_user_spc_emp where emp_code=p_emp_code into v_default_shift_full_hours;
				-- v_default_shift_full_hours:=coalesce(v_default_shift_full_hours,'08:00');
				 -- v_shift_minutes:=((left(trim(v_default_shift_full_hours),2)::numeric)*60+(substring(trim(v_default_shift_full_hours),4,2)::int))::numeric(18,4);

				SELECT * FROM vw_user_spc_emp WHERE emp_code::bigint = p_emp_code AND is_active='1' INTO v_user_specific_setting;

				IF v_user_specific_setting.minimum_working_hours_required_for_day = 'Strict' THEN
					IF v_user_specific_setting.manual_input_shift_hours = 'manual_input' THEN
						v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.full_day_time::INTERVAL)/60;
					ELSIF v_user_specific_setting.manual_input_shift_hours = 'shift_hours' OR v_user_specific_setting.manual_input_shift_hours = 'shift_hrs' THEN
						v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.default_shift_full_hours::INTERVAL)/60;
					END IF;
				END IF;

				IF v_user_specific_setting.minimum_working_hours_required_for_day = 'Lenient' THEN
					IF v_user_specific_setting.manual_input_shift_hours = 'manual_input_len' THEN
						v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.per_day_time::INTERVAL)/60;
					ELSIF v_user_specific_setting.manual_input_shift_hours = 'shift_hours_len' THEN
						v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.default_shift_full_hours::INTERVAL)/60;
					END IF;
				END IF;

				-- START CHANGE [1.11] - Get Shift Time from the Advance Shift Changes if v_shift_minutes is Null or 0
					IF v_shift_minutes IS NULL OR v_shift_minutes = 0 THEN
						SELECT * FROM vw_shifts_emp_wise WHERE emp_code::bigint = p_emp_code AND is_active='1' INTO v_user_specific_setting;
						IF v_user_specific_setting.min_working_hrs_request_mode = 'Strict' THEN
							IF v_user_specific_setting.min_working_hrs_request_mode_type = 'manual_input' OR v_user_specific_setting.min_working_hrs_request_mode_type = 'manual' THEN
								v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.strict_manual_full_day_hrs::INTERVAL)/60;
							ELSIF v_user_specific_setting.min_working_hrs_request_mode_type = 'shift_hours' OR v_user_specific_setting.min_working_hrs_request_mode_type = 'shift_hrs' THEN
								v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.default_shift_full_hours::INTERVAL)/60;
							END IF;
						END IF;

						IF v_user_specific_setting.min_working_hrs_request_mode = 'Lenient' THEN
							IF v_user_specific_setting.min_working_hrs_request_mode_type = 'manual_input_len' OR v_user_specific_setting.min_working_hrs_request_mode_type = 'manual' THEN
								v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.lenient_per_day_hrs::INTERVAL)/60;
							ELSIF v_user_specific_setting.min_working_hrs_request_mode_type = 'shift_hours_len' OR v_user_specific_setting.min_working_hrs_request_mode_type = 'shift' THEN
								v_shift_minutes := EXTRACT(EPOCH FROM v_user_specific_setting.default_shift_full_hours::INTERVAL)/60;
							END IF;
						END IF;
					END IF;
				-- END CHANGE [1.11] - Get Shift Time from the Advance Shift Changes if v_shift_minutes is Null or 0

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

				v_shift_minutes := (v_shift_minutes - (EXTRACT(EPOCH FROM v_total_break_unpaid::INTERVAL)/60));

				-- STEP 7: Aggregate exact clocked working minutes resolving half-days, holiday overrides, and specific overtime mappings
				select sum(
				/************Change 1.12 starts**********************************/
				case when coalesce(att_type_proposed,'') in ('HO','WO') and attendance_type ='PP'  and p_multipayoutrequestid =0 
						then v_shift_minutes
						+case when (no_of_overtime_hours_worked is not null and  no_of_hours_worked <>'00:00:00') then (((left(trim(no_of_overtime_hours_worked),2)::numeric)*60+(substring(trim(no_of_overtime_hours_worked),4,2)::int)))::numeric(18,4) else 0 end
				when coalesce(att_type_proposed,'') in ('HO','WO') and attendance_type in('HO','WO') and  p_multipayoutrequestid =0 
						then v_shift_minutes
				 when (no_of_hours_worked is null or no_of_hours_worked ='00:00:00') and  p_multipayoutrequestid =0 and attendance_type ='PP' 
						then v_shift_minutes		
				/************Change 1.12 starts**********************************/
					 when (no_of_hours_worked is null or no_of_hours_worked ='00:00:00') and  p_multipayoutrequestid =0 
						then 0
					 when (no_of_hours_worked is null or no_of_hours_worked ='00:00:00') and  p_multipayoutrequestid >0 
						then (case when attendance_type in ('PP','HO','WO','WFH','OD','TR','ASL') then 1 
										when attendance_type in ('HD') then 0.5 end)*v_shift_minutes
					else
						(left(trim(no_of_hours_worked),2)::numeric)*60+substring(trim(no_of_hours_worked),4,2)::int
					end
					)::numeric(18,4) ,
					 sum(
							case when (no_of_hours_worked is null or no_of_hours_worked ='00:00:00') and  p_multipayoutrequestid =0 
								then 0
							 when (no_of_hours_worked is null or no_of_hours_worked ='00:00:00') and  p_multipayoutrequestid >0 
									then
								(case when attendance_type  ='LL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 1
								when attendance_type='HD' and nullif(leavetype,'') is not null and nullif(leavetype,'')<>'AA' and coalesce(leave_ctg,'Paid')<>'Unpaid' 
									then 0.5 
								when attendance_type  ='HL' and coalesce(leave_ctg,'Paid')<>'Unpaid' 
									then 0.5 
								else 0.0 
								end)*v_shift_minutes
								end )::numeric(18,4)
							,sum(case when attendance_type in ('PP','HO','WO','WFH','OD','TR') then 1 else 0 end )
						into v_working_minutes,v_working_leaves	,v_monthpresentdays	   
						from tbl_monthly_attendance 
						where customeraccountid=v_customeraccountid and emp_code=p_emp_code
						and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
						and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
						and isactive='1' 
						and lower(is_attendance_salary)='attendance' 
						and approval_status='A';
				v_paiddays:=round(v_working_minutes/v_shift_minutes,2);		
				v_leavetaken:=round(v_working_leaves/v_shift_minutes,2);	
				select count(case when approval_status='A' then 1 else null end) as approved_attendance,
						count(case when coalesce(approval_status,'')<>'A' then 1 else null end) as unapproved_attendance	
									from tbl_monthly_attendance 
									where customeraccountid=v_customeraccountid and emp_code=p_emp_code
									and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
									and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
									and isactive='1'
				into v_rec_attendance;	  
				  
			/****************Advance Block************************************/  
			-- STEP 8: Salary Mode 'Advance' - Determine paid and leave days from standard (non-hourly) approved attendance statuses
			elsif exists(select 1 from tbl_monthly_attendance 
						where customeraccountid=v_customeraccountid and emp_code=p_emp_code and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
						and attendance_salary_status='1' and is_attendance_salary='Salary' and approval_status='A'
						and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)) then 
				if coalesce(v_empsalaryregister.flexiblemonthdays,'N')='N' then
						select sum(case when attendance_type in ('PP','HO','WO','WFH','OD','TR','ASL') then 1 
										when attendance_type in ('HD') then 0.5 end) paiddays,
								sum(case when attendance_type  ='LL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 1 when attendance_type='HD' and nullif(leavetype,'') is not null and nullif(leavetype,'')<>'AA' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 when attendance_type  ='HL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 else 0.0 end) leavetaken
							,sum(case when attendance_type in ('PP','HO','WO','WFH','OD','TR') then 1 else 0 end )
						into v_paiddays,v_leavetaken	,v_monthpresentdays		   
						from tbl_monthly_attendance 
						where customeraccountid=v_customeraccountid and emp_code=p_emp_code
						and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
						--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
						and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
						and attendance_salary_status='1'
						and lower(is_attendance_salary)='salary' 
						and approval_status='A';

					select count(case when approval_status='A' then 1 else null end) as approved_attendance,
						count(case when coalesce(approval_status,'')<>'A' then 1 else null end) as unapproved_attendance	
									from tbl_monthly_attendance 
									where customeraccountid=v_customeraccountid and emp_code=p_emp_code
									and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
									--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
									and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
									and attendance_salary_status='1'
									and lower(is_attendance_salary)='salary' 
				into v_rec_attendance;
				else
	
						select sum(case when attendance_type in ('PP'/*,'HO','WO','WFH','OD','TR','ASL'*/) then 1 
										when attendance_type in ('HD') then 0.5 end) paiddays,
								sum(case when attendance_type  ='LL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 1 when attendance_type='HD' and nullif(leavetype,'') is not null and nullif(leavetype,'')<>'AA' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 when attendance_type  ='HL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 else 0.0 end) leavetaken
							,sum(case when attendance_type in ('PP'/*,'HO','WO','WFH','OD','TR'*/) then 1 else 0 end )
						into v_paiddays,v_leavetaken	,v_monthpresentdays		   
						from tbl_monthly_attendance 
						where customeraccountid=v_customeraccountid and emp_code=p_emp_code
						and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
						--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
						and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
						and attendance_salary_status='1'
						and lower(is_attendance_salary)='salary' 
						and approval_status='A';
			--Raise Notice 'p_multipayoutrequestid=% v_paiddays=%',p_multipayoutrequestid,v_paiddays;

				--Raise Notice 'v_empsalaryregister.flexiblemonthdays=% v_rec_payrolldates.start_dt=%,v_doj=%,v_dor=%,v_rec_payrolldates.end_dt=%',v_empsalaryregister.flexiblemonthdays,v_rec_payrolldates.start_dt,v_doj,v_dor,v_rec_payrolldates.end_dt;

					select count(case when approval_status='A' then 1 else null end) as approved_attendance,
						   count(case when coalesce(approval_status,'')<>'A' then 1 else null end) as unapproved_attendance	
									from tbl_monthly_attendance 
									where customeraccountid=v_customeraccountid and emp_code=p_emp_code
									and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
									--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
									and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
									and attendance_salary_status='1'
									and lower(is_attendance_salary)='salary' 
				into v_rec_attendance;
				end if;

				v_advance_or_current:='Advance';
				/****************Current Block************************************/  
				else
					-- STEP 9: Salary Mode 'Current' - Standard iteration accumulating specific daily log types
					if coalesce(v_empsalaryregister.flexiblemonthdays,'N')='N' then
					select sum(case when attendance_type in ('PP','HO','WO','WFH','OD','TR','ASL') then 1 
										when attendance_type in ('HD') then 0.5 end) paiddays,
								sum(case when attendance_type  ='LL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 1 when attendance_type='HD' and nullif(leavetype,'') is not null and nullif(leavetype,'')<>'AA' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 when attendance_type  ='HL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 else 0.0 end) leavetaken
							,sum(case when attendance_type in ('PP','HO','WO','WFH','OD','TR') then 1 else 0 end )
						into v_paiddays,v_leavetaken ,v_monthpresentdays			   
						from tbl_monthly_attendance 
						where customeraccountid=v_customeraccountid and emp_code=p_emp_code
						and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
						--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
						and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
						and isactive='1' 
						and lower(is_attendance_salary)='attendance' 
						and approval_status='A';
						
				select count(case when approval_status='A' then 1 else null end) as approved_attendance,
						count(case when coalesce(approval_status,'')<>'A' then 1 else null end) as unapproved_attendance	
									from tbl_monthly_attendance 
									where customeraccountid=v_customeraccountid and emp_code=p_emp_code
									and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
									--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
									and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
									and isactive='1'
				into v_rec_attendance;
			else
			
			select sum(case when attendance_type in ('PP'/*,'HO','WO','WFH','OD','TR','ASL'*/) then 1 
										when attendance_type in ('HD') then 0.5 end) paiddays,
								sum(case when attendance_type  ='LL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 1 when attendance_type='HD' and nullif(leavetype,'') is not null and nullif(leavetype,'')<>'AA' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 when attendance_type  ='HL' and coalesce(leave_ctg,'Paid')<>'Unpaid' then 0.5 else 0.0 end) leavetaken
							,sum(case when attendance_type in ('PP'/*,'HO','WO','WFH','OD','TR'*/) then 1 else 0 end )
						into v_paiddays,v_leavetaken ,v_monthpresentdays			   
						from tbl_monthly_attendance 
						where customeraccountid=v_customeraccountid and emp_code=p_emp_code
						and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
						--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
						and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
						and isactive='1' 
						and lower(is_attendance_salary)='attendance' 
						and approval_status='A';
				-- Raise Notice 'p_multipayoutrequestid=% v_paiddays=%',p_multipayoutrequestid,v_paiddays;
				-- Raise Notice 'v_empsalaryregister.flexiblemonthdays=% v_rec_payrolldates.start_dt=%,v_doj=%,v_dor=%,v_rec_payrolldates.end_dt=%',v_empsalaryregister.flexiblemonthdays,v_rec_payrolldates.start_dt,v_doj,v_dor,v_rec_payrolldates.end_dt;
		
					select count(case when approval_status='A' then 1 else null end) as approved_attendance,
					   count(case when coalesce(approval_status,'')<>'A' then 1 else null end) as unapproved_attendance	
									from tbl_monthly_attendance 
									where customeraccountid=v_customeraccountid and emp_code=p_emp_code
									and (p_multipayoutrequestid=0 or multipayoutrequestid=p_multipayoutrequestid)
									--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
									and att_date between greatest(v_rec_payrolldates.start_dt,v_doj) and least(v_rec_payrolldates.end_dt,coalesce(v_dor,v_rec_payrolldates.end_dt))
									and isactive='1'
				into v_rec_attendance;
				end if;
				v_advance_or_current:='Current';						
				end if;
		end if;
		end if;
	delete from paymentadvice where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and coalesce(advicelockstatus,'')<>'Locked' and attendancemode='MPR'; 
	

	if ((coalesce(v_rec_attendance.approved_attendance,0)>0 and coalesce(v_rec_attendance.unapproved_attendance,0)=0) or p_salmode='Provisional')
	and (not exists(select * from paymentadvice where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and advicelockstatus='Locked'  and attendancemode='MPR')
		 or p_multipayoutrequestid<>0)
	then
	-- STEP 10: Create an isolated in-memory temporary table to simulate "downloaded wages" based on the tabulated logic
	drop table if exists pg_temp.cmsdownloadedwages_pregenerate;						
	create /*GLOBAL*/ temporary table pg_temp.cmsdownloadedwages_pregenerate
	as
	select * from cmsdownloadedwages where 1=2;
					INSERT INTO pg_temp.cmsdownloadedwages_pregenerate(
				mprmonth, mpryear, empcode, employeename, pancardno, dateofjoining, deputeddate, projectname, contractno, 
						agencyname, contractcategory, contracttype, dateofleaving, 
						lossofpay, totalpaiddays, totalleavetaken, 
						hrgeneratedon, mpruploadeddate, ismultilocated, remark, 
						companycode, bunit, isactive, createdon, createdbyip,
						batch_no, bunitname, agencyid, customeraccountid, customeraccountname,
						jobrole, relieveddate, multi_performerwagesflag, 
						cms_contractid, cms_salremark, cms_trackingid, cms_jobid, cms_posting_department, 
						cms_posting_location, transactionid, attendancemode, manualmodereason, cjcode
						,working_minutes,shift_minutes)

				select p_month,p_year,openappointments.emp_code,emp_name,pancard,dateofjoining,dateofjoining,contract_name,crm_order_number,
						agencyname,contract_category,type_of_contract,dateofrelieveing,
						v_monthdays-(coalesce(v_paiddays,0)+coalesce(v_leavetaken,0)) lossofpay, 
						coalesce(v_paiddays,0)paiddays,coalesce(v_leavetaken,0) leavetaken, 
						to_char(current_timestamp,'dd Mon yyyy hh24:mi'),current_timestamp,'N','TP Attendance Moved',
						'A0001',1,'1',current_timestamp,p_createdbyip,
						(current_timestamp::text),'TP',null,customeraccountid,tbl_account.accountname,
						post_offered,dateofrelieveing,'Y',
						contractid,'',trackingid,jobid,posting_department,
						posting_location, EXTRACT(EPOCH FROM current_timestamp)::bigint,'MPR','TP',cjcode
						,v_working_minutes,v_shift_minutes
				from openappointments inner join tbl_account
				on openappointments.customeraccountid=tbl_account.id	  
				where openappointments.emp_code=p_emp_code;

SELECT json_agg(row_to_json(t))::text into v_advice_attendancerecord
FROM (
    SELECT *
    FROM cmsdownloadedwages_pregenerate
) t;
/********Change 1.***************/

-- open v_rfc for select * from pg_temp.cmsdownloadedwages_pregenerate;
-- return v_rfc;
if v_empsalaryregister.fullmonthincentiveapplicable='Y' and v_monthpresentdays>=(case when v_empsalaryregister.salaryindaysopted='Y' then v_empsalaryregister.salarydays else v_monthdays end) then
		v_fullmonthincentive:=coalesce(nullif(v_empsalaryregister.grossearningcomponents,0),v_empsalaryregister.gross)/case when v_empsalaryregister.salaryindaysopted='Y' then v_empsalaryregister.salarydays else v_monthdays end;
end if;
-- Raise Notice 'p_month=% year=% p_emp_code=% =p_createdby=% p_createdbyip=% =v_cnt=% v_paiddays=% v_leavetaken=%',p_month,p_year,p_emp_code,p_createdby,p_createdbyip,v_cnt,v_paiddays,v_leavetaken;
				-- STEP 11: Invoke the foundational wage generation procedure to mock calculations based on this temporary simulation
				select  public.uspgetorderwisewages_pregenerate(
										p_mprmonth =>p_month,
										p_mpryear =>p_year,
										p_ordernumber =>''::character varying,
										p_emp_code =>p_emp_code,
										p_batch_no =>''::character varying,
										p_action =>'Retrieve_Salary'::character varying,
										p_createdby =>p_createdby::bigint,
										createdbyip =>p_createdbyip::character varying,
										p_criteria =>'Employee'::character varying,
										p_process_status =>'NotProcessed'::character varying,
										p_issalaryorliability =>'L'::character varying,
										p_tptype =>'TP'::character varying,
										p_advice_attendancerecord=>v_advice_attendancerecord,
										p_advance_or_current=>v_advance_or_current,
										p_multipayoutrequestid=>p_multipayoutrequestid,
										p_fullmonthincentive=>v_fullmonthincentive
										)
				into v_rfc;	
end if;				
		return v_rfc;
		
		end if;
-- 	exception when others then
-- 	return 0;
end if;
		return v_rfc;
	end;

$BODY$;

ALTER FUNCTION public.uspwagesfromattendance_pregenerate(character varying, bigint, bigint, character varying, integer, integer, character varying, numeric, bigint)
    OWNER TO payrollingdb;

