-- FUNCTION: public.uspsavebulkattendance_business(character varying, bigint, bigint, character varying, character varying, text, bigint, bigint, text, text, text, text, integer, integer, character varying, integer, integer)

-- DROP FUNCTION IF EXISTS public.uspsavebulkattendance_business(character varying, bigint, bigint, character varying, character varying, text, bigint, bigint, text, text, text, text, integer, integer, character varying, integer, integer);

CREATE OR REPLACE FUNCTION public.uspsavebulkattendance_business(
	p_action character varying DEFAULT ''::character varying,
	p_emp_code bigint DEFAULT '-9999'::integer,
	p_createdby bigint DEFAULT '-9999'::integer,
	p_createdbyip character varying DEFAULT ''::character varying,
	p_marked_by_usertype character varying DEFAULT ''::character varying,
	p_attendancedates text DEFAULT ''::text,
	p_customeraccountid bigint DEFAULT '-9999'::integer,
	p_leavebankid bigint DEFAULT 0,
	p_attendancesource text DEFAULT 'application'::text,
	p_payout_with_attendance text DEFAULT 'PWA'::text,
	p_att_purpose text DEFAULT 'Attendance'::text,
	p_payout_frequencytype text DEFAULT 'SAP'::text,
	p_year integer DEFAULT 0,
	p_month integer DEFAULT 0,
	p_month_direction character varying DEFAULT 'N'::character varying,
	p_month_start_day integer DEFAULT 0,
	p_month_end_day integer DEFAULT 0)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
	msg text:='';
	v_month integer;
	v_year integer;
	v_emp_name varchar(100);
	v_customeraccountid int;
	v_alertmsg text;
	v_emp_code bigint;
	v_doj date;
	v_dateofrelieveing date;
	v_tempmgs text='';
	v_openappointments openappointments%rowtype;
	v_rfcadvice refcursor;
	v_cnt int;
	v_mst_account_custom_month_settings mst_account_custom_month_settings%rowtype;	
	v_monthenddate date;	
	v_finerecord record;
	v_rec_payrolldates record;
	v_check_att_status_before_approval text:=''; -- Change [2.1]
	v_recattemployees record;
	v_multipayoutrequestid bigint:=0;
	v_recadvice record;
	v_paymentadvice paymentadvice%rowtype;
/*************************************************************************************************
Version Date			Change										Done_by
1.0		02-Dec-2022		Initial Version								Shiv Kumar
1.1		31-Jul-2023		Set Credit Used								Shiv Kumar
1.2		09-May-2024		Update Tax									Shiv Kumar
1.3		24-Jun-2024		update advice on Attendance Approval		Shiv Kumar
1.4		18-Jul-2024		Add function usp_manage_att_status_before_approval 	Shiv Kumar(function given by Vinod Maurya)
1.5		02-Dec-2024		Paid V/s Unpaid Leave						Shiv Kumar
1.6		15-Feb-2025		Cross Month									Shiv Kumar
1.7		26-Feb-2025		Add p_payout_with_attendance Changes		Parveen Kumar
1.8		05-March-2025	Early going/ Late coming/OT					Shiv Kumar
1.9		23-March-2025	Manage Future Attendance					Shiv Kumar
2.0		26-March-2025	Stop calendar Attendance					Shiv Kumar
						 if Salary mode  attendance exists
2.1		22-April-2025	Check MP before attendance approval			Parveen Kumar
2.2		14-Apr-2025		change application source					Shiv Kumar					
2.3		25-Apr-2025		Add new acion for ApproveBulkAttendance		Shiv Kumar	
2.4		22-May-2025		No Advice delete on Leave Approal etc.		Shiv Kumar	
2.5		15-Jul-2025		Cross Month and Multipayout	.				Shiv Kumar	
2.6		08-Jan-2026		Add att_catagory in json data	.			Vinod Kumar	
**************************************************************************************************/
begin
		select * 
		from mst_account_custom_month_settings 
		where account_id= p_customeraccountid and status='1'
		AND month_start_day <>0
		into v_mst_account_custom_month_settings;
		v_mst_account_custom_month_settings.row_id:=coalesce(v_mst_account_custom_month_settings.row_id,-9999);
		v_mst_account_custom_month_settings.month_category:=coalesce(v_mst_account_custom_month_settings.month_category,'standard');
	
	-- ==========================================================================================
	-- FLOW: BULK EXCEL ATTENDANCE APPROVAL ('ApproveBulkAttendanceFromExcel_New')
	-- Approves attendance records uploaded via Excel. Calculates late coming/early going deductions,
	-- updates ledgers, and triggers pre-wage/tax calculations.
	-- ==========================================================================================
	if p_action='ApproveBulkAttendanceFromExcel_New' then
		-- STEP 1: Parse incoming JSON payload to extract employee codes, month, and year
		SELECT (json_data ->> 'empCode') AS emp_codes,(json_data ->> 'month') AS month,(json_data ->> 'year') AS year
			into v_recattemployees	
		FROM json_array_elements(p_attendancedates::json) AS json_data;

		select v_recattemployees.month,v_recattemployees.year
		into v_month,v_year;
		
		select null::date start_dt,null::date end_dt into v_rec_payrolldates;				
/*
		SELECT 
			-- added on 23.06.2025 vinod
		(CASE WHEN month_direction='F' THEN make_date(v_year::int, v_month::int,month_start_day)::date
		ELSE (make_date(v_year::int, v_month::int,month_start_day)- interval '1 month') END)::date  start_dt,
		
		CASE WHEN month_direction='F' THEN (make_date(v_year::int, v_month::int,month_end_day)+ interval '1 month')::date  
		ELSE make_date(v_year::int, v_month::int,month_end_day)::date  END end_dt
		-- added on 23.06.2025	 
		/* make_date(v_year::int, v_month::int, month_start_day)::date start_dt,
			(make_date(v_year::int, v_month::int, month_end_day) + INTERVAL '1 month')::date end_dt
			*/
		into v_rec_payrolldates
		from mst_account_custom_month_settings 
		where account_id= p_customeraccountid and status='1'  AND month_start_day <>0;
		v_rec_payrolldates.start_dt:=coalesce(v_rec_payrolldates.start_dt,make_date(v_year::int, v_month::int,1));
		v_rec_payrolldates.end_dt:=coalesce(v_rec_payrolldates.end_dt,(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date);
*/
			-- STEP 2: Determine payroll start and end dates based on custom account settings or defaults
			if coalesce(p_month_direction,'N')<>'N' then
				v_month=p_month;
				v_year:=p_year;
				SELECT 
				(CASE WHEN p_month_direction='F' THEN make_date(v_year::int, v_month::int,p_month_start_day)::date
				ELSE (make_date(v_year::int, v_month::int,p_month_start_day)- interval '1 month') END)::date  start_dt,

				CASE WHEN p_month_direction='F' THEN (make_date(v_year::int, v_month::int,p_month_end_day)+ interval '1 month')::date  
				ELSE make_date(v_year::int, v_month::int,p_month_end_day)::date  END end_dt
				into v_rec_payrolldates;
			else
				v_rec_payrolldates.start_dt:=make_date(v_year::int, v_month::int,1);
				v_rec_payrolldates.end_dt:=(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date;	
			end if;			
		-- STEP 3: Setup Common Table Expressions (CTEs) to filter eligible employees and existing records
		with tmp_emp_code as 
			(
				-- 3a: Convert comma-separated employee codes into a table
				select regexp_split_to_table(v_recattemployees.emp_codes,',')::bigint  as emp_codes
			)
		,tbl_attendanceonly as(
				-- 3b: Identify employees configured for attendance/leave only (no salary processing)
				select distinct t1.emp_code from (				
				select op.emp_code,trim(unnest(string_to_array(op.assigned_ou_ids, ',')))::bigint AS assigned_ou_ids
		 		from openappointments op inner join tmp_emp_code on op.emp_code=tmp_emp_code.emp_codes
					) t1 inner join  tbl_org_unit_geofencing 
		 		on t1.assigned_ou_ids=tbl_org_unit_geofencing.id
				and is_attendance_leave_only='Y'
			)	
			, tbl_lockedadvice as
					(
						-- 3c: Identify employees with locked payment advice for the target month
						SELECT DISTINCT emp_code as adv_emp_code
						FROM paymentadvice	WHERE paiddays > 0
						  AND attendancemode = 'MPR'
						  AND paymentadvice.customeraccountid = p_customeraccountid
						  AND paymentadvice.mpryear=v_year AND paymentadvice.mprmonth=v_month
						  AND advicelockstatus = 'Locked'
					) 
		,tblapproved_attendance as(
							-- 3d: Identify employees who already have approved salary attendance
							SELECT DISTINCT emp_code as taa_emp_code
							FROM tbl_monthly_attendance
							where tbl_monthly_attendance.customeraccountid = p_customeraccountid
								and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
								and attendance_salary_status='1'
								and lower(is_attendance_salary)='salary'
								and p_att_purpose='Attendance'
								)  
		,tblmultipayout as(
							-- 3e: Identify employees already part of a multi-payout request
							SELECT DISTINCT emp_code as taa2_emp_code
							FROM tbl_monthly_attendance
							where tbl_monthly_attendance.customeraccountid = p_customeraccountid
								and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
								and (isactive='1' or attendance_salary_status='1')
								and approval_status='A'
								and multipayoutrequestid<>0
								) 
		,tmp1 as(	
			-- STEP 4: Update attendance status to Approved ('A') for eligible records
			update tbl_monthly_attendance
				set approval_status='A',
					modifiedby=p_createdby,
					modifiedon=current_timestamp,
					modifiedbyip=p_createdbyip,
					approved_by=p_customeraccountid,
					approved_on=current_timestamp,
					approved_by_ip=p_createdbyip
		from tmp_emp_code inner join openappointments op
			on op.emp_code=tmp_emp_code.emp_codes
			left join tbl_lockedadvice tl on tmp_emp_code.emp_codes=tl.adv_emp_code
			left join tblapproved_attendance tl2 on tmp_emp_code.emp_codes=tl2.taa_emp_code
			left join tblmultipayout on tmp_emp_code.emp_codes=tblmultipayout.taa2_emp_code
			where tbl_monthly_attendance.emp_code=tmp_emp_code.emp_codes	
		and tbl_monthly_attendance.att_date between greatest(v_rec_payrolldates.start_dt,op.dateofjoining) and least(v_rec_payrolldates.end_dt,coalesce(op.dateofrelieveing,v_rec_payrolldates.end_dt))
				AND 
				(
					(tbl_monthly_attendance.isactive = '1' AND p_att_purpose = 'Attendance' AND tbl_monthly_attendance.attendance_salary_status = '0' AND tbl_monthly_attendance.is_attendance_salary = 'Attendance')  
					OR  
					(tbl_monthly_attendance.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND tbl_monthly_attendance.isactive = '0' AND tbl_monthly_attendance.is_attendance_salary = 'Salary')
				)
				and tbl_monthly_attendance.approval_status='P'
				and tbl_monthly_attendance.att_date>=op.dateofjoining
				and (op.dateofrelieveing is null or tbl_monthly_attendance.att_date<=op.dateofrelieveing)
           		and tl.adv_emp_code is null
				and tl2.taa_emp_code is null
				and tblmultipayout.taa2_emp_code is null
			returning tbl_monthly_attendance.*
		)
		,tbl_finerecord as
		(
				-- STEP 5: Calculate aggregate late coming and early going deduction hours
				select tmp1.emp_code,sum(latehoursdeduction) latehoursdeduction,sum(earlyhoursdeduction) earlyhoursdeduction
				from tmp1 left join tbl_attendanceonly
				on tmp1.emp_code= tbl_attendanceonly.emp_code
				where tbl_attendanceonly.emp_code is null
				and no_of_hours_worked is not null
				and (p_att_purpose = 'Attendance' and current_date>v_rec_payrolldates.end_dt)
			    group by tmp1.emp_code
		),
	tmp3 as
	(
	-- STEP 6: Deactivate old/unprocessed late and early fine ledger entries
	update tbl_employeeledger set isactive='0'
		from tmp_emp_code inner join tbl_finerecord
		on tmp_emp_code.emp_codes=tbl_finerecord.emp_code
		where tmp_emp_code.emp_codes=tbl_employeeledger.emp_code
		and headid in (171,172) 
		and processmonth=v_month
		and processyear=v_year
		and isactive='1' 
		and coalesce(isledgerdisbursed,'0')='0'
	 returning *
	),
	tbl_latehoursdeduction as
	(
		-- STEP 7: Insert new late coming fine deduction into the employee ledger
		insert into tbl_employeeledger
			(
				emp_id,emp_code,headid,headname,amount,processmonth,processyear,
				isactive,createdby,createdon,createdbyip,masterhead,is_taxable,is_billable,remarks
			)
			select op2.emp_id,op2.emp_code,171,'Late Coming Fine',tbl_finerecord.latehoursdeduction*-1,v_month,v_year,
				'1',p_createdby,current_timestamp,p_createdbyip ,'Deduction','N','Y','Late Coming Fine'
			from tbl_finerecord inner join openappointments op2
			on op2.emp_code=tbl_finerecord.emp_code
		and coalesce(tbl_finerecord.latehoursdeduction,0)>0
		returning *
	),
	tbl_earlyhoursdeduction as
	(
	
			-- STEP 8: Insert new early going fine deduction into the employee ledger
			insert into tbl_employeeledger
			(
				emp_id,emp_code,headid,headname,amount,processmonth,processyear,
				isactive,createdby,createdon,createdbyip,masterhead,is_taxable,is_billable,remarks
			)
			select op2.emp_id,op2.emp_code,172,'Early Going Fine',tbl_finerecord.earlyhoursdeduction*-1,v_month,v_year,
				'1',p_createdby,current_timestamp,p_createdbyip ,'Deduction','N','Y','Early Going Fine'
			from tbl_finerecord inner join openappointments op2
			on op2.emp_code=tbl_finerecord.emp_code
		and coalesce(tbl_finerecord.earlyhoursdeduction,0)>0
	)
	select
	 (
		SELECT array_to_json(array_agg(row_to_json(t)))::jsonb as data_t from
		(
			select  count(distinct emp_code)||' Records Processed' as message from tmp1 
		) t

	 ) into msg;
	return msg;

end if;

	-- ==========================================================================================
	-- FLOW: LEGACY EXCEL ATTENDANCE APPROVAL ('ApproveBulkAttendanceFromExcel')
	-- Iterates through employees, approves uploaded attendance if not already locked, handles 
	-- deductions, and generates preliminary wages and tax structures.
	-- ==========================================================================================
	if p_action='ApproveBulkAttendanceFromExcel' then
		v_cnt:=0;
			-- STEP 1: Create a temporary table to store approval response messages for each employee
			create temporary table tmpresponse_approve
			(
				emp_code bigint,
				orgempcode varchar(30),
				tpcode varchar(30),
				empname varchar(100),
				pmessage text
			) on commit drop;
		
			-- STEP 2: Parse incoming JSON payload to extract employee codes, month, and year
			SELECT (json_data ->> 'empCode') AS emp_codes,(json_data ->> 'month') AS month,(json_data ->> 'year') AS year
				into v_recattemployees	
			FROM    json_array_elements(p_attendancedates::json) AS json_data;

				select v_recattemployees.month,v_recattemployees.year
				into v_month,v_year;
				--RAISE NOTICE 'v_month => %', v_month;
				--RAISE NOTICE 'v_year => %', v_year;
		-- STEP 3: Iterate through each employee code extracted from the payload
		for v_emp_code in (select regexp_split_to_table(v_recattemployees.emp_codes,',')::bigint)
		loop
			select * from openappointments where emp_code=v_emp_code into v_openappointments;

			-- STEP 4: Skip approval if payment advice is already locked for the employee
			IF EXISTS (
				SELECT DISTINCT emp_code
				FROM paymentadvice
				WHERE paiddays > 0
				  AND attendancemode = 'MPR'
				  AND paymentadvice.customeraccountid = p_customeraccountid
				  AND v_year = paymentadvice.mpryear
				  AND v_month = paymentadvice.mprmonth
				  AND emp_code = v_emp_code
				  AND advicelockstatus = 'Locked'
			) THEN
			insert into tmpresponse_approve	(emp_code,orgempcode,tpcode,empname,pmessage) values(v_emp_code,v_openappointments.orgempcode,v_openappointments.cjcode,v_openappointments.emp_name,' Record(s) not approved due to payment advice already locked.');
				continue;
			END IF;

/*****************************Change 2.0 starts*****************************************************/		
		-- STEP 5: Calculate payroll start and end dates for validation
		SELECT 
			-- added on 23.06.2025 vinod
		(CASE WHEN month_direction='F' THEN make_date(v_year::int, v_month::int,month_start_day)::date
		ELSE (make_date(v_year::int, v_month::int,month_start_day)- interval '1 month') END)::date  start_dt,
		
		CASE WHEN month_direction='F' THEN (make_date(v_year::int, v_month::int,month_end_day)+ interval '1 month')::date  
		ELSE make_date(v_year::int, v_month::int,month_end_day)::date  END end_dt
		-- added on 23.06.2025	 
		
		/* make_date(v_year::int, v_month::int, month_start_day)::date start_dt,
			(make_date(v_year::int, v_month::int, month_end_day) + INTERVAL '1 month')::date end_dt 
			*/
		into v_rec_payrolldates
		from mst_account_custom_month_settings 
		where account_id= p_customeraccountid and status='1'  AND month_start_day <>0;
		v_rec_payrolldates.start_dt:=coalesce(v_rec_payrolldates.start_dt,make_date(v_year::int, v_month::int,1));
		v_rec_payrolldates.end_dt:=coalesce(v_rec_payrolldates.end_dt,(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date);
				
			-- STEP 6: Skip approval if advance attendance exists for salary processing
			IF EXISTS (
				SELECT DISTINCT emp_code
				FROM tbl_monthly_attendance
				where emp_code=v_emp_code
						and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
						and attendance_salary_status='1'
						and lower(is_attendance_salary)='salary' 
			)
			and p_att_purpose='Attendance'
			THEN
			insert into tmpresponse_approve	(emp_code,orgempcode,tpcode,empname,pmessage) values(v_emp_code,v_openappointments.orgempcode,v_openappointments.cjcode,v_openappointments.emp_name,' Record(s) not approved due to advance attendance already exists.');
				continue;
			END IF;
/*****************************Change 2.0 ends*****************************************************/	
				-- STEP 7: Update attendance status to Approved ('A') for the current employee's eligible dates
				update tbl_monthly_attendance
				set approval_status='A',
					modifiedby=p_createdby,
					modifiedon=current_timestamp,
					modifiedbyip=p_createdbyip,
					approved_by=p_customeraccountid,
					approved_on=current_timestamp,
					approved_by_ip=p_createdbyip
				where --tbl_monthly_attendance.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
				        tbl_monthly_attendance.att_date between greatest(v_rec_payrolldates.start_dt,v_openappointments.dateofjoining) and least(v_rec_payrolldates.end_dt,coalesce(v_openappointments.dateofrelieveing,v_rec_payrolldates.end_dt))
				and tbl_monthly_attendance.emp_code=v_emp_code
				AND 
				(
					(tbl_monthly_attendance.isactive = '1' AND p_att_purpose = 'Attendance' AND tbl_monthly_attendance.attendance_salary_status = '0' AND tbl_monthly_attendance.is_attendance_salary = p_att_purpose)  
					OR  
					(tbl_monthly_attendance.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND tbl_monthly_attendance.isactive = '0' AND tbl_monthly_attendance.is_attendance_salary = p_att_purpose)
				)
				and tbl_monthly_attendance.approval_status='P'
				and tbl_monthly_attendance.att_date>=v_openappointments.dateofjoining
				and (v_openappointments.dateofrelieveing is null or tbl_monthly_attendance.att_date<=v_openappointments.dateofrelieveing);

			insert into tmpresponse_approve	(emp_code,orgempcode,tpcode,empname,pmessage) values(v_emp_code,v_openappointments.orgempcode,v_openappointments.cjcode,v_openappointments.emp_name,' Record(s) Approved.');

	-- STEP 8: Apply late coming and early going fines for employees not configured as attendance-only
	if not EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array((select COALESCE(COALESCE(NULLIF(op.assigned_ou_ids, ''),'0')) from openappointments op where op.emp_code=v_emp_code), ',')) AS input_ou_ids
		WHERE input_ou_ids::bigint in (select id from tbl_org_unit_geofencing where is_attendance_leave_only='Y')
		) then
		
	/**************************Late Coming/Early Going block starts**********************************************/	
		if (p_att_purpose = 'Attendance' and current_date>v_rec_payrolldates.end_dt) then	
			select sum(latehoursdeduction) latehoursdeduction,sum(earlyhoursdeduction) earlyhoursdeduction
			from tbl_monthly_attendance 
			where emp_code=v_emp_code 
			and customeraccountid=p_customeraccountid
			--and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
			and tbl_monthly_attendance.att_date between greatest(v_rec_payrolldates.start_dt,v_openappointments.dateofjoining) and least(v_rec_payrolldates.end_dt,coalesce(v_openappointments.dateofrelieveing,v_rec_payrolldates.end_dt))
			and isactive='1'
			and approval_status='A'	
			and no_of_hours_worked is not null
			into v_finerecord;
			
		update tbl_employeeledger set isactive='0'
		where emp_code=v_emp_code and headid in (171,172) 
		and processmonth=v_month
		and processyear=v_year
		and isactive='1' and coalesce(isledgerdisbursed,'0')='0';
		
		/**************PRODUCTION IDs TO BE REPLACED****/
			if coalesce(v_finerecord.latehoursdeduction,0)>0 then
			insert into tbl_employeeledger
			(
				emp_id,emp_code,headid,headname,amount,processmonth,processyear,
				isactive,createdby,createdon,createdbyip,masterhead,is_taxable,is_billable,remarks
			)
			select v_openappointments.emp_id,v_emp_code,171,'Late Coming Fine',v_finerecord.latehoursdeduction*-1,v_month,v_year,
				'1',p_createdby,current_timestamp,p_createdbyip ,'Deduction','N','Y','Late Coming Fine';
			end if;
			if coalesce(v_finerecord.earlyhoursdeduction,0)>0 then	
			insert into tbl_employeeledger
			(
				emp_id,emp_code,headid,headname,amount,processmonth,processyear,
				isactive,createdby,createdon,createdbyip,masterhead,is_taxable,is_billable,remarks
			)
			select v_openappointments.emp_id,v_emp_code,172,'Early Going Fine',v_finerecord.earlyhoursdeduction*-1,v_month,v_year,
				'1',p_createdby,current_timestamp,p_createdbyip ,'Deduction','N','Y','Early Going Fine';
			end if;	
	end if;
	/**************************Late Coming/Early Going block ends**********************************************/	
			-- STEP 9: Update tax on advice based on the newly approved attendance
			select uspupdatetaonadvice	(p_customeraccountid =>p_customeraccountid,p_month=>v_month,p_year=>v_year,
						 p_geofenceid=>0,p_emp_code =>v_emp_code,
						 p_createdby=>p_createdby,p_createdbyip=>p_createdbyip)
			into v_rfcadvice;
			
			-- STEP 10: Pre-generate wages and calculate tax projection for the employee
			select 	uspwagesfromattendance_pregenerate(
						p_action =>'GenerateWages_pregenerate',
						p_emp_code =>v_emp_code,
						p_createdby =>p_customeraccountid,
						p_createdbyip =>'::1',
						p_month =>v_month,
						p_year =>v_year)
						into v_rfcadvice;
			v_cnt:=v_cnt+1;
	end if;
end loop;

	select
	 (
		SELECT array_to_json(array_agg(row_to_json(t)))::jsonb as data_t from
		(
			select  count(*)||pmessage as message from tmpresponse_approve   group by pmessage
		) t

	 ) into msg;
	 
return msg; --v_cnt::text||' records have been approved successfully.';

end if;
	
	-- ==========================================================================================
	-- FLOW: ATTENDANCE MAKING, APPROVAL, AND LOCKING
	-- This main block handles saving raw attendance data (making), approving it, and locking 
	-- it to proceed with payroll and tax calculation.
	-- ==========================================================================================
	if p_action='SaveBulkAttendance' or  p_action='ApproveBulkAttendance' or p_action='LockAttendance'  then
		select * from openappointments where emp_code=p_emp_code into v_openappointments;

		-- STEP 1: Create or truncate temporary table to hold incoming bulk attendance data
		if to_regclass('pg_temp.tmpbulkattendance') IS NULL then
			create temporary table tmpbulkattendance 
			(
				attendancedate text,
				attendancetype text,
				leavetype text,
				leave_ctg text,
				att_catagory text
			) on commit drop;
		else
			truncate table tmpbulkattendance;
		end if;

		-- STEP 2: Create or truncate temporary table to track database operations (Inserted/Updated/Cleared)
		if to_regclass('pg_temp.tmpresponse') IS NULL then		
			create temporary table tmpresponse
			(
				att_date date,
				op text
			) on commit drop;
		else
			truncate table tmpresponse;
		end if;

		select dateofjoining,dateofrelieveing from openappointments where emp_code=p_emp_code into v_doj,v_dateofrelieveing;
		
		-- STEP 3: Parse JSON payload and insert into temporary attendance table
		insert into tmpbulkattendance
		select * from json_populate_recordset(null::record, p_attendancedates::json)
		as (
				attendancedate text,
				attendancetype text,
				leavetype text,			
				leave_ctg text,
				att_catagory text
			);
		/**************************************************************************/
		-- STEP 4: Standardize leave categories based on system configurations
		update tmpbulkattendance set leave_ctg=(select distinct leave_ctg 
												from public.mst_tp_leavetype where status='1'
        										and is_enable='Y' 
												and (type_account_id::bigint=v_openappointments.customeraccountid or type_account_id=0::bigint)
											   and mst_tp_leavetype.leavetypecode=tmpbulkattendance.leavetype
											   );
		/**************************************************************************/
		
		if p_action='SaveBulkAttendance' then
			-- --------------------------------------------------------------------------------------
			-- 1. ATTENDANCE MAKING FLOW ('SaveBulkAttendance')
			-- Parses the incoming JSON attendance data, handles weekly off/holiday logic, 
			-- applies leave categories, and inserts/updates the records in 'tbl_monthly_attendance'.
			-- --------------------------------------------------------------------------------------
			SELECT * FROM openappointments WHERE emp_code=p_emp_code into v_openappointments;
			/*
				if v_mst_account_custom_month_settings.row_id=-9999 then
						select extract('month' from to_date(attendancedate,'dd/mm/yyyy'))::int, extract('year' from to_date(attendancedate,'dd/mm/yyyy'))::int 
						from tmpbulkattendance limit 1
						into v_month,v_year;
					else
						select  max(to_date(attendancedate,'dd/mm/yyyy')) from tmpbulkattendance into v_monthenddate;
						if extract('day' from v_monthenddate)<=v_mst_account_custom_month_settings.month_end_day then
							v_year:=extract('year' from v_monthenddate);
							v_month:=extract('month' from v_monthenddate);
						else
							v_year:=extract('year' from v_monthenddate+interval '1 month');
							v_month:=extract('month' from v_monthenddate+interval '1 month');
						end if;
					end if;
			*/
			/*****************************Change 2.0 starts*****************************************************/
			-- STEP 5: Calculate actual payroll start and end dates based on direction and custom settings
			v_rec_payrolldates:=null;
			select null::date start_dt,null::date end_dt into v_rec_payrolldates;
			if coalesce(p_month_direction,'N')<>'N' then
				v_month=p_month;
				v_year:=p_year;
				SELECT 
					-- added on 23.06.2025 vinod
					(CASE WHEN p_month_direction='F' THEN make_date(v_year::int, v_month::int,p_month_start_day)::date
					ELSE (make_date(v_year::int, v_month::int,p_month_start_day)- interval '1 month') END)::date  start_dt,
					
					CASE WHEN p_month_direction='F' THEN (make_date(v_year::int, v_month::int,p_month_end_day)+ interval '1 month')::date  
					ELSE make_date(v_year::int, v_month::int,p_month_end_day)::date  END end_dt
					-- added on 23.06.2025	 
					
					/* make_date(v_year::int, v_month::int, month_start_day)::date start_dt,
					(make_date(v_year::int, v_month::int, month_end_day) + INTERVAL '1 month')::date end_dt
					*/
				into v_rec_payrolldates;
				--Raise Notice 'v_rec_payrolldates.start_dt=%,v_rec_payrolldates.end_dt=%',v_rec_payrolldates.start_dt,v_rec_payrolldates.end_dt;		
			else
				select extract('month' from to_date(attendancedate,'dd/mm/yyyy'))::int, extract('year' from to_date(attendancedate,'dd/mm/yyyy'))::int 
				from tmpbulkattendance limit 1
				into v_month,v_year;		
				v_rec_payrolldates.start_dt:=make_date(v_year::int, v_month::int,1);
				v_rec_payrolldates.end_dt:=(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date;
			end if;

			-- STEP 6: Reject operation if a multi-payout request is currently in progress
			if EXISTS (SELECT * FROM tbl_monthlysalary where emp_code=p_emp_code and mprmonth=v_month and mpryear=v_year and is_rejected='0' and multipayoutrequestid<>0) then		
				return 'Multi Payout already in process';
			end if;
			/*****************************Change 2.0 ends*****************************************************/					
			-- STEP 7: Deactivate any old ledger entries to reset the processing state
			update tbl_employeeledger set isactive='0'
			where emp_code=p_emp_code and headid not in(173,174) -- change prod Ids
			and processmonth=v_month
			and processyear=v_year
			and isactive='1' and coalesce(isledgerdisbursed,'0')='0'; 

			/*****************************Change 2.4 starts*****************************************************/		
			-- STEP 8: Remove unlocked payment advice unless salary attendance has already been approved
			DECLARE
				v_calc_start date;
				v_calc_end date;
				v_exists_flag boolean := false;
			BEGIN
				v_calc_start := greatest(v_rec_payrolldates.start_dt, v_openappointments.dateofjoining);
				v_calc_end := least(v_rec_payrolldates.end_dt, coalesce(v_openappointments.dateofrelieveing, v_rec_payrolldates.end_dt));

				IF p_att_purpose = 'Attendance'::text THEN
					SELECT EXISTS (
						SELECT 1 FROM tbl_monthly_attendance
						WHERE emp_code = p_emp_code
						  AND att_date BETWEEN v_calc_start AND v_calc_end
						  AND attendance_salary_status = '1' 
						  AND is_attendance_salary = 'Salary'
						  AND approval_status = 'A'
					) INTO v_exists_flag;
				END IF;

				IF v_exists_flag THEN
					null;   
				ELSE
			/*****************************Change 2.4 ends*****************************************************/		
					delete from paymentadvice where emp_code=p_emp_code and mprmonth=v_month and mpryear=v_year AND coalesce(advicelockstatus,'') <> 'Locked' and attendancemode<>'Ledger';
				END IF; /***Change 2.4 if condition ends**/
			END;

			if not exists(select * from cmsdownloadedwages where empcode::bigint=p_emp_code and mprmonth=v_month and mpryear=v_year and isactive='1' and cmsdownloadedwages.attendancemode NOT IN ('Ledger', 'Manual') and multipayoutrequestid=0) OR p_payout_with_attendance = 'P' then
				-- 	if p_attendancesource ='bulkexcel' then
				if p_att_purpose ='Salary' then
					-- STEP 9: For 'Salary' purpose, deactivate existing attendance records for the provided dates
					truncate table tmpresponse;
					with tmp2 as (
						update tbl_monthly_attendance
						set isactive='0',
							attendance_salary_status='0',
							modifiedby=p_createdby,
							modifiedon=current_timestamp,
							modifiedbyip=p_createdbyip,
							marked_by_usertype=p_marked_by_usertype,
							marked_by=p_createdby,
							marked_on=current_timestamp,
							markedby_ip=p_createdbyip,
							markedbycustomeraccountid=case when p_marked_by_usertype='Employer' then p_createdby else null end
						from tmpbulkattendance						
						where tbl_monthly_attendance.att_date=to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')
						and tbl_monthly_attendance.emp_code=p_emp_code
						and attendance_salary_status='1'
						-- and COALESCE(attendancesource,'') = 'bulkexcel'
						-- and tbl_monthly_attendance.approval_status='P'
						-- and (tmpbulkattendance.attendancetype<>'CLS' and tmpbulkattendance.attendancetype<>'CL')
						returning att_date
					)
				insert into tmpresponse
				select tmp2.att_date,'Updated' from tmp2;
				v_alertmsg:=coalesce(v_alertmsg,'')||coalesce(','||(select string_agg(att_date::text||' Marked '||tmpresponse.op,', ') from tmpresponse ),'');
				v_alertmsg:=trim(v_alertmsg,',');
				truncate table tmpresponse;
				-- STEP 10: Insert new active attendance records mapped with holiday/weekly-off logic
				with tmp3 as(
					-- CHANGE [1.7]
					INSERT INTO public.tbl_monthly_attendance(
						emp_code,customeraccountid,attendance_type, att_date, createdby, createdon, createdbyip, isactive,approval_status, marked_by_usertype,
								marked_by, marked_on, markedby_ip,leavetype,leavebankid,attendancesource
						,att_type_proposed,leave_ctg
					,calendar_type,payroll_month,payroll_year,calendarid
					,attendance_salary_status,is_attendance_salary)
				select p_emp_code,p_customeraccountid,tmpbulkattendance.attendancetype,to_timestamp(tmpbulkattendance.attendancedate,'dd/mm/yyyy'),p_createdby,current_timestamp,p_createdbyip,'0',CASE WHEN COALESCE(p_attendancesource,'') = 'bulkexcel' THEN 'P' WHEN p_payout_with_attendance = 'P' THEN 'P' ELSE 'P' END,p_marked_by_usertype,
							p_createdby,current_timestamp,p_createdbyip,leavetype,nullif(p_leavebankid,0),p_attendancesource
			        ,tmpho.wo_ho_type
					,case when coalesce(tmpbulkattendance.leave_ctg,'')='Unpaid' then 'Unpaid' else 'Paid' end
					,v_mst_account_custom_month_settings.month_category,v_month,v_year,nullif(v_mst_account_custom_month_settings.row_id,-9999)
					,'1','Salary'
					from tmpbulkattendance 
			left join (select * from public.usp_get_weekly_off_n_holiday_dates (p_accountid =>p_customeraccountid, p_emp_id  =>v_openappointments.emp_id,p_month =>v_month,p_year =>v_year)) tmpho on to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')=tmpho.weekly_off_ho_date
					where (p_emp_code,to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy'))
					not in (select tbl_monthly_attendance.emp_code,tbl_monthly_attendance.att_date
							from public.tbl_monthly_attendance
							 where tbl_monthly_attendance.emp_code=p_emp_code
								and tbl_monthly_attendance.attendance_salary_status='1')
					and (tmpbulkattendance.attendancetype<>'CLS' and tmpbulkattendance.attendancetype<>'CL')
					and to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')>=v_doj
					and to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')<=coalesce(v_dateofrelieveing,to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy'))
				returning att_date
				)
				insert into tmpresponse
				select tmp3.att_date,'Inserted' from tmp3;
				v_alertmsg:=coalesce(v_alertmsg,'')||coalesce(','||(select string_agg(att_date::text||' Marked ',', ') from tmpresponse ),'');
				v_alertmsg:=trim(v_alertmsg,',');
			else
				-- STEP 9 (Alternative): Clear specific existing leave records (CLS, CL)
				with tmp2 as
				(
					update tbl_monthly_attendance
					set isactive='0',
						modifiedby=p_createdby,
						modifiedon=current_timestamp,
						modifiedbyip=p_createdbyip,
						marked_by_usertype=p_marked_by_usertype,
						marked_by=p_createdby,
						marked_on=current_timestamp,
						markedby_ip=p_createdbyip,
						markedbycustomeraccountid=case when p_marked_by_usertype='Employer' then p_createdby else null end
					from tmpbulkattendance
					where tbl_monthly_attendance.att_date=to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')
					and tbl_monthly_attendance.emp_code=p_emp_code
					and tbl_monthly_attendance.isactive='1'
					--and coalesce(tbl_monthly_attendance.approval_status,'P')='P'
					and (tmpbulkattendance.attendancetype='CLS'	or tmpbulkattendance.attendancetype='CL')	
					returning att_date)
					insert into tmpresponse
					select tmp2.att_date,'Cleared' from tmp2;
			
					select string_agg(att_date::text||' '||tmpresponse.op,', ') from tmpresponse into v_alertmsg;
					v_alertmsg:=trim(v_alertmsg,',');
					/********************************************************************/
					/* vinod comment on 09.10.2025 as disscussed not remove the punches from tbl_attendance
					IF p_payout_with_attendance = 'P' THEN -- CHANGE [1.7]
						update public.tbl_attendance
						set isactive='0',
							modifiedon=current_timestamp,
							modifiedbyip=p_createdbyip	
						from tmpresponse
						where tbl_attendance.check_in_time::date=tmpresponse.att_date
						and tbl_attendance.emp_code=p_emp_code
						and tbl_attendance.isactive='1'
						--and coalesce(tbl_attendance.approval_status,'P')='P';
					END IF;
					*/

					/********************************************************************/
					truncate table tmpresponse;
					-- STEP 10 (Alternative): Update existing attendance records with new bulk data
					with tmp2 as
					(
						update tbl_monthly_attendance
						set attendance_type=tmpbulkattendance.attendancetype,
							att_catagory =  NULLIF(tmpbulkattendance.att_catagory,'') ,
							leavetype=tmpbulkattendance.leavetype,
							modifiedby=p_createdby,
							modifiedon=current_timestamp,
							modifiedbyip=p_createdbyip,
							marked_by_usertype=p_marked_by_usertype,
							marked_by=p_createdby,
							marked_on=current_timestamp,
							markedby_ip=p_createdbyip,
							approval_status = CASE WHEN COALESCE(attendancesource,'') = 'bulkexcel' THEN approval_status WHEN p_payout_with_attendance = 'P' THEN 'P' ELSE 'P' END, -- CHANGE [1.7]
							markedbycustomeraccountid=case when p_marked_by_usertype='Employer' then p_createdby else null end,
							leavebankid=nullif(p_leavebankid,0),
							attendancesource=case when coalesce(attendancesource,'') = 'bulkexcel' then attendancesource else p_attendancesource end,
							leave_ctg=case when coalesce(tmpbulkattendance.leave_ctg,'')='Unpaid' then 'Unpaid' else 'Paid' end,
							calendar_type=v_mst_account_custom_month_settings.month_category,
							payroll_month=v_month,
							payroll_year=v_year,
							calendarid=nullif(v_mst_account_custom_month_settings.row_id,-9999)
						from tmpbulkattendance						
						where tbl_monthly_attendance.att_date=to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')
						and tbl_monthly_attendance.emp_code=p_emp_code
						and tbl_monthly_attendance.isactive='1'
						--and tbl_monthly_attendance.approval_status='P'
						and (tmpbulkattendance.attendancetype<>'CLS' and tmpbulkattendance.attendancetype<>'CL')
						returning att_date)	
						insert into tmpresponse
						select tmp2.att_date,'Updated' from tmp2;
						v_alertmsg:=coalesce(v_alertmsg,'')||coalesce(','||(select string_agg(att_date::text||' Marked '||tmpresponse.op,', ') from tmpresponse ),'');
						v_alertmsg:=trim(v_alertmsg,',');
						truncate table tmpresponse;
						-- STEP 11: Insert new attendance records for dates missing in the system
						with tmp3 as(
						-- CHANGE [1.7]
						INSERT INTO public.tbl_monthly_attendance(
							emp_code,customeraccountid,attendance_type, att_date, createdby, createdon, createdbyip, isactive,approval_status, marked_by_usertype,
									marked_by, marked_on, markedby_ip,leavetype,leavebankid,attendancesource
							,att_type_proposed,leave_ctg
						,calendar_type,payroll_month,payroll_year,calendarid,att_catagory)
						select p_emp_code,p_customeraccountid,tmpbulkattendance.attendancetype,to_timestamp(tmpbulkattendance.attendancedate,'dd/mm/yyyy'),p_createdby,current_timestamp,p_createdbyip,'1',CASE WHEN COALESCE(p_attendancesource,'') = 'bulkexcel' THEN 'P' WHEN p_payout_with_attendance = 'P' THEN 'P' ELSE 'P' END,p_marked_by_usertype,
									p_createdby,current_timestamp,p_createdbyip,leavetype,nullif(p_leavebankid,0),p_attendancesource
							,tmpho.wo_ho_type
							,case when coalesce(tmpbulkattendance.leave_ctg,'')='Unpaid' then 'Unpaid' else 'Paid' end
							,v_mst_account_custom_month_settings.month_category,v_month,v_year,nullif(v_mst_account_custom_month_settings.row_id,-9999),
							NULLIF(tmpbulkattendance.att_catagory,'')::varchar
							from tmpbulkattendance 
					left join (select * from public.usp_get_weekly_off_n_holiday_dates (p_accountid =>p_customeraccountid, p_emp_id  =>v_openappointments.emp_id,p_month =>v_month,p_year =>v_year)) tmpho on to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')=tmpho.weekly_off_ho_date
							where (p_emp_code,to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy'))
							not in (select tbl_monthly_attendance.emp_code,tbl_monthly_attendance.att_date
									from public.tbl_monthly_attendance
									 where tbl_monthly_attendance.emp_code=p_emp_code
										and tbl_monthly_attendance.isactive='1')
							and (tmpbulkattendance.attendancetype<>'CLS' and tmpbulkattendance.attendancetype<>'CL')
							and to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')>=v_doj
							and to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')<=coalesce(v_dateofrelieveing,to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy'))
						returning att_date)
						insert into tmpresponse
						select tmp3.att_date,'Inserted' from tmp3;
						v_alertmsg:=coalesce(v_alertmsg,'')||coalesce(','||(select string_agg(att_date::text||' Marked ',', ') from tmpresponse ),'');
						v_alertmsg:=trim(v_alertmsg,',');
				end if;	
			end if;		
		begin
			-- STEP 12: Trigger user alerts if attendance is marked by an Employee directly
			if p_marked_by_usertype='Employee' then
				select emp_name,customeraccountid from openappointments where emp_code=p_emp_code  into v_emp_name,v_customeraccountid;
				if (select count(*) from tmpresponse)=1 and (select att_date from tmpresponse)=current_date then
					perform usppopulatetpalerts
					(
						p_action =>'PopulateAlert',
						p_js_id =>-9999,p_customeraccountid =>v_customeraccountid,
						p_alertusertype =>'Employer',
						p_alerttypeid =>1,
						p_alertmessage=>v_emp_name||' marked their attendance for today ('||v_alertmsg||')'
				   );
				else
					perform usppopulatetpalerts
					(
						p_action =>'PopulateAlert',
						p_js_id =>-9999,p_customeraccountid =>v_customeraccountid,
						p_alertusertype =>'Employer',
						p_alerttypeid =>3,
						p_alertmessage=>v_emp_name||' marked their attendance for Dates ('||v_alertmsg||')'
					);
				end if;
			end if;					
	/*************Change 1.3 starts*********************/

	/*************change 1.4 starts*********************************/	
begin

	perform usp_manage_att_status_before_approval(
		p_action =>'modify_attendance_type_for_HO_WO',
		p_account_id =>p_customeraccountid::varchar,
		p_emp_code =>p_emp_code::varchar,
		p_mprmonth=>v_month::varchar,
		p_mpryear =>v_year::varchar,
		p_user_ip =>p_createdbyip::varchar,
		p_user_by =>p_createdby::varchar);

exception when others then
null;
end;
/*************change 1.4 ends*********************************/

-- 	perform 	uspwagesfromattendance_pregenerate(
-- 						p_action =>'GenerateWages_pregenerate',
-- 						p_emp_code =>p_emp_code,
-- 						p_createdby =>p_customeraccountid,
-- 						p_createdbyip =>'::1',
-- 						p_month =>v_month,
-- 						p_year =>v_year);
	/*************Change 1.3 ends*********************/
		-- exception when others then
		-- null;
		end;
		select array_to_json(array_agg(tmpresponse.att_date||' '||tmpresponse.op)) into msg from tmpresponse;
		return msg;
	end if;

		if p_action='ApproveBulkAttendance' or p_action='LockAttendance' then
			-- --------------------------------------------------------------------------------------
			-- 2. ATTENDANCE APPROVAL FLOW ('ApproveBulkAttendance' / 'LockAttendance')
			-- Validates if advance attendance or locked payment advices exist. If clear, updates
			-- 'tbl_monthly_attendance' records to Approved ('A') status.
			-- --------------------------------------------------------------------------------------
			select extract('month' from to_date(attendancedate,'dd/mm/yyyy'))::int, extract('year' from to_date(attendancedate,'dd/mm/yyyy'))::int 
			from tmpbulkattendance limit 1
			into v_month,v_year;
			if coalesce(p_month_direction,'N')<>'N' then
				v_month=p_month;
				v_year:=p_year;
			end if;	
			--RAISE NOTICE 'v_month => %', v_month;
			--RAISE NOTICE 'v_year => %', v_year;

			-- START - Change [2.1]
				-- STEP 1: Check for any pending mis-punch validations before proceeding with approval
				IF p_action='ApproveBulkAttendance' THEN
					SELECT public.usp_manage_att_status_before_approval
					(
						p_action => 'check_att_status_before_approval'::character varying,
						p_account_id => p_customeraccountid::character varying,
						p_emp_code => p_emp_code::character varying,
						p_mprmonth => v_month::character varying,
						p_mpryear => v_year::character varying,
						p_user_ip => p_createdbyip::character varying,
						p_user_by => p_createdby::character varying,
						p_attendance_purpose => p_att_purpose::character varying
					) INTO v_check_att_status_before_approval;
					IF (v_check_att_status_before_approval::JSONB ->> 'msgcd') = '0' THEN
						RETURN 'MisPunchError:'||(v_check_att_status_before_approval::JSONB ->> 'msg');
					END IF;
				END IF;
			-- END - Change [2.1]

			-- STEP 2: Abort if payment advice is already locked
			IF EXISTS (
				SELECT DISTINCT emp_code
				FROM paymentadvice
				WHERE paiddays > 0
				  AND attendancemode = 'MPR'
				  AND paymentadvice.customeraccountid = p_customeraccountid
				  AND v_year = paymentadvice.mpryear
				  AND v_month = paymentadvice.mprmonth
				  AND emp_code = p_emp_code
				  AND advicelockstatus = 'Locked'
			) THEN
				RETURN 'Already Locked.';
			END IF;

/*****************************Change 2.0 starts*****************************************************/
			v_rec_payrolldates:=null;
			select null::date start_dt,null::date end_dt into v_rec_payrolldates;		
if coalesce(p_month_direction,'N')<>'N' then
		SELECT 
		-- added on 23.06.2025 vinod
		(CASE WHEN p_month_direction='F' THEN make_date(v_year::int, v_month::int,p_month_start_day)::date
		ELSE (make_date(v_year::int, v_month::int,p_month_start_day)- interval '1 month') END)::date  start_dt,
		
		CASE WHEN p_month_direction='F' THEN (make_date(v_year::int, v_month::int,p_month_end_day)+ interval '1 month')::date  
		ELSE make_date(v_year::int, v_month::int,p_month_end_day)::date  END end_dt
		-- added on 23.06.2025	 
		
		/* make_date(v_year::int, v_month::int, month_start_day)::date start_dt,
			(make_date(v_year::int, v_month::int, month_end_day) + INTERVAL '1 month')::date end_dt
			*/
		into v_rec_payrolldates;
else		
		v_rec_payrolldates.start_dt:=make_date(v_year::int, v_month::int,1);
		v_rec_payrolldates.end_dt:=(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date;
		--Raise Notice 'v_rec_payrolldates.start_dt=%,v_rec_payrolldates.end_dt=%',v_rec_payrolldates.start_dt,v_rec_payrolldates.end_dt;		
end if;		
			-- STEP 3: Abort if advance attendance is already marked for 'Attendance' purpose
			IF EXISTS (
				SELECT DISTINCT emp_code
				FROM tbl_monthly_attendance
				where emp_code=p_emp_code
						and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
						and attendance_salary_status='1'
						and lower(is_attendance_salary)='salary' 
			) 
			and p_att_purpose='Attendance'
			THEN
				RETURN 'Advance attendance already exists.';
			END IF;
/*****************************Change 2.0 ends*****************************************************/	
			-- STEP 4: Update matching attendance records to Approved ('A')
			with tmp2 as
			(
				update tbl_monthly_attendance
				set approval_status='A',
					modifiedby=p_createdby,
					modifiedon=current_timestamp,
					modifiedbyip=p_createdbyip,
					approved_by=p_customeraccountid,
					approved_on=current_timestamp,
					approved_by_ip=p_createdbyip
				from tmpbulkattendance
				where tbl_monthly_attendance.att_date=to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')
					  and tbl_monthly_attendance.att_date between greatest(v_rec_payrolldates.start_dt,v_openappointments.dateofjoining) and least(v_rec_payrolldates.end_dt,coalesce(v_openappointments.dateofrelieveing,v_rec_payrolldates.end_dt))
				and tbl_monthly_attendance.emp_code=p_emp_code
-- 				and tbl_monthly_attendance.isactive='1'
				--SIDDHARTH BANSAL 25/03/2025
				AND 
				(
					(tbl_monthly_attendance.isactive = '1' AND p_att_purpose = 'Attendance' AND tbl_monthly_attendance.attendance_salary_status = '0' AND tbl_monthly_attendance.is_attendance_salary = p_att_purpose)  
					OR  
					(tbl_monthly_attendance.attendance_salary_status = '1' AND p_att_purpose = 'Salary' AND tbl_monthly_attendance.isactive = '0' AND tbl_monthly_attendance.is_attendance_salary = p_att_purpose)
				)
				--END
				and tbl_monthly_attendance.approval_status='P'
				and tbl_monthly_attendance.att_date>=v_doj
				and to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')<=coalesce(v_dateofrelieveing,to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy'))
				-- comment on 14.04.2025 
				-- and coalesce(attendancesource,'application')= case when p_attendancesource ='bulkexcel' then 'bulkexcel' else coalesce(attendancesource,'application') end
				returning att_date
			)
			insert into tmpresponse
			select tmp2.att_date, 'Approved' from tmp2;	
			select array_to_json(array_agg(tmpresponse.att_date||' '||tmpresponse.op)) into msg from tmpresponse;
		--select count(*) from tbl_monthly_attendance where emp_code = p_emp_code and approval_status='A' and isactive='1' and date_trunc('month',att_date)='2025-04-01' into v_cnt;	
		--raise notice 'uspsavebulkattendance_business====>Count=%',v_cnt;
	/*************Change 1.2 starts*********************/
			--begin
				select uspupdatetaonadvice	(p_customeraccountid =>p_customeraccountid,p_month=>v_month,p_year=>v_year,
							 p_geofenceid=>0,p_emp_code =>p_emp_code,
							 p_createdby=>p_createdby,p_createdbyip=>p_createdbyip)
				into v_rfcadvice;
			--exception when others then
			--	null;
			--end;
	/*************Change 1.2 ends*********************/	
	/*************Change 1.3 starts*********************/		/*****************Change 1.13 starts*************/		
		-- STEP 5: Apply late coming and early going fines to the employee ledger (if applicable)
		if not EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array((select COALESCE(COALESCE(NULLIF(op.assigned_ou_ids, ''),'0')) from openappointments op where op.emp_code=p_emp_code), ',')) AS input_ou_ids
		WHERE input_ou_ids::bigint in (select id from tbl_org_unit_geofencing where is_attendance_leave_only='Y')
		) then
		
		/**************************1.8 starts**********************************************/
/*
		SELECT 
				-- added on 23.06.2025 vinod
				(CASE WHEN month_direction='F' THEN make_date(v_year::int, v_month::int,month_start_day)::date
				ELSE (make_date(v_year::int, v_month::int,month_start_day)- interval '1 month') END)::date  start_dt,
				
				CASE WHEN month_direction='F' THEN (make_date(v_year::int, v_month::int,month_end_day)+ interval '1 month')::date  
				ELSE make_date(v_year::int, v_month::int,month_end_day)::date  END end_dt
				-- added on 23.06.2025	 
			
			/* make_date(v_year::int, v_month::int, month_start_day)::date start_dt,
			(make_date(v_year::int, v_month::int, month_end_day) + INTERVAL '1 month')::date end_dt
			*/
		into v_rec_payrolldates
		from mst_account_custom_month_settings 
		where account_id= p_customeraccountid and status='1'  AND month_start_day <>0;
		v_rec_payrolldates.start_dt:=coalesce(v_rec_payrolldates.start_dt,make_date(v_year::int, v_month::int,1));
		v_rec_payrolldates.end_dt:=coalesce(v_rec_payrolldates.end_dt,(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date);
		Raise Notice 'v_rec_payrolldates.start_dt=%,v_rec_payrolldates.end_dt=%',v_rec_payrolldates.start_dt,v_rec_payrolldates.end_dt;		
*/
	if (p_att_purpose = 'Attendance' /*and current_date>v_rec_payrolldates.end_dt commented on 18-Sep-2025*/)  then	
			select sum(latehoursdeduction) latehoursdeduction,sum(earlyhoursdeduction) earlyhoursdeduction
			from tbl_monthly_attendance 
			where emp_code=p_emp_code 
			and customeraccountid=p_customeraccountid
			and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
			and isactive='1'
			and approval_status='A'	
			and no_of_hours_worked is not null
			into v_finerecord;
			
		update tbl_employeeledger set isactive='0'
		where emp_code=p_emp_code and headid in (171,172) 
		and processmonth=v_month
		and processyear=v_year
		and isactive='1' and coalesce(isledgerdisbursed,'0')='0';
	if coalesce(v_finerecord.latehoursdeduction,0)>0 then
	insert into tbl_employeeledger
	(
		emp_id,emp_code,headid,headname,amount,processmonth,processyear,
		isactive,createdby,createdon,createdbyip,masterhead,is_taxable,is_billable,remarks
	)
	select null,p_emp_code,171,'Late Coming Fine',v_finerecord.latehoursdeduction*-1,v_month,v_year,
		'1',p_createdby,current_timestamp,p_createdbyip ,'Deduction','N','Y','Late Coming Fine';
	end if;
	if coalesce(v_finerecord.earlyhoursdeduction,0)>0 then	
	insert into tbl_employeeledger
	(
		emp_id,emp_code,headid,headname,amount,processmonth,processyear,
		isactive,createdby,createdon,createdbyip,masterhead,is_taxable,is_billable,remarks
	)
	select null,p_emp_code,172,'Early Going Fine',v_finerecord.earlyhoursdeduction*-1,v_month,v_year,
		'1',p_createdby,current_timestamp,p_createdbyip ,'Deduction','N','Y','Early Going Fine';
	end if;	
	end if;
	/**************************1.8 ends***********************************************/			
		/*****************Change 1.13 ends*************/
RAISE NOTICE 'Pre Payment  Advice block';
			-- --------------------------------------------------------------------------------------
			-- 3. TAX & PRE-WAGE CALCULATION FLOW 
			-- Calls 'uspwagesfromattendance_pregenerate' to calculate preliminary wages, 
			-- applicable taxes, and deductions based on the approved attendance days.
			-- --------------------------------------------------------------------------------------
			select 	uspwagesfromattendance_pregenerate(
						p_action =>'GenerateWages_pregenerate',
						p_emp_code =>p_emp_code,
						p_createdby =>p_customeraccountid,
						p_createdbyip =>'::1',
						p_month =>v_month,
						p_year =>v_year)
						into v_rfcadvice;
RAISE NOTICE 'post Payment  Advice block';

	/*************Change 1.3 ends*********************/
	end if;
			RAISE NOTICE 'p_emp_code => %', p_emp_code;
			if p_action='LockAttendance' then		
				begin
					-- --------------------------------------------------------------------------------------
					-- 4. ATTENDANCE LOCK & WAGE GENERATION FLOW ('LockAttendance')
					-- Freezes the attendance for the month and triggers 'uspcreatewagesfromattendance' 
					-- to formally move the attendance data into actual wages for final payout processing.
					-- --------------------------------------------------------------------------------------
					perform public.uspcreatewagesfromattendance
					(
						p_action =>'MoveAttendanceToWages',
						p_emp_code =>p_emp_code,
						p_createdby =>p_createdby,
						p_createdbyip =>p_createdbyip,
						p_month =>v_month,
						p_year =>v_year
					);
					-- exception when others then
				end;
			end if;
			--RAISE NOTICE 'msg => %', msg;
			return msg;
		end if;
	end if;

	-- ==========================================================================================
	-- FLOW: FINAL PAYOUT AND SALARY PROCESSING ('PaySalary')
	-- Iterates through eligible employees to convert flexi or standard attendance into final 
	-- wage records. This applies all calculated taxes, updates ledgers, and readies for final payout.
	-- ==========================================================================================
	if p_action='PaySalary' then		
		begin

		-- STEP 1: Parse Year and Month from the incoming JSON payload
		select (p_attendancedates::jsonb ->> 'Year')::int ,(p_attendancedates::jsonb ->> 'Month')::int limit 1
		into v_year,v_month;

		-- STEP 2: Iterate through active employees assigned to the account
		for v_emp_code in(select oa.emp_code
					  		from tbl_account ta inner join openappointments oa 
							on oa.customeraccountid = ta.id 
							and ta.status = '1' and oa.converted = 'Y' and oa.appointment_status_id = '11'
							and ta.id=p_customeraccountid
						  	and not(coalesce(oa.is_account_verified,'0')='0' and v_payout_mode_type='standard')
							and date_trunc('month',oa.dateofjoining)::date <=make_date (v_year,v_month,1)
							and (oa.dateofrelieveing is null or oa.dateofrelieveing>=make_date (v_year,v_month,1))
					) loop

			-- STEP 3: Convert attendance records into final wages
			if exists(select tm.* from tbl_monthwise_flexi_attendance tm where tm.emp_code=v_emp_code
							and tm.attendancemonth=v_month	and tm.attendanceyear=v_year and tm.isactive='1') then
				-- Process flexi attendance to wages
				select public.uspcreatewagesfromflexiattendance(
						p_action =>'MoveAttendanceToWages',
						p_emp_code =>v_emp_code,
						p_createdby =>p_createdby,
						p_createdbyip =>p_createdbyip,
						p_month =>v_month,
						p_year =>v_year)
						into v_tempmgs;
				msg:=msg||coalesce(v_tempmgs,'');
				raise notice '%',v_tempmgs;
			else
				-- Clean up old payment advice and process standard attendance to wages
				delete from paymentadvice where emp_code=v_emp_code and mprmonth=v_month and mpryear=v_year; /******change 1.3********/
				select public.uspcreatewagesfromattendance(
						p_action =>'MoveAttendanceToWages',
						p_emp_code =>v_emp_code,
						p_createdby =>p_createdby,
						p_createdbyip =>p_createdbyip,
						p_month =>v_month,
						p_year =>v_year)
						into v_tempmgs;
				msg:=msg||coalesce(v_tempmgs,'');
			end if;
		end loop;
		/**************************change 1.1 starts****(Commented on 09-Oct-2023)*********************************************
				update tbl_receivables 
				set credit_used='Y',mdified_on=current_timestamp,
				mdified_by=p_createdby,mdified_byip=p_createdbyip	
				where  customeraccountid=p_customeraccountid 
					and coalesce(credit_applicable,'N')='Y'
					and coalesce(credit_used,'N')='N' 
					and isactive='1';
		**************************change 1.1 ends*************************************************/						
		end;	
		return msg;	
	end if;	
-- 	exception when others then
-- 		return 'Some Error Occurred';

	-- ==========================================================================================
	-- FLOW: DAILY ATTENDANCE APPROVAL & DIRECT PAYOUT ('ApproveDailyAttendance')
	-- Handles multi-payout scenarios. Approves daily attendance, computes taxes/wages 
	-- via 'pregenerate', and directly creates a payout advice via 'uspcreatepayoutfromadvice'.
	-- ==========================================================================================
	if p_action='ApproveDailyAttendance' then
			
		-- STEP 1: Determine payroll date ranges and boundaries
		v_month=p_month;
				v_year:=p_year;
				select * from openappointments where emp_code=p_emp_code into v_openappointments;
				v_doj:=v_openappointments.dateofjoining;
				v_dateofrelieveing:=v_openappointments.dateofrelieveing;

			select null::date start_dt,null::date end_dt into v_rec_payrolldates;
			if p_month_direction='N' then
				v_rec_payrolldates.start_dt:=make_date(v_year::int, v_month::int,1);
				v_rec_payrolldates.end_dt:=(make_date(v_year::int, v_month::int,1)+ interval '1 month -1 day')::date;
			else
				SELECT 
				(CASE WHEN p_month_direction='F' THEN make_date(v_year::int, v_month::int,p_month_start_day)::date
				ELSE (make_date(v_year::int, v_month::int,p_month_start_day)- interval '1 month') END)::date  start_dt,

				CASE WHEN p_month_direction='F' THEN (make_date(v_year::int, v_month::int,p_month_end_day)+ interval '1 month')::date  
				ELSE make_date(v_year::int, v_month::int,p_month_end_day)::date  END end_dt
				into v_rec_payrolldates;
			end if;		
				
		-- STEP 2: Prepare temporary tables for incoming daily attendance data
		if to_regclass('pg_temp.tmpbulkattendance') IS NULL then
																							  
			 
		create temporary table tmpbulkattendance 
		(
			attendancedate text,
			attendancetype text,
			leavetype text,
			leave_ctg text
		) on commit drop;
		else
			truncate table tmpbulkattendance;
		end if;	
		
		if to_regclass('pg_temp.tmpresponse') IS NULL then		
																						
			   
		create temporary table tmpresponse
		(
			att_date date,
			op text
		) on commit drop;
		else
			truncate table tmpresponse;
		end if;
		
				-- STEP 3: Parse JSON payload to extract daily attendance records
				insert into tmpbulkattendance
				select * from json_populate_recordset(null::type_attendancedates_business, p_attendancedates::json);

			-- STEP 4: Prevent daily approval if a single full-month payout already exists
			IF EXISTS (
						SELECT DISTINCT emp_code
						FROM paymentadvice
						WHERE paiddays > 0
						  AND attendancemode = 'MPR'
						  AND paymentadvice.customeraccountid = p_customeraccountid
						  AND v_year = paymentadvice.mpryear
						  AND v_month = paymentadvice.mprmonth
						  AND emp_code = p_emp_code
					) THEN
				RETURN 'Single Payout Already exists.';
			END IF;
			IF EXISTS (
						SELECT DISTINCT emp_code
						FROM tbl_monthlysalary
						WHERE paiddays > 0
						  AND attendancemode = 'MPR'
						  AND v_year = tbl_monthlysalary.mpryear
						  AND v_month = tbl_monthlysalary.mprmonth
						  AND emp_code = p_emp_code
						  and is_rejected='0'
						  AND COALESCE(multipayoutrequestid,0)=0 
					) THEN
				RETURN 'Single Payout Already exists.';
			END IF;
/*****************************Change 2.0 ends*****************************************************/	
		-- STEP 5: Generate a unique ID for the multi-payout request
		v_multipayoutrequestid:=nextval('seq_multipayoutrequest'::regclass);

			-- STEP 6: Update specific daily attendance records to Approved ('A') under Multi-Payout ('MAP')
			with tmp2 as
			(
				update tbl_monthly_attendance
				set approval_status='A',
					modifiedby=p_createdby,
					modifiedon=current_timestamp,
					modifiedbyip=p_createdbyip,
					approved_by=p_customeraccountid,
					approved_on=current_timestamp,
					approved_by_ip=p_createdbyip,
					payout_frequencytype='MAP',
					multipayoutrequestid=v_multipayoutrequestid
				from tmpbulkattendance
				where tbl_monthly_attendance.att_date=to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')
					  and tbl_monthly_attendance.att_date between greatest(v_rec_payrolldates.start_dt,v_openappointments.dateofjoining) and least(v_rec_payrolldates.end_dt,coalesce(v_openappointments.dateofrelieveing,v_rec_payrolldates.end_dt))
				and tbl_monthly_attendance.emp_code=p_emp_code
-- 				and tbl_monthly_attendance.isactive='1'
				and tbl_monthly_attendance.approval_status='P'
				and tbl_monthly_attendance.att_date>=v_doj
				and to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy')<=coalesce(v_dateofrelieveing,to_date(tmpbulkattendance.attendancedate,'dd/mm/yyyy'))
				and coalesce(multipayoutrequestid,0)=0
				returning att_date
			)
			insert into tmpresponse
			select tmp2.att_date, 'Approved' from tmp2;	
			select array_to_json(array_agg(tmpresponse.att_date||' '||tmpresponse.op)) into msg from tmpresponse;
			Raise Notice 'msg=%',msg;
		--select count(*) from tbl_monthly_attendance where emp_code = p_emp_code and approval_status='A' and isactive='1' and date_trunc('month',att_date)='2025-04-01' into v_cnt;	
		--raise notice 'uspsavebulkattendance_business====>Count=%',v_cnt;
	/*************Change 1.2 starts*********************/
			--begin
			/*	select uspupdatetaonadvice	(p_customeraccountid =>p_customeraccountid,p_month=>v_month,p_year=>v_year,
							 p_geofenceid=>0,p_emp_code =>p_emp_code,
							 p_createdby=>p_createdby,p_createdbyip=>p_createdbyip)
				into v_rfcadvice;
				*/
			--exception when others then
			--	null;
			--end;
	/*************Change 1.2 ends*********************/	
		if not EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array((select COALESCE(COALESCE(NULLIF(op.assigned_ou_ids, ''),'0')) from openappointments op where op.emp_code=p_emp_code), ',')) AS input_ou_ids
		WHERE input_ou_ids::bigint in (select id from tbl_org_unit_geofencing where is_attendance_leave_only='Y')
		) then
	/**************************1.8 ends***********************************************/			
		/*****************Change 1.13 ends*************/
			-- STEP 7: Pre-generate wages and tax calculations for the approved daily dates
			select 	uspwagesfromattendance_pregenerate(
						p_action =>'GenerateWages_pregenerate',
						p_emp_code =>p_emp_code,
						p_createdby =>p_customeraccountid,
						p_createdbyip =>'::1',
						p_month =>v_month,
						p_year =>v_year,
						p_multipayoutrequestid=>v_multipayoutrequestid)
						into v_rfcadvice;
						
						select * into v_recadvice from paymentadvice 
						where 	multipayoutrequestid=v_multipayoutrequestid;			
	
						if not v_recadvice is null then
						
						Raise Notice 'p_emp_code=%,p_createdby=%,p_createdbyip=%',p_emp_code,p_createdby,p_createdbyip;
						Raise Notice 'v_recadvice.mprmonth=%,>v_recadvice.mpryear=%,p_createdbyip=%,v_paymentadvice.emp_code=%',v_recadvice.mprmonth,v_recadvice.mpryear,p_createdbyip,v_recadvice.emp_code;
						Raise Notice 'v_multipayoutrequestid=%',v_multipayoutrequestid;

						-- STEP 8: Finalize the payout by moving advice data to formal payment records
						call public.uspcreatepayoutfromadvice
							(
								p_action =>'MoveAttendanceToWages',
								p_emp_code =>p_emp_code,
								p_createdby =>p_createdby,
								p_createdbyip =>p_createdbyip,
								p_month =>v_recadvice.mprmonth,
								p_year =>v_recadvice.mpryear,
								p_payment_record_id=>-9999,
								p_paymentadvice=>v_recadvice,
								p_multipayoutrequestid=>v_multipayoutrequestid
							);
						-- Clean up temporary advice data linked to this multi-payout request
						delete from paymentadvice where multipayoutrequestid=v_multipayoutrequestid;

						end if;	
				
	
	/*************Change 1.3 ends*********************/
	end if;
			return msg;
		end if;
end;
$BODY$;

ALTER FUNCTION public.uspsavebulkattendance_business(character varying, bigint, bigint, character varying, character varying, text, bigint, bigint, text, text, text, text, integer, integer, character varying, integer, integer)
    OWNER TO payrollingdb;

