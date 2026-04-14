-- FUNCTION: public.uspgetorderwisewages_pregenerate(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, character varying, text, text, bigint, numeric)

-- DROP FUNCTION IF EXISTS public.uspgetorderwisewages_pregenerate(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, character varying, text, text, bigint, numeric);

CREATE OR REPLACE FUNCTION public.uspgetorderwisewages_pregenerate(
	p_mprmonth integer,
	p_mpryear integer,
	p_ordernumber character varying DEFAULT NULL::character varying,
	p_emp_code bigint DEFAULT NULL::bigint,
	p_batch_no character varying DEFAULT NULL::character varying,
	p_action character varying DEFAULT NULL::character varying,
	p_createdby bigint DEFAULT NULL::bigint,
	createdbyip character varying DEFAULT NULL::character varying,
	p_criteria character varying DEFAULT NULL::character varying,
	p_process_status character varying DEFAULT NULL::character varying,
	p_issalaryorliability character varying DEFAULT 'S'::character varying,
	p_tptype character varying DEFAULT 'TP'::character varying,
	p_advice_attendancerecord text DEFAULT ''::text,
	p_advance_or_current text DEFAULT 'Current'::text,
	p_multipayoutrequestid bigint DEFAULT 0,
	p_fullmonthincentive numeric DEFAULT 0.0000)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$

declare 
sal refcursor;
v_monthdays int;
v_querytext text;
v_querytext2 text;
v_pausequery varchar;
p_createdbyip varchar(200);
v_innerprocresult int:=0;
v_lwfemployee numeric(18,2);
v_lwfemployer numeric(18,2);
v_lwftotal numeric(18,2);
v_lwfdeductionmonths varchar(50);
declare 
	v_empid bigint;
	v_startdate date;
	v_enddate date;
	v_advancestartdate date;
	v_advanceenddate date;
	v_financial_year varchar(9);
	v_year1 int;
	v_year2 int;
	v_salstartdate date;
	v_salenddate date;
	v_advancesalstartdate date;
	v_advancesalenddate date;
	v_prevsaldate date;
	v_pancard varchar(10);
	v_tppaiddays int;	
	v_cnt int;
	v_openappointments openappointments%rowtype;
	v_overtime numeric(18,2):=0;
	v_weekly_consecutive_overtime numeric(18,2):=0;
	v_empsalaryregister empsalaryregister%rowtype;
	v_actualdays int;
	v_tea_allowance  numeric(18,2):=0;
	v_rec_payrolldates record;
	v_cmsdownloadedwages cmsdownloadedwages%rowtype;
	v_attendancetablename varchar(100):='cmsdownloadedwages_pregenerate';
	v_finerecord record;
	v_shifthours numeric(18,2);
	v_tbl_account tbl_account%rowtype;
	v_isbackward varchar(1):='N';
	v_nextmonthdays int:=0;

				
							   
	v_totalsalarydays numeric(18,2):=0;
									 
	v_incentivedays numeric(18,2):=0;
									   
								  
						 
	v_holidaycount int:=0;
begin
																	
/*************************************************************************
Version Date			Change								Done_by
1.0		15-Mar-2021		Initial Version						Shiv Kumar
1.1		05-Apr-2021		Adding other arears					Shiv Kumar
1.2		06-Apr-2021		Adding ESI on Arears case			Shiv Kumar
1.3		10-Apr-2021		Adding Other Variables to			Shiv Kumar
						Gross Earning and Net Pay
1.4		05-May-2021		Handling Manual and Auto			Shiv Kumar
						attendance	
1.5		21-May-2021		Mid Month Increment					Shiv Kumar
1.6		19-Jul-2021		Lock Status							Shiv Kumar
1.7		10-Aug-2021		Unlock First Salary					Shiv Kumar
1.8		11-Aug-2021		Applying New Variable				Shiv Kumar
						Condition
1.9		13-Aug-2021		Applying New LWF  Logic				Shiv Kumar	
1.10	07-Sep-2021		Ledger Deductions for CTC2			Shiv Kumar
1.11	07-Sep-2021		VPF From Other Deductions			Shiv Kumar
1.12	24-Nov-2021		Adding Arrears in current salary	Shiv Kumar
						for Processed Records
1.13	30-Dec-2021		Deducting Gross Deduction Amount  	Shiv Kumar	
						CTC2 after Discussion with Yatin Sir
1.14	01-Mar-2022		Changing AC_1 and AC_10 Logic	  	Shiv Kumar
1.15	09-Mar-2022		Disable for relieved after F&F	  	Shiv Kumar
1.16	05-May-2022		Add Taxable Ledger Deduction	  	Shiv Kumar
1.17	03-Jun-2022		Current Month Tax on hrgenerated  	Shiv Kumar
1.18	01-Jul-2022		Save Liability on Set EPF/ECR	  	Shiv Kumar
1.19	27-Jul-2022		No Tax deduction 				  	Shiv Kumar
						when tax>=grossearning
1.20	28-Jul-2022		Separate Payrolling				  	Shiv Kumar
						 and Disbursement
1.20	09-Sep-2022		Handling Future Increment		  	Shiv Kumar						 
1.21	14-Sep-2022		Partialy Processed				  	Shiv Kumar	
1.22	10-Nov-2022		Tax on Pancard					  	Shiv Kumar
1.23	29-Dec-2022		TP Type Added					  	Shiv Kumar
1.24	20-Mar-2024		Add Conveyance					  	Shiv Kumar
1.25	13-May-2024		Temporary table anme changes	  	Shiv Kumar
1.26	17-May-2024		Taxable/Non Taxable Voucher		  	Shiv Kumar
1.27	29-May-2024		As per new Fixed Structure		  	Shiv Kumar
1.28	15-Jun-2024		For PT (Current month+Arrear) 		Shiv Kumar
						grossearning will be considered
1.29	18-Jun-2024		Add Daily Allowance	  				Shiv Kumar
1.30	01-Aug-2024		Add jobtype in Advice  				Shiv Kumar
1.31	29-Aug-2024		Shiftwise OT Calculation			Shiv Kumar
1.32	30-Aug-2024		Per Kilometer Calculation			Shiv Kumar
1.33	03-Sep-2024		Tea Allowance Calculation			Shiv Kumar
1.34	14-Feb-2025		Cross Month Attendance				Shiv Kumar
1.35	04-March-2025	Cross Month Start date and end date changes				Parveen Kumar
1.36	05-March-2025	Early going/ Late coming/OT			Shiv Kumar
1.37	11-March-2025	Contractual 1%TDS					Shiv Kumar
1.38	12-Apr-2025		Calculate overtime after every 		Shiv Kumar
						half hour completion	
1.39	24-Apr-2025		Change OT Rate Calculations			Shiv Kumar
1.40	07-May-2025		Independent Contractors TDS Calc.	Shiv Kumar
1.41	19-Jun-2025		TDSExemption check					Shiv Kumar
1.42	30-Jun-2025		Meal Voucher						Shiv Kumar
1.43	01-Jul-2025		Manual TDS							Shiv Kumar
1.44	24-Sep-2025		Gross and grossearning			Shiv Kumar
												 
																		 
1.46	10-Nov-2025		One day incentive					Shiv Kumar
1.47	02-Dec-2025		Add flexiblemonthdays				Shiv Kumar
1.49	16-Dec-2025		Add Incentivedays for hourlysetup	Shiv Kumar
1.50	10-Mar-2026		PT deduction Month should be        Vinod Kumar
						mpr month amount
1.51	31-Mar-2026		ta-days for Jivo ACCOUNT	        Vinod Kumar
************************************************************************/
	-- =================================================================================================
	-- 1. ATTENDANCE INITIALIZATION
	-- Extract download wages information based on attendance mode.
	-- If manual, take the direct values, else query the pregenerate table.
	-- attendance mode =>Ledger, MPR,Manual
	-- =================================================================================================
	select *
	into v_cmsdownloadedwages
	from cmsdownloadedwages
	where empcode = p_emp_code::text 
	  and isactive = '1' 
	  and batch_no = p_batch_no;

	if v_cmsdownloadedwages.attendancemode = 'Manual' then
		v_attendancetablename := '';
		v_totalsalarydays := coalesce(v_cmsdownloadedwages.totalpaiddays, 0) + coalesce(v_cmsdownloadedwages.totalleavetaken, 0);
	else
		select coalesce(cp.totalpaiddays, 0) + coalesce(cp.totalleavetaken, 0) 
		into v_totalsalarydays
		from cmsdownloadedwages_pregenerate cp;
	end if;

	-- =================================================================================================
	-- 2. DATES AND CONFIGURATION SETUP
	-- Calculate total days in the MPR month and fetch employee appointment/account profiles.
	-- Handle flexible month days and subtract holidays if opted.
	-- =================================================================================================
	v_monthdays := date_part('day', DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');
	
	select * from openappointments where emp_code = p_emp_code into v_openappointments;
	select * from tbl_account where id = v_openappointments.customeraccountid into v_tbl_account;
	select * from empsalaryregister where appointment_id = v_openappointments.emp_id and isactive = '1' into v_empsalaryregister;

	if coalesce(v_empsalaryregister.flexiblemonthdays, 'N') = 'Y' then
		select count(*) into v_holidaycount from public.usp_get_weekly_off_n_holiday_dates (
			p_accountid => v_tbl_account.id, 
			p_emp_id => v_openappointments.emp_id, 
			p_month => p_mprmonth, 
			p_year => p_mpryear
		);
		v_monthdays := v_monthdays - coalesce(v_holidaycount, 0);
	end if;

	v_actualdays := case 
		when coalesce(v_empsalaryregister.salaryindaysopted, 'N') = 'N' or v_empsalaryregister.salarydays = 1 or coalesce(v_empsalaryregister.flexiblemonthdays, 'N') = 'Y' 
		then v_monthdays  
		else v_empsalaryregister.salarydays 
	end;
	
	v_overtime := 0;

	-- =================================================================================================
	-- 3. SHIFT HOURS CALCULATION
	-- Fetch the shift hours based on manual input or default shift rules.
	-- =================================================================================================
	SELECT
		(CASE
			WHEN manual_input_shift_hours = 'manual_input' THEN
				EXTRACT(EPOCH FROM COALESCE(NULLIF(full_day_time, ''), '08:00:00')::INTERVAL)/60
			ELSE
				EXTRACT(EPOCH FROM COALESCE(NULLIF(default_shift_full_hours, ''), '08:00:00')::INTERVAL)/60
		END)/60
	INTO v_shifthours
	FROM vw_user_spc_emp WHERE emp_code = p_emp_code;

	-- =================================================================================================
	-- 4. INCENTIVE DAYS FOR HOURLY SETUP
	-- Limit total paid days to month days for hourly setups and put excess as incentive days.
	-- =================================================================================================
	if coalesce(v_empsalaryregister.ishourlysetup, 'N') = 'Y' then
		if v_totalsalarydays > v_monthdays then
			v_incentivedays := v_totalsalarydays - v_monthdays;
			update cmsdownloadedwages_pregenerate
			set totalpaiddays = least(v_totalsalarydays, v_monthdays)
			where empcode = p_emp_code::text;
		end if;
	end if;
/**************************1.49 ends***********************************************/
			
	   
	-- =================================================================================================
	-- 5. PAYROLL DATES CONFIGURATION
	-- Calculate the precise payroll start and end dates based on custom account settings.
	-- Handle shifting back one month (backward) or forward based on `month_direction`.
	-- =================================================================================================
	SELECT
		CASE WHEN month_direction = 'F' THEN make_date(p_mpryear::int, p_mprmonth::int, month_start_day)::date
			 ELSE (make_date(p_mpryear::int, p_mprmonth::int, month_start_day) - interval '1 month') 
		END as start_dt,
		CASE WHEN month_direction = 'F' THEN (make_date(p_mpryear::int, p_mprmonth::int, month_end_day) + interval '1 month')::date 
			 ELSE make_date(p_mpryear::int, p_mprmonth::int, month_end_day)::date  
		END as end_dt,
		month_start_day,
		month_direction				 
	into v_rec_payrolldates
	from mst_account_custom_month_settings 
	where account_id = v_openappointments.customeraccountid and status = '1' AND month_start_day <> 0;

	v_rec_payrolldates.start_dt := coalesce(v_rec_payrolldates.start_dt, make_date(p_mpryear::int, p_mprmonth::int, 1));
	v_rec_payrolldates.end_dt := coalesce(v_rec_payrolldates.end_dt, (make_date(p_mpryear::int, p_mprmonth::int, 1) + interval '1 month - 1 day')::date);

	if coalesce(v_rec_payrolldates.month_start_day, 0) > 1 and coalesce(v_rec_payrolldates.month_direction, 'N') = 'B' then
		v_nextmonthdays := v_monthdays;
		v_monthdays := date_part('day', DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE) - INTERVAL '1 DAY');
		v_isbackward := 'Y';
	end if;

	-- =================================================================================================
	-- 6. WEEKDAYS OVERTIME COMPUTATION
	-- Calculate standard overtime generated on regular working days based on shift, role, and attendance.
	-- =================================================================================================
	with v1 as(
select emp_code, a.id,c.ot_rule_name,c.effective_date,a.customeraccountid,a.overtime_rate,a.double_time_rate,a.category_type,a.category_type_name,
after_overtime_hours,after_doubletime_hours,default_shift_time_from,default_shift_time_to,is_night_shift,
	EXTRACT(epoch FROM (CASE
        WHEN default_shift_time_to >= default_shift_time_from THEN
            default_shift_time_to::time - default_shift_time_from::time
        ELSE
            (default_shift_time_to::time + interval '24 hours') - default_shift_time_from::time
    END)/3600) AS shifthours
	from tbl_tp_ot_rules_trn a  join mst_tp_otrule_category_type b on a.category_id=b.id
join tbl_tp_ot_rules_name c on a.otrule_id_fk=c.id  join vw_user_spc_emp v on a.shift_id=v.shift_id 
where a.isactive='1' and b.status='1' and c.isactive='1' and v.emp_code is not null
and emp_code=p_emp_code and a.customeraccountid=v_openappointments.customeraccountid
),
v2 as
(
select trim(to_char(att_date,'Day')) as attday,(left(trim(no_of_overtime_hours_worked),2)::numeric
+(substring(trim(no_of_overtime_hours_worked),4,2)::int/30)/2.0
)::numeric(18,4) as othours,(left(trim(no_of_hours_worked),2)::numeric
+(substring(trim(no_of_hours_worked),4,2)::int/30)/2.0
)::numeric(18,4) as workinghour, *
	from tbl_monthly_attendance 
	where emp_code=p_emp_code 
	and customeraccountid=v_openappointments.customeraccountid
	and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	--and date_trunc('month',att_date) = make_date(p_mpryear,p_mprmonth,1)
	and isactive='1'
	and approval_status='A'	
	and no_of_hours_worked is not null
	--and is_overtime='Y'
)
select
	sum
	(
		case
		when coalesce(after_doubletime_hours,0)=0 then
			greatest((coalesce(othours::numeric,0)),0)*coalesce(overtime_rate,0)*(v_empsalaryregister.gross/(case when v_empsalaryregister.salarydays=1 then 1 else v_actualdays end))/v_shifthours
		else
			greatest(coalesce(workinghour::numeric,0)-coalesce(after_doubletime_hours,0))*coalesce(double_time_rate,0)*(v_empsalaryregister.gross/(case when v_empsalaryregister.salarydays=1 then 1 else v_actualdays end))/v_shifthours+
			(greatest(coalesce(workinghour::numeric,0)-coalesce(after_overtime_hours,0)-greatest((coalesce(workinghour::numeric,0)-coalesce(after_overtime_hours,0)),0),0)*coalesce(overtime_rate,0)*(v_empsalaryregister.gross/(case when v_empsalaryregister.salarydays=1 then 1 else v_actualdays end))/v_shifthours)
		end
	)
	from v1 join v2
on ((v2.attendance_type='HO' and v1.category_type=4 and no_of_hours_worked is not null) or 
	(v2.attendance_type<>'HO' and v2.attday=v1.category_type_name and no_of_hours_worked is not null))
	
	into v_overtime;
	v_overtime := coalesce(v_overtime, 0);

	-- =================================================================================================
	-- 7. WEEKLY & CONSECUTIVE 7-DAYS OVERTIME COMPUTATION
	-- Evaluates total weekly hours and sums overtime exceeding base norms (Double Time logic included).
	-- =================================================================================================
	with v1 as(
select emp_code, a.id,c.ot_rule_name,c.effective_date,a.customeraccountid,a.overtime_rate,a.double_time_rate,a.category_type,a.category_type_name,
after_overtime_hours,after_doubletime_hours,default_shift_time_from,default_shift_time_to,is_night_shift,
	EXTRACT(epoch FROM (CASE
        WHEN default_shift_time_to >= default_shift_time_from THEN
            default_shift_time_to::time - default_shift_time_from::time
        ELSE
            (default_shift_time_to::time + interval '24 hours') - default_shift_time_from::time
    END)/3600) AS shifthours
	from tbl_tp_ot_rules_trn a  join mst_tp_otrule_category_type b on a.category_id=b.id
join tbl_tp_ot_rules_name c on a.otrule_id_fk=c.id  join vw_user_spc_emp v on a.shift_id=v.shift_id 
where a.isactive='1' and b.status='1' and c.isactive='1' and v.emp_code is not null
and emp_code=p_emp_code and a.customeraccountid=v_openappointments.customeraccountid
),
v2 as
(
select attweek,sum(workinghour) workinghour from(
select att_date,(trim(to_char(att_date,'dd'))::int-1)/7 as attweek,
trim(to_char(att_date,'dd'))::int as attdaynum,
(left(trim(no_of_hours_worked),2)::numeric
+(substring(trim(no_of_hours_worked),4,2)::int/30)/2.0
)::numeric(18,4) as workinghour, *
	from tbl_monthly_attendance 
	where emp_code=p_emp_code 
	and customeraccountid=v_openappointments.customeraccountid
	--and date_trunc('month',att_date) = make_date(p_mpryear,p_mprmonth,1)
	and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	and isactive='1'
	and approval_status='A'	
	and no_of_hours_worked is not null
	)tmp group by attweek 
 )
select
	sum
	(
		case
		when coalesce(after_overtime_hours,0)=0 or coalesce(workinghour::numeric,0)<=coalesce(after_overtime_hours,0) then
			0
		when coalesce(after_doubletime_hours,0)=0 then
			greatest((coalesce(workinghour::numeric,0)-coalesce(after_overtime_hours,0)),0)*coalesce(overtime_rate,0)*(v_empsalaryregister.gross/(case when v_empsalaryregister.salarydays=1 then 1 else v_actualdays end))/v_shifthours
		else
			greatest(coalesce(workinghour::numeric,0)-coalesce(after_doubletime_hours,0))*coalesce(double_time_rate,0)*(v_empsalaryregister.gross/(case when v_empsalaryregister.salarydays=1 then 1 else v_actualdays end))/v_shifthours+
			(greatest(coalesce(workinghour::numeric,0)-coalesce(after_overtime_hours,0)-greatest((coalesce(workinghour::numeric,0)-coalesce(after_overtime_hours,0)),0),0)*coalesce(overtime_rate,0)*(v_empsalaryregister.gross/(case when v_empsalaryregister.salarydays=1 then 1 else v_actualdays end))/v_shifthours)
		end
	)
	from v1 join v2
on v1.category_type in(2,3)
	into v_weekly_consecutive_overtime;	
	
	v_weekly_consecutive_overtime := coalesce(v_weekly_consecutive_overtime, 0);
	v_overtime := v_overtime + v_weekly_consecutive_overtime;

	-- =================================================================================================
	-- 8. LATE/EARLY FINES & DEDUCTIONS
	-- Grab fines from attendance and apply towards adjusting total OT logic.
	-- Hourly setups wipe custom overtime to 0.
	-- =================================================================================================
	select sum(latehoursdeduction) latehoursdeduction, sum(earlyhoursdeduction) earlyhoursdeduction,
		   sum(overtime_amount_approved_by_employer) overtime_amount_approved_by_employer
	into v_finerecord
	from tbl_monthly_attendance 
	where emp_code = p_emp_code 
	  and customeraccountid = v_openappointments.customeraccountid
	  and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	  and isactive = '1'
	  and approval_status = 'A'	
	  and no_of_hours_worked is not null;

	v_overtime := coalesce(nullif(v_finerecord.overtime_amount_approved_by_employer, 0), v_overtime);
	if coalesce(v_empsalaryregister.ishourlysetup, 'N') = 'Y' then
		v_overtime := 0;
	end if;

	-- =================================================================================================
	-- 9. TEA ALLOWANCE CALCULATION
	-- Cross-references worked hours vs the tea rate criteria (e.g. rate per hours range).
	-- =================================================================================================
	with 
v1 as (
select id as tearateid,hours_range_to-hours_range_from,
(left((hours_range_to-hours_range_from)::text,2)::numeric
+substring((hours_range_to-hours_range_from)::text,4,2)::numeric/60
+right((hours_range_to-hours_range_from)::text,2)::numeric/3600)::numeric(18,4) as tearatehours,
	regexp_split_to_table(daytype,',') daytype, rate from mst_tea_allowance_rate 
	where customeraccountid=v_openappointments.customeraccountid
	and isactive='1'
),
v2 as
(
select id as attid,trim(to_char(att_date,'Day')) as attday,(left(trim(no_of_hours_worked),2)::numeric
+substring(trim(no_of_hours_worked),4,2)::numeric/60
+right(trim(no_of_hours_worked),2)::numeric/3600)::numeric(18,4) as workinghour, *
	from tbl_monthly_attendance 
	where emp_code=p_emp_code 
	and customeraccountid=v_openappointments.customeraccountid
	and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	--and date_trunc('month',att_date) = make_date(p_mpryear,p_mprmonth,1)
	and isactive='1'
	and approval_status='A'	
	and no_of_hours_worked is not null
),
v3 as (
	select v1.daytype,v1.tearatehours,v1.rate,v2.workinghour,v1.tearateid,v2.attid
		,row_number()over(partition by v2.attid order by v1.rate desc,id desc) as rn
from v1 inner join v2
on v2.workinghour>=v1.tearatehours and
 (
		(v2.attendance_type='HO' and trim(v1.daytype)='Holiday')
		or
		(v2.attendance_type<>'HO' and trim(v2.attday)=trim(v1.daytype))
	)
	)
	select sum(rate) into v_tea_allowance from v3 where rn=1;	
	v_tea_allowance := coalesce(v_tea_allowance, 0);

	-- =================================================================================================
	-- 10. FINANCIAL YEAR & SALARY BOUNDARIES SETUP
	-- Determines current financial year start/end dates for tax, advances, and arrears calculation bounds.
	-- =================================================================================================
	if p_mprmonth in (1, 2, 3) then
		v_financial_year := (p_mpryear - 1)::text || '-' || p_mpryear::text;
	else
		v_financial_year := p_mpryear::text || '-' || (p_mpryear + 1)::text;
	end if;
	
	v_year1 := left(v_financial_year, 4)::int;
	v_year2 := right(v_financial_year, 4)::int;

	v_startdate := to_date(v_year1::text || '-05-01', 'yyyy-mm-dd');
	v_enddate := to_date(v_year2::text || '-04-30', 'yyyy-mm-dd');

	v_advancestartdate := to_date(v_year1::text || '-04-01', 'yyyy-mm-dd');
	v_advanceenddate := to_date(v_year1::text || '-04-30', 'yyyy-mm-dd');

	select 
		DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
		(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
		(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE ) - INTERVAL '1 DAY')::date,
		DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
		(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date
	into v_salstartdate, v_salenddate, v_prevsaldate, v_advancesalstartdate, v_advancesalenddate;
	
	p_createdbyip := createdbyip;	
	-- =================================================================================================
	-- 11. VERIFIED SALARY RETRIEVAL
	-- Short circuit execution. If we only need the verified salary, run a distinct SQL block 
	-- that accesses `tbl_monthlysalary` directly and returns the refcursor.
	-- =================================================================================================
	if p_action = 'RetrieveVerified_Salary' then	
		v_querytext := 'SELECT TO_CHAR(TO_TIMESTAMP ('||p_mprmonth||'::text, ''MM''), ''Mon'')'||'||''-''||'||p_mpryear::text||' AS Mon,
							   tbl_monthlysalary.*,
							   cmsdownloadedwages.dateofjoining,
							   openappointments.esinumber,
							   openappointments.posting_department,
							   cmsdownloadedwages.ismultilocated,
							   cmsdownloadedwages.projectname,
							   cmsdownloadedwages.contractno,
							   cmsdownloadedwages.contractcategory,
							   cmsdownloadedwages.contracttype
						FROM public.tbl_monthlysalary 
						LEFT JOIN cmsdownloadedwages 
						  ON tbl_monthlysalary.batch_no = cmsdownloadedwages.batch_no
						 AND upper(tbl_monthlysalary.emp_code::varchar) = upper(cmsdownloadedwages.empcode) 
						 AND coalesce(cmsdownloadedwages.multi_performerwagesflag, ''Y'') = ''Y''
						INNER JOIN openappointments 
						  ON openappointments.emp_code = tbl_monthlysalary.emp_code
						 AND openappointments.appointment_status_id <> 13
						WHERE tbl_monthlysalary.emp_code = '||p_emp_code||'
						  AND tbl_monthlysalary.mpryear = '||p_mpryear||'
						  AND tbl_monthlysalary.mprmonth = '||p_mprmonth||'';		
				 
		open sal for execute v_querytext;				 
		return sal;					 
	end if;

	-- =================================================================================================
	-- 12. EMPLOYEE & LWF INITIALIZATION
	-- Extract Employee ID/Pancard if context is Employee and fetch the active state LWF rates.
	-- =================================================================================================
	if p_criteria = 'Employee' then
		select emp_id, nullif(trim(pancard),'') into v_empid, v_pancard 
		from openappointments 
		where emp_code = p_emp_code;
	end if;

	select employeelwfrate, employerlwfrate, deductionmonths 
	into v_lwfemployee, v_lwfemployer, v_lwfdeductionmonths 
	from statewiselwfrate 
	where statecode = 7 
	  and isactive = '1'
	  and (select customeraccountid from openappointments where emp_code = p_emp_code) <> 3254;


	-- =================================================================================================
	-- 13. DYNAMIC QUERY ASSEMBLY (v_querytext)
	-- Start of the massive dynamic SELECT build matching the desired output for `tmp_sal_pregenerate`.
	-- Configures output headers based on action 'Save_Salary' vs 'Retrieve_Salary'
	-- =================================================================================================
	v_querytext := 'SELECT ';

	if p_action = 'Save_Salary' then	
		v_querytext := v_querytext || p_mprmonth || ' as mprmonth, ' || p_mpryear || ' as mpryear, batch_no as batchid, ' || 
					   p_createdby || ' as createdby, current_timestamp as createdon, ''' || 
					   createdbyip || ''' as createdbyip, arearids, tptype, ';
	end if;

	if p_action = 'Retrieve_Salary' then	
		v_querytext := v_querytext || 'fnfarrivalstatus, ' || p_mprmonth || ' as mprmonth, ' || p_mpryear || ' as mpryear, is_paused, emp_id, ' ||
					   'TO_CHAR(TO_TIMESTAMP(' || p_mprmonth || '::text, ''MM''), ''Mon'') || ''-'' || ' || p_mpryear || ' AS Mon, ' ||
					   'dateofjoining, esinumber, posting_department, projectname, contractno, contractcategory, contracttype, ' ||
					   'CASE WHEN activeinbatch = ''1'' THEN ''Active'' ELSE ''Inactive'' END as activeinbatch, ' ||
					   'appointment_status_id, nullif(trim(remark), '''') as remark, lockstatus, is_account_verified, ' ||
					   'CASE WHEN isesiexceptionalcase = ''Y'' AND esiapplicabletilldate <= to_date(''01'' || ''' || lpad(p_mprmonth::text, 2, '0') || p_mpryear::text || ''', ''ddmmyyyy'') ' ||
					   'THEN ''Y'' ELSE ''N'' END as isesiexceptionalcase, esicexceptionmessage, ';	
	end if;
	
	-- =================================================================================================
	-- 14. CORE COMPONENTS & ALLOWANCES
	-- Appending base employee details, fixed allowances, and calculated basic rates to the query.
	-- =================================================================================================
	v_querytext := v_querytext ||'
		emp_code, bunit as subunit, dateofleaving, totalleavetaken,
		emp_name, post_offered, emp_address, email, mobilenum, upper(pancard) pancard, gender, dateofbirth,
		fathername, residential_address, pfnumber, uannumber,
		(case when coalesce(salaryindaysopted,''N'')=''N'' or salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end) - (case when coalesce(salaryindaysopted,''N'')=''N'' or salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end) as lossofpay,
		paiddays as paiddays, 
		(case when coalesce(salaryindaysopted,''N'')=''N''or salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y''  then '||v_monthdays||'  else salarydays end) as monthdays,
		(RateBasic) as RateBasic, (RateHRA) as RateHRA, (RateCONV) as RateCONV,
		(RateMedical) as RateMedical, (RateSpecialAllowance) as RateSpecialAllowance,
		(FixedAllowancesTotalRate) as FixedAllowancesTotalRate,
		(Basic) as Basic, (HRA) as HRA, (CONV) as CONV,
		(Medical) as Medical, (SpecialAllowance) as SpecialAllowance,
		(FixedAllowancesTotal) + (FixedAllowancesTotalRate*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)) as FixedAllowancesTotal,
		(RateBasic_arr) as RateBasic_arr, (RateHRA_arr) as RateHRA_arr,
		(RateCONV_arr) as RateCONV_arr,
		(RateMedical_arr) as RateMedical_arr, (RateSpecialAllowance_arr) as RateSpecialAllowance_arr,
		(FixedAllowancesTotalRate_arr) as FixedAllowancesTotalRate_arr,
		(Incentive) as Incentive, coalesce(othertaxablerefunds,0) as Refund,
		
		/* ====================== GROSS EARNINGS ====================== */
		(coalesce(grossearningcomponents,FixedAllowancesTotal)+(FixedAllowancesTotalRate_arr)+
		coalesce((coalesce(grossearningcomponentsrate,FixedAllowancesTotalRate)*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)),0)+
		(Incentive)+coalesce(othertaxablerefunds,0)+ (coalesce(govt_bonus_amt*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0))+coalesce(otherledgerarear,0) +coalesce(othervariables*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0)+coalesce(otherledgerarearwithoutesi,0)+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+coalesce(tea_allowance,0)) as GrossEarning,
		
		/* ====================== DEDUCTIONS ====================== */
		case when epf>0 then
			case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*12.0/100 
				else
					case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000 then pfapplicablecomponents*12.0/100 
						else greatest(1800-coalesce(epfalreadydeducted,0),0) 
					end
		       end
		else 0 end as epf,
		
		(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end) as vpf,
		
		ceil(coalesce(case when employeeesirate>0 then coalesce(((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0))))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))*0.00750,0) +coalesce(othertaxablerefunds,0)*0.00750+	(((coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0))+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))))*0.00750) +(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*.0075)+(coalesce(otherledgerarear,0)*0.0075) else 0 end,0) +coalesce(employee_esi_incentive_deduction,0) +coalesce(employee_esi_incentive_deduction_previous,0)) as employeeesirate,
		
		case when is_exemptedfromtds=''Y'' then 0 
		     when ('''|| coalesce(v_tbl_account.tds_enablestatus,'Y')||'''=''N'' and '''||coalesce(v_empsalaryregister.tdsmode,'Auto')||'''=''Manual'') then '|| coalesce(v_empsalaryregister.taxes,0)||'  
		     when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger'' and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) 
		     else 0 end as tds, 
		(loan) as loan, (lwf) as lwf, (Insurance) as Insurance,
		(Mobile) as Mobile, (Advance) as Advance, (Other) as Other,
		
		( (	case when epf>0 then
			case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*12.0/100 
				else
					case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*12.0/100 
						else greatest(1800-coalesce(epfalreadydeducted,0),0) 
					end
		       end
		else 0 end)+(coalesce(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end,0))+ceil((case when employeeesirate>0 then coalesce(othertaxablerefunds,0)*0.00750+ coalesce(((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0))))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N''  then '||v_monthdays||'  else salarydays end))*0.00750,0)+((coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0))+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))))*0.00750+(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*0.0075)+(coalesce(otherledgerarear,0)*0.0075) else 0 end) )+ (case  when  is_exemptedfromtds=''Y'' then 0  when ('''|| coalesce(v_tbl_account.tds_enablestatus,'Y')||'''=''N'' and '''||coalesce(v_empsalaryregister.tdsmode,'Auto')||'''=''Manual'' ) then '|| coalesce(v_empsalaryregister.taxes,0)||' when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger''  and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) else 0 end)+(coalesce(loan,0))+(coalesce(lwf,0))+ case when isgroupinsurance=''Y'' then (coalesce(Insurance,0)) else 0 end+ (coalesce(Advance,0))+ (coalesce(Other,0))+(coalesce(otherdeductions,0))+coalesce(otherledgerdeductions,0)+coalesce(employee_esi_incentive_deduction,0)+coalesce(employee_esi_incentive_deduction_previous,0))+coalesce(charity_contribution_amount,0) as GrossDeduction,

		/* ====================== NET PAY ====================== */
		case when coalesce(is_special_category,''N'')=''Y'' then (actual_paid_ctc2) else
		(coalesce(grossearningcomponentsrate,FixedAllowancesTotalRate)*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))+
		((coalesce(grossearningcomponents,FixedAllowancesTotal,0))+(coalesce(FixedAllowancesTotalRate_arr,0))+
			(coalesce(Incentive,0))+(coalesce(othertaxablerefunds,0))+(coalesce(Mobile,0))+ (coalesce(govt_bonus_amt*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0))+coalesce(netarear,0)+coalesce(otherledgerarear,0) +coalesce(othervariables*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0)
			+coalesce(otherledgerarearwithoutesi,0)+'||v_overtime||'
			+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+coalesce(tea_allowance,0))
			-( (case when epf>0 then
			case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*12.0/100 
				else
					case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*12.0/100 
						else greatest(1800-coalesce(epfalreadydeducted,0),0) 
					end
		       end
		else 0 end)+(coalesce(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0))+ceil( (case when employeeesirate>0 then coalesce((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))*0.00750,0) +coalesce(othertaxablerefunds,0)*0.00750+((coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0))+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))))*0.00750+(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*0.0075)+(coalesce(otherledgerarear,0)*0.0075) else 0 end)) + (case when  is_exemptedfromtds=''Y'' then 0 when ('''|| coalesce(v_tbl_account.tds_enablestatus,'Y')||'''=''N'' and '''||coalesce(v_empsalaryregister.tdsmode,'Auto')||'''=''Manual'' ) then '|| coalesce(v_empsalaryregister.taxes,0)||'  when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger''  and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) else 0 end)+(coalesce(loan,0))+(coalesce(lwf,0))+case when isgroupinsurance=''Y'' then  (coalesce(Insurance,0)) else 0 end+ (coalesce(Advance,0))+ (coalesce(Other,0))+(coalesce(otherdeductions,0))+coalesce(otherledgerdeductions,0)+coalesce(employee_esi_incentive_deduction,0)+coalesce(employee_esi_incentive_deduction_previous,0)) 
				end - coalesce(charity_contribution_amount,0) as NetPay,

		/* ====================== EMPLOYER EPF/VPF COMPONENTS ====================== */
		case when epf>0 then
			case when coalesce(pfcapapplied,''Y'')=''N'' or (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<=15000 then pfapplicablecomponents*0.0367
			else
				greatest(550.5-coalesce(coalesce(pfapplicablecomponentsalreadypaid,0)*0.0367,0),0) 
			end
			+
			case when coalesce(epf_pension_opted,''Y'')=''Y'' and coalesce(pfcapapplied,''Y'')=''Y'' then 0
				 when coalesce(epf_pension_opted,''Y'')=''Y'' and coalesce(pfcapapplied,''Y'')=''N'' then
						case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<=15000 then 0
							 else 
								case when coalesce(pfapplicablecomponentsalreadypaid,0)<=15000 then (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))*0.0833-1249.5
									 else pfapplicablecomponents*0.0833
								end	
						end
				when coalesce(epf_pension_opted,''Y'')=''N'' and coalesce(pfcapapplied,''Y'')=''Y'' then
						case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<=15000 then pfapplicablecomponents*0.0833
							 else 
								case when coalesce(pfapplicablecomponentsalreadypaid,0)<=15000 then greatest(1249.5-(coalesce(pfapplicablecomponentsalreadypaid,0))*0.0833,0)
									 else 0
								end	
						end
				when coalesce(epf_pension_opted,''Y'')=''N'' and coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*0.0833
			end	
		else 0 end as Ac_1,

		-------------------------------------------------------------------------------	
		case when epf>0 and coalesce(epf_pension_opted,''Y'')=''Y'' then
			case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000 then pfapplicablecomponents*0.0833
				 else greatest(1249.5-coalesce(ac_10alreadydeducted,0),0) 
			end
		else 0 end as Ac_10,	
		
		case when epf>0 and coalesce(nullif(trim(edli_adminchargesincludeinctc),''''),''Y'')=''Y'' then
			case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*0.005
				 else
					case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000 then pfapplicablecomponents*0.005
						 else greatest(75-coalesce(ac_2alreadydeducted,0),0) 
					end
		    end
		else 0 end as Ac_2,
		
		case when epf>0 and coalesce(nullif(trim(edli_adminchargesincludeinctc),''''),''Y'')=''Y'' then
			case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*0.005
				 else
					case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000 then pfapplicablecomponents*0.005
						 else greatest(75-coalesce(ac_21alreadydeducted,0),0) 
					end
		    end
		else 0 end as Ac21,	

		case when employeresirate>0 then
			coalesce((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end))*0.03250,0) +
			coalesce(othertaxablerefunds,0)*0.03250 +
			((coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0))+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0)))*0.03250) +
			(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end*0.0325) +
			(coalesce(otherledgerarear,0)*0.0325) +
			coalesce(employer_esi_incentive_deduction,0) +
			coalesce(employer_esi_incentive_deduction_previous,0)
		else 0 end as employeresirate,

		/* ====================== OTHER EMPLOYER DATA ====================== */
		0 as LWFContr, (ews) as ews, (gratuity) as gratuity, recordtype, govt_bonus_opted,
		(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end) as govt_bonus_amt';

	if p_action = 'Save_Salary' then	
		v_querytext := v_querytext || ', cast(null as integer) as modifiedby, cast(null as timestamp) as modifiedon, null as modifiedbyip';
	end if;	  
	
	v_querytext := v_querytext || ', is_special_category, ct2';
	v_querytext := v_querytext || ', batch_no, (actual_paid_ctc2) as actual_paid_ctc2, (ctc) as ctc';
	v_querytext := v_querytext || ', (ctc_paid_days) as ctc_paid_days, (ctc_actual_paid) as ctc_actual_paid, (mobile_deduction) as mobile_deduction, salaryid';

	v_querytext := v_querytext || '
		, coalesce(employeenpsrate,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as employeenpsrate
		, coalesce(employernpsrate,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as employernpsrate
		, case when isgroupinsurance=''Y'' then coalesce(insuranceamount,0) else 0 end as insuranceamount
		, case when isgroupinsurance=''Y'' then coalesce(familyinsuranceamount,0) else 0 end as familyinsuranceamount
		, bankaccountno, ifsccode, bankname, bankbranch, coalesce(netarear,0) as netarear, arearaddedmonths
		, coalesce(employee_esi_incentive_deduction_previous,0) + coalesce(employee_esi_incentive_deduction,0) as employee_esi_incentive_deduction
		, coalesce(employer_esi_incentive_deduction_previous,0) + coalesce(employer_esi_incentive_deduction,0) as employer_esi_incentive_deduction
		, coalesce(total_esi_incentive_deduction_previous,0) + coalesce(total_esi_incentive_deduction,0) as total_esi_incentive_deduction
		, salaryindaysopted, salarydays, otherledgerarear, otherledgerdeductions, attendancemode
		, 0 as incrementarear, 0 as incrementarear_basic, 0 as incrementarear_hra, 0 as incrementarear_allowance
		, 0 as incrementarear_gross, 0 as incrementarear_employeeesi, 0 as incrementarear_employeresi
		, lwf_employee, lwf_employer, bonus, otherledgerarearwithoutesi
		, coalesce(otherdeductions,0) as otherdeductions
		, coalesce(othervariables*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0) as othervariables
		, (coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end) as otherdeductionswithesi
		, lwfstatecode, coalesce(tdsadjustment,0) tdsadjustment
		, case when ('''|| coalesce(v_tbl_account.tds_enablestatus,'Y')||'''=''N'' and '''||coalesce(v_empsalaryregister.tdsmode,'Auto')||'''=''Manual'' ) then '|| coalesce(v_empsalaryregister.taxes,0)||' when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger'' and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) else 0 end as atds
		, hrgeneratedon, disbursedledgerids, security_amt
		, case when tptype=''TP'' then ''S'' else ''L'' end as issalaryorliability
		, 0 as professionaltax, customtaxablecomponents, customnontaxablecomponents
		
		/* ====================== FIXED ALLOWANCE RATE COMPONENTS ====================== */
		/* Applied per structure changes 1.27 */
		, ratesalarybonus, ratecommission
		, coalesce(ratetransport_allowance,0)+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0)) as ratetransport_allowance
		, ratetravelling_allowance, rateleave_encashment
		, coalesce(rateovertime_allowance,0) + '||v_overtime||' as rateovertime_allowance
		, ratenotice_pay, ratehold_salary_non_taxable, ratechildren_education_allowance, rategratuityinhand
		, salarybonus, commission
		, coalesce(transport_allowance,0)+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0)) as transport_allowance
		, travelling_allowance, leave_encashment
		, coalesce(overtime_allowance,0) + '||v_overtime||' + coalesce((FixedAllowancesTotalRate*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end)),0) as overtime_allowance
		, notice_pay, hold_salary_non_taxable, children_education_allowance, gratuityinhand
		
		, customeraccountid, orgempcode, cjcode
		, coalesce(tea_allowance,0) as tea_allowance
		, pfapplicablecomponents, esiapplicablecomponents
		, isgroupinsurance, employerinsuranceamount
		, incentivedays, charity_contribution_amount, mealvoucher
	';
						  
from
	(
		/* =================================================================================================
		-- 15. INNER SELECT QUERY (DATA SOURCE)
		-- Base fields and pre-calculations fetched directly from openappointments, empsalaryregister,
		-- and cmsdownloadedwages. This forms the foundation for the outer query calculations.
		-- ================================================================================================= */
		select openappointments.emp_code, bunit as bunit, coalesce(is_account_verified,''0'')::bit as is_account_verified,';

	if p_action = 'Retrieve_Salary' then	
		v_querytext := v_querytext || 'to_char(dateofleaving,''dd/mm/yyyy'') as dateofleaving, emp_id, is_paused,';
	elsif  p_action = 'Save_Salary' then	
		v_querytext := v_querytext || 'dateofleaving,';
	end if;		

	v_querytext := v_querytext || 'emp_name, jobrole as post_offered, emp_address, email, mobile as mobilenum, pancard, gender,';

	if p_action = 'Retrieve_Salary' then	
		v_querytext := v_querytext || 'to_char(dateofbirth,''dd-Mon-yy'') as dateofbirth, coalesce(cmsdownloadedwages.isactive,''0'') as activeinbatch';
	elsif  p_action = 'Save_Salary' then	
		v_querytext := v_querytext || 'dateofbirth';
	end if;
	
	v_querytext := v_querytext || ', fathername, residential_address, pfnumber, uannumber, lossofpay as lossofpay,
		
		/* ====================== PAYROLL DAYS ====================== */
		case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as monthdays,
		(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end) as paiddays,
		totalleavetaken,
		
		/* ====================== EARNING RATES ====================== */
		basic as RateBasic, hra as RateHRA, coalesce(conveyance_allowance,0) as RateCONV,
		medical_allowance as RateMedical, allowances as RateSpecialAllowance,
		gross as FixedAllowancesTotalRate,
	
		/* ====================== PRORATED EARNINGS ====================== */
		basic*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as Basic,
		hra*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as HRA,
		(coalesce(conveyance_allowance,0))*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as CONV,
		medical_allowance*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as Medical,
		allowances*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as SpecialAllowance,
		gross*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as FixedAllowancesTotal,
		
		/* ====================== ARREAR EARNING COMPONENTS ====================== */
		cast(0.0000 as double precision) as RateBasic_arr, cast(0.0000 as double precision) as RateHRA_arr, cast(0.0000 as double precision) as RateCONV_arr,
		cast(0.0000 as double precision) as RateMedical_arr, cast(0.0000 as double precision) as RateSpecialAllowance_arr,
		cast(0.0000 as double precision) as FixedAllowancesTotalRate_arr,
		'||p_fullmonthincentive||' as Incentive, cast(0.0000 as double precision) as Refund,
		
		/* ====================== COMPLIANCE RATES & DEDUCTIONS ====================== */
	    employeeepfrate as epf, (coalesce(vpfemployee,0)+coalesce(variablevpf,0)) as vpf,
		employeeesirate, employeresirate, (coalesce(taxes,0.0)+coalesce(tdsadjustment,0)) as tds,
		cast(0.0000 as double precision) as loan, 0::numeric(18,2) as lwf,
		
		case when openappointments.customeraccountid in(6927,7416,6533) then (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))-coalesce(alreadyinsurance,0) 
			 else (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end 
		end as Insurance,
		
		cast(0.0000 as double precision) as Mobile, cast(0.0000 as double precision) as Advance,
		(coalesce(ews,0)+coalesce(gratuity,0)+coalesce(bonus,0)-coalesce(alreadyother,0)) as Other,
		ews-coalesce(ewsalready,0) as ews, gratuity-coalesce(gratuityalready,0) as gratuity, salaryinhand,
		case when recordsource=''MIS'' then ''Existing'' else ''NewRecord'' end as recordtype,
		
		openappointments.govt_bonus_opted, govt_bonus_amt,
		(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end) as totalsalarydays,
		to_char(cmsdownloadedwages.dateofjoining,''dd-Mon-yy'') as dateofjoining,
		openappointments.esinumber, posting_department, batch_no,
		tblotherdeductions.otherdeductions*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as otherdeductions,
		projectname, contractno, contractcategory, contracttype, totalpaiddays,
		empsalaryregister.is_special_category, ctc, empsalaryregister.ct2,
		(empsalaryregister.ct2*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end) as actual_paid_ctc2, 
		cast(0.0000 as double precision) as ctc_paid_days, cast(0.0000 as double precision) as ctc_actual_paid,
		cast(0.0000 as double precision) as mobile_deduction, empsalaryregister.id as salaryid,
		nullif(trim(empsalaryregister.pfcapapplied),'''') as pfcapapplied, pfopted, esiopted, monthlyofferedpackage,
		employeenpsrate, employernpsrate,
		
		/* ====================== INSURANCE AND BANKING ====================== */
		case when openappointments.customeraccountid in(6927,7416,6533) then coalesce(insuranceamount,0)-coalesce(alreadyinsuranceamount,0) 
			 else insuranceamount*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end 
		end as insuranceamount,
		
		case when openappointments.customeraccountid in(6927,7416,6533) then coalesce(familyinsuranceamount,0)-coalesce(alreadyfamilyfamilyinsurance,0) 
			 else familyinsuranceamount*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end 
		end as familyinsuranceamount,
		
		openappointments.bankaccountno, openappointments.ifsccode, openappointments.bankname, openappointments.bankbranch,
		tmparear.netarear, tmparear.total_esi_incentive, tmparear.arearaddedmonths,
		tblotherdeductionswithesi.otherdeductionswithesi, empsalaryregister.isgroupinsurance,
		employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction,
		openappointments.appointment_status_id, empsalaryregister.salaryindaysopted, empsalaryregister.salarydays,
		
		/* ====================== OTHER VARIABLES ====================== */
		coalesce(tblotherledger.otherledgerarear,0) as otherledgerarear,
		coalesce(tblotherledger.otherledgerdeductions,0)+coalesce(security_amt,0)-coalesce(alreadysecurity_amt,0) as otherledgerdeductions,
		coalesce(othervariables,0) as othervariables,
		employee_esi_incentive_deduction_previous, employer_esi_incentive_deduction_previous, total_esi_incentive_deduction_previous,
		attendancemode, epfalreadydeducted, ac_1alreadydeducted, ac_10alreadydeducted, ac_2alreadydeducted, ac_21alreadydeducted,
		basicalreadypaid, cmsdownloadedwages.remark, tblcurrenttax.currentmonthtaxdeducted as alreadytds,
		bonus-coalesce(bonusalready) as bonus, otherledgerarearwithoutesi as otherledgerarearwithoutesi,
		0::numeric(18,2) as lwf_employee, 0::numeric(18,2) as lwf_employer, empsalaryregister.lwfstatecode,
		
		/* ====================== LOCKS & COMPLIANCES ====================== */
		''Unlocked'' as lockstatus, /* Change 1.6 */
		coalesce(tdsadjustment,0) as tdsadjustment, variablevpf,
		empsalaryregister.isesiexceptionalcase, empsalaryregister.esicexceptionmessage, empsalaryregister.esiapplicabletilldate,
		arearids, hrgeneratedon,
		case when coalesce(openappointments.left_flag,''N'')=''Y'' and openappointments.dateofrelieveing<=current_date and coalesce(ee_finalduesclearancedate,openappointments.dateofrelieveing,to_date(''0101900'',''ddmmyyyy''))>current_date then ''FNFLock'' else ''NoFNFLock'' end as fnfarrivalstatus,
		disbursedledgerids, coalesce(othertaxablerefunds,0) as othertaxablerefunds,
		coalesce(security_amt,0)-coalesce(alreadysecurity_amt,0) as security_amt,
		openappointments.epf_pension_opted,
		case when openappointments.recordsource=''HUBTPCRM'' then ''TP'' else ''NonTP'' end as tptype,
		case when '''||coalesce(v_empsalaryregister.ishourlysetup,'N')||'''=''Y'' then '|| coalesce(v_incentivedays,0)||' 
			 when salarydays<(totalpaiddays+totalleavetaken) and coalesce(empsalaryregister.salaryindaysopted,''N'')=''Y'' and empsalaryregister.salarydays>1 then (totalpaiddays+totalleavetaken)-salarydays 
			 else 0 
		end as incentivedays, customtaxablecomponents, customnontaxablecomponents,
		
		/* ====================== ALLOWANCE RATES (CHANGE 1.27) ====================== */
		coalesce(salarybonus,0) as ratesalarybonus, coalesce(commission,0) as ratecommission,
		coalesce(transport_allowance,0) as ratetransport_allowance, coalesce(travelling_allowance,0) as ratetravelling_allowance,
		coalesce(leave_encashment,0) as rateleave_encashment, coalesce(overtime_allowance,0) as rateovertime_allowance,
		coalesce(notice_pay,0) as ratenotice_pay, coalesce(hold_salary_non_taxable,0) as ratehold_salary_non_taxable,
		coalesce(children_education_allowance,0) as ratechildren_education_allowance, coalesce(gratuityinhand,0) as rategratuityinhand,
		
		coalesce(salarybonus,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as salarybonus,
		coalesce(commission,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as commission,
		coalesce(transport_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as transport_allowance,
		coalesce(travelling_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as travelling_allowance,
		coalesce(leave_encashment,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as leave_encashment,
		coalesce(overtime_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as overtime_allowance,
		coalesce(notice_pay,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as notice_pay,
		coalesce(hold_salary_non_taxable,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as hold_salary_non_taxable,
		coalesce(children_education_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y''  then '||v_monthdays||' else salarydays end as children_education_allowance,
		coalesce(gratuityinhand,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y''  then '||v_monthdays||' else salarydays end as gratuityinhand,
		
		openappointments.customeraccountid, openappointments.orgempcode, openappointments.cjcode,
		km_distance, perkilometerrate, ta_days, travelallowance_rate,
		case when empsalaryregister.tea_allowance_enabled=''Y'' then '||v_tea_allowance ||' else 0 end as tea_allowance,
		edli_adminchargesincludeinctc, coalesce(pfapplicablecomponentsalreadypaid,0) as pfapplicablecomponentsalreadypaid,
		coalesce(coalesce(nullif(pfapplicablecomponents,0),basic),0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as pfapplicablecomponents,
		esiapplicablecomponents*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as esiapplicablecomponents,
		
		case when openappointments.customeraccountid in(6927,7416,6533) then coalesce(employerinsuranceamount,0)-coalesce(alreadyemployerinsuranceamount,0) 
			 else coalesce(employerinsuranceamount,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end 
		end as employerinsuranceamount,
		
		case when coalesce(charity_contribution,''N'')=''Y'' then basic else 0 end*0.001*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as charity_contribution_amount,
		
		coalesce(empsalaryregister.is_exemptedfromtds,''N'') as is_exemptedfromtds,
		greatest(coalesce(mealvoucher,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end-coalesce(alreadymealvoucher,0),0) as mealvoucher,
		grossearningcomponents*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||' else salarydays end as grossearningcomponents,
		grossearningcomponents as grossearningcomponentsrate


		/* =================================================================================================
		-- 15.a. BASE TABLES & CORE JOINS
		-- Linking employee salary matrix with their active appointment details.
		-- Includes logic to skip records for new joiners starting next month and handling active structures.
		-- ================================================================================================= */
		from public.empsalaryregister
		inner join public.openappointments
			on empsalaryregister.appointment_id = openappointments.emp_id
			and openappointments.recordsource = case when '''||p_tptype||'''=''TP'' then ''HUBTPCRM'' else nullif(openappointments.recordsource,''HUBTPCRM'') end
			and openappointments.emp_id not in (
				select e7.appointment_id 
				from empsalaryregister e7 
				inner join openappointments op2 on op2.emp_id = e7.appointment_id  
				where e7.effectivefrom between to_date(''02'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') 
					  and to_date('''||coalesce(nullif(v_nextmonthdays,0),v_monthdays)::text||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') 
					  and op2.dateofjoining <= to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') 
					  and e7.isactive = ''1''
			)
		';
		
	if p_criteria = 'Employee' then
		v_querytext := v_querytext || ' and openappointments.emp_code='||p_emp_code;
		v_querytext := v_querytext || ' and empsalaryregister.appointment_id='||v_empid;
	end if;	

	/* ====================== PROCESS STATUS VERIFICATION ====================== */
	if (p_action = 'Retrieve_Salary' or p_action = 'Save_Salary') and coalesce(nullif(p_process_status,''),'NotProcessed') = 'NotProcessed' then
		v_querytext := v_querytext || ' and 1=1 ';
	else
		v_querytext := v_querytext || ' and 1=2 ';
	end if;				 

	/* =================================================================================================
	-- 15.b. MAXIMUM SALARY REGISTER ID RESOLUTION
	-- Handles complex active structure determination. Finds the maximum ID for active structures up to 
	-- the month start, handles newly joined employees mid-month, and factors in already processed salaries.
	-- ================================================================================================= */
    v_querytext := v_querytext || ' and 
	   (empsalaryregister.appointment_id, empsalaryregister.id) in (
			select e1.appointment_id, max(e1.id)
			from empsalaryregister e1
			where (e1.isactive = ''1'' ';
			
	if p_criteria = 'Employee' then
		v_querytext := v_querytext || ' and e1.appointment_id='||v_empid;
	end if;	
	
	v_querytext := v_querytext || ' and (coalesce(e1.effectivefrom,to_date(''2021-03-01'',''yyyy-mm-dd''))) <= to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') 
			)
			/* Handle newly processed salaries */
			or (e1.appointment_id, e1.id) in (
				select opsal.emp_id, max(tblsal.salaryid)
				from openappointments opsal 
				inner join tbl_monthlysalary tblsal on opsal.emp_code= tblsal.emp_code and tblsal.is_rejected=''0''
				and to_date(tblsal.mpryear::text||''-''||lpad(tblsal.mprmonth::text,2,''0'')||''-01'',''yyyy-mm-dd'') <= to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'')';
	
	if p_criteria = 'Employee' then
		v_querytext := v_querytext || ' and opsal.emp_id='||v_empid;
	end if;	
	
	v_querytext := v_querytext || ' 
				group by opsal.emp_id
			)
			/* Handle Mid-month new joiners where effective from is after month start */
			or ( (effectivefrom < (make_date('||p_mpryear||','||p_mprmonth||',1) + interval ''1 month'')::date) and e1.appointment_id in (
					select op1.emp_id 
					from openappointments op1
					where op1.appointment_status_id <> 13 and coalesce(op1.converted,''N'') = ''Y'' ';
					
	if p_criteria = 'Employee' then
		v_querytext := v_querytext || ' and op1.emp_id='||v_empid;
	end if;	
	
	v_querytext := v_querytext || ' and op1.dateofjoining >= make_date('||p_mpryear||','||p_mprmonth||',1) 
				)
			)
			group by e1.appointment_id
			
			union
			
			select e2.appointment_id, max(e2.id)
			from empsalaryregister e2 ';
			
	if p_criteria = 'Employee' then
		v_querytext := v_querytext || ' where e2.appointment_id='||v_empid;
	end if;	
	
	v_querytext := v_querytext || '
			and effectivefrom < '''||(v_advancesalstartdate+interval '1 month')::date ||'''::date
			group by e2.appointment_id ';
			
	if p_tptype = 'TP' then
		v_querytext := v_querytext || ' having count(*)=1 ';
	end if;
	
	v_querytext := v_querytext || ' 
		)
		/* Filter out unapproved/inactive appointments */
		and openappointments.appointment_status_id <> 13
		and coalesce(converted,''N'') = ''Y''
	';
	/*if p_action='Save_Salary' then			
	v_querytext:=v_querytext||'and 
	(
	openappointments.emp_id not in(select EmpId from ManageTempPausedSalary
					WHERE ManageTempPausedSalary.ProcessYear ='||p_mpryear||'
					and ManageTempPausedSalary.ProcessMonth ='||p_mprmonth||'
					and ManageTempPausedSalary.IsActive=''1''
					and coalesce(ManageTempPausedSalary.PausedStatus,''Enable'')=''Enable'')
	or '''||p_issalaryorliability||'''=''L''
	)	';
	end if;	*/

	/* =================================================================================================
	-- 15.c. TEMPORARY PAUSE SALARY CHECK
	-- Verifies if salary generation has been paused for any specific employees current month/year.
	-- ================================================================================================= */
	if p_action = 'Retrieve_Salary' then	
		v_querytext := v_querytext || ' 
		left join (
			select empid, pausedstatus as is_paused  
			from ManageTempPausedSalary
			WHERE ManageTempPausedSalary.ProcessYear ='||p_mpryear||'
			and ManageTempPausedSalary.ProcessMonth ='||p_mprmonth||'
		) MTempPausedSalary on openappointments.emp_id = MTempPausedSalary.empid ';
	end if;

	/* =================================================================================================
	-- 15.d. ATTENDANCE DSR & DYNAMIC ALLOWANCE (TA/DA)
	-- Fetching Travel allowance and per-km data.
	-- ================================================================================================= */
	v_querytext := v_querytext || ' 
		left join (
			select account_id, emp_code as transp_empcode,
				sum(case when data_type=''dsr-days'' then days_per_month else 0 end) as days_per_month,
				sum(case when data_type=''km-distance'' then days_per_month else 0 end) as km_distance, 
				sum(case when data_type=''ta-days'' then days_per_month else 0 end) as ta_days
			from tbl_attendnace_dsr_da_data 
			where tbl_attendnace_dsr_da_data.emp_code='||p_emp_code||'
				and coalesce(tbl_attendnace_dsr_da_data.status,''0'')=''1''
				and tbl_attendnace_dsr_da_data.month='||p_mprmonth||' 
				and tbl_attendnace_dsr_da_data.year='||p_mpryear||'
				and coalesce(tbl_attendnace_dsr_da_data.is_processed,''N'')=''N''
			group by account_id, emp_code		 
		) ta on openappointments.emp_code = ta.transp_empcode and openappointments.customeraccountid = ta.account_id  ';

	/* =================================================================================================
	-- 15.e. NET ARREARS & ESI INCENTIVE AGGREGATION
	-- Calculates cumulative arrears and incentives that have been processed previously.
	-- ================================================================================================= */				 
	v_querytext := v_querytext || '	
		left join (
			select tbl_monthlysalary.emp_code, sum(netpay) as netarear, sum(total_esi_incentive) as total_esi_incentive
				, STRING_AGG (tbl_monthlysalary.mprmonth || ''-'' || tbl_monthlysalary.mpryear,'','') as arearaddedmonths
				, sum(employee_esi_incentive) as employee_esi_incentive_deduction
				, sum(employer_esi_incentive) as employer_esi_incentive_deduction
				, sum(total_esi_incentive) as total_esi_incentive_deduction
				, STRING_AGG (tbl_monthlysalary.id::text,'','') as arearids
			from public.tbl_monthlysalary
			where isarear=''Y'' and arearprocessmonth='||p_mprmonth||' and coalesce(is_rejected,''0'')<>''1''
				and recordscreen not in (''Previous Wages'',''Current Wages'',''Increment Voucher'')
				and arearprocessyear='||p_mpryear||'
				and (tbl_monthlysalary.emp_code, tbl_monthlysalary.id) not in (
					select arrs.emp_code, trim(regexp_split_to_table(arrs.arearids,'',''))::bigint 
					from tbl_monthlysalary arrs where coalesce(arrs.is_rejected,''0'')<>''1''
				)	 
				and tbl_monthlysalary.createdon::date >= to_date(''2021-12-01'',''yyyy-mm-dd'')
				and 1=2
			group by tbl_monthlysalary.emp_code
		) tmparear on tmparear.emp_code = openappointments.emp_code';						

	/* =================================================================================================
	-- 15.f. PREVIOUS ESI INCENTIVE DEDUCTIONS
	-- Fetch previous wages where ESI incentives were not fully processed.
	-- ================================================================================================= */
	v_querytext := v_querytext || '	
		left join (
			select tbl_monthlysalary.emp_code
				, sum(employee_esi_incentive) as employee_esi_incentive_deduction_previous
				, sum(employer_esi_incentive) as employer_esi_incentive_deduction_previous
				, sum(total_esi_incentive) as total_esi_incentive_deduction_previous
			from public.tbl_monthlysalary
			where isarear=''Y'' 
				and coalesce(esi_incentive_processed,''0'')<>''1''
				and coalesce(is_rejected,''0'')<>''1''
				and recordscreen=''Previous Wages''
			group by tbl_monthlysalary.emp_code
		) tmpesiarear on tmpesiarear.emp_code = openappointments.emp_code';
										
	/* =================================================================================================
	-- 15.g. CORE ATTENDANCE AGGREGATION
	-- The central attendance grouping logic. Fetches and sums attendance from target attendance table
	-- (`v_attendancetablename`). Avoids fetching multiple batches for already processed salaries.
	-- ================================================================================================= */
	v_querytext := v_querytext || '	
		inner join (
			select mprmonth, mpryear, empcode, 
				max(dateofjoining) as dateofjoining,
				max(bunit) as bunit, 
				max(dateofleaving) as dateofleaving,
				sum(totalleavetaken) as totalleavetaken,
				0 as totalsalarydays,
				sum(totalpaiddays) as totalpaiddays,
				sum(lossofpay) as lossofpay,
				max(isactive::int)::bit as isactive,
				batch_no,
				max(projectname) as projectname,
				max(contractno) as contractno, 
				max(contractcategory) as contractcategory,
				max(contracttype) as contracttype, 
				max(attendancemode) as attendancemode,
				max(remark) as remark,
				to_char(max(to_timestamp(hrgeneratedon,''dd Mon yyyy hh24:mi'')),''dd Mon yyyy hh24:mi'') as hrgeneratedon,
				max(jobrole) as jobrole
			from '||v_attendancetablename||' cmsdownloadedwages
			where cmsdownloadedwages.isactive=''1'' ';
	  	
	if p_criteria = 'Order' then
		v_querytext := v_querytext || ' and cmsdownloadedwages.contractno='''||p_ordernumber||''' ';
	end if;
	
	if p_criteria = 'Employee' then
		v_querytext := v_querytext || ' and cmsdownloadedwages.empcode='''||p_emp_code||''' ';
	end if;	
		
	v_querytext := v_querytext || ' 
			and cmsdownloadedwages.mpryear='||p_mpryear||'
			and cmsdownloadedwages.mprmonth='||p_mprmonth||'
			and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''''),''Y'')<>''N''
			and (cmsdownloadedwages.mprmonth, cmsdownloadedwages.mpryear, cmsdownloadedwages.empcode::bigint, cmsdownloadedwages.batch_no) not in (
				select m5.mprmonth, m5.mpryear, m5.emp_code, trim(regexp_split_to_table(m5.batchid,'','')) 
				from tbl_monthlysalary m5 
				where coalesce(m5.is_rejected,''0'')<>''1''
					and m5.recordscreen<>''Increment Arear'' 
					and m5.mprmonth='||p_mprmonth||' 
					and m5.mpryear='||p_mpryear||'
			)
			and (cmsdownloadedwages.mprmonth, cmsdownloadedwages.mpryear, cmsdownloadedwages.empcode::bigint, cmsdownloadedwages.batch_no||cmsdownloadedwages.transactionid::text) not in (
				select m6.mprmonth, m6.mpryear, m6.emp_code, trim(regexp_split_to_table(m6.batchid,'','')) 
				from tbl_monthlysalary m6 
				where coalesce(m6.is_rejected,''0'')<>''1''
					and m6.recordscreen<>''Increment Arear'' 
					and m6.mprmonth='||p_mprmonth||' 
					and m6.mpryear='||p_mpryear||'
			)	
			group by mprmonth, mpryear, empcode, batch_no
		) cmsdownloadedwages on cmsdownloadedwages.empcode::bigint = openappointments.emp_code ';	
	
	if nullif(trim(p_batch_no),'') is not null then
		v_querytext := v_querytext || ' and cmsdownloadedwages.batch_no='''||p_batch_no||'''';
	end if;
	/* =================================================================================================
	-- 15.h. OTHER DEDUCTIONS AGGREGATION
	-- Calculates recurring flat monthly deductions (except exclusions like Meal Vouchers / Security).
	-- ================================================================================================= */
	v_querytext := v_querytext || '	
		left join (
			select salaryid, candidate_id, sum(otherdeductions) as otherdeductions
			from (
				/* Fixed frequency non-monthly deductions */
				select salaryid, candidate_id, sum(deduction_amount) as otherdeductions
				from public.trn_candidate_otherduction
				where public.trn_candidate_otherduction.active=''Y''
					and coalesce(trn_candidate_otherduction.includedinctc,''N'')=''Y'' 
					and coalesce(isvariable,''N'')=''N''  --change 1.8
					and trn_candidate_otherduction.deduction_id not in (7,10)
					and trn_candidate_otherduction.deduction_frequency in (''Quarterly'',''Half Yearly'',''Annually'')
				group by salaryid, public.trn_candidate_otherduction.candidate_id	  

				union all
				
				/* Monthly flat deductions */
				select salaryid, candidate_id, sum(deduction_amount)*1 as otherdeductions
				from public.trn_candidate_otherduction
				inner join mst_otherduction motd on motd.id = trn_candidate_otherduction.deduction_id
				where public.trn_candidate_otherduction.active=''Y''
					and deduction_amount > 0
					and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
					and trn_candidate_otherduction.deduction_id not in (5,6,7,10)
					and coalesce(trn_candidate_otherduction.is_taxable,''N'')=''N''
					and motd.id <> 134 --Meal Voucher ID
				group by salaryid, public.trn_candidate_otherduction.candidate_id  
			) tblotherdeductions
			group by salaryid, candidate_id 
		) tblotherdeductions on openappointments.emp_id = tblotherdeductions.candidate_id and empsalaryregister.id = tblotherdeductions.salaryid

	/* =================================================================================================
	-- 15.i. TAXABLE COMPONENTS & OTHER DEDUCTIONS WITH ESI
	-- Gets variables like Performance Incentives (PI) and OT that are configured to attract ESI liability.
	-- ================================================================================================= */					  
		left join (
			select salaryid, candidate_id, sum(deduction_amount) as otherdeductionswithesi
				, string_agg(deduction_name || '':'' || deduction_amount, '','') as customtaxablecomponents
			from public.trn_candidate_otherduction
			inner join mst_otherduction motd on motd.id = trn_candidate_otherduction.deduction_id
			where public.trn_candidate_otherduction.active=''Y'' 
				and motd.deduction_name not in (''Medical Expenses'')
				and deduction_amount > 0
				and (trn_candidate_otherduction.deduction_id in (5,6) or coalesce(trn_candidate_otherduction.is_taxable,''N'')=''Y'')
				and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				and motd.id <> 134 --Meal Voucher ID
			group by salaryid, public.trn_candidate_otherduction.candidate_id
		) tblotherdeductionswithesi on openappointments.emp_id = tblotherdeductionswithesi.candidate_id and empsalaryregister.id = tblotherdeductionswithesi.salaryid

	/* =================================================================================================
	-- 15.j. VARIABLE VPF
	-- Pulls Variable Provident Fund deductions (Code 10).
	-- ================================================================================================= */
		left join (
			select salaryid, candidate_id, sum(deduction_amount) as variablevpf
			from public.trn_candidate_otherduction
			where public.trn_candidate_otherduction.active=''Y'' 
				and trn_candidate_otherduction.deduction_id = 10
			group by salaryid, public.trn_candidate_otherduction.candidate_id
		) tblvariablevpf on openappointments.emp_id = tblvariablevpf.candidate_id and empsalaryregister.id = tblvariablevpf.salaryid	

	/* =================================================================================================
	-- 15.k. EMPLOYEE LEDGER ARREARS & DEDUCTIONS
	-- Retrieves one-time additions or deductions pushed via Employee Ledger (e.g., TDS adjustments,
	-- missed salary compensation, security amounts). Prevents re-fetching already disbursed ledger entries.
	-- ================================================================================================= */
		left join (
			select emp_code, sum(otherledgerarear) as otherledgerarear,
				sum(otherledgerdeductions) as otherledgerdeductions,
				sum(otherledgerarearwithoutesi) as otherledgerarearwithoutesi,
				STRING_AGG(disbursedledgerids::text, '','') as disbursedledgerids,
				sum(othertaxablerefunds) as othertaxablerefunds,
				sum(security_amt) as security_amt,
				sum(conveyance) as conveyance,
				sum(tdsadjustment) as tdsadjustment 
			from (
				select emp_code
						, sum(case when amount>0 and (headid in (5,6) or coalesce(tbl_employeeledger.is_taxable,''N'')=''Y'') then amount else 0 end) as otherledgerarear
						, sum(case when amount<0 and coalesce(tbl_employeeledger.is_taxable,''N'')=''N'' and headid not in (12) then amount else 0 end) * -1 as otherledgerdeductions
						, sum(case when amount>0 and (headid not in (5,6,12) and coalesce(tbl_employeeledger.is_taxable,''N'')=''N'') then amount else 0 end) as otherledgerarearwithoutesi
						, sum(case when headid = 12 then amount else 0 end) as tdsadjustment
						, STRING_AGG(tbl_employeeledger.id::text, '','') as disbursedledgerids
						, sum(case when amount<0 and coalesce(tbl_employeeledger.is_taxable,''N'')=''Y'' and headid not in (12) then amount else 0 end) as othertaxablerefunds
						, 0 as security_amt
						, 0 as conveyance
				from tbl_employeeledger 
				inner join mst_otherduction on tbl_employeeledger.headid = mst_otherduction.id
				where tbl_employeeledger.isactive=''1'' 
					and processmonth='||p_mprmonth||'
					and processyear='||p_mpryear||'
					and tbl_employeeledger.id not in (
						select trim(regexp_split_to_table(dl.disbursedledgerids,'',''))::bigint 
						from tbl_monthlysalary dl 
						where dl.mprmonth='||p_mprmonth||' and dl.mpryear='||p_mpryear||' and coalesce(dl.is_rejected,''0'')<>''1''
					)
				group by emp_code
				
				union all
				
				/* Security amount deductions */
				select emp_code, sum(case when deduction_amount>0 then deduction_amount else 0 end) as otherledgerarear
						, 0 as otherledgerdeductions
						, 0 as otherledgerarearwithoutesi
						, 0 as tdsadjustment
						, null as disbursedledgerids
						, 0 as othertaxablerefunds
						, sum(case when deduction_amount<0 then deduction_amount else 0 end) * -1 as security_amt
						, 0 as conveyance
				from public.trn_candidate_otherduction 
				inner join openappointments on trn_candidate_otherduction.candidate_id = openappointments.emp_id
				where public.trn_candidate_otherduction.active=''Y''
					and trn_candidate_otherduction.deduction_id = 7
				group by emp_code
				
				union all
				
				/* Monthly Conveyance overrides (Code 87) */
				select emp_code, 0 as otherledgerarear
						, 0 as otherledgerdeductions
						, 0 as otherledgerarearwithoutesi
						, 0 as tdsadjustment
						, null as disbursedledgerids
						, 0 as othertaxablerefunds
						, 0 as security_amt
						, sum(case when deduction_amount>0 then deduction_amount else 0 end) as conveyance
				from public.trn_candidate_otherduction 
				inner join openappointments on trn_candidate_otherduction.candidate_id = openappointments.emp_id
				inner join mst_otherduction motd on motd.id = trn_candidate_otherduction.deduction_id
				where public.trn_candidate_otherduction.active=''Y''
					and trn_candidate_otherduction.deduction_frequency=''Monthly''
					and motd.id <> 134 
					and trn_candidate_otherduction.deduction_id = 87
				group by emp_code
			) tblotherledger1 
			group by emp_code
		) tblotherledger on cmsdownloadedwages.empcode::bigint = tblotherledger.emp_code  				  

	/* =================================================================================================
	-- 15.l. MEAL VOUCHERS
	-- Meal Voucher deductions (Code 134).
	-- ================================================================================================= */					  
		left join (
			select salaryid, candidate_id, sum(deduction_amount) as mealvoucher
			from public.trn_candidate_otherduction
			inner join mst_otherduction motd on motd.id = trn_candidate_otherduction.deduction_id
			where public.trn_candidate_otherduction.active=''Y'' 
				and deduction_amount > 0
				and motd.id = 134
			group by salaryid, public.trn_candidate_otherduction.candidate_id
		) tblmealvoucher on openappointments.emp_id = tblmealvoucher.candidate_id and empsalaryregister.id = tblmealvoucher.salaryid 	

	/* =================================================================================================
	-- 15.m. OTHER NON-TAXABLE VARIABLES
	-- Additional monthly components that are non-taxable and don't attract ESI.
	-- ================================================================================================= */	
		left join (
			select salaryid, candidate_id, sum(deduction_amount) as othervariables
				, string_agg(deduction_name || '':'' || deduction_amount, '','') as customnontaxablecomponents
			from public.trn_candidate_otherduction
			inner join mst_otherduction motd on motd.id = trn_candidate_otherduction.deduction_id
			where public.trn_candidate_otherduction.active=''Y''
				and motd.deduction_name not in (''Conveyance'')
				and deduction_amount > 0
				and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				and trn_candidate_otherduction.deduction_id not in (5,6,7,10)
				and coalesce(trn_candidate_otherduction.is_taxable,''N'')=''N''
				and motd.id <> 134
			group by salaryid, public.trn_candidate_otherduction.candidate_id
		) tblothervariables on openappointments.emp_id = tblothervariables.candidate_id and empsalaryregister.id = tblothervariables.salaryid
	';
	/* =================================================================================================
	-- 15.n. ALREADY PAID / PROCESSED COMPONENTS
	-- Aggregates values that have already been processed in the current month/year to prevent duplicate payouts.
	-- ================================================================================================= */
	v_querytext := v_querytext || '
		left join (
			select emp_code, sum(basic) as basicalreadypaid, sum(epf) as epfalreadydeducted
				, sum(coalesce(Ac_1,0)) as Ac_1alreadydeducted
				, sum(coalesce(Ac_10,0)) as ac_10alreadydeducted
				, sum(coalesce(Ac_2,0)) as ac_2alreadydeducted
				, sum(coalesce(Ac21,0)) as ac_21alreadydeducted
				, sum(insurance) as alreadyinsurance
				, sum(insuranceamount) as alreadyinsuranceamount
				, sum(familyinsurance) as alreadyfamilyfamilyinsurance
				, sum(otherledgerarears) as alreadyotherledgerarears
				, sum(otherledgerdeductions) as alreadyotherledgerdeductions
				, sum(tds) as alreadytds
				, sum(other) as alreadyother
				, sum(otherledgerarearwithoutesi) as otherledgerarearwithoutesialready
				, sum(lwf) as lwfalready
				, sum(lwf_employee) as lwf_employeealready
				, sum(lwf_employer) as lwf_employeralready
				, sum(ews) as ewsalready
				, sum(gratuity) as gratuityalready
				, sum(bonus) as bonusalready
				, sum(tdsadjustment) as alreadytdsadjustment
				, sum(security_amt) as alreadysecurity_amt
				, sum(grossearning) as alreadygrossearning
				, sum(coalesce(nullif(pfapplicablecomponents,0),basic) ) as pfapplicablecomponentsalreadypaid
				, sum(employerinsuranceamount) as alreadyemployerinsuranceamount
				, sum(mealvoucher) as alreadymealvoucher
			from tbl_monthlysalary 
			where mprmonth='||p_mprmonth||'
				and mpryear='||p_mpryear||'
				and coalesce(is_rejected,''0'')<>''1''
			group by emp_code
		) tblalreadypf on tblalreadypf.emp_code = openappointments.emp_code

	/* =================================================================================================
	-- 15.o. CURRENT MONTH TAX DEDUCTION TRACKING
	-- Identifies tax deductions across regular and liability payrolls tracking by PAN / EmpCode.
	-- Handles complex overlaps for advance salaries.
	-- ================================================================================================= */
		left join (
			select coalesce(nullif(trim(op2.pancard),''''), op2.emp_code::text) as taxpancard, sum(currentmonthtaxdeducted) as currentmonthtaxdeducted 
			from (
				select emp_code, sum(case when 
					(
						(
							(
								(
									to_date(left(hrgeneratedon,11),''dd Mon yyyy'') between '''||v_salstartdate::date||''' and '''||v_salenddate::date ||'''
									and to_date((mpryear::text||''-''||lpad(mprmonth::text,2,''0'')||''-01''),''yyyy-mm-dd'') < '''||v_salstartdate::date||'''
								)
								or
								(	
									to_date(left(hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancesalstartdate::date||''' and '''||v_advancesalenddate::date||'''	
									and mprmonth='||p_mprmonth||' and mpryear='||p_mpryear||'
								)
							)
							and attendancemode<>''Ledger''
						)
						or (to_date(left(hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancestartdate::date||''' and '''||v_advancesalenddate::date||''' and attendancemode=''Ledger'')	  
					)
					then tds else 0 end) as currentmonthtaxdeducted
				from (
					/* Regular Monthly Salaries */
					select emp_code, tds, grossearning, voucher_amount, otherdeductions, hrgeneratedon, is_rejected, mprmonth, mpryear, attendancemode
					from tbl_monthlysalary
					where ';
					
	if p_criteria = 'Employee' then	  
		v_querytext := v_querytext || ' 	 
						(tbl_monthlysalary.emp_code='||p_emp_code||' or tbl_monthlysalary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	
	v_querytext := v_querytext || ' 
						(( (
							to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_startdate::date||''' and '''||v_enddate::date||'''	 
							or
							(
								to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancestartdate::date ||''' and '''||v_advanceenddate::date||'''		 
								and mprmonth=4 and mpryear='||v_year1||'
							)
						)
						and attendancemode<>''Ledger''
						)
						or (to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancestartdate::date ||''' and '''||v_advanceenddate::date||''' and attendancemode=''Ledger'')	  
					)
					and not(mprmonth=4 and mpryear='||v_year2||')
					and coalesce(is_rejected,''0'')<>''1''
					
					union all
					
					/* Liability Salaries */
					select emp_code, tds, grossearning, voucher_amount, otherdeductions, hrgeneratedon, is_rejected, mprmonth, mpryear, attendancemode
					from tbl_monthly_liability_salary
					where ';
					
	if p_criteria = 'Employee' then	  
		v_querytext := v_querytext || ' 	 
						(tbl_monthly_liability_salary.emp_code='||p_emp_code||' or tbl_monthly_liability_salary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	
	v_querytext := v_querytext || '  
						coalesce(salary_remarks,'''') <> ''Invalid Paid Days''
						and coalesce(is_rejected,''0'') = ''0''
						and (emp_code, mprmonth, mpryear, batchid) not in (select '||p_emp_code||','||p_mprmonth||', '||p_mpryear||', '''||p_batch_no||''') 	
						and (emp_code, mprmonth, mpryear, batchid||transactionid) not in (select '||p_emp_code||','||p_mprmonth||', '||p_mpryear||', '''||p_batch_no||''') 		  
						and not(mprmonth=4 and mpryear='||v_year2||')
						and (
							to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_startdate::date||''' and '''||v_enddate::date||'''	 
							or
							(
								to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancestartdate::date||''' and '''||v_advanceenddate::date||'''		 
								and mprmonth=4 and mpryear='||v_year1||'
							)
						)
						and (emp_code, mprmonth, mpryear, batchid) not in (
							select emp_code, mprmonth, mpryear, batchid 
							from tbl_monthlysalary 
							where ';
							
	if p_criteria = 'Employee' then	  
		v_querytext := v_querytext || ' 	 
								(tbl_monthlysalary.emp_code='||p_emp_code||' or tbl_monthlysalary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	
	v_querytext := v_querytext || ' 
								(
									to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_startdate::date||''' and '''||v_enddate::date||'''	 
									or
									(
										to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancestartdate::date||''' and '''||v_advanceenddate::date||'''		 
										and mprmonth=4 and mpryear='||v_year1||'
									)
								)
								and coalesce(is_rejected,''0'')=''0''
						)
					union all
					(
						select emp_code, mprmonth, mpryear, batchid || coalesce(transactionid::text,'''')
						from tbl_monthlysalary 
						where  ';
						
	if p_criteria = 'Employee' then	  
		v_querytext := v_querytext || ' 	 
							(tbl_monthlysalary.emp_code='||p_emp_code||' or tbl_monthlysalary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	
	v_querytext := v_querytext || '
							(
								to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_startdate::date||''' and '''||v_enddate||'''	 
								or
								(
									to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancestartdate||''' and '''||v_advanceenddate||'''	 
									and mprmonth=4 and mpryear='||v_year1||'
								)
							)
							and coalesce(is_rejected,''0'')=''0''
					) 
					union all
					(
						select m.mprmonth, m.mpryear, m.emp_code, trim(regexp_split_to_table(m.batchid,'''','''')) 
						from tbl_monthlysalary m 
						where ';
						
	if p_criteria = 'Employee' then	  
		v_querytext := v_querytext || ' 	 
							(m.emp_code='||p_emp_code||' or m.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	
	v_querytext := v_querytext || ' 
							coalesce(m.is_rejected,''0'')=''0''
							and (
								to_date(left(m.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_startdate||''' and '''||v_enddate||'''	 
								or
								(
									to_date(left(m.hrgeneratedon,11),''dd Mon yyyy'') between '''||v_advancestartdate||''' and '''||v_advanceenddate||'''		 
									and m.mprmonth=4 and m.mpryear='||v_year1||'
								)
							)
					)
				) tbl_monthlysalary
				group by emp_code
			) tblcurrenttax
			inner join openappointments op2 on tblcurrenttax.emp_code = op2.emp_code
			group by coalesce(nullif(trim(op2.pancard),''''), op2.emp_code::text) 	
		) tblcurrenttax on coalesce(nullif(trim(openappointments.pancard),''''), openappointments.emp_code::text) = tblcurrenttax.taxpancard

	/* =================================================================================================
	-- 15.p. EMPLOYEE EXIT DETAILS
	-- Resolves relieving date and final dues clearance checks.
	-- ================================================================================================= */
		left join (
			select ee_empid, coalesce(ee_termination_date, ee_actualrelievingdate) as ee_relieveingdate, ee_finalduesclearancedate::date as ee_finalduesclearancedate 
			from public.employee_exit 
			where employee_exit.isactive=''1'' 
		) ee on openappointments.emp_id = ee.ee_empid
	';

	/* =================================================================================================
	-- 16. FINAL FILTERING CLAUSES
	-- Adding core filters for Criteria Type (Order, Employee, or Batch).
	-- ================================================================================================= */
	if p_criteria = 'Order' then
		v_querytext := v_querytext || ' where cmsdownloadedwages.contractno='''||p_ordernumber||''' ';
	end if;
	
	if p_criteria = 'Employee' then
		v_querytext := v_querytext || ' where cmsdownloadedwages.empcode='''||p_emp_code||''' ';
	end if;
	
	if p_criteria = 'Batch' then
		v_querytext := v_querytext || ' where cmsdownloadedwages.batch_no='''||p_batch_no||''' ';
	end if;
	
	v_querytext := v_querytext || ' ) tmp';
-----To print dynamic Query(Open when debuggig Needed)----------------------				 
	--raise notice 'Query: % ', v_querytext;	
-----To print dynamic Query----------------------	
if p_action='Retrieve_Salary' or p_action='Save_Salary'  then
if EXISTS (SELECT * FROM pg_catalog.pg_class c   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    		WHERE  c.relname = 'tmp_sal_pregenerate' AND c.relkind = 'r' and n.oid=pg_my_temp_schema()
					  ) then
DROP TABLE tmp_sal_pregenerate;
end if;					  
v_querytext2='CREATE TEMP TABLE tmp_sal_pregenerate ON COMMIT DROP as '||v_querytext;
 execute v_querytext2;
--raise notice 'Query: % ', v_querytext2;	
update tmp_sal_pregenerate set ctc_paid_days=round((actual_paid_ctc2/ctc)*monthdays)
where is_special_category='Y';
/***************************Changes for 1.37****************/
update tmp_sal_pregenerate 
	set tds=grossearning*coalesce(customtaxpercent/100.0,.01),atds=grossearning*coalesce(customtaxpercent/100.0,.01),
	grossdeduction=grossdeduction-coalesce(tds,0)+grossearning*coalesce(customtaxpercent/100.0,.01),
	netpay=netpay+coalesce(tds,0)-grossearning*coalesce(customtaxpercent/100.0,.01)
from openappointments op inner join empsalaryregister e
	on op.emp_id=e.appointment_id
where tmp_sal_pregenerate.emp_code=op.emp_code and op.jobtype='Independent Contractors'
	 and e.id=tmp_sal_pregenerate.salaryid;
/***************************Changes for 1.19****************/
update tmp_sal_pregenerate 
	set tds=0,atds=0,
	grossdeduction=grossdeduction-coalesce(tds,0),
	netpay=netpay+coalesce(tds,0)
where coalesce(tds,0)>coalesce(grossearning,0);
/***************************Changes for 1.19 end here****************/		
/***************************Below changes for 1.13****************/
-- update tmp_sal_pregenerate set ctc_actual_paid=(ctc*ctc_paid_days/monthdays),
-- 	mobile_deduction=(ctc*ctc_paid_days/monthdays)-actual_paid_ctc2
-- 	,netpay=netpay+coalesce(otherledgerarear,0)-coalesce(otherledgerdeductions,0)+coalesce(otherledgerarearwithoutesi,0)
--    where is_special_category='Y';
/*********Change 1.14**************************/
/***********Change 1.14 ends here*****************************/
update tmp_sal_pregenerate set ctc_actual_paid=(ctc*ctc_paid_days/monthdays),
       netpay=netpay+coalesce(otherledgerarear,0)-coalesce(grossdeduction,0)+coalesce(otherledgerarearwithoutesi,0)
   where is_special_category='Y'; 
   
 update tmp_sal_pregenerate  
	set mobile_deduction=case when ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0)) >0 then ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0))  else 0 end
	             ,mobile=case when ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0)) >0 then ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0))  else 0 end
	            ,incentive=case when (coalesce(netpay,0.0)-(grossearning-coalesce(grossdeduction,0.0))) >0 then (coalesce(netpay,0.0)-(grossearning-coalesce(grossdeduction,0.0)))  else 0 end
where is_special_category='Y'; 

update tmp_sal_pregenerate set 
       netpay=netpay+coalesce(netarear,0)
   where is_special_category='Y'; 
/***************************Changes for 1.13 ends****************/
/***************************Changes for 1.24****************/
with tmpexgrossearning as
(
select emp_code,sum(grossearning) grossearning,sum(professionaltax) pt from tbl_monthlysalary
	where emp_code in (select emp_code from tmp_sal_pregenerate) and
	  (
		  (mprmonth=p_mprmonth and mpryear=p_mpryear)
		  or
			(to_date(left(hrgeneratedon,11),'dd Mon yyyy')
				between v_salstartdate  and v_salenddate
			 and  recordscreen<>'Current Wages'
			 )
-- 			or
-- 				(
-- 				to_date(left(hrgeneratedon,11),'dd Mon yyyy')
-- 				between v_advancesalstartdate  and v_advancesalenddate		 
-- 				and mprmonth=p_mprmonth and mpryear=p_mpryear
-- 				 )
			)
	and is_rejected='0'
	and istaxapplicable='1'
	group by emp_code
)
update tmp_sal_pregenerate 
	set professionaltax=tbl1.professionaltax,grossdeduction=grossdeduction+coalesce(tbl1.professionaltax,0)
	,netpay=netpay-coalesce(tbl1.professionaltax,0)
	from (select op.emp_code,e.id,mst_statewiseprofftax.ptamount professionaltax,te.grossearning,mst_statewiseprofftax.lowerlimit,mst_statewiseprofftax.upperlimit,te.pt
		  from  openappointments op 
	inner join empsalaryregister e on e.appointment_id=op.emp_id
		  and op.emp_code=p_emp_code and e.appointment_id=v_openappointments.emp_id
		  inner join tmp_sal_pregenerate on op.emp_code=tmp_sal_pregenerate.emp_code and e.id=tmp_sal_pregenerate.salaryid
		  inner join vw_mst_statewiseprofftax mst_statewiseprofftax on mst_statewiseprofftax.ptid=e.ptid 
		 --  and extract ('month' from (current_date-interval '1 month'))=mst_statewiseprofftax.ptmonth 
		 -- pt month should be mpr-month as disussed with yatin sir dated. 10.03.2026
		   and  mst_statewiseprofftax.ptmonth = p_mprmonth ::int
		 -- end 
		  and trim(lower(case when op.gender='M' then 'Male' when op.gender='F' then 'Female' else op.gender end))=trim(lower(mst_statewiseprofftax.ptgender))
		  and mst_statewiseprofftax.isactive='1'
		  --and (date_trunc('month',current_date)-interval '1 month')::date  between mst_statewiseprofftax.ptapplicablefrom and mst_statewiseprofftax.ptapplicableto
		 left join tmpexgrossearning te on te.emp_code=op.emp_code) tbl1
	where tmp_sal_pregenerate.emp_code=tbl1.emp_code and tbl1.professionaltax>0
	and (coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_pregenerate.grossearning,0)) between tbl1.lowerlimit and tbl1.upperlimit
	and coalesce(tbl1.pt,0)<=0;
/***************************Changes for 1.24 end here****************/	
/***************************Changes for 1.25****************/
with tmpexgrossearning as
(
select emp_code,sum(grossearning) grossearning,sum(lwf_employee) lwf_employee
	from tbl_monthlysalary
	where emp_code in (select emp_code from tmp_sal_pregenerate) 
	and mprmonth=p_mprmonth 
	and mpryear=p_mpryear
	and is_rejected='0'
	and istaxapplicable='1'
	group by emp_code
)
update tmp_sal_pregenerate 
	set lwf=least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_pregenerate.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0)),
		lwf_employee=least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_pregenerate.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0)),
		lwf_employer=least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_pregenerate.grossearning,0))*employer_lwfpercent/100,coalesce(tbl1.employerlwfrate,0)),coalesce(tbl1.employerlwfrate,0)),
		grossdeduction=grossdeduction+least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_pregenerate.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0)),
		netpay=netpay-least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_pregenerate.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0))
	from (select op.emp_code,e.id,statewiselwfrate.employeelwfrate ,statewiselwfrate.employerlwfrate,te.grossearning,statewiselwfrate.lwfexemptionlimit,te.lwf_employee,statewiselwfrate.deductionmonths
		  ,e.islwfstate
		  ,statewiselwfrate.employee_lwfpercent,statewiselwfrate.employer_lwfpercent
		  from  openappointments op 
	inner join empsalaryregister e on e.appointment_id=op.emp_id
		  and op.emp_code=p_emp_code and e.appointment_id=v_openappointments.emp_id
		  inner join tmp_sal_pregenerate on op.emp_code=tmp_sal_pregenerate.emp_code and e.id=tmp_sal_pregenerate.salaryid
		  left join statewiselwfrate on coalesce(e.lwfstatecode,0)=statewiselwfrate.statecode and statewiselwfrate.isactive='1'
		 left join tmpexgrossearning te on te.emp_code=op.emp_code) tbl1
	where tmp_sal_pregenerate.emp_code=tbl1.emp_code and coalesce(tbl1.employeelwfrate,0)>0
	and tmp_sal_pregenerate.mprmonth in (select regexp_split_to_table(tbl1.deductionmonths,',')::int)
	and (coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_pregenerate.grossearning,0)) >= coalesce(tbl1.lwfexemptionlimit,0)
	and coalesce(tbl1.lwf_employee,0)<=0
	and coalesce(islwfstate,'N')='Y'
	;
update tmp_sal_pregenerate 	set lwf=0,lwf_employee=0,lwf_employer=0,grossdeduction=grossdeduction-coalesce(lwf_employee,0),netpay=netpay+coalesce(lwf_employee,0) where paiddays=0;	
/***************************Changes for 1.25 end here****************/	
end if;

																																					
																																													

if p_action='Retrieve_Salary' and p_process_status='NotProcessed' then	
				
	 
	delete from paymentadvice where emp_code=p_emp_code and mprmonth=p_mprmonth and mpryear=p_mpryear and coalesce(v_cmsdownloadedwages.attendancemode,'') not in ('Manual','Ledger') and attendancemode<>'Ledger' and p_multipayoutrequestid=0;
							  
	 
										  
														 
														  
  
																						  

 
		--open sal for select * from (
	/* =================================================================================================
	-- 17. FINAL PAYMENT ADVICE GENERATION
	-- If processing is standard ('NotProcessed' state), the final generated salary components from the 
	-- temporary table are verified, stamped with status flags, and inserted into the system's `paymentadvice` log.
	-- ================================================================================================= */
	
	/* Clear any pre-existing unverified entries for this batch */
	delete from paymentadvice 
	where emp_code = p_emp_code 
		and mprmonth = p_mprmonth 
		and mpryear = p_mpryear 
		and coalesce(v_cmsdownloadedwages.attendancemode,'') not in ('Manual','Ledger') 
		and attendancemode <> 'Ledger' 
		and p_multipayoutrequestid = 0;

	insert into paymentadvice (
		fnfarrivalstatus, mprmonth, mpryear, is_paused, emp_id, mon, dateofjoining, esinumber, 
		posting_department, projectname, contractno, contractcategory, contracttype, activeinbatch, 
		appointment_status_id, remark, lockstatus, is_account_verified, isesiexceptionalcase, 
		esicexceptionmessage, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, 
		post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, 
		residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, 
		ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, 
		hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, 
		rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, 
		incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, 
		mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, 
		lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, is_special_category, 
		ct2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, 
		salaryid, employeenpsrate, employernpsrate, insuranceamount, familyinsuranceamount, 
		bankaccountno, ifsccode, bankname, bankbranch, netarear, arearaddedmonths, 
		employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, 
		salaryindaysopted, salarydays, otherledgerarear, otherledgerdeductions, attendancemode, 
		incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, 
		incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, 
		lwf_employer, bonus, otherledgerarearwithoutesi, otherdeductions, othervariables, 
		otherdeductionswithesi, lwfstatecode, tdsadjustment, atds, hrgeneratedon, disbursedledgerids, 
		security_amt, issalaryorliability, professionaltax, customtaxablecomponents, customnontaxablecomponents, 
		ratesalarybonus, ratecommission, ratetransport_allowance, ratetravelling_allowance, 
		rateleave_encashment, rateovertime_allowance, ratenotice_pay, ratehold_salary_non_taxable, 
		ratechildren_education_allowance, rategratuityinhand, salarybonus, commission, 
		transport_allowance, travelling_allowance, leave_encashment, overtime_allowance, 
		notice_pay, hold_salary_non_taxable, children_education_allowance, gratuityinhand, 
		customeraccountid, orgempcode, tpcode, tea_allowance, pfapplicablecomponents, 
		esiapplicablecomponents, isgroupinsurance, employerinsuranceamount, incentivepaiddays, 
		charity_contribution_amount, mealvoucher, verificationstatus, hasarrear, rejectstatus, 
		processedon, paiddaysstatus, pfpaystatus, attendanceid, jobtype, multipayoutrequestid
	)
	select *, p_multipayoutrequestid 
	from (
		select tmp_sal_pregenerate.*
			, case 
				when m.emp_code is null then 'Not Verified'		
				when coalesce(m.is_rejected,'0') = '1' then 'Rejected'
				when m.emp_code is not null then 'Verified'
			  end as verificationstatus
			, case when tblhasarear.empcode is null then 'No Arear' else 'Has Arear' end as hasarrear
			, case when m.is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus
			, to_char(m.createdon,'dd-Mon-yyyy') as processedon
			, case 
				when (invpddays_empcode is null and tms3.invpddays_empcode2 is null) or v_empsalaryregister.flexiblemonthdays='Y' then 'Valid' 
				else 'Invalid' 
			  end as paiddaysstatus
			, case when epfecr_empcode is not null then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus
			, null::bigint
			, v_openappointments.jobtype
		from tmp_sal_pregenerate
		
		left join tbl_monthlysalary m on tmp_sal_pregenerate.emp_code = m.emp_code
			and tmp_sal_pregenerate.mpryear = m.mpryear
			and tmp_sal_pregenerate.mprmonth = m.mprmonth
			and tmp_sal_pregenerate.batch_no = m.batchid
			and m.emp_code = p_emp_code 
			
		left join (
			select distinct empcode
			from cmsdownloadedwages
			where to_date('01'||lpad(cmsdownloadedwages.mprmonth::text,2,'0')||cmsdownloadedwages.mpryear::text,'ddmmyyyy') <= to_date('01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text,'ddmmyyyy')
				and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y') <> 'N'
				and cmsdownloadedwages.empcode::bigint = p_emp_code
		) tblhasarear on tmp_sal_pregenerate.emp_code = tblhasarear.empcode::bigint
		
		left join (
			select empcode as invpddays_empcode, sum(coalesce(totalpaiddays,0) + coalesce(totalleavetaken,0)) as invdays
			from cmsdownloadedwages
			where mprmonth = p_mprmonth
				and mpryear = p_mpryear
				and isactive = '1'
				and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y') <> 'N'
				and cmsdownloadedwages.empcode::bigint = p_emp_code
			group by empcode
			having sum(coalesce(totalpaiddays,0) + coalesce(totalleavetaken,0)) > v_monthdays 
				or v_empsalaryregister.flexiblemonthdays = 'Y'
		) m4 on tmp_sal_pregenerate.emp_code = m4.invpddays_empcode::bigint
		
		left join (
			select tms2.emp_code as invpddays_empcode2, sum(coalesce(tms2.paiddays,0)) as invdays2
			from (
				select emp_code, paiddays from tmp_sal_pregenerate
				union all
				select emp_code, paiddays from tbl_monthlysalary 
				where emp_code in (select emp_code from tmp_sal_pregenerate) 
					and is_rejected = '0' 
					and recordscreen not in ('Increment Arear')
					and mprmonth = p_mprmonth
					and mpryear = p_mpryear
					and tbl_monthlysalary.emp_code = p_emp_code
			) tms2
			group by tms2.emp_code
			having sum(coalesce(tms2.paiddays,0)) > v_monthdays
		) tms3 on tmp_sal_pregenerate.emp_code = tms3.invpddays_empcode2::bigint
		
		left join (
			select distinct unprocessed_epfecrreport.emp_code as epfecr_empcode
				, unprocessed_epfecrreport.rpt_year
				, unprocessed_epfecrreport.rpt_month
				, unprocessed_epfecrreport.batchid
			from unprocessed_epfecrreport
			where rpt_month = p_mprmonth
				and rpt_year = p_mpryear
				and unprocessed_epfecrreport.emp_code = p_emp_code
		) tmpepfecr on tmp_sal_pregenerate.emp_code = tmpepfecr.epfecr_empcode
			and tmp_sal_pregenerate.mpryear = tmpepfecr.rpt_year
			and tmp_sal_pregenerate.mprmonth = tmpepfecr.rpt_month
			and tmp_sal_pregenerate.batch_no = tmpepfecr.batchid
	) tmp2;
								  

													   

								   
															
						 
				 
						   
							 
											  
  
				 
													

	open sal for select * from paymentadvice where emp_code=p_emp_code and mprmonth=p_mprmonth and mpryear=p_mpryear and multipayoutrequestid=p_multipayoutrequestid order by COALESCE(attendancemode ,'MPR') desc limit 1; 
			return sal;
end if;	
	/* =================================================================================================
	-- 18. RETRIEVE PROCESSED/UNPROCESSED SALARIES (GET PROCESSED SALARIES)
	-- Handles the retrieval of salaries that are fully processed or not processed.
	-- Joins with historical processed tables (`tbl_monthlysalary`), active tracking logs, and pauses.
	-- ================================================================================================= */
	if (coalesce(nullif(p_process_status,''),'NotProcessed') in ('Processed','NotProcessed') and p_action='GetProcessedSalaries') then
		open sal for 
		with tblmain as (
			select 
				'NoFNFLock' as fnfarrivalstatus /* column added for change 1.15 */, 
				tbl_monthlysalary.mprmonth, 
				tbl_monthlysalary.mpryear, 
				MTempPausedSalary.is_paused, 
				openappointments.emp_id, 
				to_char(to_timestamp(p_mprmonth::text, 'MM'), 'Mon') || '-' || p_mpryear::text as Mon,
				to_char(dateofjoining, 'dd/mm/yyyy') as dateofjoining, esinumber, posting_department, '' as projectname,
				cm.contractno as contractno, '' as contractcategory, '' as contracttype, 'Active' as activeinbatch, 
				appointment_status_id, '' as remark, 'Unlocked' as lockstatus,
				coalesce(is_account_verified, '0')::bit as is_account_verified,
				null as isesiexceptionalcase, null as esicexceptionmessage,
				openappointments.emp_code, subunit, to_char(dateofleaving, 'dd-Mon-yyyy') as dateofleaving, totalleavetaken, 
				openappointments.emp_name, openappointments.post_offered, openappointments.emp_address, openappointments.email,
				mobilenum, openappointments.pancard, openappointments.gender, to_char(openappointments.dateofbirth, 'dd/mm/yyyy') as dateofbirth, 
				openappointments.fathername, openappointments.residential_address, openappointments.pfnumber, openappointments.uannumber, 
				lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, 
				fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal,
				ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, 
				incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, tbl_monthlysalary.mobile, advance,
				other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, 
				tbl_monthlysalary.govt_bonus_opted, govt_bonus_amt, is_special_category, ctc2 as ct2, batch_no, actual_paid_ctc2, 
				ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, employeenps, employernps, insuranceamount, 
				familyinsurance, tbl_monthlysalary.bankaccountno, tbl_monthlysalary.ifsccode, tbl_monthlysalary.bankname, tbl_monthlysalary.bankbranch,
				totalarear as netarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction,
				total_esi_incentive_deduction, salaryindaysopted, mastersalarydays as salarydays, otherledgerarears as otherledgerarear, 
				otherledgerdeductions, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, 
				incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, bonus, 
				otherledgerarearwithoutesi, otherdeductions, othervariables, otherbonuswithesi as otherdeductionswithesi, 
				tbl_monthlysalary.lwfstatecode, tbl_monthlysalary.tdsadjustment, atds, hrgeneratedon, '' as disbursedledgerids, 
				security_amt, issalaryorliability, professionaltax, 
				case when issalaryorliability='L' then 'Not Verified' else 'Verified' end as verificationstatus, 
				'' as hasarear, 
				case when is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus, 
				to_char(tbl_monthlysalary.createdon, 'dd-Mon-yyyy') as processedon, 'Valid' as paiddaysstatus,
				case when epfecr_empcode is not null or issalaryorliability='L' then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus, 
				disbursementmode
			from public.tbl_monthlysalary 
			inner join openappointments on tbl_monthlysalary.emp_code = openappointments.emp_code
				and openappointments.appointment_status_id <> 13 
				and coalesce(tbl_monthlysalary.is_rejected, '0') <> '1'
				and (tbl_monthlysalary.isarear <> 'Y' or tbl_monthlysalary.recordscreen = 'Previous Wages')
				and issalaryorliability = case 
					when (p_action='Retrieve_Salary' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') or (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='NotProcessed') then 'L' 
					when (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') then 'S' 
				end
			/* Processed record search criteria */
			and tbl_monthlysalary.emp_code = case when p_criteria='Employee' then p_emp_code else tbl_monthlysalary.emp_code end
			
			left join (
				select empcode, mprmonth, mpryear, batch_no as batchn, string_agg(contractno,',') as contractno
				from cmsdownloadedwages cm 
				where cm.mprmonth = p_mprmonth
					and cm.mpryear = p_mpryear
					and cm.isactive = '1'
					and cm.contractno = case when p_criteria='Order' then p_ordernumber else cm.contractno end
				group by empcode, mprmonth, mpryear, batch_no
			) cm on tbl_monthlysalary.emp_code = cm.empcode::bigint and tbl_monthlysalary.batchid = cm.batchn							   
			
			left join (
				select empid, pausedstatus as is_paused  
				from ManageTempPausedSalary
				where ManageTempPausedSalary.ProcessYear = p_mpryear
					and ManageTempPausedSalary.ProcessMonth = p_mprmonth
			) MTempPausedSalary on openappointments.emp_id = MTempPausedSalary.empid 
			
			left join (
				select distinct epfecrreport.emp_code as epfecr_empcode, epfecrreport.rpt_year, epfecrreport.rpt_month, epfecrreport.batchid
				from epfecrreport
				where rpt_month = p_mprmonth and rpt_year = p_mpryear
			) tmpepfecr on tbl_monthlysalary.emp_code = tmpepfecr.epfecr_empcode
				and tbl_monthlysalary.mpryear = tmpepfecr.rpt_year
				and tbl_monthlysalary.mprmonth = tmpepfecr.rpt_month
				and tbl_monthlysalary.batchid = tmpepfecr.batchid												
			where tbl_monthlysalary.mprmonth = p_mprmonth
				and tbl_monthlysalary.mpryear = p_mpryear
				and coalesce(cm.contractno,'') = case when p_criteria='Order' then p_ordernumber else coalesce(cm.contractno,'') end
		)
		select tblmain.*, tblbalance.ledgerbalance 
		from tblmain 
		inner join (
			select tblbalance.emp_code, sum(tblbalance.netpay) as ledgerbalance
			from tblmain as tblbalance 
			group by tblbalance.emp_code
		) tblbalance on tblmain.emp_code = tblbalance.emp_code
		order by tblmain.emp_code;
			 
		return sal;				 
	end if;
	/* =================================================================================================
	-- 19. RETRIEVE PARTIALLY PROCESSED SALARIES
	-- Specifically targets the "Ledger" attendance mode to identify partially processed or adjusted historical wages.
	-- Handles past month processing lookbacks based on 'L' (liability) entries.
	-- ================================================================================================= */
	if (coalesce(nullif(p_process_status,''),'NotProcessed') = 'PartiallyProcessed' and p_action = 'GetProcessedSalaries') then
		open sal for			
		with tblmain as ( 
			select 
				'NoFNFLock' as fnfarrivalstatus /* column added for change 1.15 */, 
				tbl_monthlysalary.mprmonth, 
				tbl_monthlysalary.mpryear, 
				MTempPausedSalary.is_paused, 
				openappointments.emp_id, 
				to_char(to_timestamp(p_mprmonth::text, 'MM'), 'Mon') || '-' || p_mpryear::text as Mon,
				to_char(dateofjoining, 'dd/mm/yyyy') as dateofjoining, esinumber, posting_department, '' as projectname,
				cm.contractno as contractno, '' as contractcategory, '' as contracttype, 'Active' as activeinbatch, 
				appointment_status_id, '' as remark, 'Unlocked' as lockstatus,
				coalesce(is_account_verified, '0')::bit as is_account_verified,
				null as isesiexceptionalcase, null as esicexceptionmessage,
				openappointments.emp_code, subunit, to_char(dateofleaving, 'dd-Mon-yyyy') as dateofleaving, totalleavetaken, 
				openappointments.emp_name, openappointments.post_offered, openappointments.emp_address, openappointments.email,
				mobilenum, openappointments.pancard, openappointments.gender, to_char(openappointments.dateofbirth, 'dd/mm/yyyy') as dateofbirth, 
				openappointments.fathername, openappointments.residential_address, openappointments.pfnumber, openappointments.uannumber, 
				lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, 
				fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal,
				ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, 
				incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, tbl_monthlysalary.mobile, advance,
				other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, 
				tbl_monthlysalary.govt_bonus_opted, govt_bonus_amt, is_special_category, ctc2 as ct2, batch_no, actual_paid_ctc2, 
				ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, employeenps, employernps, insuranceamount, 
				familyinsurance, tbl_monthlysalary.bankaccountno, tbl_monthlysalary.ifsccode, tbl_monthlysalary.bankname, tbl_monthlysalary.bankbranch,
				totalarear as netarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction,
				total_esi_incentive_deduction, salaryindaysopted, mastersalarydays as salarydays, otherledgerarears as otherledgerarear, 
				otherledgerdeductions, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, 
				incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, bonus, 
				otherledgerarearwithoutesi, otherdeductions, othervariables, otherbonuswithesi as otherdeductionswithesi, 
				tbl_monthlysalary.lwfstatecode, tbl_monthlysalary.tdsadjustment, atds, hrgeneratedon, '' as disbursedledgerids, 
				security_amt, issalaryorliability, professionaltax, 
				case when issalaryorliability='L' then 'Not Verified' else 'Verified' end as verificationstatus, 
				'' as hasarear, 
				case when is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus, 
				to_char(tbl_monthlysalary.createdon, 'dd-Mon-yyyy') as processedon, 'Valid' as paiddaysstatus,
				case when epfecr_empcode is not null or issalaryorliability='L' then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus, 
				disbursementmode			
			from public.tbl_monthlysalary 
			inner join openappointments on tbl_monthlysalary.emp_code = openappointments.emp_code
				and openappointments.appointment_status_id <> 13 
				and coalesce(tbl_monthlysalary.is_rejected, '0') <> '1'
				and (tbl_monthlysalary.isarear <> 'Y' or tbl_monthlysalary.recordscreen = 'Previous Wages')
				and issalaryorliability = 'L'
				and tbl_monthlysalary.attendancemode = 'Ledger'			
			
			/* Processed record search criteria */
			and tbl_monthlysalary.emp_code = case when p_criteria='Employee' then p_emp_code else tbl_monthlysalary.emp_code end
			
			left join (
				select empcode, mprmonth, mpryear, batch_no as batchn, string_agg(contractno,',') as contractno
				from cmsdownloadedwages cm 
				where cm.mprmonth = p_mprmonth
					and cm.mpryear = p_mpryear
					and cm.isactive = '1'
					and cm.contractno = case when p_criteria='Order' then p_ordernumber else cm.contractno end
				group by empcode, mprmonth, mpryear, batch_no
			) cm on tbl_monthlysalary.emp_code = cm.empcode::bigint and tbl_monthlysalary.batchid = cm.batchn							   
			
			left join (
				select empid, pausedstatus as is_paused  
				from ManageTempPausedSalary
				where ManageTempPausedSalary.ProcessYear = p_mpryear
					and ManageTempPausedSalary.ProcessMonth = p_mprmonth
			) MTempPausedSalary on openappointments.emp_id = MTempPausedSalary.empid 
			
			left join (
				select distinct epfecrreport.emp_code as epfecr_empcode, epfecrreport.rpt_year, epfecrreport.rpt_month, epfecrreport.batchid
				from epfecrreport
				where rpt_month = p_mprmonth and rpt_year = p_mpryear
			) tmpepfecr on tbl_monthlysalary.emp_code = tmpepfecr.epfecr_empcode
				and tbl_monthlysalary.mpryear = tmpepfecr.rpt_year
				and tbl_monthlysalary.mprmonth = tmpepfecr.rpt_month
				and tbl_monthlysalary.batchid = tmpepfecr.batchid												
			where tbl_monthlysalary.is_rejected = '0' 
				and (
					(tbl_monthlysalary.mprmonth < p_mprmonth and tbl_monthlysalary.mpryear = p_mpryear) 
					or tbl_monthlysalary.mpryear < p_mpryear
				)
				and coalesce(cm.contractno,'') = case when p_criteria='Order' then p_ordernumber else coalesce(cm.contractno,'') end
		)
		select tblmain.*, tblbalance.ledgerbalance 
		from tblmain 
		inner join (
			select tblbalance.emp_code, sum(tblbalance.netpay) as ledgerbalance
			from tblmain as tblbalance 
			group by tblbalance.emp_code
		) tblbalance on tblmain.emp_code = tblbalance.emp_code
		order by tblmain.emp_code;
			 
		return sal;				 
	end if;
/*****************Change 1.21 ends here**************************************/
 if (coalesce(nullif(p_process_status,''),'NotProcessed')='Processed' and p_action='Retrieve_Salary') then
 			open sal for 
 			SELECT 'NoFNFLock' as fnfarrivalstatus /* column added for change 1.15 */, 
				tbl_monthlysalary.mprmonth, 
				tbl_monthlysalary.mpryear, 
				MTempPausedSalary.is_paused, 
				openappointments.emp_id, 
				to_char(to_timestamp(p_mprmonth::text, 'MM'), 'Mon') || '-' || p_mpryear::text as Mon,
				to_char(dateofjoining, 'dd/mm/yyyy') as dateofjoining, esinumber, posting_department, '' as projectname,
				cm.contractno as contractno, '' as contractcategory, '' as contracttype, 'Active' as activeinbatch, 
				appointment_status_id, '' as remark, 'Unlocked' as lockstatus,
				coalesce(is_account_verified, '0')::bit as is_account_verified,
				null as isesiexceptionalcase, null as esicexceptionmessage,
				openappointments.emp_code, subunit, to_char(dateofleaving, 'dd-Mon-yyyy') as dateofleaving, totalleavetaken, 
				openappointments.emp_name, openappointments.post_offered, openappointments.emp_address, openappointments.email,
				mobilenum, openappointments.pancard, openappointments.gender, to_char(openappointments.dateofbirth, 'dd/mm/yyyy') as dateofbirth, 
				openappointments.fathername, openappointments.residential_address, openappointments.pfnumber, openappointments.uannumber, 
				lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, 
				fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal,
				ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, 
				incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, tbl_monthlysalary.mobile, advance,
				other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, 
				tbl_monthlysalary.govt_bonus_opted, govt_bonus_amt, is_special_category, ctc2 as ct2, batch_no, actual_paid_ctc2, 
				ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, employeenps, employernps, insuranceamount, 
				familyinsurance, tbl_monthlysalary.bankaccountno, tbl_monthlysalary.ifsccode, tbl_monthlysalary.bankname, tbl_monthlysalary.bankbranch,
				totalarear as netarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction,
				total_esi_incentive_deduction, salaryindaysopted, mastersalarydays as salarydays, otherledgerarears as otherledgerarear, 
				otherledgerdeductions, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, 
				incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, bonus, 
				otherledgerarearwithoutesi, otherdeductions, othervariables, otherbonuswithesi as otherdeductionswithesi, 
				tbl_monthlysalary.lwfstatecode, tbl_monthlysalary.tdsadjustment, atds, hrgeneratedon, '' as disbursedledgerids, 
				security_amt, issalaryorliability, 
				case when issalaryorliability='L' then 'Not Verified' else 'Verified' end as verificationstatus, 
				'' as hasarear, 
				case when is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus, 
				to_char(tbl_monthlysalary.createdon, 'dd-Mon-yyyy') as processedon, 'Valid' as paiddaysstatus,
				case when epfecr_empcode is not null or issalaryorliability='L' then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus
		from public.tbl_monthlysalary 
		inner join openappointments on tbl_monthlysalary.emp_code = openappointments.emp_code
			and openappointments.appointment_status_id <> 13 
			and coalesce(tbl_monthlysalary.is_rejected, '0') <> '1'
			and (tbl_monthlysalary.isarear <> 'Y' or tbl_monthlysalary.recordscreen = 'Previous Wages')
			and issalaryorliability = case 
				when (p_action='Retrieve_Salary' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') or (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='NotProcessed') then 'L' 
				when (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') then 'S' 
			end
		
		/* Processed record search criteria */
		and tbl_monthlysalary.emp_code = case when p_criteria='Employee' then p_emp_code else tbl_monthlysalary.emp_code end
		left join (
			select empcode, mprmonth, mpryear, batch_no as batchn, string_agg(contractno,',') as contractno
			from cmsdownloadedwages cm 
			where cm.mprmonth = p_mprmonth
				and cm.mpryear = p_mpryear
				and cm.isactive = '1'
				and cm.contractno = case when p_criteria='Order' then p_ordernumber else cm.contractno end
			group by empcode, mprmonth, mpryear, batch_no
		) cm on tbl_monthlysalary.emp_code = cm.empcode::bigint and tbl_monthlysalary.batchid = cm.batchn							   
		
		left join (
			select empid, pausedstatus as is_paused  
			from ManageTempPausedSalary
			where ManageTempPausedSalary.ProcessYear = p_mpryear
				and ManageTempPausedSalary.ProcessMonth = p_mprmonth
		) MTempPausedSalary on openappointments.emp_id = MTempPausedSalary.empid 
		
		left join (
			select distinct epfecrreport.emp_code as epfecr_empcode, epfecrreport.rpt_year, epfecrreport.rpt_month, epfecrreport.batchid
			from epfecrreport
			where rpt_month = p_mprmonth and rpt_year = p_mpryear
		) tmpepfecr on tbl_monthlysalary.emp_code = tmpepfecr.epfecr_empcode
			and tbl_monthlysalary.mpryear = tmpepfecr.rpt_year
			and tbl_monthlysalary.mprmonth = tmpepfecr.rpt_month
			and tbl_monthlysalary.batchid = tmpepfecr.batchid												
		where tbl_monthlysalary.mprmonth = p_mprmonth
			and tbl_monthlysalary.mpryear = p_mpryear
			and coalesce(cm.contractno,'') = case when p_criteria='Order' then p_ordernumber else coalesce(cm.contractno,'') end;
			 
return sal;				 
end if;
-- exception when others then
 --raise notice 'Query: % ', v_querytext;		
-- open sal for select 0 as cnt;		
-- 	return sal;		
end;

$BODY$;

ALTER FUNCTION public.uspgetorderwisewages_pregenerate(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, character varying, text, text, bigint, numeric)
    OWNER TO payrollingdb;

