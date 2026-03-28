-- FUNCTION: public.uspcalculatetaxprojection(bigint, character varying, character varying, integer, integer, text)

-- DROP FUNCTION IF EXISTS public.uspcalculatetaxprojection(bigint, character varying, character varying, integer, integer, text);

CREATE OR REPLACE FUNCTION public.uspcalculatetaxprojection(
	p_emp_code bigint,
	p_financial_year character varying,
	p_regime character varying,
	p_month integer DEFAULT 0,
	p_year integer DEFAULT 0,
	p_isleft text DEFAULT 'N'::text)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
v_empid bigint;
v_gender varchar(10);
v_totalincome numeric(18,2):=0;
v_lossonproperty numeric(18,2):=0;
v_incomepreviousemployer  numeric(18,2):=0;
v_previousemployertax  numeric(18,2):=0;
v_letoutpropertyincome  numeric(18,2):=0;
v_incomefromothersources numeric(18,2):=0;
v_businessincome numeric(18,2):=0;
v_incomefromcapitalgains  numeric(18,2):=0;
v_anyotherincome  numeric(18,2):=0;
v_interestonsavingbank  numeric(18,2):=0;
v_tds_others  numeric(18,2):=0;
v_chapter6deductions numeric(18,2):=0;
v_us80cdeductions numeric(18,2):=0;
v_us80ccd_deductions numeric(18,2):=0;
v_totalsavings numeric(18,2):=0;
v_taxableincome numeric(18,2):=0;

v_taxonincome numeric(18,2):=0;
v_us87a12500 numeric(18,2):=0;
v_surcharge numeric(18,2):=0;
v_pretaxonincome numeric(18,2):=0;
v_healtheducess numeric(18,2):=0;
v_netpayabletax  numeric(18,2):=0;

v_taxdeducted numeric(18,2):=0;
v_balancetax numeric(18,2):=0;
v_taxslab varchar(20):='';
v_rfctaxproj refcursor;

v_year1 int;
v_year2 int;
v_effectivefrom date;
v_mon1 int;
v_mon2 int;
v_hra  numeric(18,2):=0;
v_basic  numeric(18,2):=0;
v_locationtype varchar(20);
v_rentpaid numeric(18,2):=0;
v_metrononmetrohra numeric(18,2):=0;
v_hraexemption numeric(18,2):=0;
v_isbefore01apr1999 varchar(1);

v_existingbasic numeric(18,2):=0;
v_existinghra numeric(18,2):=0;
v_existinggrossearning numeric(18,2):=0;
v_existingotherdeductions numeric(18,2):=0;
v_otherdeductions numeric(18,2):=0;
v_leftflag varchar(1):='N';
v_currentmonthtaxdeducted numeric(18,2):=0;
v_declaration_or_proof varchar(1);
v_financial_year text;
v_proofapplicabledate date;
v_is_fianncialyearcompleted varchar(1);
v_startdate date;
v_enddate date;
v_advancestartdate date;
v_advanceenddate date;

v_salstartdate date;
v_salenddate date;
v_advancesalstartdate date;
v_advancesalenddate date;
v_prevsaldate date;
v_cjcode varchar(40);
v_cjcodeopen  varchar(40);
	
	
v_lastempcode bigint;
v_lastleftflag varchar(1);
v_lastdateofrelieving date;
v_pancard varchar(10);
v_lastempid bigint;
v_finyearstartdate date;
v_finyearenddate date;
v_openfrom date;				
v_professionaltax  numeric(18,2):=0;
v_marginal_relief   numeric(18,2):=0;
v_presurcharge numeric(18,2):=0;

v_insurance  numeric(18,2):=0;
v_pf  numeric(18,2):=0;
v_vpf  numeric(18,2):=0;
v_ptid int;
v_marginal_reliefsmall   numeric(18,2):=0;

v_previousemployerbasic  numeric(18,2):=0;
v_previousemployerhra  numeric(18,2):=0;
v_rec record;
v_customeraccountid bigint;
v_flexocomponents    numeric(18,2):=0;
v_lta    numeric(18,2):=0;
v_disbursedsalaryids varchar(500);
v_projectedalaryids varchar(500);
v_onemonthbasic    numeric(18,2):=0;
v_activesalaryid bigint;

v_commission numeric(18,2) := 0;
v_transport_allowance numeric(18,2) := 0;
v_travelling_allowance numeric(18,2) := 0;
v_leave_encashment numeric(18,2) := 0;
v_overtime_allowance numeric(18,2) := 0;
v_notice_pay numeric(18,2) := 0;
v_hold_salary_non_taxable numeric(18,2) := 0;
v_children_education_allowance numeric(18,2) := 0;
v_gratuityinhand numeric(18,2) := 0;
v_salarybonus numeric(18,2) := 0;
v_existingcommission numeric(18,2) := 0;
v_existingtransport_allowance numeric(18,2) := 0;
v_existingtravelling_allowance numeric(18,2) := 0;
v_existingleave_encashment numeric(18,2) := 0;
v_existingovertime_allowance numeric(18,2) := 0;
v_existingnotice_pay numeric(18,2) := 0;
v_existinghold_salary_non_taxable numeric(18,2) := 0;
v_existingchildren_education_allowance numeric(18,2) := 0;
v_existinggratuityinhand numeric(18,2) := 0;
v_existingsalarybonus numeric(18,2) := 0;
v_existingconv numeric(18,2) := 0;
v_existingallowance numeric(18,2) := 0;
v_existingmedical_allowance numeric(18,2) := 0;

v_conv numeric(18,2) := 0;
v_allowances numeric(18,2) := 0;
v_medicalallowance numeric(18,2) := 0;

v_tax_marginal_relief   numeric(18,2):=0;
v_empdeclr_prevemployerinc_dtls empdeclr_prevemployerinc_dtls%rowtype;
v_standard_deduction NUMERIC(18,2);
v_health_education_cess NUMERIC(18,2);
v_surcharge_rate NUMERIC := 0;
v_recus87a record;
v_rec_taxmarginalrelief record;
v_rec_surcharge_rate record;
v_thresholdvalue numeric(18,2);
v_thresholdsurchargerate  numeric(18,2);
v_existingmealvoucher NUMERIC(18,2) := 0;
v_mealvoucher NUMERIC(18,2) := 0;
v_is_exemptedfromtds varchar(1):='N';

v_salary_head_text text;
v_rec_component record;
v_sql text;
v_sum_list text;
begin
/*************************************************************************
Version Date			Change								Done_by
1.1		25-Feb-2022		Added for Left Candidates			Shiv Kumar
1.2		05-Mar-2022		Only Approved Declarations			Shiv Kumar
1.3		29-Mar-2022		Tax Refund							Shiv Kumar
1.4		30-May-2022		Tax at hrgenerated					Shiv Kumar
1.5		10-Oct-2022		Add CJ Code							Shiv Kumar
1.6		07-Nov-2022		Tax on Pancard						Shiv Kumar
1.7		23-Feb-2022		Eliminate current Month projection	Shiv Kumar
						if salary disbursed
1.8		19-Apr-2023		New Regime 2023-2024 onwards		Shiv Kumar
1.9		31-May-2023		Marginal Relief for earners			Shiv Kumar
						with earning more than 750000
1.10	02-Oct-2023		Club Insurance and External			Shiv Kumar
						 Health Insurance
1.11	24-Sep-2024		New Regime 2024-2025 changes		Shiv Kumar
1.12	06-Nov-2024		Migrated Clients Data				Shiv Kumar
1.13	20-Jan-2025		Flexi Allowance						Shiv Kumar
1.14	01-Apr-2025		Dynamic Tax Configuration			Siddharth
						(Taking reference HUB)
1.15	04-Jul-2025		Meal Voucher						Shiv Kumar
1.17	12-Nov-2025		Add is left condition for FNF		Shiv Kumar
1.18	20-Feb-2026		Flexi Components Min. Check			Shiv Kumar
**************************************************************************/
/*****************Change 1.12 starts**********************************/
select customeraccountid from openappointments where emp_code=p_emp_code into v_customeraccountid;
select 
sum(grossearning) grossearning,sum(basic) basic,sum(hra) hra,
sum(tds) tds,sum(pf) pf,sum(vpf) vpf,sum(insurance) as insurance
from tbl_migratedcustomerincomedtld rp inner join openappointments op
on rp.orgempcode=op.orgempcode
and op.customeraccountid=v_customeraccountid
and op.emp_code=p_emp_code
and finyear=p_financial_year
and rp.isactive='1'
into v_rec;
/*****************Change 1.12 ends**********************************/
select 
coalesce(baisc_apr2024::numeric(18),0)+
coalesce(basic_may2024::numeric(18),0)+
coalesce(basic_jun2024::numeric(18),0)+
coalesce(basic_jul2024::numeric(18),0)+
coalesce(basic_aug2024::numeric(18),0),

coalesce(hra_apr2024::numeric(18),0)+
coalesce(hra_may2024::numeric(18),0)+
coalesce(hra_jun2024::numeric(18),0)+
coalesce(hra_jul2024::numeric(18),0)+
coalesce(hra_aug2024::numeric(18),0)
from regenesyspreviousincome rp inner join openappointments op
on rp.employee_code=op.orgempcode
and op.customeraccountid=5484
and op.emp_code=p_emp_code
and p_financial_year='2024-2025'
into v_previousemployerbasic,v_previousemployerhra;

v_previousemployerbasic:=coalesce(v_previousemployerbasic,0);
v_previousemployerhra:=coalesce(v_previousemployerhra,0);

if exists(select 'x' 
			from public.inv_declr_duration_employee where financialyear=p_financial_year and employeecode=p_emp_code
			and active='1'
			and customeraccountid=(select customeraccountid from openappointments where emp_code=p_emp_code) 
			)
then
	select coalesce(declaration_or_proof,'D'),financialyear,proofapplicabledate,is_fianncialyearcompleted,openfrom 
	into v_declaration_or_proof,v_financial_year,v_proofapplicabledate,v_is_fianncialyearcompleted,v_openfrom 
	from public.inv_declr_duration_employee where financialyear=p_financial_year and employeecode=p_emp_code
	and active='1'
	and customeraccountid=(select customeraccountid from openappointments where emp_code=p_emp_code) ;
else
select declaration_or_proof,financialyear,proofapplicabledate,is_fianncialyearcompleted,openfrom into v_declaration_or_proof,v_financial_year,v_proofapplicabledate,v_is_fianncialyearcompleted,v_openfrom from public.inv_declr_duration where financialyear=p_financial_year 
and customeraccountid=(select customeraccountid from openappointments where emp_code=p_emp_code) ;
end if;

select coalesce(left_flag,'N'),nullif(trim(pancard),'') into v_leftflag,v_pancard from openappointments where emp_code=p_emp_code;

v_financial_year:=p_financial_year;

v_proofapplicabledate:=v_openfrom;								  
v_year1:=left(v_financial_year,4)::int;
v_year2:=right(v_financial_year,4)::int;
/****************change 1.4*******************************/
v_startdate:=to_date(v_year1::text||'-05-01','yyyy-mm-dd');
v_enddate:=to_date(v_year2::text||'-04-30','yyyy-mm-dd');

v_advancestartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_advanceenddate:=to_date(v_year1::text||'-04-30','yyyy-mm-dd');

if p_month>0 and p_year>0 then
 select DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE ) - INTERVAL '1 DAY')::date,
	DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;
end if;	
/****************change 1.4 ends here*******************************/
/****************change 1.6*******************************/
v_finyearstartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_finyearenddate:=to_date(v_year2::text||'-03-31','yyyy-mm-dd');
select emp_id,emp_code,left_flag,dateofrelieveing
from openappointments
where (emp_code=p_emp_code or pancard=v_pancard)
and appointment_status_id in(11,14) and converted='Y'
and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)
order by emp_id desc
limit 1
into v_lastempid,v_lastempcode,v_lastleftflag,v_lastdateofrelieving;
/****************change 1.6 ends here*******************************/
select emp_id,gender,cjcode
into v_empid,v_gender,v_cjcodeopen
from openappointments
where emp_code=v_lastempcode
and appointment_status_id<>13;

create temporary table tmpsalstructure
(
basic numeric(18,2),
hra numeric(18,2),
allowances numeric(18,2),
conv numeric(18,2),
medicalAllowance numeric(18,2),
effectivefrom date,
effectiveto date,
totalmonths int,
locationtype varchar(30),
otherdeductions  numeric(18,2),
commission numeric(18,2),
transport_allowance numeric(18,2),
travelling_allowance numeric(18,2),
leave_encashment numeric(18,2),
overtime_allowance numeric(18,2),
notice_pay numeric(18,2),
hold_salary_non_taxable numeric(18,2),
children_education_allowance numeric(18,2),
gratuityinhand numeric(18,2),
salarybonus numeric(18,2),
salaryids varchar(500),
mealvoucher numeric(18,2)
) on commit drop;

insert into tmpsalstructure
select basic,hra,allowances,conveyance_allowance,medical_allowance,effectivefrom,effectiveto,12,locationtype
,(select sum(deduction_amount) from trn_candidate_otherduction where candidate_id=v_empid 
  and trn_candidate_otherduction.salaryid=empsalaryregister.id
  and coalesce(includedinctc,'N')='Y'
	and deduction_id not in(5,6,7,12,10,134)--134 Meal Voucher ID
	and coalesce(isvariable,'N')='N'
	and deduction_frequency in ('Quarterly','Half Yearly','Annually')) as otherdeductions,
	commission,
    transport_allowance,
    travelling_allowance,
    leave_encashment,
    overtime_allowance,
    notice_pay,
    hold_salary_non_taxable,
    children_education_allowance,
    gratuityinhand,
    salarybonus 
	,id::text
---------------Added Meal Voucher --------------------------					  
,(select sum(deduction_amount) from trn_candidate_otherduction where candidate_id=v_empid
	and public.trn_candidate_otherduction.active='Y'
	and trn_candidate_otherduction.salaryid=empsalaryregister.id
	and deduction_amount>0
	and deduction_id=134 --Meal Voucher ID, Change for Production
) mealvoucher			  
----------------------------------------------------------------------	
from public.empsalaryregister
where isactive='1'
and appointment_id=v_lastempid
order by id desc
limit 1;

select e.is_exemptedfromtds from empsalaryregister e where e.id=(select t.salaryids::bigint from tmpsalstructure t) into v_is_exemptedfromtds;
v_mon1:=extract (month from current_date);
--v_mon1:=3;
if v_mon1 between  5 and 12 then
	v_mon1:=(12-v_mon1)+4;
else
	v_mon1:=(3-v_mon1)+1;
end if;
--Change 1.1
if extract (month from current_date)=4 then
	if extract (year from current_date)<v_year2 then
		v_mon1:=12;
	else
		v_mon1:=0;
	end if;
end if;	
if v_is_fianncialyearcompleted='C' then
    v_mon1:=0;
end if;
if v_leftflag='Y' then 
	v_mon1:=0;
end if;

--Change 1.1 ends
/****************************************************/
select coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0),coalesce(employeeepfrate,0),coalesce(vpfemployee,0),ptid
from openappointments op inner join empsalaryregister e on op.emp_id=e.appointment_id and op.emp_code=p_emp_code and e.isactive='1'
into v_insurance,v_pf,v_vpf,v_professionaltax,v_ptid;

if not exists(
	select *
from public.trn_investment
where  headid=1
and emp_code=p_emp_code
and financial_year=p_financial_year
and isactive='1'
and trn_investment.investment_id=5
and investment_amount>0) then
	v_insurance:=v_insurance*v_mon1;
else
	v_insurance:=0;
end if;
v_insurance:=coalesce(v_insurance,0)+coalesce(v_rec.insurance,0);

if not exists(	
select *
from public.trn_investment
where  headid=2
and emp_code=p_emp_code
and financial_year=p_financial_year
and isactive='1'
and trn_investment.investment_id=25
and investment_amount>0) then
	v_pf:=v_pf*v_mon1;
else
	v_pf:=0;
end if;

if not exists(
select *
from public.trn_investment
where  headid=2
and emp_code=p_emp_code
and financial_year=p_financial_year
and isactive='1'
and trn_investment.investment_id=26
and investment_amount>0) then
	v_vpf:=v_vpf*v_mon1;
else
	v_vpf:=0;
end if;
/****************************************************/
--Change 1.7 starts
if exists(select * from tbl_monthlysalary 
		  where emp_code=p_emp_code 
		  		and mprmonth=extract('month' from current_date)::int 
		  		and mpryear=extract('year' from current_date)::int
		 		and is_rejected='0'
		 		and recordscreen in ('Current Wages','Previous Wages')
		 		and paiddays>0) then
				
v_mon1:=v_mon1-1;				
v_mon1:=greatest(v_mon1,0);				
end if;				
--Change 1.7 ends
update tmpsalstructure set totalmonths=v_mon1;

if v_mon1=0 then
	update tmpsalstructure set salaryids=null;
end if;

select salaryids into v_activesalaryid from tmpsalstructure;

select  sum(basic+coalesce(incrementarear_basic,0)),
		sum(hra+coalesce(incrementarear_hra,0)),
		sum(coalesce(professionaltax,0))
		,sum(commission) commission
		,sum(transport_allowance) transport_allowance
		,sum(travelling_allowance) travelling_allowance
		,sum(leave_encashment) leave_encashment
		,sum(overtime_allowance) overtime_allowance
		,sum(notice_pay) notice_pay
		,sum(hold_salary_non_taxable) hold_salary_non_taxable
		,sum(children_education_allowance) children_education_allowance
		,sum(gratuityinhand) gratuityinhand
		,sum(salarybonus ) salarybonus ,sum(conv) conv,sum(specialallowance) specialallowance,sum(medical) medical
		,string_agg(salaryid::text,',')
		,sum(mealvoucher)
		into v_existingbasic,
		v_existinghra
		,v_professionaltax
		,v_existingcommission
		,v_existingtransport_allowance
		,v_existingtravelling_allowance
		,v_existingleave_encashment
		,v_existingovertime_allowance
		,v_existingnotice_pay
		,v_existinghold_salary_non_taxable
		,v_existingchildren_education_allowance
		,v_existinggratuityinhand
		,v_existingsalarybonus,v_existingconv,v_existingallowance,v_existingmedical_allowance
		,v_disbursedsalaryids
		,v_existingmealvoucher
from (select emp_code,basic,incrementarear_basic,hra,incrementarear_hra,isarear,recordscreen,hrgeneratedon,is_rejected,professionaltax,salaryid,  
	commission,
    transport_allowance,
    travelling_allowance,
    leave_encashment,
    overtime_allowance,
    notice_pay,
    hold_salary_non_taxable,
    children_education_allowance,
    gratuityinhand,
    salarybonus,conv,specialallowance,medical
	 ,mealvoucher
	   from tbl_monthlysalary
	 	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/))   and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1'  and
	  (isarear<>'Y' or recordscreen  in ('Previous Wages','Increment Arear','Arear Wages'))
		and 
	  (
	  ((
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	   and attendancemode<>'Ledger'
	   )
		or(to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')	between v_advancestartdate  and v_finyearenddate and attendancemode='Ledger')	  
	 )
	  	and not(mprmonth=4 and mpryear=v_year2)
		and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1'
		/*******************change 1.17 starts***************************************/
	union all
	  select emp_code,basic,incrementarear_basic,hra,incrementarear_hra,'N','Current Wages' recordscreen,hrgeneratedon,'0' is_rejected,professionaltax,salaryid,
	 commission,
    transport_allowance,
    travelling_allowance,
    leave_encashment,
    overtime_allowance,
    notice_pay,
    hold_salary_non_taxable,
    children_education_allowance,
    gratuityinhand,
    salarybonus,conv,specialallowance,medical
	 ,mealvoucher
		from paymentadvice
		where  p_isleft='Y'
		and (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' ))
	 	and (
			to_date(left(paymentadvice.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(paymentadvice.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	  	  and not(mprmonth=4 and mpryear=v_year2)
		/*******************change 1.17 ends***************************************/
		
	  union all
	  select emp_code,basic,incrementarear_basic,hra,incrementarear_hra,isarear,recordscreen,hrgeneratedon,is_rejected,professionaltax,salaryid,
	 commission,
    transport_allowance,
    travelling_allowance,
    leave_encashment,
    overtime_allowance,
    notice_pay,
    hold_salary_non_taxable,
    children_education_allowance,
    gratuityinhand,
    salarybonus,conv,specialallowance,medical
	,mealvoucher
		from tbl_monthly_liability_salary
		where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and 
	  coalesce(salary_remarks,'')<>'Invalid Paid Days'
		and coalesce(tbl_monthly_liability_salary.is_rejected,'0')='0'
	 	and (
			to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	  	  and not(mprmonth=4 and mpryear=v_year2)
	and (emp_code,mprmonth, mpryear, batchid) not in
	(select emp_code,mprmonth, mpryear, batchid 
		 from tbl_monthlysalary 
	 where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	 and coalesce(tbl_monthlysalary.is_rejected,'0')='0'
	)
	and (emp_code,mprmonth, mpryear, batchid) not in
	(select emp_code,mprmonth, mpryear, batchid ||coalesce(transactionid::text,'')
		 from tbl_monthlysalary where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	 and coalesce(is_rejected,'0')='0'
	) 
	and (mprmonth, mpryear, emp_code,batchid) not in 
	(select m.mprmonth, m.mpryear,  m.emp_code,trim(regexp_split_to_table(m.batchid,'','')) 
	 from tbl_monthlysalary m where (m.emp_code=p_emp_code or  m.emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and coalesce(m.is_rejected,'0')='0'
	and (
			to_date(left(m.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(m.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			))
	 )tbl_monthlysalary
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/))
and (isarear<>'Y' or recordscreen in ('Previous Wages','Arear Wages','Increment Arear'))
/*and to_date('01'||lpad(mprmonth::text,2,'0')||mpryear::text,'ddmmyyyy')
between to_date(v_year1||'-04-01','yyyy-mm-dd') and least((DATE_TRUNC('MONTH', current_date) - INTERVAL '1 DAY'),to_date(v_year2||'-03-31','yyyy-mm-dd')) 
*/
and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1';

select sum(tds)
,sum(case when p_month>0 and p_year>0 then
	case when 
	 (
						(
							to_date(left(hrgeneratedon,11),'dd Mon yyyy')
							between v_salstartdate  and v_salenddate
							and to_date((mpryear::text||'-'||lpad(mprmonth::text,2,'0')||'-01'),'yyyy-mm-dd')<v_salstartdate
						)
					or
						(	
						to_date(left(hrgeneratedon,11),'dd Mon yyyy')
						 between v_advancesalstartdate  and v_advancesalenddate	
							and mprmonth=p_month and mpryear=p_year
						)
			)
	 then tds else 0 end
	else 0 end) 
,sum(grossearning-coalesce(voucher_amount,0)/*+coalesce(vpf,0)*/)   -- Added on 23 Oct 2021 with disucssion with Account Team
,sum(otherdeductions)
into v_taxdeducted
,v_currentmonthtaxdeducted  --change 1.3
,v_existinggrossearning,
v_existingotherdeductions
from (select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear
	  from tbl_monthlysalary
	 where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/))   and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1' and (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	  	  	and not(mprmonth=4 and mpryear=v_year2)
		and coalesce(is_rejected,'0')<>'1'
	  
	 union all
	  select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear
	from tbl_monthly_liability_salary
	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and coalesce(salary_remarks,'')<>'Invalid Paid Days'
	and coalesce(is_rejected,'0')='0'
	  	 and not(mprmonth=4 and mpryear=v_year2)
	  	 and (
			to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
-----------------------------------------------------------------------	  
	and (emp_code,mprmonth, mpryear, batchid) not in
	  (
	(select emp_code,mprmonth, mpryear, batchid 
		 from tbl_monthlysalary 
	 	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	 and coalesce(is_rejected,'0')='0'
	)
union all
	--and (emp_code,mprmonth, mpryear, batchid) not in
	(select emp_code,mprmonth, mpryear, batchid ||coalesce(transactionid::text,'')
		 from tbl_monthlysalary where  (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and(
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	 and coalesce(is_rejected,'0')='0'
	) 
	 
-------------------------------------------------------	  
	--and (mprmonth, mpryear, emp_code,batchid) not in 
		  union all
	(select m.mprmonth, m.mpryear,  m.emp_code,trim(regexp_split_to_table(m.batchid,'','')) 
	 from tbl_monthlysalary m where (m.emp_code=p_emp_code or  m.emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/)) and coalesce(m.is_rejected,'0')='0'
	and (
			to_date(left(m.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(m.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and m.mprmonth=4 and m.mpryear=v_year1
				 )
			))
		  )
	 )tbl_monthlysalary
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' /*and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)*/))
--and (isarear<>'Y' or recordscreen ='Previous Wages')
/*and to_date('01'||lpad(mprmonth::text,2,'0')||mpryear::text,'ddmmyyyy')
between to_date(v_year1||'-04-01','yyyy-mm-dd') and least((DATE_TRUNC('MONTH', current_date) - INTERVAL '1 DAY'),to_date(v_year2||'-03-31','yyyy-mm-dd'))*/  
and coalesce(is_rejected,'0')<>'1';

v_taxdeducted:=coalesce(v_taxdeducted,0);
v_professionaltax:=coalesce(v_professionaltax,0);

/*****************************************************/
    select  tr.investment_amount 
    from public.trn_investment tr
    where emp_code=p_emp_code 
    and headid=8 
    and financial_year=p_financial_year 
    and investment_id=50 
    and tr.isactive='1'
    into v_professionaltax;
v_professionaltax:=coalesce(v_professionaltax,0);    
/*****************************************************/
select sum(
(coalesce(basic,0)+coalesce(hra,0)+coalesce(allowances,0)
+coalesce(conv,0)+coalesce(medicalallowance,0)-coalesce(otherdeductions,0)
+coalesce(commission,0)
+coalesce(transport_allowance,0)
+coalesce(travelling_allowance,0)
+coalesce(leave_encashment,0)
+coalesce(overtime_allowance,0)
+coalesce(notice_pay,0)
+coalesce(hold_salary_non_taxable,0)
+coalesce(children_education_allowance,0)
+coalesce(gratuityinhand,0)
+coalesce(salarybonus,0)+coalesce(mealvoucher,0))*totalmonths
)+coalesce(v_existinggrossearning,0)-
coalesce(v_existingotherdeductions,0)
+coalesce(v_existingmealvoucher,0),
sum(basic*totalmonths)+coalesce(v_existingbasic,0),sum(hra*totalmonths)+coalesce(v_existinghra,0),max(locationtype),
SUM(commission * totalmonths) + COALESCE(v_existingcommission, 0),
SUM(transport_allowance * totalmonths) + COALESCE(v_existingtransport_allowance, 0),
SUM(travelling_allowance * totalmonths) + COALESCE(v_existingtravelling_allowance, 0),
SUM(leave_encashment * totalmonths) + COALESCE(v_existingleave_encashment, 0),
SUM(overtime_allowance * totalmonths) + COALESCE(v_existingovertime_allowance, 0),
SUM(notice_pay * totalmonths) + COALESCE(v_existingnotice_pay, 0),
SUM(hold_salary_non_taxable * totalmonths) + COALESCE(v_existinghold_salary_non_taxable, 0),
SUM(children_education_allowance * totalmonths) + COALESCE(v_existingchildren_education_allowance, 0),
SUM(gratuityinhand * totalmonths) + COALESCE(v_existinggratuityinhand, 0),
SUM(salarybonus * totalmonths) + COALESCE(v_existingsalarybonus, 0),
SUM(conv * totalmonths) + COALESCE(v_existingconv , 0),
SUM(allowances * totalmonths) + COALESCE(v_existingallowance , 0),
SUM(medicalAllowance * totalmonths) + COALESCE(v_existingmedical_allowance , 0),
SUM(coalesce(mealvoucher,0) * totalmonths) + COALESCE(v_existingmealvoucher , 0)
into v_totalincome,v_basic,v_hra,v_locationtype,
v_commission,
v_transport_allowance,
v_travelling_allowance,
v_leave_encashment,
v_overtime_allowance,
v_notice_pay,
v_hold_salary_non_taxable,
v_children_education_allowance,
v_gratuityinhand,
v_salarybonus,
v_conv,
v_allowances,
v_medicalallowance,
v_mealvoucher
from tmpsalstructure;

v_metrononmetrohra:=case when upper(v_locationtype)='METRO' then v_basic*0.5 else v_basic*0.4 end;
/****************change 1.5 starts here*******************************/
select LAST_VALUE (cjcode)  OVER (PARTITION BY empcode  ORDER BY deputeddate  DESC) into v_cjcode			 
			 from public.cmsdownloadedwages
			 where (cmsdownloadedwages.empcode::bigint=p_emp_code or  cmsdownloadedwages.empcode::bigint in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)))
			and cmsdownloadedwages.attendancemode='MPR'
			 and isactive='1'
			 and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y')<>'N'
			LIMIT 1;
/****************change 1.5 ends here*******************************/
---------------------------------
-- if exists(select *
-- 	from empdeclaration_rentdetails
-- 	where emp_code=p_emp_code
--  	and financial_year=v_financial_year
--  	and isactive='1'
--  	and approval_status='A') 
-- then

	select sum(rentpaid) into v_rentpaid
	from empdeclaration_rentdetails
	where emp_code=v_lastempcode
	 and financial_year=v_financial_year
	 and isactive='1'
	 and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then 'A' else coalesce(approval_status,'P') end;
	 --and approval_status='A';
--  else
-- 	select sum(rentpaid) into v_rentpaid
-- 	from empdeclaration_rentdetails
-- 	where emp_code=p_emp_code
-- 	 and financial_year=v_financial_year
-- 	 and isactive='1';

-- end if;
-------------------------------------------------------------------------------

v_hraexemption:=least((v_hra+v_previousemployerhra+coalesce(v_rec.hra,0)),v_metrononmetrohra,greatest(v_rentpaid-(v_basic+v_previousemployerbasic+coalesce(v_rec.basic,0))*.10,0));

 select sum(total_income),sum(tds) 
 into v_incomepreviousemployer,v_previousemployertax
 from public.empdeclr_prevemployerinc_dtls
 where emp_code=v_lastempcode
 and financial_year=v_financial_year
 and active='1'
 and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then 'A' else coalesce(approval_status,'P') end;
 
 v_incomepreviousemployer:=coalesce(v_incomepreviousemployer,0);
 v_previousemployertax:=coalesce(v_previousemployertax,0);
 
 v_taxdeducted:=coalesce(v_taxdeducted,0)+coalesce(v_previousemployertax,0)+coalesce(v_rec.tds,0);
 
 select netincomefromhouse
 into v_letoutpropertyincome
 from public.empdeclr_letoutpropertyincome
 where emp_code=v_lastempcode
 and financial_year=v_financial_year
 and active='1';
 
 
 select interest_on_borrowed_capital,isbefore01apr1999
 into v_lossonproperty,v_isbefore01apr1999
 from public.empdeclr_homeloan
 where emp_code=v_lastempcode
 and financial_year=v_financial_year
 and active='1'
 and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then 'A' else coalesce(approval_status,'P') end;
 --and coalesce(approval_status,'P')='A';--Added for change 1.2
 
 if coalesce(v_isbefore01apr1999,'N')='Y' then
 	v_lossonproperty:=least(30000, coalesce(v_lossonproperty,0));
 else
    v_lossonproperty:=least(200000, coalesce(v_lossonproperty,0));
 end if;

 
select  incomefromothersources,businessincome,incomefromcapitalgains
,anyotherincome,interestonsavingbank,tds_others
 into v_incomefromothersources,
v_businessincome,
v_incomefromcapitalgains,
v_anyotherincome,
v_interestonsavingbank,
v_tds_others
from public.empdeclr_otherincome_dtls
where emp_code=v_lastempcode
 and financial_year=v_financial_year
 and active='1';

 ---------------------------------------------
 if p_regime='New' then
 v_totalincome:=v_totalincome
+coalesce(v_incomepreviousemployer,0)
+coalesce(v_rec.grossearning,0);
else
v_totalincome:=v_totalincome
 +coalesce(v_incomepreviousemployer,0)
 +coalesce(v_rec.grossearning,0);
end if;
-----------------------------------------------
--v_totalincome:=785000;
-----------------------------------------------
if v_customeraccountid=7416 then
		select salary_head_text 
		into v_salary_head_text 
		from mst_tp_business_setups 
		where tp_account_id=v_customeraccountid::bigint and row_status='1';
	create temporary table tmp_flexilimit on commit drop
	as
	with tmpcomponent as
	(
		select *  from jsonb_populate_recordset(null::record,v_salary_head_text::jsonb)
		as 
			( 
		       id text ,
		       earningtype text ,
		       componentname text,
		       calculationtype text ,
		       calculationbasis text ,
		       epfapplicable text ,
		       esiapplicable text ,
		       calculationpercent numeric(18,2),
		       isactive text ,
		       displayorder int ,
			  includedingross text,
			  gratuityapplicable text,
			  formula_sign text,
			  formula_value text,
			  custom_formula_basis text
			)
			where isactive='Y'	
		),
	tmp1 as
	(
	select tmpcomponent.componentname,(replace(replace(replace(lower(componentname),' ','_'),'(',''),')','')) as newcomponentname 
		from tmpcomponent inner join mst_investment_section
		on tmpcomponent.earningtype=mst_investment_section.investmentname
		and mst_investment_section.headid=10 
		and mst_investment_section.id<>58
	)
	select * from tmp1;

    SELECT string_agg('SUM(' || quote_ident(replace(newcomponentname,'conveyance','conv')) || ') AS ' || quote_ident(newcomponentname), ', ')
    INTO v_sum_list
    FROM tmp_flexilimit;

    v_sql := ' create temporary table tmp2 on commit drop as
    WITH salary_data AS (
        SELECT *
        FROM (
             SELECT emp_code, basic, incrementarear_basic, hra, incrementarear_hra, isarear, recordscreen, hrgeneratedon, is_rejected, professionaltax, salaryid,  
                    commission, transport_allowance, travelling_allowance, leave_encashment, overtime_allowance, notice_pay, hold_salary_non_taxable, 
                    children_education_allowance, gratuityinhand, salarybonus, conv, specialallowance, medical
             FROM tbl_monthlysalary
             WHERE emp_code = $1 
               AND COALESCE(tbl_monthlysalary.istaxapplicable, ''1'') = ''1'' 
               AND (isarear <> ''Y'' OR recordscreen IN (''Previous Wages'', ''Increment Arear'', ''Arear Wages''))
               AND (
                   (
                       (TO_DATE(LEFT(tbl_monthlysalary.hrgeneratedon, 11), ''dd Mon yyyy'') BETWEEN $2 AND $3
                        OR (
                            TO_DATE(LEFT(tbl_monthlysalary.hrgeneratedon, 11), ''dd Mon yyyy'') BETWEEN $4 AND $5
                            AND mprmonth = 4 AND mpryear = $6
                        ))
                       AND attendancemode <> ''Ledger''
                   )
                   OR (TO_DATE(LEFT(tbl_monthlysalary.hrgeneratedon, 11), ''dd Mon yyyy'') BETWEEN $4 AND $7 AND attendancemode = ''Ledger'')
               )
               AND NOT (mprmonth = 4 AND mpryear = $8)
               AND COALESCE(tbl_monthlysalary.is_rejected, ''0'') <> ''1''
             
             UNION ALL
             
             SELECT emp_code, basic, incrementarear_basic, hra, incrementarear_hra, ''N'', ''Current Wages'' recordscreen, hrgeneratedon, ''0'' is_rejected, professionaltax, salaryid,
                    commission, transport_allowance, travelling_allowance, leave_encashment, overtime_allowance, notice_pay, hold_salary_non_taxable, 
                    children_education_allowance, gratuityinhand, salarybonus, conv, specialallowance, medical
             FROM paymentadvice
             WHERE $9 = ''Y'' -- p_isleft
               AND emp_code = $1
               AND (
                   TO_DATE(LEFT(paymentadvice.hrgeneratedon, 11), ''dd Mon yyyy'') BETWEEN $2 AND $3
                   OR (
                       TO_DATE(LEFT(paymentadvice.hrgeneratedon, 11), ''dd Mon yyyy'') BETWEEN $4 AND $5
                       AND mprmonth = 4 AND mpryear = $6
                   )
               )
               AND NOT (mprmonth = 4 AND mpryear = $8)
        ) tbl_monthlysalary
        WHERE emp_code = $1
          AND (isarear <> ''Y'' OR recordscreen IN (''Previous Wages'', ''Arear Wages'', ''Increment Arear''))
          AND COALESCE(is_rejected, ''0'') <> ''1''
    ),
    -- Aggregated CTE: Calculates all sums in a single row
    aggregated_totals AS (
        SELECT ' || v_sum_list || '
        FROM salary_data
    )
    -- Final SELECT: Unpivots the single row to match tmp_flexilimit rows
    SELECT 
        t1.componentname,
        t1.newcomponentname,
        COALESCE((jsonb_extract_path_text(to_jsonb(agg), t1.newcomponentname))::numeric, 0) as total_amount
    FROM tmp_flexilimit t1
    CROSS JOIN aggregated_totals agg';
Raise Notice 'v_sum_list=%',v_sum_list;
Raise Notice 'v_sum_list=%',v_sql;

    -- 3. Execute the query
    -- Using RETURN QUERY if this is inside a function returning SETOF ...
    EXECUTE v_sql 
    USING p_emp_code,          -- $1
          v_startdate,        -- $2
          v_enddate,          -- $3
          v_advancestartdate, -- $4
          v_advanceenddate,   -- $5
          v_year1,            -- $6
          v_finyearenddate,   -- $7
          v_year2,            -- $8
          p_isleft;           -- $9
 /********change 1.13 starts***************/
select
sum(least(coalesce(total_amount,0),coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0)))
into v_flexocomponents
from trn_investment
inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and trn_investment.headid=10
and trn_investment.isactive='1'
and trn_investment.emp_code=v_lastempcode
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id<>58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
left join tmp2 on tmp2.newcomponentname=mst_investment_section.investmentname
--group by investment_id
;
else

select
sum(least(coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0)))
into v_flexocomponents
from trn_investment
inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and trn_investment.headid=10
and trn_investment.isactive='1'
and trn_investment.emp_code=v_lastempcode
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id<>58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
--group by investment_id
;
end if; 

v_flexocomponents:=coalesce(v_flexocomponents,0);

select
sum(least(coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0)))
into v_lta
from trn_investment
inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and trn_investment.headid=10
and trn_investment.isactive='1'
and trn_investment.emp_code=v_lastempcode
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id=58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
group by investment_id;
 
v_projectedalaryids:=coalesce(v_projectedalaryids,'')||coalesce(','||v_activesalaryid,'');
--Raise notice 'v_projectedalaryids=%',v_projectedalaryids;
select basic from empsalaryregister 
		where id =(select  max(a) from (
							select unnest(string_to_array(trim(v_projectedalaryids,','), ','))::integer as a)tmp
				  )
into v_onemonthbasic;
v_onemonthbasic:=coalesce(v_onemonthbasic,0);
v_lta:=coalesce(v_lta,0);
v_lta:=least(v_lta,v_basic,v_onemonthbasic);

v_flexocomponents:=v_flexocomponents+v_lta;
  /********Added for change 1.13 ends***************/

select
sum(case when mst_investment_section.id in (11,52) then coalesce(investment_amount,0)
   when mst_investment_section.id =51 then coalesce(investment_amount,0)*.50
      when mst_investment_section.id =5 then least(coalesce(investment_amount,0)+coalesce(v_insurance,0),coalesce(max_limit,coalesce(investment_amount,0)+coalesce(v_insurance,0),0))
	else
	least(coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0))
   end)into v_chapter6deductions
from( select investment_id,sum(investment_amount) investment_amount
	 from (select case when  investment_id=1 then 5 else investment_id end as investment_id,investment_amount
	   from trn_investment
where  trn_investment.emp_code=v_lastempcode
 and trn_investment.financial_year=v_financial_year
 and trn_investment.isactive='1'
 and trn_investment.headid=1
 and coalesce(approval_status,'P')= case when trn_investment.investment_id in (5) then 'A' when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
  ) trn_investment
	 group by investment_id
) trn_investment
 
 inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and mst_investment_section.isactive='1';
  /********Added for change 1.10 ends***************/
 v_chapter6deductions:=coalesce(v_chapter6deductions,0);
 v_chapter6deductions:=v_chapter6deductions+coalesce(v_insurance,0);

select sum(investment_amount)
into v_us80cdeductions
from public.trn_investment
where  headid=2
and emp_code=v_lastempcode
and financial_year=v_financial_year
and isactive='1'
and trn_investment.investment_id not in (/*23,*/24) --Added on 02-Apr-2022
and coalesce(approval_status,'P')= case when trn_investment.investment_id in (25,26) then 'A'  when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end;
--and coalesce(approval_status,'P')='A';--Added for change 1.2
--Added for 80ccd dated 22 oct2021
select sum(investment_amount)
into v_us80ccd_deductions
from public.trn_investment
where  headid=2
and emp_code=v_lastempcode
and financial_year=v_financial_year
and isactive='1'
and trn_investment.investment_id=24
and coalesce(approval_status,'P')= case when trn_investment.investment_id in (25,26) then 'A' when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end;
--and coalesce(approval_status,'P')='A';--Added for change 1.2
--Added for 80ccd dated 22 oct2021 end here
v_us80ccd_deductions:=case when coalesce(v_us80ccd_deductions,0)>50000 then 50000 else coalesce(v_us80ccd_deductions,0) end;--Added on 02-Apr-2022

v_us80cdeductions:=coalesce(v_us80cdeductions,0)+coalesce(v_pf,0)+coalesce(v_vpf,0)+coalesce(v_rec.pf,0)+coalesce(v_rec.vpf,0);
 
v_us80cdeductions:=least(coalesce(v_us80cdeductions,0),150000);
/****************change 1.11 starts*******************************/

-- Calculation of standard deduction Dyanamic
SELECT configvalue INTO v_standard_deduction
FROM mst_taxrebates 
WHERE financial_year = p_financial_year AND regimetype = p_regime AND configname = 'standard_deduction' 
AND isactive = '1'
LIMIT 1;
v_standard_deduction:=coalesce(v_standard_deduction,0);

SELECT configvalue INTO v_health_education_cess
FROM mst_taxrebates 
WHERE financial_year = p_financial_year AND regimetype = p_regime AND configname = 'healtheducess' 
AND isactive = '1'
LIMIT 1;
v_health_education_cess:=coalesce(v_health_education_cess,0);

		if p_regime='New' then
			v_totalsavings:=v_standard_deduction;
		else
			v_totalsavings:=coalesce(v_lossonproperty,0)+v_chapter6deductions+v_us80cdeductions+v_standard_deduction+v_hraexemption+coalesce(v_us80ccd_deductions,0)+coalesce(v_professionaltax,0)+coalesce(v_flexocomponents,0)+coalesce(v_mealvoucher,0);
		end if;
		
		v_taxableincome:=v_totalincome+coalesce(v_mealvoucher,0);
		v_taxableincome:=v_totalincome-v_totalsavings;
		v_taxableincome:=greatest(v_taxableincome,0);
		
		select sum(tax)	INTO v_taxonincome
		from(	
			SELECT (least(t.taxableincometo,v_taxableincome)-(coalesce(LAG(taxableincometo, 1) OVER (ORDER BY id),0)))* t.taxrate / 100.0 as tax
			FROM mst_taxslabs t
			WHERE t.financial_year = p_financial_year and t.configname = 'TaxRate' and t.isactive = '1'
			AND t.regimetype = p_regime
			and v_taxableincome>=t.taxableincomefrom
		)tmp;	
		
		v_taxonincome:=round(coalesce(v_taxonincome,0),0);
/*************Surcharge Block**********************/

/*************Tax Marginal Relief Block**********************/
		v_tax_marginal_relief:=0;
		SELECT * into v_rec_taxmarginalrelief
		FROM public.mst_taxrebates
		WHERE financial_year = p_financial_year AND regimetype = p_regime AND configname = 'taxmarginalrelief' 
		and v_taxableincome between min_income_limit and max_income_limit 
			and v_taxonincome>(v_taxableincome-min_income_limit)
		AND isactive = '1'
		LIMIT 1;

		if v_rec_taxmarginalrelief.id is not null 
			 then
				v_tax_marginal_relief:=v_taxonincome-(v_taxableincome- v_rec_taxmarginalrelief.min_income_limit);
		end if;
		v_tax_marginal_relief:=greatest(v_tax_marginal_relief,0);
		v_taxonincome:=v_taxonincome-v_tax_marginal_relief;		
/*************Tax Marginal Relief Block ends**********************/

if coalesce(v_is_exemptedfromtds,'N')='Y' then
v_taxonincome:=0;
end if;
/*************Surcharge And Marginal Relief Block**********************/
		SELECT * INTO v_rec_surcharge_rate 
		FROM public.mst_taxslabs
		WHERE financial_year = p_financial_year
		  AND regimetype = p_regime
		  AND v_taxableincome BETWEEN taxableincomefrom AND taxableincometo
		  AND configname = 'Surcharge' and isactive = '1'
		LIMIT 1;

if coalesce(v_rec_surcharge_rate.taxrate,0)>0 then

		v_surcharge_rate:=coalesce(v_rec_surcharge_rate.taxrate,0);
		v_surcharge_rate:=coalesce(v_surcharge_rate,0);
		v_surcharge := ROUND(v_taxonincome * COALESCE(v_surcharge_rate, 0) / 100, 0);
		v_surcharge:=coalesce(v_surcharge,0);
		v_presurcharge:=v_surcharge;
		if coalesce(v_rec_surcharge_rate.marginal_relief_applicable,'0')='1' then
	
		select sum(tax)	INTO v_thresholdvalue
		from(	
			SELECT (least(t.taxableincometo,coalesce(v_rec_surcharge_rate.taxableincomefrom-1,0))-(coalesce(LAG(taxableincometo, 1) OVER (ORDER BY id),0)))* t.taxrate / 100.0 as tax
			FROM mst_taxslabs t
			WHERE t.financial_year = p_financial_year and t.configname = 'TaxRate' and t.isactive = '1'
			AND t.regimetype = p_regime
			and coalesce(v_rec_surcharge_rate.taxableincomefrom-1,0)>=t.taxableincomefrom
		)tmp;
	
	

			SELECT max(t.taxrate) into v_thresholdsurchargerate
			FROM mst_taxslabs t
			WHERE t.financial_year = p_financial_year and t.configname = 'Surcharge' and t.isactive = '1'
			AND t.regimetype = p_regime
			and coalesce(v_rec_surcharge_rate.taxableincomefrom-1,0)>=t.taxableincomefrom;
			v_thresholdsurchargerate:=coalesce(v_thresholdsurchargerate,0);
		
		v_thresholdvalue:=coalesce(v_thresholdvalue,0);
		v_marginal_relief:=(v_taxonincome+v_surcharge-v_thresholdvalue*(100+coalesce(v_thresholdsurchargerate,0))/100.0)-(v_taxableincome-coalesce(v_rec_surcharge_rate.taxableincomefrom-1,0));
end if;
end if;
v_marginal_relief:=coalesce(v_marginal_relief,0);						
v_marginal_relief:=greatest(v_marginal_relief,0);						
v_surcharge:=ROUND(greatest(v_surcharge-v_marginal_relief),0);
/*************Surcharge and Marginal Relief Block ends**********************/
				
SELECT * into v_recus87a
FROM public.mst_taxrebates
WHERE financial_year = p_financial_year AND regimetype = p_regime AND configname = 'us87a' 
AND isactive = '1' LIMIT 1;

v_us87a12500:=case when v_taxableincome<=coalesce(v_recus87a.max_income_limit,0) then least(v_taxonincome,coalesce(v_recus87a.max_rebate_amount,0)) else 0 end;
v_pretaxonincome:=coalesce(v_taxonincome,0)-coalesce(v_us87a12500,0)+coalesce(v_surcharge,0);
v_healtheducess:=ROUND(v_pretaxonincome*coalesce(v_health_education_cess,0),0);
v_netpayabletax:=(v_pretaxonincome+v_healtheducess);
v_balancetax:=greatest(coalesce(v_netpayabletax-v_taxdeducted,0),0);

SELECT taxslab INTO v_taxslab 
FROM mst_taxslabs 
WHERE financial_year = p_financial_year	AND regimetype = p_regime
AND isactive = '1' and configname = 'TaxRate'
AND v_taxableincome BETWEEN taxableincomefrom AND taxableincometo;
-------------------------------------------------

/*if v_year2>2024 then
		if p_regime='New' then
			v_totalsavings:=75000;
		else
			v_totalsavings:=coalesce(v_lossonproperty,0)+v_chapter6deductions+v_us80cdeductions+50000+v_hraexemption+coalesce(v_us80ccd_deductions,0)+coalesce(v_professionaltax,0)+coalesce(v_flexocomponents,0);
		end if;

		v_taxableincome:=v_totalincome-v_totalsavings;
		v_taxableincome:=greatest(v_taxableincome,0);

			if p_regime::text='New'::text then
					v_taxonincome:=ROUND(case when v_taxableincome<=300000 then 0
										when v_taxableincome<=700000 then (v_taxableincome-300000)*5/100
										when v_taxableincome<=1000000 then (v_taxableincome-700000)*10/100+20000
										when v_taxableincome<=1200000 then (v_taxableincome-1000000)*15/100+50000
										when v_taxableincome<=1500000 then (v_taxableincome-1200000)*20/100+80000
										when v_taxableincome>=1500000 then (v_taxableincome-1500000)*30/100+140000 end,0);
			else

						v_taxonincome:=ROUND(
						case when v_taxableincome<=250000 then 0 else
						  case when v_taxableincome<=500000 then (v_taxableincome-250000)*.05 else
						 case when v_taxableincome<=1000000 then (v_taxableincome-500000)*.2+12500 else
						(v_taxableincome-1000000)*.3+112500
						 end
						  end
						end
						,0);
			end if;

			v_taxableincome:=coalesce(v_taxableincome,0);
		/****************change 1.9 starts*******************************/	
		if p_regime='New' and v_taxableincome between 700000 and 797222 and v_taxonincome>(v_taxableincome-700000) then
			v_marginal_reliefsmall:=v_taxonincome-(v_taxableincome-700000);
		else
			v_marginal_reliefsmall:=0;
		end if;
		v_marginal_reliefsmall:=greatest(v_marginal_reliefsmall,0);
		v_taxonincome:=v_taxonincome-v_marginal_reliefsmall;
		/****************change 1.9 ends*******************************/
			v_surcharge:=ROUND(case when coalesce(v_taxableincome,0)<=5000000 then 0
									when coalesce(v_taxableincome,0)<=10000000 then v_taxonincome*10.0/100
									when coalesce(v_taxableincome,0)<=20000000 then v_taxonincome*15.0/100 end
								,0);

				v_presurcharge:=v_surcharge;

				if p_regime::text='New'::text then
				       if v_year2<=2024 then
						v_marginal_relief:=case when coalesce(v_taxableincome,0)<=5000000 then 0
										else ROUND(greatest((v_taxonincome+v_surcharge-1200000)-(v_taxableincome-5000000)),0)
										end;
						else
						v_marginal_relief:=round(case when v_taxableincome>=1000000 then
								(case when ROUND(v_taxonincome)+ROUND(v_surcharge)-ROUND(1190000)-(case when v_taxableincome>=5000000 then v_taxableincome-5000000 else 0 end ) >=0  then ROUND(v_taxonincome)+ROUND(v_surcharge)-ROUND(1190000)-(case when v_taxableincome>=5000000 then v_taxableincome-5000000 else 0 end) else (case when ROUND(v_taxonincome)+ROUND(v_surcharge)-ROUND(269000)-ROUND(269000)-(case when v_taxableincome>=10000000 then v_taxableincome-10000000 else 0 end)>=0 then ROUND(v_taxonincome)+ROUND(v_surcharge)-ROUND(2690000)-ROUND(269000)-(case when v_taxableincome>=10000000 then v_taxableincome-10000000 else 0 end) else 0 end) end)
								 else 0 end);
						--Raise notice 'taxonincome=% v_surcharge=% marginal_relief=%',v_taxonincome,v_surcharge,v_marginal_relief;				
						end if;	
				else

						v_marginal_relief:=case when coalesce(v_taxableincome,0)<=5000000 then 0
										else ROUND(greatest((v_taxonincome+v_surcharge-1312500)-(v_taxableincome-5000000)),0)
										end;
				end if;

				v_marginal_relief:=greatest(v_marginal_relief,0);						
				v_surcharge:=ROUND(greatest(v_surcharge-v_marginal_relief),0);

				if p_regime::text='New'::text then
					v_us87a12500:=case when v_taxableincome<=700000 then least(v_taxonincome,25000) else 0 end;
				else
					v_us87a12500:=case when v_taxableincome<=500000 then least(v_taxonincome,12500) else 0 end;
				end if;

				v_pretaxonincome:=coalesce(v_taxonincome,0)-coalesce(v_us87a12500,0)+coalesce(v_surcharge,0);
				v_healtheducess:=ROUND(v_pretaxonincome*.04,0);

				v_netpayabletax:=(v_pretaxonincome+v_healtheducess);

				v_balancetax:=greatest(coalesce(v_netpayabletax-v_taxdeducted,0),0);
				if p_regime::text='New'::text then
				v_taxslab:=case 
							 when v_taxableincome<=300000 then 'Nil' 
							 when v_taxableincome<=700000 then '5' 
							 when v_taxableincome<=1000000 then '10'
							 when v_taxableincome<=1200000 then '15' 
							 when v_taxableincome<=1500000 then '20' 
							 else
							'30'
						end;
				else
						v_taxslab:=case when v_taxableincome<=250000 then 'Nil'
							 when v_taxableincome<=500000 then '5' 
							 when v_taxableincome<=1000000 then '20' else
							'30'
						end;

				end if;
/****************change 1.11 ends*******************************/
/****************change 1.8 starts*******************************/
elsif v_year2>2023 then
		if p_regime='New' then
			v_totalsavings:=50000;
		else
			v_totalsavings:=coalesce(v_lossonproperty,0)+v_chapter6deductions+v_us80cdeductions+50000+v_hraexemption+coalesce(v_us80ccd_deductions,0)+coalesce(v_professionaltax,0);
		end if;

		v_taxableincome:=v_totalincome-v_totalsavings;
		v_taxableincome:=greatest(v_taxableincome,0);

			if p_regime::text='New'::text then
					v_taxonincome:=ROUND(case when v_taxableincome<=300000 then 0
										when v_taxableincome<=600000 then (v_taxableincome-300000)*5/100
										when v_taxableincome<=900000 then (v_taxableincome-600000)*10/100+15000
										when v_taxableincome<=1200000 then (v_taxableincome-900000)*15/100+45000
										when v_taxableincome<=1500000 then (v_taxableincome-1200000)*20/100+90000
										when v_taxableincome>=1500000 then (v_taxableincome-1500000)*30/100+150000 end,0);
			else

						v_taxonincome:=ROUND(
						case when v_taxableincome<=250000 then 0 else
						  case when v_taxableincome<=500000 then (v_taxableincome-250000)*.05 else
						 case when v_taxableincome<=1000000 then (v_taxableincome-500000)*.2+12500 else
						(v_taxableincome-1000000)*.3+112500
						 end
						  end
						end
						,0);
			end if;

			v_taxableincome:=coalesce(v_taxableincome,0);
		/****************change 1.9 starts*******************************/	
		if p_regime='New' and v_taxableincome between 700000 and 727778 and v_taxonincome>(v_taxableincome-700000) then
			v_marginal_reliefsmall:=v_taxonincome-(v_taxableincome-700000);
		else
			v_marginal_reliefsmall:=0;
		end if;
		v_marginal_reliefsmall:=greatest(v_marginal_reliefsmall,0);
		v_taxonincome:=v_taxonincome-v_marginal_reliefsmall;
		/****************change 1.9 ends*******************************/
			v_surcharge:=ROUND(case when coalesce(v_taxableincome,0)<=5000000 then 0
									when coalesce(v_taxableincome,0)<=10000000 then v_taxonincome*10.0/100
									when coalesce(v_taxableincome,0)<=20000000 then v_taxonincome*15.0/100 end
								,0);

				v_presurcharge:=v_surcharge;

				if p_regime::text='New'::text then
						v_marginal_relief:=case when coalesce(v_taxableincome,0)<=5000000 then 0
										else ROUND(greatest((v_taxonincome+v_surcharge-1200000)-(v_taxableincome-5000000)),0)
										end;
				else

						v_marginal_relief:=case when coalesce(v_taxableincome,0)<=5000000 then 0
										else ROUND(greatest((v_taxonincome+v_surcharge-1312500)-(v_taxableincome-5000000)),0)
										end;
				end if;

				v_marginal_relief:=greatest(v_marginal_relief,0);						
				v_surcharge:=ROUND(greatest(v_surcharge-v_marginal_relief),0);

				if p_regime::text='New'::text then
					v_us87a12500:=case when v_taxableincome<=700000 then least(v_taxonincome,25000) else 0 end;
				else
					v_us87a12500:=case when v_taxableincome<=500000 then least(v_taxonincome,12500) else 0 end;
				end if;

				v_pretaxonincome:=coalesce(v_taxonincome,0)-coalesce(v_us87a12500,0)+coalesce(v_surcharge,0);
				v_healtheducess:=ROUND(v_pretaxonincome*.04,0);

				v_netpayabletax:=(v_pretaxonincome+v_healtheducess);

				v_balancetax:=greatest(coalesce(v_netpayabletax-v_taxdeducted,0),0);
				if p_regime::text='New'::text then
				v_taxslab:=case 
							 when v_taxableincome<=300000 then 'Nil' 
							 when v_taxableincome<=600000 then '5' 
							 when v_taxableincome<=900000 then '10'
							 when v_taxableincome<=1200000 then '15' 
							 when v_taxableincome<=1500000 then '20' 
							 else
							'30'
						end;
				else
						v_taxslab:=case when v_taxableincome<=250000 then 'Nil'
							 when v_taxableincome<=500000 then '5' 
							 when v_taxableincome<=1000000 then '20' else
							'30'
						end;

				end if;
else
/****************change 1.8 ends*******************************/
if p_regime='New' then
v_totalsavings:=0;--50000;
else
v_totalsavings:=coalesce(v_lossonproperty,0)+v_chapter6deductions+v_us80cdeductions+50000+v_hraexemption+coalesce(v_us80ccd_deductions,0)+coalesce(v_professionaltax,0);
end if;

v_taxableincome:=v_totalincome-v_totalsavings;
v_taxableincome:=greatest(v_taxableincome,0);

if p_regime::text='New'::text then
v_taxonincome:=ROUND(
	case when v_taxableincome<=250000 then 0 else
  	case when v_taxableincome<=500000 then (v_taxableincome-250000)*.05 else
 	case when v_taxableincome<=750000 then (v_taxableincome-500000)*.1+12500 else
	case when v_taxableincome<=1000000 then (v_taxableincome-750000)*.15+37500 else
	case when v_taxableincome<=1250000 then (v_taxableincome-1000000)*.20+75000 else
	case when v_taxableincome<=1500000 then (v_taxableincome-1250000)*.25+125000 
	else (v_taxableincome-1500000)*.30+187500
 end
  end
end
	 end
  end
end
,0);
else

v_taxonincome:=ROUND(
case when v_taxableincome<=250000 then 0 else
  case when v_taxableincome<=500000 then (v_taxableincome-250000)*.05 else
 case when v_taxableincome<=1000000 then (v_taxableincome-500000)*.2+12500 else
(v_taxableincome-1000000)*.3+112500
 end
  end
end
,0);
end if;

v_us87a12500:=case when v_taxableincome<=500000 then least(v_taxonincome,12500) else 0 end;

v_surcharge:=0;
v_pretaxonincome:=coalesce(v_taxonincome,0)-coalesce(v_us87a12500,0)+coalesce(v_surcharge,0);
v_healtheducess:=ROUND(v_pretaxonincome*.04,0);

v_netpayabletax:=(v_pretaxonincome+v_healtheducess);

v_balancetax:=greatest(coalesce(v_netpayabletax-v_taxdeducted,0),0);
if p_regime::text='New'::text then
v_taxslab:=case 
			 when v_taxableincome<=250000 then 'Nil' 
			 when v_taxableincome<=500000 then '5' 
			 when v_taxableincome<=750000 then '10'
			 when v_taxableincome<=1000000 then '15' 
			 when v_taxableincome<=1250000 then '20' 
			 when v_taxableincome<=1500000 then '25'
			 else
			'30'
		end;
else
		v_taxslab:=case when v_taxableincome<=250000 then 'Nil'
			 when v_taxableincome<=500000 then '5' 
			 when v_taxableincome<=1000000 then '20' else
			'30'
		end;

end if;
-------------------------------------------------
end if;*/
open v_rfctaxproj for
select round(v_totalincome) totalincome,
	  round(v_totalsavings) totalsavings,
      round(v_taxableincome) taxableincome,
	  round(v_netpayabletax) netpayabletax,
	  round(v_taxdeducted) taxdeducted,
	  round(v_balancetax) balancetax,
	  v_taxslab taxslab
	 ,coalesce(v_currentmonthtaxdeducted,0) currentmonthtaxdeducted,coalesce(v_cjcode,v_cjcodeopen,p_emp_code::text) cjcode,v_presurcharge presurcharge,v_marginal_relief marginal_relief,v_surcharge surcharge,v_mealvoucher mealvoucher;  --change 1.3;
return v_rfctaxproj;
end;
$BODY$;

ALTER FUNCTION public.uspcalculatetaxprojection(bigint, character varying, character varying, integer, integer, text)
    OWNER TO payrollingdb;

