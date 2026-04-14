-- FUNCTION: public.uspgetorderwisewages(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, character varying, character varying, bigint, record, bigint)

-- DROP FUNCTION IF EXISTS public.uspgetorderwisewages(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, character varying, character varying, bigint, record, bigint);

CREATE OR REPLACE FUNCTION public.uspgetorderwisewages(
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
	p_companycode character varying DEFAULT 'A0001'::character varying,
	p_payment_recordid bigint DEFAULT (- (9999)::bigint),
	p_paymentadvice record DEFAULT NULL::record,
	p_multipayoutrequestid bigint DEFAULT (0)::bigint)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    SET plan_cache_mode='force_custom_plan'
AS $BODY$


	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 1: Variable Declarations
	-- Description: Declares core variables required for the main salary generation logic.
	-------------------------------------------------------------------------------------------------------------------------
DECLARE 
	sal refcursor;
	v_monthdays int;
	v_querytext varchar;
	v_querytext2 varchar;
	v_pausequery varchar;
	p_createdbyip varchar(200);
	v_innerprocresult int:=0;
	v_lwfemployee numeric(18,2);
	v_lwfemployer numeric(18,2);
	v_lwftotal numeric(18,2);
	v_lwfdeductionmonths varchar(50);

DECLARE
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
	v_rec record;
	v_openappointments openappointments%rowtype;
	v_overtime numeric(18,2);
	v_weekly_consecutive_overtime numeric(18,2):=0;
	v_empsalaryregister empsalaryregister%rowtype;
	v_actualdays int;
	v_tea_allowance  numeric(18,2):=0;
	v_isarear varchar(1):='N';
	v_recordscreen varchar(20):='Current Wages';
	v_isarearprocessed varchar(1):='N';
	v_arearprocessmonth int :=0;
	v_arearprocessyear int:=0;
	v_attendancemode varchar(30);
	v_rec_payrolldates record;
	v_investmentresult int;
	v_finerecord record;
	v_shifthours numeric(18,2);
	v_salaryid bigint:=0;
	v_adviceexists int:=0;
	v_tds numeric:=0.0;
	v_isbackward varchar(1):='N';
	v_nextmonthdays int:=0;

	v_otherearningcomponents text;
	v_totalsalarydays numeric(18,2):=0;
	v_rec_otherearningcomponents record;
	v_incentivedays numeric(18,2):=0;
	v_salarycalendardays numeric(18,2):=0;
	v_barepaiddays  numeric(18,2):=0;
	v_salarymasterjson text;
BEGIN
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
1.24	11-Apr-2023		Professional Tax				  	Shiv Kumar
1.25	04-Jul-2023		LWF grossearning threshold		  	Shiv Kumar
1.26	29-Aug-2023		Implement company filter		  	Shiv Kumar
1.27	29-May-2024		As per new Fixed Structure		  	Shiv Kumar
1.28	15-Jun-2024		For PT (Current month+Arrear) 		Shiv Kumar
						grossearning will be considered
1.28.1	07-Jun-2024		Remove Bank verification 		  	Shiv Kumar
						condition for hybrid
1.29	18-Jun-2024		Add Daily Allowance	  				Shiv Kumar
1.31	29-Aug-2024		Shiftwise OT Calculation			Shiv Kumar
1.32	30-Aug-2024		Per Kilometer Calculation			Shiv Kumar
1.33	04-Sep-2024		Tea Allowance Calculation			Shiv Kumar
1.34	27-Jan-2025		Arrear Liability					Shiv Kumar
1.35	14-Feb-2025		Cross Month Attendance				Shiv Kumar
1.36	19-Feb-2025		Populate Monthwise Investment		Shiv Kumar
1.37	04-Feb-2025		Cross Month Start date and end date changes		Parveen Kumar
1.38	05-March-2025	Early going/ Late coming/OT			Shiv Kumar
1.39	11-March-2025	Contractual 1%TDS					Shiv Kumar
1.40	07-May-2025		Independent Contractors TDS Calc.	Shiv Kumar
1.41	05-May-2025		Add Monthly Variables				Shiv Kumar
1.41	04-Jul-2025		Meal Voucher						Shiv Kumar
1.42	07-Jul-2025		Avoid sequalize error				Shiv Kumar
1.43	01-Aug-2025		Save Meal Voucher					Shiv Kumar
1.44	23-Sep-2025		Adding Monthly Components in netpay	Shiv Kumar
1.45	13-Oct-2025		Separate ot allowance and ot		Shiv Kumar
1.46	14-Oct-2025		Smart Payrolling					Shiv Kumar
1.47	02-Dec-2025		Add flexiblemonthdays				Shiv Kumar
1.48	17-Dec-2025		Hourly Setup Incentive Paid Days	Shiv Kumar
*************************************************************************/
	
if not p_paymentadvice is null then
	v_adviceexists:=1;
	v_salaryid:=coalesce(p_paymentadvice.salaryid,0);
	v_tds:=coalesce(p_paymentadvice.tds,0);
end if;
/****************change 1.31 starts*****************************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 3: Compute Available Days & Holidays
	-- Description: Determines number of days in ongoing month and adjusts totals based on flexible rules and weekly off setup.
	-------------------------------------------------------------------------------------------------------------------------
	v_monthdays:=date_part('day',DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');
select * from openappointments where emp_code=p_emp_code into v_openappointments;

/**********************change 1.35 starts***************************************************/
-- select  (make_date(p_mpryear::int, p_mprmonth::int,month_start_day)- interval '1 month')::date start_dt
-- , make_date(p_mpryear::int, p_mprmonth::int,month_end_day)::date  end_dt
-- Change - START [1.37]

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 6: Payroll Cycle & Dynamic Date Variables
	-- Description: Configures custom start and end bounds based on corporate payroll configurations.
	-------------------------------------------------------------------------------------------------------------------------
SELECT
		-- added on 23.06.2025
		CASE WHEN month_direction='F' THEN make_date(p_mpryear::int, p_mprmonth::int,month_start_day)::date
		ELSE (make_date(p_mpryear::int, p_mprmonth::int,month_start_day)- interval '1 month') END start_dt,
		CASE WHEN month_direction='F' THEN (make_date(p_mpryear::int, p_mprmonth::int,month_end_day)+ interval '1 month')::date 
		ELSE make_date(p_mpryear::int, p_mprmonth::int,month_end_day)::date  END end_dt
		,month_start_day,month_direction
		-- end
	/* 
	
	make_date(p_mpryear::int, p_mprmonth::int, month_start_day)::date start_dt,
	(make_date(p_mpryear::int, p_mprmonth::int, month_end_day) + INTERVAL '1 month')::date end_dt
	
	*/
-- Change - END [1.37]
into v_rec_payrolldates
from mst_account_custom_month_settings 
where account_id= v_openappointments.customeraccountid and status='1'  AND month_start_day <>0;
v_rec_payrolldates.start_dt:=coalesce(v_rec_payrolldates.start_dt,make_date(p_mpryear::int, p_mprmonth::int,1));
v_rec_payrolldates.end_dt:=coalesce(v_rec_payrolldates.end_dt,(make_date(p_mpryear::int, p_mprmonth::int,1)+ interval '1 month -1 day')::date);
/**********************change 1.35 ends***************************************************/

select * from empsalaryregister where appointment_id=v_openappointments.emp_id and isactive='1' into v_empsalaryregister;

	if coalesce(v_empsalaryregister.flexiblemonthdays,'N')='Y' then
		v_monthdays:=p_paymentadvice.monthdays;
	end if;
	v_actualdays:=case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='N' or v_empsalaryregister.salarydays=1 then v_monthdays  else v_empsalaryregister.salarydays end;
v_overtime:=0;
/**************change 1.40 starts***********************************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 4: Shift Hours Extraction
	-- Description: Computes default or manual shift hours for translating basic calculations.
	-------------------------------------------------------------------------------------------------------------------------
SELECT
		(CASE
		WHEN manual_input_shift_hours = 'manual_input' THEN
			EXTRACT(EPOCH FROM full_day_time::INTERVAL)/60
		ELSE
			EXTRACT(EPOCH FROM default_shift_full_hours::INTERVAL)/60
		END)/60
	FROM vw_user_spc_emp WHERE emp_code=p_emp_code
	INTO v_shifthours;
/**************change 1.40 ends***********************************/
if coalesce(v_rec_payrolldates.month_start_day,0)>1 and coalesce(v_rec_payrolldates.month_direction,'N')='B' then
	v_nextmonthdays:=v_monthdays;
	v_monthdays:=date_part('day',DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE) - INTERVAL '1 DAY');
	v_isbackward:='Y';
end if;
/**********************change 1.46 starts************************

	select coalesce(cp.totalpaiddays,0)+coalesce(cp.totalleavetaken) 
	from cmsdownloadedwages cp 
	where emp_code=p_emp_code and mprmonth=p_mprmonth and mpryear=p_mpryear and batch_no=p_batch_no and isactive='1'
	into v_totalsalarydays;

	
select salary_component_amount,0::numeric(18,2) incentive_amount,0::numeric(18,2) totalearning_amount,''::text salarymasterjson  into v_rec_otherearningcomponents where 1=2;

v_incentivedays:=case when v_empsalaryregister.salarydays<v_totalsalarydays and coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' and v_empsalaryregister.salarydays>1 then v_totalsalarydays-v_empsalaryregister.salarydays else 0 end; 
v_salarycalendardays:=case when v_empsalaryregister.coalesce(salaryindaysopted,'N')='N' or v_empsalaryregister.salarydays=1  then v_monthdays  else v_empsalaryregister.salarydays end;
v_barepaiddays:=least(v_salarycalendardays,v_totalsalarydays);

select 0::numeric(18,2) salary_component_amount,0::numeric(18,2) incentive_amount,0::numeric(18,2) totalearning_amount,null::text salarymasterjson  into v_rec_otherearningcomponents where 1=2;

v_incentivedays:=case when v_empsalaryregister.salarydays<v_totalsalarydays and coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' and v_empsalaryregister.salarydays>1 then v_totalsalarydays-v_empsalaryregister.salarydays else 0 end; 
v_salarycalendardays:=case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='N' or v_empsalaryregister.salarydays=1  or coalesce(v_empsalaryregister.flexiblemonthdays,'N')='Y' then v_monthdays  else v_empsalaryregister.salarydays end;
v_barepaiddays:=least(v_salarycalendardays,v_totalsalarydays);

		WITH data AS (SELECT salarymasterjson::jsonb as json_data
		            FROM empSalaryRegister e
		            WHERE e.id = v_empsalaryregister.id
		              AND e.isactive = '1'
		)
		SELECT array_to_json(array_agg(row_to_json(t)))::text into v_otherearningcomponents
		   from (
		SELECT
		    key AS salary_component_name,
		    value::numeric AS salary_component_amount
		FROM data,
		LATERAL jsonb_array_elements(json_data) AS arr(elem),
		LATERAL jsonb_each_text(elem)
		where upper(key) 
		not in ('BASIC SALARY','HRA','SPECIAL ALLOWANCE','CONVEYANCE',
				'MEDICAL EXPENSES','SALARY BONUS'
				,'COMMISSION','TRANSPORT ALLOWANCE','TRAVELLING ALLOWANCE',
				'LEAVE ENCASHMENT','OVERTIME ALLOWANCE',
				'NOTICE PAY','HOLD SALARY (NON TAXABLE)'
					,'CHILDREN EDUCATION ALLOWANCE','GRATUITY IN HAND')
				)t;
**********************change 1.46 ends**************************/
v_incentivedays:=coalesce(p_paymentadvice.incentivepaiddays,0);
if v_otherearningcomponents is not null then
 WITH tmp AS (
    SELECT *
		    FROM jsonb_populate_recordset(NULL::record,v_otherearningcomponents::jsonb)
			AS t(salary_component_name text, salary_component_amount numeric(18,2))
			),
	tmp1 as
	(
	select salary_component_name,
		(coalesce(salary_component_amount,0)*v_barepaiddays/v_salarycalendardays)::numeric(18,2) as salary_component_amount,
		(coalesce(salary_component_amount,0)*v_incentivedays/v_salarycalendardays)::numeric(18,2) as incentive_amount,
		(coalesce(salary_component_amount,0)*v_totalsalarydays/v_salarycalendardays)::numeric(18,2) as totalearning_amount
	from tmp
	)

	select  sum(salary_component_amount) as salary_component_amount,
			sum(incentive_amount) as incentive_amount,
			sum(totalearning_amount) as totalearning_amount,
			array_to_json(array_agg(row_to_json(t)))::text as  salarymasterjson
			into v_rec_otherearningcomponents
		   	from (
		   			select * from tmp1 
		   		)t;

end if;

/**********************change 1.46 ends************************/


	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 7: Weekdays Overtime Calculus
	-- Description: Evaluates rules against typical weekday attendance entries for base overtime.
	-------------------------------------------------------------------------------------------------------------------------
/***********Weekdays OT*************************
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
select trim(to_char(att_date,'Day')) as attday,(left(trim(no_of_hours_worked),2)::numeric
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
on ((v2.attendance_type='HO' and v1.category_type=4 and no_of_hours_worked is not null) or 
	(v2.attendance_type<>'HO' and v2.attday=v1.category_type_name and no_of_hours_worked is not null))
	
into v_overtime;
v_overtime:=coalesce(v_overtime,0);
*/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 8: Weekly / Consecutive 7-Days Overtime
	-- Description: Calculates compound overtime across weekend days or extended week shifts based on rule sets.
	-------------------------------------------------------------------------------------------------------------------------
/***********Weekly and Consecutive 7 days OT*************************
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
	and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	--and date_trunc('month',att_date) = make_date(p_mpryear,p_mprmonth,1)
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
v_weekly_consecutive_overtime:=coalesce(v_weekly_consecutive_overtime,0);
v_overtime:=v_overtime+v_weekly_consecutive_overtime;	
****************change 1.31 ends*******************************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 9: Employer Fines and External OT Adjustments
	-- Description: Loads fines (late arrival/early going) and employer override amounts for Overtime.
	-------------------------------------------------------------------------------------------------------------------------
/**************************1.36 starts**********************************************
	select sum(latehoursdeduction) latehoursdeduction,sum(earlyhoursdeduction) earlyhoursdeduction
	,sum(overtime_amount_approved_by_employer) overtime_amount_approved_by_employer
	from tbl_monthly_attendance 
	where emp_code=p_emp_code 
	and customeraccountid=v_openappointments.customeraccountid
	and att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	and isactive='1'
	and approval_status='A'	
	and no_of_hours_worked is not null
	into v_finerecord;
v_overtime=coalesce(nullif(v_finerecord.overtime_amount_approved_by_employer,0),v_overtime);
**************************1.36 ends***********************************************/
if coalesce(v_empsalaryregister.ishourlysetup,'N')='Y' then
	v_overtime:=0;
end if;

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 10: Tea Allowance Formulation
	-- Description: Determines if custom hourly or attendance rules entitle the employee to a tea monetary allowance.
	-------------------------------------------------------------------------------------------------------------------------
/*********change 1.32 Tea Allowance Calculation*****************/
v_overtime:=coalesce(p_paymentadvice.overtime,0);
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
select sum(rate) from v3 where rn=1
into v_tea_allowance;
v_tea_allowance:=coalesce(v_tea_allowance,0);
/****************change 1.17*******************************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 11: Set Temporal/Financial Bounds
	-- Description: Establishes current financial year spans along with exact salary periods in case of advance payrolls.
	-------------------------------------------------------------------------------------------------------------------------
if p_mprmonth in (1,2,3) then
	v_financial_year:=(p_mpryear-1)::text||'-'||p_mpryear::text;
else
	v_financial_year:=(p_mpryear)::text||'-'||(p_mpryear+1)::text;
end if;
v_year1:=left(v_financial_year,4)::int;
v_year2:=right(v_financial_year,4)::int;

v_startdate:=to_date(v_year1::text||'-05-01','yyyy-mm-dd');
v_enddate:=to_date(v_year2::text||'-04-30','yyyy-mm-dd');

v_advancestartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_advanceenddate:=to_date(v_year1::text||'-04-30','yyyy-mm-dd');

 select DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE ) - INTERVAL '1 DAY')::date,
	DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;
/****************change 1.17 ends here*******************************/
p_createdbyip:=createdbyip;	

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 12: Action Segment - RetrieveVerified_Salary
	-- Description: Skips extensive recalculation if simple retrieval of verified prior batches is requested.
	-------------------------------------------------------------------------------------------------------------------------
if p_action='RetrieveVerified_Salary' then	
v_querytext:='SELECT TO_CHAR(TO_TIMESTAMP ('||p_mprmonth||'::text, ''MM''), ''Mon'')'||'||''-''||'||p_mpryear::text||' AS Mon,tbl_monthlysalary.* 
,cmsdownloadedwages.dateofjoining
,openappointments.esinumber,openappointments.posting_department,
cmsdownloadedwages.ismultilocated,cmsdownloadedwages.projectname,
cmsdownloadedwages.contractno,cmsdownloadedwages.contractcategory,cmsdownloadedwages.contracttype
FROM public.tbl_monthlysalary 
left join cmsdownloadedwages on tbl_monthlysalary.batch_no=cmsdownloadedwages.batch_no
and upper(tbl_monthlysalary.emp_code::varchar)=upper(cmsdownloadedwages.empcode) 
and coalesce(cmsdownloadedwages.multi_performerwagesflag,''Y'')=''Y''
inner join openappointments on openappointments.emp_code=tbl_monthlysalary.emp_code
and openappointments.appointment_status_id<>13
WHERE 
		tbl_monthlysalary.emp_code='||p_emp_code||'
		and tbl_monthlysalary.mpryear='||p_mpryear||'
		and tbl_monthlysalary.mprmonth='||p_mprmonth||'
		and tbl_monthlysalary.tptype='''||p_tptype||''' ';		
				 
		open sal for
		execute v_querytext;				 
return sal;					 
end if;

if p_criteria='Employee' then
select emp_id,nullif(trim(pancard),'') into v_empid,v_pancard from openappointments where emp_code=p_emp_code;
end if;

select employeelwfrate,employerlwfrate,deductionmonths into v_lwfemployee,v_lwfemployer,v_lwfdeductionmonths from statewiselwfrate where statecode=7 and isactive='1'
and (select customeraccountid from openappointments where emp_code=p_emp_code)<>3254;
v_lwfemployee:=coalesce(v_lwfemployee,0);
v_lwfemployer:=coalesce(v_lwfemployer,0);
v_lwfdeductionmonths:=coalesce(v_lwfdeductionmonths,'0');

Raise notice 'v_lwfdeductionmonths=%',v_lwfdeductionmonths;
--
	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 3: Compute Available Days & Holidays
	-- Description: Determines number of days in ongoing month and adjusts totals based on flexible rules and weekly off setup.
	-------------------------------------------------------------------------------------------------------------------------
	v_monthdays:=date_part('day',DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 13: Dynamic Query Construction for Generation
	-- Description: Assembles large scale SQL command string tracking calculations across wages, deductions, fines, and ESI rules.
	-------------------------------------------------------------------------------------------------------------------------
v_querytext:='select ';

if  p_action='Save_Salary' then	
		v_querytext:=v_querytext||p_mprmonth||' mprmonth,'||p_mpryear
    ||' mpryear,batch_no batchid,'||p_createdby||' createdby,current_timestamp createdon,'''||createdbyip||''' createdbyip,arearids,tptype,';
end if;

if  p_action='Retrieve_Salary' then	
v_querytext:=v_querytext||' fnfarrivalstatus,';--change 1.15
	v_querytext:=v_querytext||p_mprmonth||' mprmonth,'||p_mpryear||' mpryear,is_paused,emp_id,'
	||'TO_CHAR(TO_TIMESTAMP ('||p_mprmonth||'::text, ''MM''), ''Mon'')'||'||''-''||'||p_mpryear||' AS Mon,dateofjoining,esinumber,posting_department,';
	v_querytext:=v_querytext||' projectname,
								contractno,
								contractcategory,
								contracttype,case when activeinbatch=''1'' then ''Active'' else ''Inactive'' end as activeinbatch,appointment_status_id,nullif(trim(remark),'''') remark,
								lockstatus,is_account_verified
								,case when isesiexceptionalcase=''Y'' and esiapplicabletilldate
							<=to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') 
							then ''Y'' else ''N'' end as isesiexceptionalcase
								,esicexceptionmessage,';	
end if;	
	
v_querytext:=v_querytext||'emp_code,bunit subunit,dateofleaving,totalleavetaken,
	emp_name,post_offered,emp_address,email,mobilenum,upper(pancard) pancard,gender,dateofbirth,
		fathername,residential_address,pfnumber,uannumber,
	    (case when coalesce(salaryindaysopted,''N'')=''N'' or salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)-(case when coalesce(salaryindaysopted,''N'')=''N'' or salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)  lossofpay,
		paiddays paiddays, (case when coalesce(salaryindaysopted,''N'')=''N'' or salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y''  then '||v_monthdays||'  else salarydays end) monthdays,
		(RateBasic) RateBasic,(RateHRA) RateHRA,(RateCONV) RateCONV,
		(RateMedical) RateMedical,(RateSpecialAllowance) RateSpecialAllowance,
		(FixedAllowancesTotalRate) FixedAllowancesTotalRate,
		
		(Basic) Basic,(HRA) HRA,
			(CONV) CONV,
		 (Medical) Medical,(SpecialAllowance) SpecialAllowance,
		 (FixedAllowancesTotal)+(FixedAllowancesTotalRate*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)) FixedAllowancesTotal,
		
		 (RateBasic_arr) RateBasic_arr,(RateHRA_arr) RateHRA_arr,
		 (RateCONV_arr) RateCONV_arr,
		 (RateMedical_arr) RateMedical_arr,(RateSpecialAllowance_arr) RateSpecialAllowance_arr,
		 (FixedAllowancesTotalRate_arr) FixedAllowancesTotalRate_arr,
		 (Incentive) Incentive,coalesce(othertaxablerefunds,0) Refund,
		(coalesce(grossearningcomponents,FixedAllowancesTotal)+(FixedAllowancesTotalRate_arr)+
		coalesce((coalesce(grossearningcomponentsrate,FixedAllowancesTotalRate)*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)),0)+
		(Incentive)+coalesce(othertaxablerefunds,0)+ (/*case when monthlyofferedpackage<25000 then*/ (coalesce(govt_bonus_amt*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0)) /*else 0 end*/)/*+coalesce(otherdeductionswithesi*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0)*/+coalesce(otherledgerarear,0) +coalesce(othervariables*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0)+coalesce(otherledgerarearwithoutesi,0)/*+coalesce(CONV,0)*/+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0))+coalesce(tea_allowance,0)) GrossEarning,
	case when epf>0 then
		case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*12.0/100 
			else
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*12.0/100 
					else greatest(1800-coalesce(epfalreadydeducted,0),0) 
				end
	       end
	else 0 end	epf,
	(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end) vpf,
	ceil(coalesce(case when employeeesirate>0 then coalesce(((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||')))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))*0.00750,0) +coalesce(othertaxablerefunds,0)*0.00750+	((coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||')+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0)))*0.00750)/*+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*.0075) */ +(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*.0075)+(coalesce(otherledgerarear,0)*0.0075) else 0 end,0) +coalesce(employee_esi_incentive_deduction,0) +coalesce(employee_esi_incentive_deduction_previous,0)) employeeesirate,
	case when '||v_adviceexists||'=1 then '||v_tds ||' when attendancemode=''Ledger'' then 0 when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger'' and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) else 0 end tds,(loan) loan,(lwf) lwf,(Insurance) Insurance,
	(Mobile) Mobile,(Advance) Advance,(Other) Other,
		
	( (	case when epf>0 then
		case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*12.0/100 
			else
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*12.0/100 
					else greatest(1800-coalesce(epfalreadydeducted,0),0) 
				end
	       end
	else 0 end)+(coalesce(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0))+ ceil((case when employeeesirate>0 then coalesce(((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||')))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))*0.00750,0) +coalesce(othertaxablerefunds,0)*0.00750+ (coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||')+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0)))*0.00750+(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*0.0075)/*+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*.0075)*/+(coalesce(otherledgerarear,0)*0.0075) else 0 end)) + (case when '||v_adviceexists||'=1 then '||v_tds ||' when attendancemode=''Ledger'' then 0 when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger''  and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) else 0 end)+(coalesce(loan,0))+(coalesce(lwf,0))+ case when isgroupinsurance=''Y'' then (coalesce(Insurance,0)) else 0 end+ (coalesce(Advance,0))+ (coalesce(Other,0))+(coalesce(otherdeductions,0))+coalesce(otherledgerdeductions,0)+coalesce(employee_esi_incentive_deduction,0)+coalesce(employee_esi_incentive_deduction_previous,0)) GrossDeduction,
	case when coalesce(is_special_category,''N'')=''Y'' then (actual_paid_ctc2) else
	(coalesce(grossearningcomponentsrate,FixedAllowancesTotalRate)*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))+
	((coalesce(grossearningcomponents,FixedAllowancesTotal,0))+(coalesce(FixedAllowancesTotalRate_arr,0))+
		(coalesce(Incentive,0))+(coalesce(othertaxablerefunds,0))+(coalesce(Mobile,0))+ /*case when monthlyofferedpackage<25000 then */(coalesce(govt_bonus_amt*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0))/* else 0 end*/+coalesce(netarear,0)/*+coalesce(otherdeductionswithesi*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0)*/+coalesce(otherledgerarear,0) +coalesce(othervariables*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0)
		+coalesce(otherledgerarearwithoutesi,0)/*+coalesce(CONV,0)*/+'||v_overtime||'
		+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0))+coalesce(tea_allowance,0))
		-( (case when epf>0 then
		case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*12.0/100 
			else
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*12.0/100 
					else greatest(1800-coalesce(epfalreadydeducted,0),0) 
				end
	       end
	else 0 end)+(coalesce(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0))+ceil( (case when employeeesirate>0 then coalesce((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||'))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))*0.00750,0) +coalesce(othertaxablerefunds,0)*0.00750+(coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||')+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0)))*0.00750+(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*0.0075)/*+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*.0075) */+(coalesce(otherledgerarear,0)*0.0075) else 0 end) )+ (case when '||v_adviceexists||'=1 then '||v_tds ||' when attendancemode=''Ledger'' then 0 when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger''  and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) else 0 end)+(coalesce(loan,0))+(coalesce(lwf,0))+case when isgroupinsurance=''Y'' then  (coalesce(Insurance,0)) else 0 end+ (coalesce(Advance,0))+ (coalesce(Other,0))+(coalesce(otherdeductions,0))+coalesce(otherledgerdeductions,0)+coalesce(employee_esi_incentive_deduction,0)+coalesce(employee_esi_incentive_deduction_previous,0)) 
			end
			NetPay,
case when epf>0 then
--------------------
	case when coalesce(pfcapapplied,''Y'')=''N''  or (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<=15000
		then pfapplicablecomponents*0.0367
	else
			greatest(550.5-coalesce(coalesce(pfapplicablecomponentsalreadypaid,0)*0.0367,0),0) 
	end
+
--------------------------------------
case when coalesce(epf_pension_opted,''Y'')=''Y'' and coalesce(pfcapapplied,''Y'')=''Y'' then
		0
	when coalesce(epf_pension_opted,''Y'')=''Y'' and coalesce(pfcapapplied,''Y'')=''N'' then
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<=15000  
					then 0
				else 
					case when coalesce(pfapplicablecomponentsalreadypaid,0)<=15000 then
						(pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))*0.0833-1249.5
					else
						pfapplicablecomponents*0.0833
					end	
				end
	when coalesce(epf_pension_opted,''Y'')=''N'' and coalesce(pfcapapplied,''Y'')=''Y'' then
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<=15000  
					then pfapplicablecomponents*0.0833
				else 
					case when coalesce(pfapplicablecomponentsalreadypaid,0)<=15000 then
						greatest(1249.5-(coalesce(pfapplicablecomponentsalreadypaid,0))*0.0833,0)
					else
						0
					end	
				end
	when coalesce(epf_pension_opted,''Y'')=''N'' and coalesce(pfcapapplied,''Y'')=''N'' then
			pfapplicablecomponents*0.0833
	end	
-------------------------------------------------------------------------------
else 0 end	Ac_1,
-------------------------------------------------------------------------------	
	case when epf>0 and coalesce(epf_pension_opted,''Y'')=''Y'' then
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*0.0833
					else greatest(1249.5-coalesce(ac_10alreadydeducted,0),0) 
				end
	else 0 end	Ac_10,	
		case when epf>0 and coalesce(nullif(trim(edli_adminchargesincludeinctc),''''),''Y'')=''Y'' then
		case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*0.005
			else
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*0.005
					else greatest(75-coalesce(ac_2alreadydeducted,0),0) 
				end
	       end
	else 0 end	Ac_2,
		case when epf>0  and coalesce(nullif(trim(edli_adminchargesincludeinctc),''''),''Y'')=''Y'' then
		case when coalesce(pfcapapplied,''Y'')=''N'' then pfapplicablecomponents*0.005
			else
				case when (pfapplicablecomponents+coalesce(pfapplicablecomponentsalreadypaid,0))<15000  then pfapplicablecomponents*0.005
					else greatest(75-coalesce(ac_21alreadydeducted,0),0) 
				end
	       end
	else 0 end	Ac21,	
--(employeresirate*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end) employeresirate,
case when employeresirate>0 then
coalesce((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||'))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end))*0.03250,0) +
coalesce(othertaxablerefunds,0)*0.03250+
((coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)+'|| coalesce(p_paymentadvice.otherearningcomponents,0)||')+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0)))*0.03250)
+(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*0.0325)
/*+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end*0.0325)*/
+(coalesce(otherledgerarear,0)*0.0325)
+coalesce(employer_esi_incentive_deduction,0)
+coalesce(employer_esi_incentive_deduction_previous,0)
else 0 end employeresirate,
0::numeric(18,2) LWFContr,(ews) ews,(gratuity) gratuity
,recordtype
,govt_bonus_opted,(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end) govt_bonus_amt';

if p_action='Save_Salary' then	
v_querytext:=v_querytext||
	  ',cast(null as integer) modifiedby,cast(null as timestamp) modifiedon,null modifiedbyip';
	  end if;	  
v_querytext:=v_querytext||',is_special_category,ct2';
		 raise notice 'Step 1 v_lwfdeductionmonths: % ', v_lwfdeductionmonths;	
	  
v_querytext:=v_querytext||',batch_no,(actual_paid_ctc2) actual_paid_ctc2,(ctc) ctc';
v_querytext:=v_querytext||', (ctc_paid_days) ctc_paid_days,(ctc_actual_paid) ctc_actual_paid, (mobile_deduction) mobile_deduction 
,case when '||v_salaryid||'<>0 then '||v_salaryid||' else salaryid end as salaryid 
,coalesce(employeenpsrate,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end employeenpsrate
,coalesce(employernpsrate,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end employernpsrate
,case when isgroupinsurance=''Y'' then coalesce(insuranceamount,0) else 0 end insuranceamount
,case when isgroupinsurance=''Y'' then coalesce(familyinsuranceamount,0) else 0 end familyinsuranceamount
,bankaccountno, ifsccode, bankname, bankbranch,coalesce(netarear,0) netarear,
arearaddedmonths
,coalesce(employee_esi_incentive_deduction_previous,0) +coalesce(employee_esi_incentive_deduction,0) employee_esi_incentive_deduction
,coalesce(employer_esi_incentive_deduction_previous,0) +coalesce(employer_esi_incentive_deduction,0) employer_esi_incentive_deduction
,coalesce(total_esi_incentive_deduction_previous,0)+coalesce(total_esi_incentive_deduction,0) total_esi_incentive_deduction
,salaryindaysopted,salarydays
,otherledgerarear
,otherledgerdeductions
,attendancemode
,0 incrementarear
,0 incrementarear_basic
,0 incrementarear_hra
,0 incrementarear_allowance
,0 incrementarear_gross 
,0 incrementarear_employeeesi
,0 incrementarear_employeresi
,lwf_employee,lwf_employer
,bonus,otherledgerarearwithoutesi
,coalesce(otherdeductions,0) otherdeductions
,coalesce(othervariables*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end,0) othervariables
,(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)  otherdeductionswithesi
,lwfstatecode
,coalesce(tdsadjustment,0) tdsadjustment
,case when (tds-coalesce(alreadytds,0))>0 or (attendancemode=''Ledger'' and coalesce(tds,0)>=0) then (tds-coalesce(alreadytds,0)) else 0 end atds
,hrgeneratedon
,disbursedledgerids
,security_amt
,case when mprdocumentpath is null and tptype=''TP'' and '||coalesce(p_multipayoutrequestid,0)||'=0 then ''S'' else ''L'' end issalaryorliability
,0 as professionaltax
/*********************Change 1.27 starts here************************************************************/	
,ratesalarybonus
,ratecommission
,coalesce(ratetransport_allowance,0)+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0)) ratetransport_allowance
,coalesce(ratetravelling_allowance,0)+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0)) ratetravelling_allowance
,rateleave_encashment
,coalesce(rateovertime_allowance,0)/*+'||v_overtime||'*/ rateovertime_allowance
,ratenotice_pay
,ratehold_salary_non_taxable
,ratechildren_education_allowance
,rategratuityinhand
,salarybonus
,commission
,coalesce(transport_allowance,0)+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0)) transport_allowance
,coalesce(travelling_allowance,0)+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0)) travelling_allowance
,leave_encashment
,coalesce(overtime_allowance,0)/*+'||v_overtime||'*/+coalesce((FixedAllowancesTotalRate*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)),0) overtime_allowance
,notice_pay
,hold_salary_non_taxable
,children_education_allowance
,gratuityinhand
/*********************Change 1.27 ends here************************************************************/
,coalesce(tea_allowance,0) tea_allowance
,pfapplicablecomponents
,esiapplicablecomponents
,isgroupinsurance
,employerinsuranceamount
,mealvoucher
,case when employeresirate>0 then coalesce((coalesce(nullif(esiapplicablecomponents,0),(coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0)))*incentivedays/(case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)),0) + coalesce(othertaxablerefunds,0)+ ((coalesce(nullif(esiapplicablecomponents,0),coalesce(basic,0)+coalesce(hra,0)+coalesce(SpecialAllowance,0)+coalesce(Medical,0)+coalesce(commission,0)+coalesce(transport_allowance,0)+coalesce(overtime_allowance,0)+coalesce(children_education_allowance,0))+'||v_overtime||'+(coalesce(km_distance,0)*coalesce(perkilometerrate,0))+(coalesce(ta_days,0)*coalesce(travelallowance_rate,0))+(coalesce(days_per_month,0)*coalesce(dailyallowance_rate,0)))) +(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end) +(coalesce(otherledgerarear,0)) else 0 end as gross_esic_income
,'||v_overtime||' overtime
from
	(
		select openappointments.emp_code,bunit bunit,coalesce(is_account_verified,''0'')::bit is_account_verified,';
if p_action='Retrieve_Salary' then	
		v_querytext:=v_querytext||'to_char(dateofleaving,''dd/mm/yyyy'') dateofleaving,emp_id,is_paused,';
elsif  p_action='Save_Salary' then	
		v_querytext:=v_querytext||'dateofleaving,';
end if;		

v_querytext:=v_querytext||'emp_name, jobrole post_offered,emp_address,email,mobile mobilenum,pancard,gender,';

if p_action='Retrieve_Salary' then	
		v_querytext:=v_querytext||'to_char(dateofbirth,''dd-Mon-yy'') dateofbirth,coalesce(cmsdownloadedwages.isactive,''0'') activeinbatch';
elsif  p_action='Save_Salary' then	
		v_querytext:=v_querytext||'dateofbirth';
end if;

		v_querytext:=v_querytext||',fathername,residential_address,pfnumber,uannumber,lossofpay lossofpay,
		case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end monthdays,
		(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then  (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end) paiddays,
		totalleavetaken,
		basic RateBasic,hra RateHRA,coalesce(conveyance_allowance,0)/*+coalesce(conveyance,0)*/	RateCONV,
		medical_allowance RateMedical,allowances RateSpecialAllowance,
		gross FixedAllowancesTotalRate,
		
		basic*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end Basic,
		hra*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end HRA,
		(coalesce(conveyance_allowance,0)/*+coalesce(conveyance,0)*/)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end	CONV,
		medical_allowance*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end Medical,
		allowances*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end SpecialAllowance,
		gross*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end FixedAllowancesTotal,
		
		 cast(0.0000 as double precision) RateBasic_arr,cast(0.0000 as double precision) RateHRA_arr,cast(0.0000 as double precision)	RateCONV_arr,
		cast(0.0000 as double precision) RateMedical_arr,cast(0.0000 as double precision) RateSpecialAllowance_arr,
		cast(0.0000 as double precision) FixedAllowancesTotalRate_arr,
		cast('|| coalesce(p_paymentadvice.incentive,0.0000)||' as double precision) Incentive,cast(0.0000 as double precision)	Refund,
	    employeeepfrate  epf,(coalesce(vpfemployee,0)+coalesce(variablevpf,0)) vpf,
		employeeesirate,employeresirate,
			(coalesce(taxes,0.0)+coalesce(tdsadjustment,0)) tds,
			cast(0.0000 as double precision) loan,
	        0::numeric(18,2) lwf,
			case when openappointments.customeraccountid in(6927,7416) then (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))-coalesce(alreadyinsurance,0) else
			(coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end /*-coalesce(alreadyinsurance,0)*/ end Insurance,
			cast(0.0000 as double precision) Mobile,cast(0.0000 as double precision) Advance,(coalesce(ews,0)+coalesce(gratuity,0)+coalesce(bonus,0)-coalesce(alreadyother,0)) Other
		,ews-coalesce(ewsalready,0) ews,gratuity-coalesce(gratuityalready,0) gratuity,	salaryinhand,
		case when recordsource =''MIS'' then ''Existing'' else ''NewRecord'' end as recordtype
		,openappointments.govt_bonus_opted,govt_bonus_amt
		,(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end) totalsalarydays
		,to_char(cmsdownloadedwages.dateofjoining,''dd-Mon-yy'') dateofjoining
		,openappointments.esinumber,posting_department,batch_no
		,tblotherdeductions.otherdeductions*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end otherdeductions
									,projectname,
									contractno,
									contractcategory,
									contracttype
									,totalpaiddays
									,empsalaryregister.is_special_category
									,ctc
									,empsalaryregister.ct2
									,(empsalaryregister.ct2*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end)  actual_paid_ctc2 
									,cast(0.0000 as double precision) ctc_paid_days,
									cast(0.0000 as double precision) ctc_actual_paid,
									cast(0.0000 as double precision) mobile_deduction
									,empsalaryregister.id salaryid
									,nullif(trim(empsalaryregister.pfcapapplied),'''') pfcapapplied,
									pfopted,esiopted,
									monthlyofferedpackage,
									employeenpsrate,employernpsrate,
									case when openappointments.customeraccountid in(6927,7416) then coalesce(insuranceamount,0)-coalesce(alreadyinsuranceamount,0) else
									insuranceamount*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end /*-coalesce(alreadyinsuranceamount,0)*/ end insuranceamount,
									case when openappointments.customeraccountid in(6927,7416) then coalesce(familyinsuranceamount,0)-coalesce(alreadyfamilyfamilyinsurance,0) else
									familyinsuranceamount*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end /*-coalesce(alreadyfamilyfamilyinsurance,0)*/ end familyinsuranceamount
									,openappointments.bankaccountno
									, openappointments.ifsccode, openappointments.bankname, openappointments.bankbranch
									,tmparear.netarear
									,tmparear.total_esi_incentive
									,tmparear.arearaddedmonths
									,tblotherdeductionswithesi.otherdeductionswithesi
									,empsalaryregister.isgroupinsurance
									,employee_esi_incentive_deduction
									,employer_esi_incentive_deduction
									,total_esi_incentive_deduction
									,openappointments.appointment_status_id
									,empsalaryregister.salaryindaysopted
									,empsalaryregister.salarydays
									,coalesce(tblotherledger.otherledgerarear,0) otherledgerarear
									,coalesce(tblotherledger.otherledgerdeductions,0)+coalesce(security_amt,0)-coalesce(alreadysecurity_amt,0) otherledgerdeductions
									,coalesce(othervariables,0) othervariables
									,employee_esi_incentive_deduction_previous
									,employer_esi_incentive_deduction_previous
									,total_esi_incentive_deduction_previous
									,attendancemode
									,epfalreadydeducted
									,ac_1alreadydeducted
									,ac_10alreadydeducted
									,ac_2alreadydeducted
									,ac_21alreadydeducted
									,basicalreadypaid
									,cmsdownloadedwages.remark
									,tblcurrenttax.currentmonthtaxdeducted alreadytds
									,bonus-coalesce(bonusalready) bonus
									,otherledgerarearwithoutesi otherledgerarearwithoutesi
									,0::numeric(18,2)  lwf_employee,
									 0::numeric(18,2) lwf_employer
									,empsalaryregister.lwfstatecode
	/************Change 1.6 starts*****************************************/
	,''Unlocked'' as lockstatus
		/************Change 1.6 ends*****************************************/
		,coalesce(tdsadjustment,0) tdsadjustment
		,variablevpf
		,empsalaryregister.isesiexceptionalcase
		,empsalaryregister.esicexceptionmessage
		,empsalaryregister.esiapplicabletilldate
		,arearids
		,hrgeneratedon
		,case when coalesce(openappointments.left_flag,''N'')=''Y'' and openappointments.dateofrelieveing<=current_date and coalesce(ee_finalduesclearancedate,openappointments.dateofrelieveing,to_date(''0101900'',''ddmmyyyy''))>current_date then ''FNFLock'' else ''NoFNFLock'' end as fnfarrivalstatus --change 1.15
		,disbursedledgerids
		,coalesce(othertaxablerefunds,0) othertaxablerefunds
		,coalesce(security_amt,0)-coalesce(alreadysecurity_amt,0) security_amt
		,openappointments.epf_pension_opted
		,case when openappointments.recordsource=''HUBTPCRM'' then ''TP'' else ''NonTP'' end as tptype 
		
		
		,case when openappointments.recordsource=''HUBTPCRM'' and /*salarydays<(totalpaiddays+totalleavetaken) and*/ ((coalesce(empsalaryregister.salaryindaysopted,''N'')=''Y'' and empsalaryregister.salarydays>1) or coalesce(empsalaryregister.ishourlysetup,''N'')=''Y'') then '||coalesce(p_paymentadvice.incentivepaiddays,0) ||' else 0 end as incentivedays		
		,mprdocumentpath
	/*********************Change 1.27 starts here************************************************************/		
		,coalesce(salarybonus,0) ratesalarybonus
		,coalesce(commission,0) ratecommission
		,coalesce(transport_allowance,0)/*+coalesce(empsalaryregister.dailyallowance_rate,0)*/ ratetransport_allowance
		,coalesce(travelling_allowance,0) ratetravelling_allowance
		,coalesce(leave_encashment,0) rateleave_encashment
		,coalesce(overtime_allowance,0) rateovertime_allowance
		,coalesce(notice_pay,0) ratenotice_pay
		,coalesce(hold_salary_non_taxable,0) ratehold_salary_non_taxable
		,coalesce(children_education_allowance,0) ratechildren_education_allowance
		,coalesce(gratuityinhand,0) rategratuityinhand
		,coalesce(salarybonus,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1  then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end salarybonus
		,coalesce(commission,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end commission
		,coalesce(transport_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end /*+(coalesce(empsalaryregister.dailyallowance_rate,0)*coalesce(ta.days_per_month,0)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*/ transport_allowance
		,coalesce(travelling_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end travelling_allowance
		,coalesce(leave_encashment,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end leave_encashment
		,coalesce(overtime_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end overtime_allowance
		,coalesce(notice_pay,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end notice_pay
		,coalesce(hold_salary_non_taxable,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end hold_salary_non_taxable
		,coalesce(children_education_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end children_education_allowance
		,coalesce(gratuityinhand,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end gratuityinhand
		,km_distance,perkilometerrate,ta_days,travelallowance_rate,days_per_month,dailyallowance_rate
	/*********************Change 1.27 ends here************************************************************/
	  ,case when empsalaryregister.tea_allowance_enabled=''Y'' then '||v_tea_allowance ||' else 0 end as tea_allowance
	  ,edli_adminchargesincludeinctc
	,coalesce(pfapplicablecomponentsalreadypaid,0) pfapplicablecomponentsalreadypaid
	,coalesce(coalesce(nullif(pfapplicablecomponents,0),basic),0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end pfapplicablecomponents
	,esiapplicablecomponents*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N''  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end esiapplicablecomponents
	,case when openappointments.customeraccountid in(6927,7416) then coalesce(employerinsuranceamount,0)-coalesce(alreadyemployerinsuranceamount,0) else
	coalesce(employerinsuranceamount,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end end employerinsuranceamount
	,greatest(coalesce(mealvoucher,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end-coalesce(alreadymealvoucher,0),0) mealvoucher
	,grossearningcomponents*(case when coalesce(salaryindaysopted,''N'')=''N'' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''=''Y'' then '||v_monthdays||'  else salarydays end grossearningcomponents
	,grossearningcomponents  grossearningcomponentsrate
	from public.empsalaryregister
				  inner join public.openappointments
				  on empsalaryregister.appointment_id=openappointments.emp_id
				  and openappointments.recordsource= case when '''||p_tptype||'''=''TP'' then ''HUBTPCRM'' else nullif(openappointments.recordsource,''HUBTPCRM'') end
				  /*and empsalaryregister.isactive=''1''*/
				  and openappointments.emp_id not in (select e7.appointment_id from empsalaryregister e7 inner join openappointments op2 on op2.emp_id=e7.appointment_id  where e7.effectivefrom between to_date(''02'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') and to_date('''||coalesce(nullif(v_nextmonthdays,0),v_monthdays)::text||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') and op2.dateofjoining<=to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') and e7.isactive=''1'')
				  ';
			
  
	if p_criteria='Employee' then
		v_querytext:=v_querytext||' and openappointments.emp_code='||p_emp_code;
		v_querytext:=v_querytext||' and empsalaryregister.appointment_id='||v_empid;
	end if;			  
				 if (p_action='Retrieve_Salary' or p_action='Save_Salary') and coalesce(nullif(p_process_status,''),'NotProcessed')='NotProcessed' then
				 	v_querytext:=v_querytext||' and 1=1 ';
				 else
				 	 v_querytext:=v_querytext||' and 1=2 ';
				 end if;
		if v_salaryid<>0 then
			v_querytext:=v_querytext||' and ('||v_salaryid||'=empsalaryregister.id) ';
		end if;
				 
				    /*******Change 1.5 starts***************/
		if v_salaryid=0 then
       v_querytext:=v_querytext||' and 
	   ((empsalaryregister.appointment_id,empsalaryregister.id) 
					in (select e1.appointment_id,max(e1.id)
						from empsalaryregister e1
						where  (e1.isactive=''1'' ';
		if p_criteria='Employee' then
			v_querytext:=v_querytext||' and e1.appointment_id='||v_empid;
		end if;	
	
					v_querytext:=v_querytext||' and (coalesce(e1.effectivefrom,to_date(''2021-03-01'',''yyyy-mm-dd'')))
							<=to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') 
						------------------Code added for new Joinee on 04-Jul-2021-------------------------------------------------
						)
						or(e1.appointment_id,e1.id) 
						in (
						select opsal.emp_id,max(tblsal.salaryid)
							from openappointments opsal inner join tbl_monthlysalary tblsal
							on opsal.emp_code= tblsal.emp_code and tblsal.is_rejected=''0''
							and to_date(tblsal.mpryear::text||''-''||lpad(tblsal.mprmonth::text,2,''0'')||''-01'',''yyyy-mm-dd'')<=
							to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'')';
							if p_criteria='Employee' then
								v_querytext:=v_querytext||' and opsal.emp_id='||v_empid;
							end if;	
						v_querytext:=v_querytext||' 
							group by opsal.emp_id
						)
						';
						------------------------------------------------------------------------------------------

						if p_tptype = 'NonTP' then
						v_querytext:=v_querytext||' or(e1.isactive=''1'' and
							e1.appointment_id 
							in (select op1.emp_id 
								from openappointments op1
								where op1.appointment_status_id<>13
								and coalesce(op1.converted,''N'')=''Y'' ';
									if p_criteria='Employee' then
										v_querytext:=v_querytext||' and op1.emp_id='||v_empid;
									end if;	
						v_querytext:=v_querytext||' and op1.dateofjoining>to_date(''01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'') 
								)
								)
							';
						else
						v_querytext:=v_querytext||' or((effectivefrom<(make_date('||p_mpryear||','||p_mprmonth||',1)+interval ''1 month'') ::date) and
							e1.appointment_id 
							in (select op1.emp_id 
								from openappointments op1
								where op1.appointment_status_id<>13
								and coalesce(op1.converted,''N'')=''Y'' ';
									if p_criteria='Employee' then
										v_querytext:=v_querytext||' and op1.emp_id='||v_empid;
									end if;	
						v_querytext:=v_querytext||' and op1.dateofjoining>=make_date('||p_mpryear||','||p_mprmonth||',1) 
								)
								)
							';
						end if;
						------------------Code added for new Joinee on 04-Jul-2021 ends here-------------------------------------------------
						v_querytext:=v_querytext||'  group by e1.appointment_id
					   union
						select e2.appointment_id,max(e2.id)
						from empsalaryregister e2 where 1=1 ';
				if p_criteria='Employee' then
					v_querytext:=v_querytext||' and e2.appointment_id='||v_empid;
				end if;	
				if p_tptype='TP' then
					v_querytext:=v_querytext||' and e2.effectivefrom<'''||(v_advancesalstartdate+interval '1 month')::date ||'''::date';
				end if;
				v_querytext:=v_querytext||'
						group by e2.appointment_id ';
					if p_tptype='TP' then	
						v_querytext:=v_querytext||' having count(*)=1 ';
					end if;	
				v_querytext:=v_querytext||' )) ';
				end if;
				 /*******Change 1.5 ends**************/
		   v_querytext:=v_querytext||'   and openappointments.appointment_status_id<>13
				  and coalesce(converted,''N'')=''Y''
				  --and coalesce(left_flag,''N'')<>''Y''
				  --and openappointments.isactive=''1''   
					';
	/*if p_action='Save_Salary' then			
	v_querytext:=v_querytext||'and 
	(
	openappointments.emp_id not in(select EmpId from ManageTempPausedSalary
					WHERE  ManageTempPausedSalary.ProcessYear ='||p_mpryear||'
					and ManageTempPausedSalary.ProcessMonth ='||p_mprmonth||'
					 and ManageTempPausedSalary.IsActive=''1''
					 and coalesce(ManageTempPausedSalary.PausedStatus,''Enable'')=''Enable'')
	or 	'''||p_issalaryorliability||'''=''L''
	)	';
	end if;	*/
if p_action='Retrieve_Salary' then	
v_querytext:=v_querytext||' left join (select empid,pausedstatus  is_paused  
										from ManageTempPausedSalary

				WHERE  ManageTempPausedSalary.ProcessYear ='||p_mpryear||'
				and ManageTempPausedSalary.ProcessMonth ='||p_mprmonth||'
				 ) MTempPausedSalary
				 on openappointments.emp_id=MTempPausedSalary.empid ';
end if;
			/******************************************/
			v_querytext:=v_querytext||' left join (select account_id,emp_code transp_empcode,
													sum(case when data_type=''dsr-days'' then days_per_month else 0 end) as days_per_month,
													sum(case when data_type=''km-distance'' then days_per_month else 0 end) as km_distance,
																															sum(case when data_type=''ta-days'' then days_per_month else 0 end) as ta_days
													from tbl_attendnace_dsr_da_data 
													where tbl_attendnace_dsr_da_data.emp_code='||p_emp_code||'
							 and coalesce(tbl_attendnace_dsr_da_data.status,''0'')=''1''
							 and tbl_attendnace_dsr_da_data.month='||p_mprmonth||' 
							 and tbl_attendnace_dsr_da_data.year='||p_mpryear||'
							 and coalesce(tbl_attendnace_dsr_da_data.is_processed,''N'')=''N''
													group by account_id,emp_code		 
													)ta
							 on openappointments.emp_code=ta.transp_empcode 
							 and openappointments.customeraccountid=ta.account_id ';

			/******************************************/				 
						v_querytext:=v_querytext||'	left join(select tbl_monthlysalary.emp_code,sum(netpay) netarear,sum(total_esi_incentive) total_esi_incentive
										,STRING_AGG (tbl_monthlysalary.mprmonth || ''-'' || tbl_monthlysalary.mpryear,'','') arearaddedmonths
										,sum(employee_esi_incentive) employee_esi_incentive_deduction
										,sum(employer_esi_incentive) employer_esi_incentive_deduction
										,sum(total_esi_incentive) total_esi_incentive_deduction
										,STRING_AGG (tbl_monthlysalary.id::text,'','') arearids
										from public.tbl_monthlysalary
										where isarear=''Y'' and arearprocessmonth='||p_mprmonth||' and coalesce(is_rejected,''0'')<>''1''
										and recordscreen not in (''Previous Wages'',''Current Wages'',''Increment Voucher'')
										and arearprocessyear='||p_mpryear||'
										and (tbl_monthlysalary.emp_code,tbl_monthlysalary.id)
								not in (select  arrs.emp_code,trim(regexp_split_to_table(arrs.arearids,'',''))::bigint 
								 from tbl_monthlysalary arrs where coalesce(arrs.is_rejected,''0'')<>''1''
								 		/* and mprmonth='||p_mprmonth||'
										 and mpryear='||p_mpryear||'*/
										 )	 
										 and tbl_monthlysalary.createdon::date>=to_date(''2021-12-01'',''yyyy-mm-dd'')
								      group by tbl_monthlysalary.emp_code) tmparear 
										on tmparear.emp_code=openappointments.emp_code';						
			v_querytext:=v_querytext||'	left join(select tbl_monthlysalary.emp_code
										,sum(employee_esi_incentive) employee_esi_incentive_deduction_previous
										,sum(employer_esi_incentive) employer_esi_incentive_deduction_previous
										,sum(total_esi_incentive) total_esi_incentive_deduction_previous
										from public.tbl_monthlysalary
										where isarear=''Y'' 
										and coalesce(esi_incentive_processed,''0'')<>''1''
										--and arearprocessmonth='||p_mprmonth||'
										and coalesce(is_rejected,''0'')<>''1''
										and recordscreen=''Previous Wages''
										--and arearprocessyear='||p_mpryear||' 
										group by tbl_monthlysalary.emp_code) tmpesiarear 
										on tmpesiarear.emp_code=openappointments.emp_code';
										
										
v_querytext:=v_querytext||'	inner join 
	(select mprmonth,mpryear,empcode, 
			max(dateofjoining) dateofjoining,
       		max(bunit) bunit, 
			max(dateofleaving) dateofleaving
	   		,sum(totalleavetaken) totalleavetaken
	   		,0 totalsalarydays
	  		 ,sum(totalpaiddays) totalpaiddays
	  		 ,sum(lossofpay) lossofpay
	  		 ,max(isactive::int)::bit isactive
	  		 ,batch_no
	  		 ,max(projectname) projectname
	   		,max(contractno) contractno 
	   		,max(contractcategory) contractcategory
	  		,max(contracttype) contracttype 
	  		,max(attendancemode) attendancemode
		    ,max(remark)  remark
			,to_char(max(to_timestamp(hrgeneratedon,''dd Mon yyyy hh24:mi'')),''dd Mon yyyy hh24:mi'')  hrgeneratedon
			,max(jobrole) jobrole
			,max(mprdocumentpath) mprdocumentpath
	  from public.cmsdownloadedwages
	  where cmsdownloadedwages.isactive=''1'' and (cmsdownloadedwages.salary_current_advance<>''Advance'' or (cmsdownloadedwages.mpryear='||p_mpryear||' and cmsdownloadedwages.mprmonth='||p_mprmonth||'))';
	  	if p_criteria='Order' then
		v_querytext:=v_querytext||' and cmsdownloadedwages.contractno='''||p_ordernumber||''' ';
		end if;
		if p_criteria='Employee' then
			v_querytext:=v_querytext||'  and cmsdownloadedwages.empcode='''||p_emp_code||''' ';
		end if;	
		
		v_querytext:=v_querytext||' and cmsdownloadedwages.mpryear='||p_mpryear||'
		and cmsdownloadedwages.mprmonth='||p_mprmonth||'
		and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''''),''Y'')<>''N''
		and (cmsdownloadedwages.mprmonth, cmsdownloadedwages.mpryear, cmsdownloadedwages.empcode::bigint,cmsdownloadedwages.batch_no) not in 
			(select m5.mprmonth, m5.mpryear,  m5.emp_code,trim(regexp_split_to_table(m5.batchid,'','')) from tbl_monthlysalary m5 where coalesce(m5.is_rejected,''0'')<>''1''
			and m5.recordscreen<>''Increment Arear'' and m5.mprmonth='||p_mprmonth||' and m5.mpryear='||p_mpryear||')
		and (cmsdownloadedwages.mprmonth, cmsdownloadedwages.mpryear, cmsdownloadedwages.empcode::bigint,cmsdownloadedwages.batch_no||cmsdownloadedwages.transactionid::text) not in 
			(select m6.mprmonth, m6.mpryear,  m6.emp_code,trim(regexp_split_to_table(m6.batchid,'','')) from tbl_monthlysalary m6 where coalesce(m6.is_rejected,''0'')<>''1''
			and m6.recordscreen<>''Increment Arear'' and m6.mprmonth='||p_mprmonth||' and m6.mpryear='||p_mpryear||')	
	   group by mprmonth,mpryear,empcode,batch_no
	   ) cmsdownloadedwages 
	on cmsdownloadedwages.empcode::bigint=openappointments.emp_code ';	
	if nullif(trim(p_batch_no),'') is not null then
		v_querytext=v_querytext||' and cmsdownloadedwages.batch_no='''||p_batch_no||'''';
	end if;
---------------------New Part Added---------------------------------
v_querytext:=v_querytext||'	left join 
(
select salaryid,candidate_id,sum(otherdeductions) otherdeductions

from
(select salaryid,candidate_id,sum(deduction_amount) otherdeductions
				   from public.trn_candidate_otherduction
				   where (public.trn_candidate_otherduction.active=''Y''
				  and coalesce(trn_candidate_otherduction.includedinctc,''N'')=''Y'' 
				  and coalesce(isvariable,''N'')=''N''  --change 1.8
				  --and trn_candidate_otherduction.deduction_id not in (5,6,7,10)
				  and trn_candidate_otherduction.deduction_id not in (7,10)
				  and trn_candidate_otherduction.deduction_id<>323 --Meal Voucher ID, Must Change for Production
				  and trn_candidate_otherduction.deduction_frequency in (''Quarterly'',''Half Yearly'',''Annually''))
				  group by salaryid,public.trn_candidate_otherduction.candidate_id	  

union all				  
				select salaryid,candidate_id,sum(deduction_amount)*1 otherdeductions
				   from public.trn_candidate_otherduction
				   inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
				   where public.trn_candidate_otherduction.active=''Y''
				   and deduction_amount>0
				  and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				  and trn_candidate_otherduction.deduction_id not in (5,6,7,10)
				  and coalesce(trn_candidate_otherduction.is_taxable,''N'')=''N''
				  and motd.id<>323 --Meal Voucher ID, Must Change for Production
				  --and '||v_openappointments.customeraccountid||' =981 /* change 1.44 */
				  group by salaryid,public.trn_candidate_otherduction.candidate_id 

				  ) tblotherdeductions
	group by salaryid,candidate_id 
	)tblotherdeductions
		          on openappointments.emp_id=tblotherdeductions.candidate_id
				  and empsalaryregister.id=tblotherdeductions.salaryid
---------------Added for PI and OT with ESI --------------------------					  
left join (select salaryid,candidate_id,sum(deduction_amount) otherdeductionswithesi
					,string_agg(deduction_name||'':''||deduction_amount,'','') customtaxablecomponents
				   from public.trn_candidate_otherduction
				   inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
				   where public.trn_candidate_otherduction.active=''Y'' 
				   and motd.deduction_name not in (''Medical Expenses'')
				   and deduction_amount>0
				  and (trn_candidate_otherduction.deduction_id in (5,6) or coalesce(trn_candidate_otherduction.is_taxable,''N'')=''Y'')
				  and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				  and motd.id<>323 --Meal Voucher ID, Must Change for Production
				  group by salaryid,public.trn_candidate_otherduction.candidate_id) tblotherdeductionswithesi
		          on openappointments.emp_id=tblotherdeductionswithesi.candidate_id
				  and empsalaryregister.id=tblotherdeductionswithesi.salaryid
------------------------------change 1.11 added----------------------------------------
left join (select salaryid,candidate_id,sum(deduction_amount) variablevpf
				   from public.trn_candidate_otherduction
				   where public.trn_candidate_otherduction.active=''Y'' 
				  and trn_candidate_otherduction.deduction_id =10
				  group by salaryid,public.trn_candidate_otherduction.candidate_id) tblvariablevpf
		          on openappointments.emp_id=tblvariablevpf.candidate_id
				  and empsalaryregister.id=tblvariablevpf.salaryid	
----------------change 1.1 ------------------------------------------------------
left join (
select emp_code,sum(otherledgerarear) otherledgerarear,
sum(otherledgerdeductions) otherledgerdeductions,
sum(otherledgerarearwithoutesi) otherledgerarearwithoutesi
,STRING_AGG (disbursedledgerids::text,'','') disbursedledgerids
,sum(othertaxablerefunds) othertaxablerefunds
,sum(security_amt) security_amt
,sum(conveyance) conveyance
,sum(tdsadjustment) tdsadjustment from (
select emp_code,sum(case when amount>0 and (headid in (5,6) or coalesce(tbl_employeeledger.is_taxable,''N'')=''Y'' /* mst_otherduction.applicationtype=''TP''*/ ) then amount else 0 end) otherledgerarear
						,sum(case when amount<0 and coalesce(tbl_employeeledger.is_taxable,''N'')=''N'' and headid not in (12) then amount else 0 end)*-1 otherledgerdeductions
						,sum(case when amount>0 and (headid not in (5,6,12) and coalesce(tbl_employeeledger.is_taxable,''N'')=''N'' /*mst_otherduction.applicationtype<>''TP''*/) then amount else 0 end) otherledgerarearwithoutesi
						,sum(case when headid =12 then amount else 0 end) tdsadjustment
						,STRING_AGG (tbl_employeeledger.id::text,'','') disbursedledgerids
						,sum(case when amount<0 and coalesce(tbl_employeeledger.is_taxable,''N'')=''Y''and headid not in (12) then amount else 0 end) othertaxablerefunds
						,0 security_amt
						,0 conveyance
				   from tbl_employeeledger  inner join mst_otherduction on tbl_employeeledger.headid= mst_otherduction.id
				   where tbl_employeeledger.isactive=''1'' 
				  and processmonth='||p_mprmonth||'
				  and processyear='||p_mpryear||'
				  and tbl_employeeledger.id not in (select  trim(regexp_split_to_table(dl.disbursedledgerids,'',''))::bigint from tbl_monthlysalary dl where dl.mprmonth='||p_mprmonth||' and dl.mpryear='||p_mpryear||' and coalesce(dl.is_rejected,''0'')<>''1'')
				  group by emp_code
			union all
		/*Below code for security amount dated 04-July2021*/
			select 
			emp_code,sum(case when deduction_amount>0 then deduction_amount else 0 end) otherledgerarear
					,0 otherledgerdeductions
					,0 otherledgerarearwithoutesi
					,0 tdsadjustment
					,null disbursedledgerids
					,0 othertaxablerefunds
					,sum(case when deduction_amount<0 then deduction_amount else 0 end)*-1 security_amt
					,0 conveyance
				   from public.trn_candidate_otherduction inner join openappointments
				   on trn_candidate_otherduction.candidate_id= openappointments.emp_id
				   where public.trn_candidate_otherduction.active=''Y''
				  and trn_candidate_otherduction.deduction_id =7
				  group by emp_code
				  	/*Below code for security amount dated 04-July2021 ends here*/
					
			/*change 1.24 starts*/		
			union all
			select 
			emp_code,0 otherledgerarear
					,0 otherledgerdeductions
					,0 otherledgerarearwithoutesi
					,0 tdsadjustment
					,null disbursedledgerids
					,0 othertaxablerefunds
					,0
					,sum(case when deduction_amount>0 then deduction_amount else 0 end) conveyance
				   from public.trn_candidate_otherduction inner join openappointments
				   on trn_candidate_otherduction.candidate_id= openappointments.emp_id
				   where public.trn_candidate_otherduction.active=''Y''
				   and trn_candidate_otherduction.deduction_frequency=''Monthly''
				  and trn_candidate_otherduction.deduction_id<>323 --Meal Voucher ID, Must Change for Production
				  and trn_candidate_otherduction.deduction_id =87
				  group by emp_code
				  			/*change 1.24 ends*/
				  ) tblotherledger1 group by emp_code
				  ) tblotherledger
		          on cmsdownloadedwages.empcode::bigint=tblotherledger.emp_code  
---------------Added Meal Voucher --------------------------					  
left join (select salaryid,candidate_id,sum(deduction_amount) mealvoucher
				   from public.trn_candidate_otherduction
				   inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
				   where public.trn_candidate_otherduction.active=''Y'' 
				   and deduction_amount>0
				  --and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				  and motd.id=323 --Meal Voucher ID, Change for Production
				  group by salaryid,public.trn_candidate_otherduction.candidate_id) tblmealvoucher
		          on openappointments.emp_id=tblmealvoucher.candidate_id
				  and empsalaryregister.id=tblmealvoucher.salaryid 				  
----------------------------------------------------------------------	
	left join (select salaryid,candidate_id,sum(deduction_amount) othervariables
	,string_agg(deduction_name||'':''||deduction_amount,'','') customnontaxablecomponents
				   from public.trn_candidate_otherduction
				   inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
				   where public.trn_candidate_otherduction.active=''Y''
				   and motd.deduction_name not in (''Conveyance'')
				   and deduction_amount>0
				  --and coalesce(trn_candidate_otherduction.includedinctc,''N'')=''N'' 
				  and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				  and motd.id<>323 --Meal Voucher ID, Must Change for Production
				  and trn_candidate_otherduction.deduction_id not in (5,6,7,10)
				  and coalesce(trn_candidate_otherduction.is_taxable,''N'')=''N''
				  group by salaryid,public.trn_candidate_otherduction.candidate_id) tblothervariables
		          on openappointments.emp_id=tblothervariables.candidate_id
				  and empsalaryregister.id=tblothervariables.salaryid
-------------------------------------------------------------------------	
left join (select emp_code,sum(basic) basicalreadypaid,sum(epf) epfalreadydeducted
									,sum(coalesce(Ac_1,0)) Ac_1alreadydeducted
									,sum(coalesce(Ac_10,0)) ac_10alreadydeducted
									,sum(coalesce(Ac_2,0)) ac_2alreadydeducted
									,sum(coalesce(Ac21,0)) ac_21alreadydeducted
									,sum(insurance) alreadyinsurance
									,sum(insuranceamount) alreadyinsuranceamount
									,sum(familyinsurance) alreadyfamilyfamilyinsurance
									,sum(otherledgerarears) alreadyotherledgerarears
									,sum(otherledgerdeductions) alreadyotherledgerdeductions
									,sum(tds) alreadytds
									,sum(other) alreadyother
									,sum(otherledgerarearwithoutesi) otherledgerarearwithoutesialready
									,sum(lwf) lwfalready
									,sum(lwf_employee) lwf_employeealready
									,sum(lwf_employer) lwf_employeralready
									,sum(ews) ewsalready
									,sum(gratuity) gratuityalready
									,sum(bonus) bonusalready
									,sum(tdsadjustment) alreadytdsadjustment
									,sum(security_amt) alreadysecurity_amt
									,sum(grossearning) alreadygrossearning
									,sum(coalesce(nullif(pfapplicablecomponents,0),basic) ) pfapplicablecomponentsalreadypaid
									,sum(employerinsuranceamount) alreadyemployerinsuranceamount
									,sum(mealvoucher) alreadymealvoucher
from tbl_monthlysalary 
where mprmonth='||p_mprmonth||'
and mpryear='||p_mpryear||'
and coalesce(is_rejected,''0'')<>''1''
group by emp_code) tblalreadypf
on tblalreadypf.emp_code=openappointments.emp_code
-----------------change 1.17 starts------------------------------------------
left join (
select coalesce(nullif(trim(op2.pancard),''''),op2.emp_code::text) taxpancard,sum(currentmonthtaxdeducted)	currentmonthtaxdeducted from(
	select emp_code
,sum(case when 
	 (
						(
							to_date(left(hrgeneratedon,11),''dd Mon yyyy'')
							between '''||v_salstartdate::date||'''  and '''||v_salenddate::date ||'''
							and to_date((mpryear::text||''-''||lpad(mprmonth::text,2,''0'')||''-01''),''yyyy-mm-dd'')<'''||v_salstartdate::date||'''
						)
					or
						(	
						to_date(left(hrgeneratedon,11),''dd Mon yyyy'')
						 between '''||v_advancesalstartdate::date||'''  and '''||v_advancesalenddate::date||'''	
							and mprmonth='||p_mprmonth||' and mpryear='||p_mpryear||'
						)
			)
	 then tds else 0 end) as currentmonthtaxdeducted
from (select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear
	  from tbl_monthlysalary
	 where  ';
	if p_criteria='Employee' then	  
		v_querytext:=v_querytext||' 	 
		 (tbl_monthlysalary.emp_code='||p_emp_code||' or tbl_monthlysalary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	v_querytext:=v_querytext||'  (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_startdate::date||'''  and '''||v_enddate::date||'''	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_advancestartdate::date ||'''  and '''||v_advanceenddate::date||'''		 
				and mprmonth=4 and mpryear='||v_year1||'
				 )
			)
	  	  	and not(mprmonth=4 and mpryear='||v_year2||')
		   and coalesce(is_rejected,''0'')<>''1''
	 union all
	  select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear
	from tbl_monthly_liability_salary
	where ';
	if p_criteria='Employee' then	  
		v_querytext:=v_querytext||' 	 
		 (tbl_monthly_liability_salary.emp_code='||p_emp_code||' or tbl_monthly_liability_salary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	v_querytext:=v_querytext||'  coalesce(salary_remarks,'''')<>''Invalid Paid Days''
	and coalesce(is_rejected,''0'')=''0''
	------------------------------------------------------------------------------------
	and (emp_code,mprmonth, mpryear, batchid) not in
		(select '||p_emp_code||','||p_mprmonth||', '||p_mpryear||', '''||p_batch_no||''') 	
	and (emp_code,mprmonth, mpryear, batchid||transactionid) not in
		(select '||p_emp_code||','||p_mprmonth||', '||p_mpryear||', '''||p_batch_no||''') 		  
	----------------------------------------------------------------------------------------	  
	  	 and not(mprmonth=4 and mpryear='||v_year2||')
	  	 and (
			to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_startdate::date||'''  and '''||v_enddate::date||'''	 
			or
				(
				to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_advancestartdate::date||'''  and '''||v_advanceenddate::date||'''		 
				and mprmonth=4 and mpryear='||v_year1||'
				 )
			)
-----------------------------------------------------------------------	  
	and (emp_code,mprmonth, mpryear, batchid) not in
	  (
	(select emp_code,mprmonth, mpryear, batchid 
		 from tbl_monthlysalary 
	 	where ';
	if p_criteria='Employee' then	  
		v_querytext:=v_querytext||' 	 
		 (tbl_monthlysalary.emp_code='||p_emp_code||' or tbl_monthlysalary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	v_querytext:=v_querytext||' (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_startdate::date||'''  and '''||v_enddate::date||'''	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_advancestartdate::date||'''  and '''||v_advanceenddate::date||'''		 
				and mprmonth=4 and mpryear='||v_year1||'
				 )
			)
	 and coalesce(is_rejected,''0'')=''0''
	)
union all
	(select emp_code,mprmonth, mpryear, batchid ||coalesce(transactionid::text,'''')
		 from tbl_monthlysalary 
	 where  ';
	if p_criteria='Employee' then	  
		v_querytext:=v_querytext||' 	 
		 (tbl_monthlysalary.emp_code='||p_emp_code||' or tbl_monthlysalary.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	v_querytext:=v_querytext||'(
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_startdate::date||'''  and '''||v_enddate||'''	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_advancestartdate||'''  and '''||v_advanceenddate||'''	 
				and mprmonth=4 and mpryear='||v_year1||'
				 )
			)
	 and coalesce(is_rejected,''0'')=''0''
	) 
	 
-------------------------------------------------------	  
		  union all
	(select m.mprmonth, m.mpryear,  m.emp_code,trim(regexp_split_to_table(m.batchid,'''','''')) 
	 from tbl_monthlysalary m where 
	 ';

	if p_criteria='Employee' then	  
		v_querytext:=v_querytext||' 	 
		 (m.emp_code='||p_emp_code||' or m.emp_code in (select emp_code from openappointments where coalesce(nullif(trim(pancard),''''),''-6666'')='''||coalesce(v_pancard,'-7777')||''')) and ';
	end if;
	v_querytext:=v_querytext||' coalesce(m.is_rejected,''0'')=''0''
	and (
			to_date(left(m.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_startdate||'''  and '''||v_enddate||'''	 
			or
				(
				to_date(left(m.hrgeneratedon,11),''dd Mon yyyy'')
				between '''||v_advancestartdate||'''  and '''||v_advanceenddate||'''		 
				and m.mprmonth=4 and m.mpryear='||v_year1||'
				 )
			))
		  )
	 )tbl_monthlysalary
group by emp_code
) tblcurrenttax
inner join openappointments op2 on 	tblcurrenttax.emp_code=op2.emp_code
group by coalesce(nullif(trim(op2.pancard),''''),op2.emp_code::text) 	
	)tblcurrenttax
on  coalesce(nullif(trim(openappointments.pancard),''''),openappointments.emp_code::text)=tblcurrenttax.taxpancard
-----------------change 1.17 ends------------------------------------------
	/**************Change 1.15************************************************/
	left join(select ee_empid,coalesce(ee_termination_date,ee_actualrelievingdate) ee_relieveingdate, ee_finalduesclearancedate::date ee_finalduesclearancedate 
	from public.employee_exit where employee_exit.isactive=''1'' 
	)ee
	on openappointments.emp_id=ee.ee_empid
	/***********change 1.15 ends***************************************************/
	 ';

	if p_criteria='Order' then
		v_querytext:=v_querytext||' where cmsdownloadedwages.contractno='''||p_ordernumber||''' ';
	end if;
	if p_criteria='Employee' then
		v_querytext:=v_querytext||'  where cmsdownloadedwages.empcode='''||p_emp_code||''' ';
	end if;
	if p_criteria='Batch' then
		v_querytext:=v_querytext||' where cmsdownloadedwages.batch_no='''||p_batch_no||''' ';
	end if;
	
  v_querytext:=v_querytext||' ) tmp';
-----To print dynamic Query----------------------				 
	--raise notice 'Query: % ', v_querytext;		
-----To print dynamic Query----------------------	

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 14: Execution of Generation Query
	-- Description: Creates the temporary table storing logic evaluations output by the dynamic query string previously built.
	-------------------------------------------------------------------------------------------------------------------------
if p_action='Retrieve_Salary' or p_action='Save_Salary'  then
if p_tptype='NonTP' then
			v_querytext2='CREATE TEMP TABLE tmp_sal ON COMMIT DROP as '||v_querytext;
			execute v_querytext2;
elsif p_tptype='TP' then
		if not EXISTS (SELECT * FROM pg_catalog.pg_class c   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    		WHERE  c.relname = 'tmp_sal' AND c.relkind = 'r' and n.oid=pg_my_temp_schema()
					  ) then
			v_querytext2='CREATE TEMP TABLE tmp_sal ON COMMIT DROP as '||v_querytext;
			execute v_querytext2;
		else
			delete from tmp_sal;
			v_querytext2='insert into tmp_sal '||v_querytext;
			execute v_querytext2;
		end if;
end if;
--raise notice 'Query: % ', v_querytext2;	
update tmp_sal set ctc_paid_days=round((actual_paid_ctc2/ctc)*monthdays)
where is_special_category='Y';

/***************************Changes for 1.19****************/
/***************************Changes for 1.19****************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 15: Post-Execution Tax/Overrides
	-- Description: Custom handling on pre-generated variables to refine TDS manually and special contractor deductions.
	-------------------------------------------------------------------------------------------------------------------------
update tmp_sal 
	set tds=grossearning*coalesce(customtaxpercent/100.0,.01),atds=grossearning*coalesce(customtaxpercent/100.0,.01),
	grossdeduction=grossdeduction-coalesce(tds,0)+grossearning*coalesce(customtaxpercent/100.0,.01),
	netpay=netpay+coalesce(tds,0)-grossearning*coalesce(customtaxpercent/100.0,.01)
from openappointments op inner join empsalaryregister e
	on op.emp_id=e.appointment_id 
where tmp_sal.emp_code=op.emp_code and op.jobtype='Independent Contractors'
	and e.id=tmp_sal.salaryid;
	
update tmp_sal 
	set tds=0,atds=0,
	grossdeduction=grossdeduction-coalesce(tds,0),
	netpay=netpay+coalesce(tds,0)
where coalesce(tds,0)>coalesce(grossearning,0);
/***************************Changes for 1.19 end here****************/		
/***************************Below changes for 1.13****************/
-- update tmp_sal set ctc_actual_paid=(ctc*ctc_paid_days/monthdays),
-- 	mobile_deduction=(ctc*ctc_paid_days/monthdays)-actual_paid_ctc2
-- 	,netpay=netpay+coalesce(otherledgerarear,0)-coalesce(otherledgerdeductions,0)+coalesce(otherledgerarearwithoutesi,0)
--    where is_special_category='Y';
/*********Change 1.14**************************/
/***********Change 1.14 ends here*****************************/
update tmp_sal set ctc_actual_paid=(ctc*ctc_paid_days/monthdays),
       netpay=netpay+coalesce(otherledgerarear,0)-coalesce(grossdeduction,0)+coalesce(otherledgerarearwithoutesi,0)
   where is_special_category='Y'; 
   
 update tmp_sal  
	set mobile_deduction=case when ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0)) >0 then ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0))  else 0 end
	             ,mobile=case when ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0)) >0 then ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0))  else 0 end
	            ,incentive=case when (coalesce(netpay,0.0)-(grossearning-coalesce(grossdeduction,0.0))) >0 then (coalesce(netpay,0.0)-(grossearning-coalesce(grossdeduction,0.0)))  else 0 end
where is_special_category='Y'; 

update tmp_sal set 
       netpay=netpay+coalesce(netarear,0)
   where is_special_category='Y'; 
/***************************Changes for 1.13 ends****************/
/***************************Changes for 1.24****************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 16: Professional Tax Computation
	-- Description: Extracts external PT rate sheets and limits over the state framework.
	-------------------------------------------------------------------------------------------------------------------------
with tmpexgrossearning as
(
select emp_code,sum(grossearning) grossearning,sum(professionaltax) pt from tbl_monthlysalary
	where emp_code in (select emp_code from tmp_sal) and
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
update tmp_sal 
	set professionaltax=tbl1.professionaltax,grossdeduction=grossdeduction+coalesce(tbl1.professionaltax,0)
	,netpay=netpay-coalesce(tbl1.professionaltax,0)
	from (select op.emp_code,e.id,mst_statewiseprofftax.ptamount professionaltax,te.grossearning,mst_statewiseprofftax.lowerlimit,mst_statewiseprofftax.upperlimit,te.pt
		  from  openappointments op 
	inner join empsalaryregister e on e.appointment_id=op.emp_id
		  inner join tmp_sal on op.emp_code=tmp_sal.emp_code and e.id=tmp_sal.salaryid
		  inner join vw_mst_statewiseprofftax mst_statewiseprofftax on mst_statewiseprofftax.ptid=e.ptid 
		  and extract ('month' from (current_date-interval '1 month'))=mst_statewiseprofftax.ptmonth 
		  and lower(case when op.gender='M' then 'Male' when op.gender='F' then 'Female' else op.gender end)=lower(mst_statewiseprofftax.ptgender)
		  and mst_statewiseprofftax.isactive='1'
		  --and (date_trunc('month',current_date)-interval '1 month')::date  between mst_statewiseprofftax.ptapplicablefrom and mst_statewiseprofftax.ptapplicableto
		 left join tmpexgrossearning te on te.emp_code=op.emp_code) tbl1
	where tmp_sal.emp_code=tbl1.emp_code and tbl1.professionaltax>0
	and (coalesce(tbl1.grossearning,0)+coalesce(tmp_sal.grossearning,0)) between tbl1.lowerlimit and tbl1.upperlimit
	and coalesce(tbl1.pt,0)<=0;
/***************************Changes for 1.24 end here****************/	
/***************************Changes for 1.25****************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 17: Labour Welfare Fund (LWF) Rule Engine
	-- Description: Maps employee and employer welfare bounds from state-based criteria tables.
	-------------------------------------------------------------------------------------------------------------------------
with tmpexgrossearning as
(
select emp_code,sum(grossearning) grossearning,sum(lwf_employee) lwf_employee
	from tbl_monthlysalary
	where emp_code in (select emp_code from tmp_sal) 
	and mprmonth=p_mprmonth 
	and mpryear=p_mpryear
	and is_rejected='0'
	and istaxapplicable='1'
	group by emp_code
)
update tmp_sal 
	set lwf=least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0)),
		lwf_employee=least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0)),
		lwf_employer=least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal.grossearning,0))*employer_lwfpercent/100,coalesce(tbl1.employerlwfrate,0)),coalesce(tbl1.employerlwfrate,0)),
		grossdeduction=grossdeduction+least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0)),
		netpay=netpay-least(coalesce((coalesce(tbl1.grossearning,0)+coalesce(tmp_sal.grossearning,0))*employee_lwfpercent/100,coalesce(tbl1.employeelwfrate,0)),coalesce(tbl1.employeelwfrate,0))
	from (select op.emp_code,e.id,statewiselwfrate.employeelwfrate ,statewiselwfrate.employerlwfrate,te.grossearning,statewiselwfrate.lwfexemptionlimit,te.lwf_employee,statewiselwfrate.deductionmonths
		  ,e.islwfstate
		  ,statewiselwfrate.employee_lwfpercent,statewiselwfrate.employer_lwfpercent
		  from  openappointments op 
	inner join empsalaryregister e on e.appointment_id=op.emp_id
		  inner join tmp_sal on op.emp_code=tmp_sal.emp_code and e.id=tmp_sal.salaryid
		  left join statewiselwfrate on coalesce(e.lwfstatecode,0)=statewiselwfrate.statecode and statewiselwfrate.isactive='1'
		 left join tmpexgrossearning te on te.emp_code=op.emp_code) tbl1
	where tmp_sal.emp_code=tbl1.emp_code and coalesce(tbl1.employeelwfrate,0)>0
	and tmp_sal.mprmonth in (select regexp_split_to_table(tbl1.deductionmonths,',')::int)
	and (coalesce(tbl1.grossearning,0)+coalesce(tmp_sal.grossearning,0)) >= coalesce(tbl1.lwfexemptionlimit,0)
	and coalesce(tbl1.lwf_employee,0)<=0
	and coalesce(islwfstate,'N')='Y'
	;
/***************************Changes for 1.25 end here****************/	
end if;


	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 18: Output & Return Formats (NotProcessed)
	-- Description: Output format when status is NotProcessed.
	-------------------------------------------------------------------------------------------------------------------------
if p_action='Retrieve_Salary' and p_process_status='NotProcessed' then	
		open sal for select * from (
		select tmp_sal.*,case when m.emp_code is null then 'Not Verified'		
		when coalesce(m.is_rejected,'0')='1' then 'Rejected'
		when m.emp_code is not null then 'Verified'
		--when m2.empcode is not null then 'Processed'
		end verificationstatus
		,case when tblhasarear.empcode is null then 'No Arear' else 'Has Arear' end as hasarrear
		,case when m.is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus
		,to_char(m.createdon,'dd-Mon-yyyy') processedon
		,case when invpddays_empcode is null and tms3.invpddays_empcode2 is null then 'Valid' else 'Invalid' end as paiddaysstatus
		,case when epfecr_empcode is not null then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus
		from tmp_sal
			left join tbl_monthlysalary m 
		on tmp_sal.emp_code=m.emp_code
		and tmp_sal.mpryear=m.mpryear
		and tmp_sal.mprmonth=m.mprmonth
		and tmp_sal.batch_no=m.batchid
		left join (select distinct empcode
		  from cmsdownloadedwages
		 where to_date('01'||lpad(cmsdownloadedwages.mprmonth::text,2,'0')||cmsdownloadedwages.mpryear::text,'ddmmyyyy')<=
		to_date('01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text,'ddmmyyyy')
		and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y')<>'N') tblhasarear
		on tmp_sal.emp_code=tblhasarear.empcode::bigint
		
		left join (select empcode invpddays_empcode,sum(coalesce(totalpaiddays,0)+coalesce(totalleavetaken,0)) invdays
									 from cmsdownloadedwages
									 where mprmonth=p_mprmonth
									 and mpryear=p_mpryear
									  and isactive='1'
				                      and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y')<>'N'
									 group by empcode
				  having sum(coalesce(totalpaiddays,0)+coalesce(totalleavetaken,0))>v_monthdays) m4
				  on tmp_sal.emp_code=m4.invpddays_empcode::bigint
				/***********************************************/
					left join (select tms2.emp_code invpddays_empcode2,sum(coalesce(tms2.paiddays,0)) invdays2
									 from 
							   (select emp_code,paiddays from tmp_sal
							   union all
							   select emp_code,paiddays from tbl_monthlysalary 
								where emp_code in (select emp_code from tmp_sal) and is_rejected='0' 
								and recordscreen not in ('Increment Arear')
								and mprmonth=p_mprmonth
								and mpryear=p_mpryear
							   ) tms2
									 group by tms2.emp_code
				  having sum(coalesce(tms2.paiddays,0))>v_monthdays) tms3
				  on tmp_sal.emp_code=tms3.invpddays_empcode2::bigint
				/***********************************************/			
			--and tmp_sal.monthdays<m4.invdays
			left join (select distinct unprocessed_epfecrreport.emp_code epfecr_empcode
									   ,unprocessed_epfecrreport.rpt_year
									   ,unprocessed_epfecrreport.rpt_month
									   ,unprocessed_epfecrreport.batchid
									 from unprocessed_epfecrreport
									 where rpt_month=p_mprmonth
									 and rpt_year=p_mpryear) tmpepfecr
				  on tmp_sal.emp_code=tmpepfecr.epfecr_empcode
					and tmp_sal.mpryear=tmpepfecr.rpt_year
					and tmp_sal.mprmonth=tmpepfecr.rpt_month
					and tmp_sal.batch_no=tmpepfecr.batchid
   
			)tmp2;
			return sal;
end if;	
/***********************Change 1.21 Starts here*************************************************/

	-------------------------------------------------------------------------------------------------------------------------
	-- BLOCK 19: Output & Return Formats (Processed vs NotProcessed states)
	-- Description: Output format when API strictly asks for processed salaries.
	-------------------------------------------------------------------------------------------------------------------------
if (coalesce(nullif(p_process_status,''),'NotProcessed') in ('Processed','NotProcessed') and  p_action='GetProcessedSalaries')  then
 			open sal for 
			with tblmain as(
			SELECT 'NoFNFLock' fnfarrivalstatus/* column added for change 1.15*/,tbl_monthlysalary.mprmonth, tbl_monthlysalary.mpryear,MTempPausedSalary.is_paused ,
  openappointments.emp_id,TO_CHAR(TO_TIMESTAMP (p_mprmonth::text, 'MM'), 'Mon')||'-'||p_mpryear::text AS Mon,
 to_char(dateofjoining,'dd/mm/yyyy') dateofjoining,esinumber,posting_department,'' projectname,
								cm.contractno contractno,
								'' contractcategory,
								'' contracttype,'Active' as activeinbatch,appointment_status_id,'' remark,'Unlocked' lockstatus,
coalesce(is_account_verified,'0')::bit is_account_verified,
null isesiexceptionalcase,
null esicexceptionmessage,
 openappointments.emp_code, subunit, to_char(dateofleaving,'dd-Mon-yyyy') dateofleaving, totalleavetaken,openappointments.emp_name,openappointments.post_offered,openappointments.emp_address,openappointments.email,
 mobilenum, openappointments.pancard, openappointments.gender, to_char(openappointments.dateofbirth,'dd/mm/yyyy') dateofbirth, openappointments.fathername,openappointments. residential_address, openappointments.pfnumber, openappointments.uannumber, 
 lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, 
 fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal,
 ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, 
 incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance,tbl_monthlysalary. mobile, advance,
 other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, tbl_monthlysalary.govt_bonus_opted, govt_bonus_amt,
  is_special_category, ctc2 ct2, batch_no,  actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, 
 employeenps, employernps, insuranceamount, familyinsurance, tbl_monthlysalary.bankaccountno, tbl_monthlysalary.ifsccode, tbl_monthlysalary.bankname, tbl_monthlysalary.bankbranch,
 totalarear netarear,arearaddedmonths, employee_esi_incentive_deduction,employer_esi_incentive_deduction,
 total_esi_incentive_deduction,salaryindaysopted,mastersalarydays salarydays,otherledgerarears otherledgerarear,otherledgerdeductions,
 attendancemode,incrementarear,
 incrementarear_basic,incrementarear_hra,incrementarear_allowance,incrementarear_gross,incrementarear_employeeesi,incrementarear_employeresi,
 lwf_employee,lwf_employer,bonus,otherledgerarearwithoutesi,otherdeductions,othervariables,otherbonuswithesi otherdeductionswithesi,tbl_monthlysalary.lwfstatecode,tbl_monthlysalary.tdsadjustment,atds,hrgeneratedon,'' disbursedledgerids,security_amt,issalaryorliability,professionaltax ,case when issalaryorliability='L' then 'Not Verified' else 'Verified' end verificationstatus,'' hasarear,case when is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus,to_char(tbl_monthlysalary.createdon,'dd-Mon-yyyy') processedon,'Valid' paiddaysstatus
,case when epfecr_empcode is not null or issalaryorliability='L' then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus
,disbursementmode
	FROM public.tbl_monthlysalary inner join openappointments 
	on tbl_monthlysalary.emp_code=openappointments.emp_code
	and openappointments.appointment_status_id<>13 
	and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1'
	and tbl_monthlysalary.tptype=p_tptype
	and (tbl_monthlysalary.isarear<>'Y' or tbl_monthlysalary.recordscreen='Previous Wages')

	and issalaryorliability=case when (p_action='Retrieve_Salary' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') or  (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='NotProcessed') then 'L' when (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') then 'S' end
	-----------Processed record searech criteria-------------------
	and tbl_monthlysalary.emp_code= case when p_criteria='Employee' then
		p_emp_code else tbl_monthlysalary.emp_code end
	left join (select empcode,mprmonth,mpryear,batch_no batchn,
			   string_agg(contractno,',') contractno
			   from cmsdownloadedwages cm 
			   where cm.mprmonth=p_mprmonth
			  and cm.mpryear=p_mpryear
			  and cm.isactive='1'
			   and cm.contractno= case when p_criteria='Order' then
		 		p_ordernumber else cm.contractno end
			   group by empcode,mprmonth,mpryear,batch_no
			  ) cm
			   on 	tbl_monthlysalary.emp_code=cm.empcode::bigint
		and tbl_monthlysalary.batchid=cm.batchn							   
		-----------Processed record searech criteria ends------------------- 
		 
	left join (select empid,pausedstatus  is_paused  
				from ManageTempPausedSalary
				WHERE  ManageTempPausedSalary.ProcessYear =p_mpryear
				and ManageTempPausedSalary.ProcessMonth =p_mprmonth
				 ) MTempPausedSalary
				 on openappointments.emp_id=MTempPausedSalary.empid 
				 			left join (select distinct epfecrreport.emp_code epfecr_empcode
									   ,epfecrreport.rpt_year
									   ,epfecrreport.rpt_month
									   ,epfecrreport.batchid
									 from epfecrreport
									 where rpt_month=p_mprmonth
									 and rpt_year=p_mpryear) tmpepfecr
				  on tbl_monthlysalary.emp_code=tmpepfecr.epfecr_empcode
					and tbl_monthlysalary.mpryear=tmpepfecr.rpt_year
					and tbl_monthlysalary.mprmonth=tmpepfecr.rpt_month
					and tbl_monthlysalary.batchid=tmpepfecr.batchid												
				 where tbl_monthlysalary.mprmonth=p_mprmonth
				 and tbl_monthlysalary.mpryear=p_mpryear
				and coalesce(cm.contractno,'')= case when p_criteria='Order' then
		 		p_ordernumber else coalesce(cm.contractno,'') end
				)
				select tblmain.*,tblbalance.ledgerbalance from tblmain inner join (select tblbalance.emp_code,sum(tblbalance.netpay) ledgerbalance
																				   from tblmain as tblbalance group by tblbalance.emp_code) tblbalance
				on tblmain.emp_code=tblbalance.emp_code
				order by tblmain.emp_code;
			 
return sal;				 
end if;
if (coalesce(nullif(p_process_status,''),'NotProcessed')='PartiallyProcessed' and  p_action='GetProcessedSalaries')  then
 			open sal for			
			with tblmain as( 
			SELECT 'NoFNFLock' fnfarrivalstatus/* column added for change 1.15*/,tbl_monthlysalary.mprmonth, tbl_monthlysalary.mpryear,MTempPausedSalary.is_paused ,
  openappointments.emp_id,TO_CHAR(TO_TIMESTAMP (p_mprmonth::text, 'MM'), 'Mon')||'-'||p_mpryear::text AS Mon,
 to_char(dateofjoining,'dd/mm/yyyy') dateofjoining,esinumber,posting_department,'' projectname,
								cm.contractno contractno,
								'' contractcategory,
								'' contracttype,'Active' as activeinbatch,appointment_status_id,'' remark,'Unlocked' lockstatus,
coalesce(is_account_verified,'0')::bit is_account_verified,
null isesiexceptionalcase,
null esicexceptionmessage,
 openappointments.emp_code, subunit, to_char(dateofleaving,'dd-Mon-yyyy') dateofleaving, totalleavetaken,openappointments.emp_name,openappointments.post_offered,openappointments.emp_address,openappointments.email,
 mobilenum, openappointments.pancard, openappointments.gender, to_char(openappointments.dateofbirth,'dd/mm/yyyy') dateofbirth, openappointments.fathername,openappointments. residential_address, openappointments.pfnumber, openappointments.uannumber, 
 lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, 
 fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal,
 ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, 
 incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance,tbl_monthlysalary. mobile, advance,
 other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, tbl_monthlysalary.govt_bonus_opted, govt_bonus_amt,
  is_special_category, ctc2 ct2, batch_no,  actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, 
 employeenps, employernps, insuranceamount, familyinsurance, tbl_monthlysalary.bankaccountno, tbl_monthlysalary.ifsccode, tbl_monthlysalary.bankname, tbl_monthlysalary.bankbranch,
 totalarear netarear,arearaddedmonths, employee_esi_incentive_deduction,employer_esi_incentive_deduction,
 total_esi_incentive_deduction,salaryindaysopted,mastersalarydays salarydays,otherledgerarears otherledgerarear,otherledgerdeductions,
 attendancemode,incrementarear,
 incrementarear_basic,incrementarear_hra,incrementarear_allowance,incrementarear_gross,incrementarear_employeeesi,incrementarear_employeresi,
 lwf_employee,lwf_employer,bonus,otherledgerarearwithoutesi,otherdeductions,othervariables,otherbonuswithesi otherdeductionswithesi,tbl_monthlysalary.lwfstatecode,tbl_monthlysalary.tdsadjustment,atds,hrgeneratedon,'' disbursedledgerids,security_amt,issalaryorliability,professionaltax,case when issalaryorliability='L' then 'Not Verified' else 'Verified' end verificationstatus,'' hasarear,case when is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus,to_char(tbl_monthlysalary.createdon,'dd-Mon-yyyy') processedon,'Valid' paiddaysstatus
,case when epfecr_empcode is not null or issalaryorliability='L' then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus
,disbursementmode			
	FROM public.tbl_monthlysalary inner join openappointments 
	on tbl_monthlysalary.emp_code=openappointments.emp_code
	and openappointments.appointment_status_id<>13 
	and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1'
	and tbl_monthlysalary.tptype=p_tptype
	and (tbl_monthlysalary.isarear<>'Y' or tbl_monthlysalary.recordscreen='Previous Wages')

	and issalaryorliability= 'L'
	and tbl_monthlysalary.attendancemode='Ledger'			
	-----------Processed record searech criteria-------------------
	and tbl_monthlysalary.emp_code= case when p_criteria='Employee' then
		p_emp_code else tbl_monthlysalary.emp_code end
	left join (select empcode,mprmonth,mpryear,batch_no batchn,
			   string_agg(contractno,',') contractno
			   from cmsdownloadedwages cm 
			   where cm.mprmonth=p_mprmonth
			  and cm.mpryear=p_mpryear
			  and cm.isactive='1'
			   and cm.contractno= case when p_criteria='Order' then
		 		p_ordernumber else cm.contractno end
			   group by empcode,mprmonth,mpryear,batch_no
			  ) cm
			   on 	tbl_monthlysalary.emp_code=cm.empcode::bigint
		and tbl_monthlysalary.batchid=cm.batchn							   
		-----------Processed record searech criteria ends------------------- 
		 
	left join (select empid,pausedstatus  is_paused  
				from ManageTempPausedSalary
				WHERE  ManageTempPausedSalary.ProcessYear =p_mpryear
				and ManageTempPausedSalary.ProcessMonth =p_mprmonth
				 ) MTempPausedSalary
				 on openappointments.emp_id=MTempPausedSalary.empid 
				 			left join (select distinct epfecrreport.emp_code epfecr_empcode
									   ,epfecrreport.rpt_year
									   ,epfecrreport.rpt_month
									   ,epfecrreport.batchid
									 from epfecrreport
									 where rpt_month=p_mprmonth
									 and rpt_year=p_mpryear) tmpepfecr
				  on tbl_monthlysalary.emp_code=tmpepfecr.epfecr_empcode
					and tbl_monthlysalary.mpryear=tmpepfecr.rpt_year
					and tbl_monthlysalary.mprmonth=tmpepfecr.rpt_month
					and tbl_monthlysalary.batchid=tmpepfecr.batchid												
				 where tbl_monthlysalary.is_rejected='0' and
				 		(
					 	(tbl_monthlysalary.mprmonth<p_mprmonth	 and tbl_monthlysalary.mpryear=p_mpryear)
					   	or 
					 	tbl_monthlysalary.mpryear<p_mpryear
					   )
				and coalesce(cm.contractno,'')= case when p_criteria='Order' then
		 		p_ordernumber else coalesce(cm.contractno,'') end
				)
				select tblmain.*,tblbalance.ledgerbalance from tblmain inner join (select tblbalance.emp_code,sum(tblbalance.netpay) ledgerbalance
																				   from tblmain as tblbalance group by tblbalance.emp_code) tblbalance
				on tblmain.emp_code=tblbalance.emp_code
				order by tblmain.emp_code;
			 
return sal;				 
end if;
/*****************Change 1.21 ends here**************************************/
 if (coalesce(nullif(p_process_status,''),'NotProcessed')='Processed' and p_action='Retrieve_Salary') then
 			open sal for 
			SELECT 'NoFNFLock' fnfarrivalstatus/* column added for change 1.15*/,tbl_monthlysalary.mprmonth, tbl_monthlysalary.mpryear,MTempPausedSalary.is_paused ,
  openappointments.emp_id,TO_CHAR(TO_TIMESTAMP (p_mprmonth::text, 'MM'), 'Mon')||'-'||p_mpryear::text AS Mon,
 to_char(dateofjoining,'dd/mm/yyyy') dateofjoining,esinumber,posting_department,'' projectname,
								cm.contractno contractno,
								'' contractcategory,
								'' contracttype,'Active' as activeinbatch,appointment_status_id,'' remark,'Unlocked' lockstatus,
coalesce(is_account_verified,'0')::bit is_account_verified,
null isesiexceptionalcase,
null esicexceptionmessage,
 openappointments.emp_code, subunit, to_char(dateofleaving,'dd-Mon-yyyy') dateofleaving, totalleavetaken,openappointments.emp_name,openappointments.post_offered,openappointments.emp_address,openappointments.email,
 mobilenum, openappointments.pancard, openappointments.gender, to_char(openappointments.dateofbirth,'dd/mm/yyyy') dateofbirth, openappointments.fathername,openappointments. residential_address, openappointments.pfnumber, openappointments.uannumber, 
 lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, 
 fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal,
 ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, 
 incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance,tbl_monthlysalary. mobile, advance,
 other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, tbl_monthlysalary.govt_bonus_opted, govt_bonus_amt,
  is_special_category, ctc2 ct2, batch_no,  actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, 
 employeenps, employernps, insuranceamount, familyinsurance, tbl_monthlysalary.bankaccountno, tbl_monthlysalary.ifsccode, tbl_monthlysalary.bankname, tbl_monthlysalary.bankbranch,
 totalarear netarear,arearaddedmonths, employee_esi_incentive_deduction,employer_esi_incentive_deduction,
 total_esi_incentive_deduction,salaryindaysopted,mastersalarydays salarydays,otherledgerarears otherledgerarear,otherledgerdeductions,
 attendancemode,incrementarear,
 incrementarear_basic,incrementarear_hra,incrementarear_allowance,incrementarear_gross,incrementarear_employeeesi,incrementarear_employeresi,
 lwf_employee,lwf_employer,bonus,otherledgerarearwithoutesi,otherdeductions,othervariables,otherbonuswithesi otherdeductionswithesi,tbl_monthlysalary.lwfstatecode,tbl_monthlysalary.tdsadjustment,atds,hrgeneratedon,'' disbursedledgerids,security_amt,issalaryorliability,professionaltax,case when issalaryorliability='L' then 'Not Verified' else 'Verified' end verificationstatus,'' hasarear,case when is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus,to_char(tbl_monthlysalary.createdon,'dd-Mon-yyyy') processedon,'Valid' paiddaysstatus
,case when epfecr_empcode is not null or issalaryorliability='L' then 'EPFPaid' else 'EPFNotPaid' end as pfpaystatus
	FROM public.tbl_monthlysalary inner join openappointments 
	on tbl_monthlysalary.emp_code=openappointments.emp_code
	and openappointments.appointment_status_id<>13 
	and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1'
	and tbl_monthlysalary.tptype=p_tptype
	and (tbl_monthlysalary.isarear<>'Y' or tbl_monthlysalary.recordscreen='Previous Wages')

	and issalaryorliability=case when (p_action='Retrieve_Salary' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') or  (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='NotProcessed') then 'L' when (p_action='GetProcessedSalaries' and coalesce(nullif(p_process_status,''),'NotProcessed')='Processed') then 'S' end
	-----------Processed record searech criteria-------------------
	and tbl_monthlysalary.emp_code= case when p_criteria='Employee' then
		p_emp_code else tbl_monthlysalary.emp_code end
	left join (select empcode,mprmonth,mpryear,batch_no batchn,
			   string_agg(contractno,',') contractno
			   from cmsdownloadedwages cm 
			   where cm.mprmonth=p_mprmonth
			  and cm.mpryear=p_mpryear
			  and cm.isactive='1'
			   and cm.contractno= case when p_criteria='Order' then
		 		p_ordernumber else cm.contractno end
			   group by empcode,mprmonth,mpryear,batch_no
			  ) cm
			   on 	tbl_monthlysalary.emp_code=cm.empcode::bigint
		and tbl_monthlysalary.batchid=cm.batchn							   
		-----------Processed record searech criteria ends------------------- 
		 
	left join (select empid,pausedstatus  is_paused  
				from ManageTempPausedSalary
				WHERE  ManageTempPausedSalary.ProcessYear =p_mpryear
				and ManageTempPausedSalary.ProcessMonth =p_mprmonth
				 ) MTempPausedSalary
				 on openappointments.emp_id=MTempPausedSalary.empid 
				 			left join (select distinct epfecrreport.emp_code epfecr_empcode
									   ,epfecrreport.rpt_year
									   ,epfecrreport.rpt_month
									   ,epfecrreport.batchid
									 from epfecrreport
									 where rpt_month=p_mprmonth
									 and rpt_year=p_mpryear) tmpepfecr
				  on tbl_monthlysalary.emp_code=tmpepfecr.epfecr_empcode
					and tbl_monthlysalary.mpryear=tmpepfecr.rpt_year
					and tbl_monthlysalary.mprmonth=tmpepfecr.rpt_month
					and tbl_monthlysalary.batchid=tmpepfecr.batchid												
				 where tbl_monthlysalary.mprmonth=p_mprmonth
				 and tbl_monthlysalary.mpryear=p_mpryear
				and coalesce(cm.contractno,'')= case when p_criteria='Order' then
		 		p_ordernumber else coalesce(cm.contractno,'') end;
			 
return sal;				 
end if;
if p_action='Save_Salary' then	
if ((select coalesce(is_account_verified,'0')::bit from openappointments where emp_code=p_emp_code)='1' or((select coalesce(ta.payout_mode_type,'') from openappointments inner join tbl_account ta on openappointments.customeraccountid=ta.id where emp_code=p_emp_code) in ('self','hybrid')))
	and not EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array((select COALESCE(COALESCE(NULLIF(op.assigned_ou_ids, ''),'0')) from openappointments op where op.emp_code=p_emp_code), ',')) AS input_ou_ids
		WHERE input_ou_ids::bigint in (select id from tbl_org_unit_geofencing where is_attendance_leave_only='Y')
		)
	then
	
	
/***************************Changes for 1.34 starts**************/
select extract ('month' from (to_date(left(hrgeneratedon,11),'dd Mon yyyy')-interval '1 month')::date),
		extract ('year' from (to_date(left(hrgeneratedon,11),'dd Mon yyyy')-interval '1 month')::date),
		attendancemode
	from tmp_sal
into v_arearprocessmonth,v_arearprocessyear,v_attendancemode;	
if (select make_date(p_mpryear,p_mprmonth,1)<make_date(v_arearprocessyear,v_arearprocessmonth,1)) and v_attendancemode='Manual' 
then			v_isarear:='Y';
				v_recordscreen:='Previous Wages';
				v_isarearprocessed:='Y';
				v_arearprocessmonth:=v_arearprocessmonth;
				v_arearprocessyear:=v_arearprocessyear;
else
				v_arearprocessmonth:=0;
				v_arearprocessyear:=0;	
end if;
	/***************************Changes for 1.34 ends****************/	
	
	
		v_querytext:='insert into tbl_monthlysalary ( mprmonth, mpryear, batchid, createdby, createdon, createdbyip,arearids,tptype, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2,batch_no,actual_paid_ctc2,ctc,ctc_paid_days,ctc_actual_paid,mobile_deduction,salaryid,employeenps,employernps,insuranceamount,familyinsurance,bankaccountno, ifsccode, bankname, bankbranch,totalarear,arearaddedmonths,employee_esi_incentive_deduction,employer_esi_incentive_deduction,total_esi_incentive_deduction,salaryindaysopted,mastersalarydays,otherledgerarears,otherledgerdeductions,attendancemode,incrementarear,incrementarear_basic,incrementarear_hra,incrementarear_allowance,incrementarear_gross,incrementarear_employeeesi,incrementarear_employeresi,lwf_employee,lwf_employer,bonus,otherledgerarearwithoutesi,otherdeductions,othervariables,otherbonuswithesi,lwfstatecode,tdsadjustment,atds,hrgeneratedon,disbursedledgerids,security_amt,issalaryorliability,professionaltax,ratesalarybonus,ratecommission,ratetransport_allowance,ratetravelling_allowance,rateleave_encashment,rateovertime_allowance,ratenotice_pay,ratehold_salary_non_taxable,ratechildren_education_allowance,rategratuityinhand,salarybonus,commission,transport_allowance,travelling_allowance,leave_encashment,overtime_allowance,notice_pay,hold_salary_non_taxable,children_education_allowance,gratuityinhand,tea_allowance,pfapplicablecomponents,esiapplicablecomponents,isgroupinsurance,employerinsuranceamount,mealvoucher,gross_esic_income,overtime,payment_record_id,isarear,recordscreen,isarearprocessed,arearprocessmonth,arearprocessyear,multipayoutrequestid,is_advice,salaryjson,otherearningcomponents,paymenttypeid) 
		select *,'|| coalesce(nullif(p_payment_recordid,-9999)::text,'null')
		||','''||v_isarear||''','''||v_recordscreen||''','''||v_isarearprocessed||''',nullif('||v_arearprocessmonth||',0),nullif('||v_arearprocessyear||',0),' ||p_multipayoutrequestid||'
		,case when '||p_multipayoutrequestid||'=0 then ''N'' else ''Y'' end
		,'''|| coalesce(p_paymentadvice.salaryjson,'')||'''
		,'|| coalesce(p_paymentadvice.otherearningcomponents,0)||'
		,'|| coalesce(v_openappointments.paymenttypeid,0)||'
		 from 
		 tmp_sal
		where (tmp_sal.mprmonth, tmp_sal.mpryear, tmp_sal.emp_code,tmp_sal.batchid) not in 
			(select m.mprmonth, m.mpryear,  m.emp_code,trim(regexp_split_to_table(m.batchid,'','')) from tbl_monthlysalary m where coalesce(m.is_rejected,''0'')<>''1''
			and m.recordscreen<>''Increment Arear''
			and m.mprmonth='||p_mprmonth||' and m.mpryear='||p_mpryear||' and m.emp_code='||p_emp_code||'
			)';
		execute v_querytext;
					update tbl_monthlysalary
					set esi_incentive_processed='1'
					,esi_incentive_processedon=current_timestamp
					,esi_incentive_processedby=p_createdby
					,esi_incentive_processedbyip=p_createdbyip
					,esi_incentive_processmonth=p_mprmonth::text
					,esi_incentive_processyear=p_mpryear::text
									where 		
									 isarear='Y' 
									and coalesce(esi_incentive_processed,'0')<>'1'
									and coalesce(is_rejected,'0')<>'1'
									and recordscreen='Previous Wages'
									and emp_code=p_emp_code;
	
         
/**************************change 1.36 starts**************************************/
	select public.uspmonthwiseinvestmentreport(p_financialyear =>v_financial_year,
								p_action =>'GetAllInvestmentReport',
								p_empcode =>p_emp_code::bigint,
								p_mprmonth =>p_mprmonth::integer,
								p_mpryear=>p_mpryear ::integer)
	into v_investmentresult;
/**************************change 1.36 ends**************************************/	
	/*****************Change 1.9 starts*****************************/
			update tbl_attendnace_dsr_da_data
			set is_processed='Y'
			,processed_dt=current_timestamp 
			where tbl_attendnace_dsr_da_data.emp_code=p_emp_code
							 and coalesce(tbl_attendnace_dsr_da_data.status,'0')='1'
							 and tbl_attendnace_dsr_da_data.month=p_mprmonth 
							 and tbl_attendnace_dsr_da_data.year=p_mpryear
							 and coalesce(tbl_attendnace_dsr_da_data.is_processed,'N')='N';
	
/*****************Change 1.9 ends*****************************/	

	if p_criteria='Employee' then	
		update tbl_employeeledger 
		set isledgerdisbursed='1',
			ledgerbatchid=p_batch_no,
			ledgerdisbursedby=createdby,
			ledgerdisbursedon=current_timestamp,
			ledgerdisbursedbyip=p_createdbyip
		where emp_code=p_emp_code
			and processmonth=p_mprmonth
			and processyear=p_mpryear
			and coalesce(isledgerdisbursed,'0')<>'1'
			and isactive='1';
	end if;
	
	delete from paymentadvice where emp_code=p_emp_code and paymentadvice_id=p_paymentadvice.paymentadvice_id;
/*****************Change 1.43 starts*****************************/	
	if exists(select * from mstmealvoucher where emp_code=p_emp_code and isactive='1' and effectivefromdate<=make_date(p_mpryear,p_mprmonth,1) and (effectivetodate>=make_date(p_mpryear,p_mprmonth,1) or effectivetodate is null))
	and not exists(select * from trnmealvoucher where emp_code=p_emp_code and isactive='1' and mealmonth=p_mprmonth and mealyear=p_mpryear)
	then
	INSERT INTO public.trnmealvoucher(
	emp_code, mealmasterid, mealmonth, mealyear, mealamount, createdby, createdon, createdbyip, isactive)
		select emp_code,mstmealvoucher.id,p_mprmonth,p_mpryear,mealamount,p_createdby,current_timestamp,p_createdbyip,'1'
		from mstmealvoucher 
		where emp_code=p_emp_code 
		and isactive='1' 
		and effectivefromdate<=make_date(p_mpryear,p_mprmonth,1) 
		and (effectivetodate>=make_date(p_mpryear,p_mprmonth,1) or effectivetodate is null);
	end if;
/*****************Change 1.43 ends*****************************/	
	end if;		
	open sal for select 1 as cnt;		
	return sal;				 
end if;
-- exception when others then
 raise notice 'Query: % ', v_querytext;		
-- open sal for select 0 as cnt;		
-- 	return sal;		
end;

$BODY$;

ALTER FUNCTION public.uspgetorderwisewages(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, character varying, character varying, bigint, record, bigint)
    OWNER TO stagingpayrolling_app;

