-- FUNCTION: public.uspcaltaxprojection_components(bigint, character varying, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.uspcaltaxprojection_components(bigint, character varying, character varying, character varying);

CREATE OR REPLACE FUNCTION public.uspcaltaxprojection_components(
	p_emp_code bigint,
	p_financial_year character varying,
	p_regime character varying,
	p_customeraccountid character varying DEFAULT '-9999'::character varying)
    RETURNS SETOF refcursor 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
declare
v_empid bigint;
v_gender varchar(10);
v_totalincome numeric(18,2):=0;
v_salaryincome numeric(18,2):=0;
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
v_rfcincome refcursor;
v_rfcsavings refcursor;
v_rfcchapter6detail refcursor;
v_rfcus80detail refcursor;
v_rfcflexicomponentsdetail refcursor;

v_year1 int;
v_year2 int;
v_effectivefrom date;
v_mon1 int;
v_mon2 int;
v_hra  numeric(18,2):=0;
v_basic  numeric(18,2):=0;
v_allowance  numeric(18,2):=0;
v_locationtype varchar(20);
v_rentpaid numeric(18,2):=0;
v_metrononmetrohra numeric(18,2):=0;
v_hraexemption numeric(18,2):=0;
v_isbefore01apr1999 varchar(1);

v_existingbasic numeric(18,2):=0;
v_existinghra numeric(18,2):=0;
v_existingnetpay numeric(18,2):=0;

v_existinggrossearning numeric(18,2):=0;
v_existingotherdeductions numeric(18,2):=0;

v_homeloanapprovalstatus varchar(1);
v_rentapprovalstatus varchar(1):='P';
v_leftflag varchar(1):='N';
v_approval_status_value varchar(1):='P';
v_declaration_or_proof varchar(1);
v_financial_year text;
v_proofapplicabledate date;
v_is_fianncialyearcompleted varchar(1);
v_startdate date;
v_enddate date;
v_advancestartdate date;
v_advanceenddate date;

	
	
v_lastempcode bigint;
v_lastleftflag varchar(1);
v_lastdateofrelieving date;
v_pancard varchar(10);
v_lastempid bigint;
v_finyearstartdate date;
v_finyearenddate date;
v_professionaltax  numeric(18,2):=0;
v_marginal_relief   numeric(18,2):=0;
v_presurcharge numeric(18,2):=0;
v_marginal_reliefsmall   numeric(18,2):=0;
v_standarddeduction   numeric(18,2):=0;	
	v_previousemployerbasic  numeric(18,2):=0;
	v_previousemployerhra  numeric(18,2):=0;
	
v_insurance  numeric(18,2):=0;
v_pf  numeric(18,2):=0;
v_vpf  numeric(18,2):=0;
v_ptid int;
	v_rec record;
v_rfctaxsummary refcursor;
v_taxbeforeus87a   numeric(18,2):=0;
v_taxafterus87a   numeric(18,2):=0;
v_taxsummary text;
v_hracomponents text;
v_taxslabmaster text;
v_rfcquarter refcursor;
v_sec_17_components_one text;
v_sec_17_components_two text;
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
v_flexocomponents    numeric(18,2):=0;
v_lta    numeric(18,2):=0;
v_disbursedsalaryids varchar(500);
v_projectedalaryids varchar(500);
v_onemonthbasic    numeric(18,2):=0;
v_activesalaryid bigint;
v_monthwiseinvestment monthwiseinvestment%rowtype;
v_rfcprevincome refcursor;
v_surcharge_rate NUMERIC := 0;
v_recus87a record;
v_rec_taxmarginalrelief record;
v_tax_marginal_relief   numeric(18,2):=0;
v_standard_deduction NUMERIC(18,2);
v_health_education_cess NUMERIC(18,2);
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
1.3		30-May-2022		Tax at hrgenerated					Shiv Kumar
1.4		07-Nov-2022		Tax on Pancard						Shiv Kumar
1.5		23-Feb-2022		Eliminate current Month projection	Shiv Kumar
						if salary disbursed
1.6		12-Apr-2023		Professional Tax					Shiv Kumar	
1.7		24-Apr-2023		Surcharge & Marginal Relief			Shiv Kumar	
1.8		31-May-2023		Marginal Relief for earners			Shiv Kumar
						with earning more than 750000
1.9		24-Sep-2024		New Regime 2024-2025 changes		Shiv Kumar
1.10	06-Nov-2024		Migrated Clients Data				Shiv Kumar
1.11	20-Jan-2025		Flexi Allowance						Shiv Kumar
1.12	01-Apr-2025		Dynamic Tax Configuration
						based on uspcalculatetaxprojection Siddharth Bansal
1.13	13-Jun-2025		Add dynamic flexi components		Shiv Kumar	
1.14	04-Jul-2025		Meal Voucher						Shiv Kumar
1.15	20-Feb-2026		Flexi Components Min. Check			Shiv Kumar
**************************************************************************/
/*****************Change 1.10 starts**********************************/
select 
sum(grossearning) grossearning,sum(basic) basic,sum(hra) hra,
sum(tds) tds,sum(pf) pf,sum(vpf) vpf,sum(insurance) as insurance
from tbl_migratedcustomerincomedtld rp inner join openappointments op
on rp.orgempcode=op.orgempcode
and op.customeraccountid=p_customeraccountid::bigint
and op.emp_code=p_emp_code
and finyear=p_financial_year
and rp.isactive='1'
into v_rec;
/*****************Change 1.10 ends**********************************/
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
			and opento>=current_date and customeraccountid=p_customeraccountid::bigint 
			)
then
Raise Notice 'Inside Employee';
	select declaration_or_proof,financialyear,proofapplicabledate,is_fianncialyearcompleted into v_declaration_or_proof,v_financial_year,v_proofapplicabledate,v_is_fianncialyearcompleted from public.inv_declr_duration_employee where financialyear=p_financial_year 
	and opento>=current_date and employeecode=p_emp_code and customeraccountid=p_customeraccountid::bigint and active='1';
else
	select declaration_or_proof,financialyear,proofapplicabledate,is_fianncialyearcompleted into v_declaration_or_proof,v_financial_year,v_proofapplicabledate,v_is_fianncialyearcompleted from public.inv_declr_duration where financialyear=p_financial_year 
	and customeraccountid=p_customeraccountid::bigint and active='1';
Raise Notice 'Inside Employer';
end if;
Raise Notice 'v_declaration_or_proof=% v_proofapplicabledate=%',v_declaration_or_proof,v_proofapplicabledate;
if v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then
v_approval_status_value:='A';
ELSE
v_approval_status_value:='P';
end if;
select coalesce(left_flag,'N'),nullif(trim(pancard),'') into v_leftflag,v_pancard from openappointments where emp_code=p_emp_code;

v_year1:=left(p_financial_year,4)::int;
v_year2:=right(p_financial_year,4)::int;

if p_regime='Old' or v_year1=2023 then
	v_standarddeduction:=50000;
else
	v_standarddeduction:=75000;
end if;
/****************change 1.3*******************************/
v_startdate:=to_date(v_year1::text||'-05-01','yyyy-mm-dd');
v_enddate:=to_date(v_year2::text||'-04-30','yyyy-mm-dd');

v_advancestartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_advanceenddate:=to_date(v_year1::text||'-04-30','yyyy-mm-dd');
/****************change 1.3 ends here*******************************/

/****************change 1.4*******************************/
v_finyearstartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_finyearenddate:=to_date(v_year2::text||'-03-31','yyyy-mm-dd');

select emp_id,emp_code,left_flag,dateofrelieveing
from openappointments
where (emp_code=p_emp_code or pancard=v_pancard)
and customeraccountid=coalesce(nullif(nullif(p_customeraccountid,''),'-9999')::bigint,customeraccountid)
and appointment_status_id=11 and converted='Y'
and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)
order by emp_id desc
limit 1
into v_lastempid,v_lastempcode,v_lastleftflag,v_lastdateofrelieving;
/****************change 1.4 ends here*******************************/

select emp_id,gender
into v_empid,v_gender
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
salaryids varchar(500)
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
from public.empsalaryregister
where isactive='1'
and appointment_id=v_lastempid
order by id desc
limit 1;

select e.is_exemptedfromtds from empsalaryregister e where e.id=(select t.salaryids::bigint from tmpsalstructure t) into v_is_exemptedfromtds;
select sum(tds)
,sum(grossearning-coalesce(voucher_amount,0)/*+coalesce(vpf,0)*/)   -- Added on 23 Oct 2021 with disucssion with Account Team
,sum(otherdeductions)
,sum(professionaltax)
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
into v_taxdeducted
,v_existinggrossearning
,v_existingotherdeductions
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
from (select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,professionaltax,
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
	  from tbl_monthlysalary
	 where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)))  and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1' and (
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
	select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,professionaltax,
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
	from tbl_monthly_liability_salary
	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and coalesce(salary_remarks,'')<>'Invalid Paid Days'
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
	 	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and (
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
union all
	--and (emp_code,mprmonth, mpryear, batchid) not in
	(select emp_code,mprmonth, mpryear, batchid ||coalesce(transactionid::text,'')
		 from tbl_monthlysalary where  (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and(
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
	 
-------------------------------------------------------	  
	--and (mprmonth, mpryear, emp_code,batchid) not in 
		  union all
	(select m.mprmonth, m.mpryear,  m.emp_code,trim(regexp_split_to_table(m.batchid,'','')) 
	 from tbl_monthlysalary m where (m.emp_code=p_emp_code or  m.emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and coalesce(m.is_rejected,'0')='0'
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
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)))
--and (isarear<>'Y' or recordscreen ='Previous Wages')
/*and to_date('01'||lpad(mprmonth::text,2,'0')||mpryear::text,'ddmmyyyy')
between to_date(v_year1||'-04-01','yyyy-mm-dd') and least((DATE_TRUNC('MONTH', current_date) - INTERVAL '1 DAY'),to_date(v_year2||'-03-31','yyyy-mm-dd'))*/  
and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1';

v_taxdeducted:=coalesce(v_taxdeducted,0);

v_taxdeducted:=coalesce(v_taxdeducted,0);
v_mon1:=extract (month from current_date);
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
if v_mon1 between 5 and 12 then
v_mon1:=(12-v_mon1)+4;
else
v_mon1:=(3-v_mon1)+1;
end if;
--Change 1.1 
if extract (month from current_date)=4 then
	if v_declaration_or_proof='P' then
		v_mon1:=0;
	else
		v_mon1:=12;
	end if;
end if;	 
if v_is_fianncialyearcompleted='C' then
    v_mon1:=0;
end if;
if v_lastleftflag='Y' then 
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
		string_agg(salaryid::text,',') 
		into v_existingbasic,
		v_existinghra
		,v_disbursedsalaryids
from (select emp_code,basic,incrementarear_basic,hra,incrementarear_hra,isarear,recordscreen,hrgeneratedon,is_rejected,salaryid
	   from tbl_monthlysalary
	 	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)))   and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1' and
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
		and coalesce(is_rejected,'0')<>'1'
	  union all
	  select emp_code,basic,incrementarear_basic,hra,incrementarear_hra,isarear,recordscreen,hrgeneratedon,is_rejected,salaryid
from tbl_monthly_liability_salary
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and 
	  coalesce(salary_remarks,'')<>'Invalid Paid Days'
	and coalesce(is_rejected,'0')='0'
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
	 where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and (
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
	and (emp_code,mprmonth, mpryear, batchid) not in
	(select emp_code,mprmonth, mpryear, batchid ||coalesce(transactionid::text,'')
		 from tbl_monthlysalary where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and (
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
	 from tbl_monthlysalary m where (m.emp_code=p_emp_code or  m.emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate))) and coalesce(m.is_rejected,'0')='0'
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
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y' and dateofjoining<=v_finyearenddate and (dateofrelieveing is null or dateofrelieveing>=v_finyearstartdate)))
and (isarear<>'Y' or recordscreen in ('Previous Wages','Arear Wages','Increment Arear'))
/*and to_date('01'||lpad(mprmonth::text,2,'0')||mpryear::text,'ddmmyyyy')
between to_date(v_year1||'-04-01','yyyy-mm-dd') and least((DATE_TRUNC('MONTH', current_date) - INTERVAL '1 DAY'),to_date(v_year2||'-03-31','yyyy-mm-dd')) 
*/
and coalesce(is_rejected,'0')<>'1';

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
+coalesce(salarybonus,0)
)*totalmonths
)+coalesce(v_existinggrossearning,0)-
coalesce(v_existingotherdeductions,0),
sum(basic*totalmonths)+coalesce(v_existingbasic,0),
sum(hra*totalmonths)+coalesce(v_existinghra,0),max(locationtype),
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
SUM(medicalAllowance * totalmonths) + COALESCE(v_existingmedical_allowance , 0)
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
v_medicalallowance
from tmpsalstructure;

v_salaryincome:=v_totalincome;
--raise notice 'HRA=%',v_hra::text;
/***************************************************************/
v_metrononmetrohra:=case when upper(v_locationtype)='METRO' then v_basic*0.5 else v_basic*0.4 end;

---------------------------------
-- if exists(select *
-- 	from empdeclaration_rentdetails
-- 	where emp_code=p_emp_code
--  	and financial_year=p_financial_year
--  	and isactive='1'
--  	and approval_status='A') 
-- then
 v_rentapprovalstatus:='A';
	select sum(rentpaid) into v_rentpaid
	from empdeclaration_rentdetails
	where emp_code=v_lastempcode
	 and financial_year=p_financial_year
	 and isactive='1'
	 --and coalesce(approval_status,'P')=v_approval_status_value;
	 and coalesce(approval_status,'P')= case when v_approval_status_value='A' then 'A' else coalesce(approval_status,'P') end;
--  else
-- 	select sum(rentpaid) into v_rentpaid
-- 	from empdeclaration_rentdetails
-- 	where emp_code=p_emp_code
-- 	 and financial_year=p_financial_year
-- 	 and isactive='1';

-- end if;
v_hraexemption:=least((v_hra+v_previousemployerhra+coalesce(v_rec.hra,0)),v_metrononmetrohra,greatest(v_rentpaid-(v_basic+v_previousemployerbasic+coalesce(v_rec.basic,0))*.10,0));
--raise notice 'v_hraexemption=%',v_hraexemption;

select sum(total_income),sum(tds) 
 into v_incomepreviousemployer,v_previousemployertax
 from public.empdeclr_prevemployerinc_dtls
 where emp_code=p_emp_code
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
 and financial_year=p_financial_year
 and active='1';
 
 
 select interest_on_borrowed_capital,isbefore01apr1999
,approval_status
 into v_lossonproperty,v_isbefore01apr1999
 ,v_homeloanapprovalstatus
 from public.empdeclr_homeloan
 where emp_code=v_lastempcode
 and financial_year=p_financial_year
 --and coalesce(approval_status,'P')=v_approval_status_value
 and coalesce(approval_status,'P')= case when v_approval_status_value='A' then 'A' else coalesce(approval_status,'P') end
 and active='1';
 
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
 and financial_year=p_financial_year
 and active='1';

 ---------------------------------------------
 if p_regime='New' then
 v_totalincome:=v_totalincome
 +coalesce(v_incomepreviousemployer,0)
+coalesce(v_rec.grossearning,0)
/*+coalesce(v_incomefromothersources,0)
+coalesce(v_businessincome,0)
+coalesce(v_incomefromcapitalgains,0)
+coalesce(v_anyotherincome,0)
+coalesce(v_interestonsavingbank,0)
-coalesce(v_tds_others,0)*/;
else
v_totalincome:=v_totalincome
 +coalesce(v_incomepreviousemployer,0)
+coalesce(v_rec.grossearning,0)
/*-- +coalesce(v_letoutpropertyincome,0)
+coalesce(v_incomefromothersources,0)
+coalesce(v_businessincome,0)
+coalesce(v_incomefromcapitalgains,0)
+coalesce(v_anyotherincome,0)
+coalesce(v_interestonsavingbank,0)
-coalesce(v_tds_others,0)*/;

 
end if;
-----------------------------------------------
if p_customeraccountid='7416' then
		select salary_head_text 
		into v_salary_head_text 
		from mst_tp_business_setups 
		where tp_account_id=p_customeraccountid::bigint and row_status='1';
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
	select tmpcomponent.componentname,(replace(replace(replace(lower(componentname),' ','_'),'(',''),')','')) as newcomponentname,
	earningtype
		from tmpcomponent inner join mst_investment_section
		on tmpcomponent.earningtype=mst_investment_section.investmentname
		and mst_investment_section.headid=10 
		and mst_investment_section.id<>58
	)
	select * from tmp1;

    SELECT string_agg('SUM(' || quote_ident(replace(newcomponentname,'conveyance','conv')) || ') AS ' || quote_ident(newcomponentname), ', ')
    INTO v_sum_list
    FROM tmp_flexilimit;
Raise Notice 'v_sum_list=%',v_sum_list;

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
               AND (coalesce(isarear,''N'') <> ''Y'' OR recordscreen IN (''Previous Wages'', ''Increment Arear'', ''Arear Wages''))
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
          v_leftflag;           -- $9
	--	   Raise Notice 'COUNT=%',(select componentname||newcomponentname||total_amount from tmp2 offset 2 limit 1);

 /********change 1.11 starts***************/
-- Raise Notice 'p_emp_code=%,v_startdate=%,v_enddate=%,v_advancestartdate=%',p_emp_code,v_startdate,v_enddate,v_advancestartdate;
-- Raise Notice 'v_year1=%,v_year2=%,v_finyearenddate=%,v_leftflag=%',v_year1,v_year2,v_finyearenddate,v_leftflag;

select
sum(least(coalesce(total_amount,0),coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0)))
into v_flexocomponents
from trn_investment
inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and trn_investment.headid=10
and trn_investment.isactive='1'
and (
	(isacustomerspecific='Y' and p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	or
	(isacustomerspecific='N' and not p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	)
and trn_investment.emp_code=v_lastempcode
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id<>58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
left join tmp_flexilimit on tmp_flexilimit.earningtype=mst_investment_section.investmentname
left join tmp2 on tmp2.componentname=tmp_flexilimit.componentname
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
and (
	(isacustomerspecific='Y' and p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	or
	(isacustomerspecific='N' and not p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	)
and trn_investment.emp_code=v_lastempcode
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id<>58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
--group by investment_id
;
end if; 
 raise notice 'flexi=%',v_flexocomponents;

v_flexocomponents:=coalesce(v_flexocomponents,0);

select
sum(least(coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0)))
into v_lta
from trn_investment
inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and trn_investment.headid=10
and trn_investment.isactive='1'
and (
	(isacustomerspecific='Y' and p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	or
	(isacustomerspecific='N' and not p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	)
and trn_investment.emp_code=v_lastempcode
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id=58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
group by investment_id;

v_projectedalaryids:=coalesce(v_projectedalaryids,'')||coalesce(','||v_activesalaryid,'');

-- raise notice 'lta=% v_projectedalaryids=%',v_lta,v_projectedalaryids;

Raise notice 'v_projectedalaryids=%',v_projectedalaryids;
select basic from empsalaryregister 
		where id =(select  max(a) from (
							select unnest(string_to_array(trim(v_projectedalaryids,','), ','))::integer as a)tmp
				  )
into v_onemonthbasic;
v_onemonthbasic:=coalesce(v_onemonthbasic,0);
-- raise notice 'v_onemonthbasic=% v_basic=%',v_onemonthbasic,v_basic;

v_lta:=coalesce(v_lta,0);
v_lta:=least(v_lta,v_basic,v_onemonthbasic);
 --raise notice 'lta=%',v_lta;

v_flexocomponents:=v_flexocomponents+coalesce(v_lta,0);
  /********Added for change 1.11 ends***************/

select
sum(case when mst_investment_section.id in (11,52) then coalesce(investment_amount,0)
   when mst_investment_section.id =51 then coalesce(investment_amount,0)*.50
	      when mst_investment_section.id =5 then least(coalesce(investment_amount,0)+coalesce(v_insurance,0),coalesce(max_limit,coalesce(investment_amount,0)+coalesce(v_insurance,0),0))
	else
	least(coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0))
   end) into v_chapter6deductions
from( select investment_id,sum(investment_amount) investment_amount
	 from (select case when  investment_id=1 then 5 else investment_id end as investment_id,investment_amount
	   from trn_investment
where  trn_investment.emp_code=v_lastempcode
 and trn_investment.financial_year=p_financial_year
 and trn_investment.isactive='1'
 and trn_investment.headid=1
 and coalesce(approval_status,'P')= case when trn_investment.investment_id in (5) then 'A' when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
  ) trn_investment 
	 group by investment_id
) trn_investment
 
 inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and mst_investment_section.isactive='1';
 
 v_chapter6deductions:=coalesce(v_chapter6deductions,0);
 
 
select sum(investment_amount)
into v_us80cdeductions
from public.trn_investment
where  headid=2
and emp_code=v_lastempcode
and financial_year=p_financial_year
and isactive='1'
and trn_investment.investment_id not in (/*23,*/24) --Added on 02-Apr-2022
and coalesce(approval_status,'P')=case when trn_investment.investment_id in (25,26) then 'A' else case when v_approval_status_value='A' then 'A' else coalesce(approval_status,'P') end end;--Added for change 1.2

--Added for 80ccd dated 22 oct2021
select sum(investment_amount)
into v_us80ccd_deductions
from public.trn_investment
where  headid=2
and emp_code=v_lastempcode
and financial_year=p_financial_year
and isactive='1'
and trn_investment.investment_id=24
and coalesce(approval_status,'P')=case when v_approval_status_value='A' then 'A' else coalesce(approval_status,'P') end;--Added for change 1.2
--Added for 80ccd dated 22 oct2021 end here
v_us80ccd_deductions:=case when coalesce(v_us80ccd_deductions,0)>50000 then 50000 else coalesce(v_us80ccd_deductions,0) end;--Added on 02-Apr-2022

v_us80cdeductions:=coalesce(v_us80cdeductions,0)+coalesce(v_rec.pf,0)+coalesce(v_pf,0)+coalesce(v_vpf,0)+coalesce(v_rec.vpf,0);

v_us80cdeductions:=least(coalesce(v_us80cdeductions,0),150000);
--v_totalincome:=771060;
/****************change 1.8 starts*******************************/

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
/**********************change 1.12****************************************/
		if p_regime='New' then
			v_totalsavings:=v_standard_deduction;
		else
		
			select sum(mealamount) mealvoucheramount 
				from public.trnmealvoucher 
				where isactive='1' and emp_code=p_emp_code
				and make_date(mealyear,mealmonth,1) between make_date(v_year1,4,1) and  make_date(v_year2,3,31)
			into v_mealvoucher;
			v_totalsavings:=coalesce(v_lossonproperty,0)+v_chapter6deductions+v_us80cdeductions+v_standard_deduction+v_hraexemption+coalesce(v_us80ccd_deductions,0)+coalesce(v_professionaltax,0)+coalesce(v_flexocomponents,0)+coalesce(v_mealvoucher,0);
		end if;
		
		v_taxableincome:=v_totalincome;	
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

if coalesce(v_is_exemptedfromtds,'N')='Y' then
v_taxonincome:=0;
end if;
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

SELECT array_to_json(
    array_agg(row_to_json(X))
)  into v_taxslabmaster
FROM (
    SELECT 
        CASE 
            WHEN taxableincomefrom IS NULL THEN 'Below ' || taxableincometo || ' = ' || taxrate || '%'
            WHEN taxableincometo IS NULL THEN 'Above ' || taxableincomefrom || ' = ' || taxrate || '%'
            ELSE taxableincomefrom || ' to ' || taxableincometo || ' = ' || taxrate || '%'
        END AS slab
    FROM mst_taxslabs
	WHERE financial_year = p_financial_year	AND regimetype = p_regime
      AND configname = 'TaxRate' 
      AND isactive = '1'
) AS X;

open v_rfctaxproj for
select coalesce(v_totalincome,0) totalincome,
	coalesce(v_totalsavings,0) totalsavings,
    coalesce(v_taxableincome,0) taxableincome,
  	coalesce(v_netpayabletax,0) netpayabletax,
  	coalesce(v_taxdeducted,0) taxdeducted,
  	coalesce(v_balancetax,0) balancetax,
  	coalesce(v_taxslab,'0') taxslab,
	p_regime||coalesce('('||case when v_is_exemptedfromtds='Y' then 'Exempted' else null end||')','') regimetype,
	coalesce(v_pancard,'') pancard
  ,coalesce(v_us87a12500,0) rebateus87a
  ,coalesce(v_healtheducess,0) educationcess
  ,coalesce(v_surcharge,0) surcharge
  ,coalesce(v_previousemployertax,0) previousemployertax
  ,v_mealvoucher mealvoucher;
return next v_rfctaxproj;
----------------Total Income-------------------------------------
open v_rfcincome for
select 'Salary' as incomehead,coalesce(v_salaryincome,0) as income
union all
select 'Income From Previous Employer' ,coalesce(v_incomepreviousemployer,0)+coalesce(v_rec.grossearning,0) as income
union all
select 'Income From Letout Property',coalesce(v_letoutpropertyincome,0) as income
union all		 
select 'Income From Other Sources' ,coalesce(v_incomefromothersources,0) as income
union all
select 'Business Income' ,coalesce(v_businessincome,0) as income
union all
select 'Income From Capital Gains' ,coalesce(v_incomefromcapitalgains,0) as income
union all
select 'Any other Income' ,coalesce(v_anyotherincome,0)-coalesce(v_tds_others,0) as income
union all
select 'Interest on Saving Bank' ,coalesce(v_interestonsavingbank,0) as income;

return next v_rfcincome;
-----------------Total Savings-----------------------------------
open v_rfcsavings for
select 'Home Loan Interest' as Savinghead,coalesce(v_lossonproperty,0) saving,4 as headid,v_homeloanapprovalstatus as approval_status
UNION ALL
SELECT 'HRA Exemption '||'<br/>'||
'(Min. of HRA/['||coalesce(v_locationtype,'Metro')||' HRA]/[Rent Paid-10% of Basic])'
||'<br/>('||round(v_hra+v_previousemployerhra)||'/'||round(v_metrononmetrohra)||'/'
||'('||round(coalesce(v_rentpaid,0),0)||'-'||round(coalesce(v_basic+v_previousemployerbasic,0)*.10)||')', round(v_hraexemption) v_hraexemption,5 as headid,case when v_approval_status_value='A' then 'A' when coalesce(v_rentpaid,0)>0 then 'P'  else null end approval_status
UNION ALL
select 'Chapter VI',v_chapter6deductions, 1 as headid,null approval_status
UNION ALL
select 'US 80C',v_us80cdeductions,2 headid,null approval_status
UNION ALL
select 'Standard Deduction',v_standarddeduction ,null as headid,null approval_status
UNION ALL
select 'NPS 80CCD (1B)',v_us80ccd_deductions ,2 as headid,null approval_status where p_regime='Old'
union all
select 'Professional Tax',v_professionaltax,null as headid,case when v_professionaltax>0 then 'A' else null end approval_status
UNION ALL
SELECT 'Flexi Allownces',coalesce(v_flexocomponents,0),10 as headid,null approval_status
UNION ALL
SELECT 'Meal Voucher',coalesce(v_mealvoucher,0),null as headid,null approval_status where p_regime='Old' and coalesce(v_mealvoucher,0)>0

;

return next v_rfcsavings;
Raise Notice 'v_lastempcode=%',v_lastempcode;
-----------------chapter6detail------------------------------------------------
select * from public.monthwiseinvestment where empcode=v_lastempcode and financialyear=p_financial_year
and createdon::date<coalesce(v_proofapplicabledate,current_date)

order by id desc limit 1
into v_monthwiseinvestment;

if v_declaration_or_proof='D' then
open v_rfcchapter6detail for
	select
	 coalesce(mst_investment_section.investmentdescription,mst_investment_section.investmentname) componentname
	 ,0 componentvalue
	 ,mst_investment_section.headid,mst_investment_section.id investment_id
	,case when coalesce(investment_amount,0)=0 then 'N/A' else trn_investment.approval_status end  as approval_status
	,coalesce(investment_amount,0)  declr_amount	
	,coalesce(mst_investment_section.max_limit::text,'') max_limit
	from public.mst_investment_section left join public.trn_investment
	on trn_investment.investment_id=mst_investment_section.id
	and  trn_investment.emp_code=v_lastempcode
	and trn_investment.financial_year=p_financial_year
	and trn_investment.isactive='1'
	where mst_investment_section.headid=1;
else
open v_rfcchapter6detail for
select componentname
	 ,coalesce(componentvalue,0) componentvalue
	 ,headid
	 ,investment_id
	,approval_status
	,coalesce(invamount,0)  declr_amount	
	,coalesce(max_limit::text,'') max_limit
from 
(select
  max(coalesce(mst_investment_section.investmentdescription,mst_investment_section.investmentname)) componentname
 ,sum(coalesce(receipt_amount,0)) componentvalue
 ,mst_investment_section.headid
 ,mst_investment_section.id investment_id
,max(trn_investment_proof.approval_status)  as approval_status
,max(coalesce(mst_investment_section.max_limit::text,'')) max_limit
from public.mst_investment_section left join public.trn_investment_proof
on trn_investment_proof.investment_id=mst_investment_section.id
and  trn_investment_proof.emp_code=v_lastempcode
and trn_investment_proof.financial_year=p_financial_year
and trn_investment_proof.isactive='1'
and approval_status in('A','P')
where mst_investment_section.headid=1
group by  mst_investment_section.headid,mst_investment_section.id) t1
full join (
select 1 as invid, coalesce(v_monthwiseinvestment."Mediclaim (Self/Spouse/Children) (80D)",0) as invamount Union All
select 2 as invid, coalesce(v_monthwiseinvestment."Mediclaim (Parents) (80D)",0) as invamount Union All
select 3 as invid, coalesce(v_monthwiseinvestment."Mediclaim (Parents) (80D)",0) as invamount Union All
select 4 as invid, coalesce(v_monthwiseinvestment."Mediclaim (Preventive Checkup Self/Spouse/Children/Parents) (80D)",0) as invamount Union All
select 5 as invid, coalesce(v_monthwiseinvestment."Mediclaim (Prem. Ded. From Sal. Self/Spouse/Children) (80D)",0) as invamount Union All
select 6 as invid, coalesce(v_monthwiseinvestment."Mediclaim (Prem. Ded. From Sal. Parents) (80D)",0) as invamount Union All
select 7 as invid, coalesce(v_monthwiseinvestment."Handicaped Dependents (80DD)",0) as invamount Union All
select 8 as invid, coalesce(v_monthwiseinvestment."Handicaped Dependents (80DD)",0) as invamount Union All
select 9 as invid, coalesce(v_monthwiseinvestment."Med. Exp. For Spec. Diseases (80DDB)",0) as invamount Union All
select 10 as invid, coalesce(v_monthwiseinvestment."Repayment of Loan for Higher Edu.(80E)",0) as invamount Union All
select 11 as invid, coalesce(v_monthwiseinvestment."Donation (Only Govt. Org.) (80G)",0) as invamount Union All
select 12 as invid, coalesce(v_monthwiseinvestment."Rent Paid (80GG)",0) as invamount Union All
select 13 as invid, coalesce(v_monthwiseinvestment."Donation-Scientific Res. & Rural(80GGA)",0) as invamount Union All
select 14 as invid, coalesce(v_monthwiseinvestment."Foreign Sources (80R)",0) as invamount Union All
select 15 as invid, coalesce(v_monthwiseinvestment."Outside India (80RRA)",0) as invamount Union All
select 16 as invid, coalesce(v_monthwiseinvestment."Interest on Saving Bank (80TTA)",0) as invamount Union All
select 17 as invid, coalesce(v_monthwiseinvestment."Pension Handicap (80U)",0) as invamount Union All
select 18 as invid, coalesce(v_monthwiseinvestment."Pension Handicap (80U)",0) as invamount Union All
select 19 as invid, coalesce(v_monthwiseinvestment."Interest on Saving Bank (80TTB)",0) as invamount Union All
select 20 as invid, coalesce(v_monthwiseinvestment."Interest Paid on Elec. Vehicle",0) as invamount Union All
select 21 as invid, coalesce(v_monthwiseinvestment."Interest on Home Loan(2016-17)",0) as invamount Union All
select 22 as invid, coalesce(v_monthwiseinvestment."Interest on Home Loan(2019-20)",0) as invamount Union All
select 51 as invid, coalesce(v_monthwiseinvestment."Donations to Charitable Institutions eligible for 50% deduction",0) as invamount Union All
select 52 as invid, coalesce(v_monthwiseinvestment."Donations to Political Parties by an Assessee eligible for 100% deduction",0) as invamount
) tmpdeclr
on t1.investment_id=tmpdeclr.invid;
end if;

return next v_rfcchapter6detail;
-----------------80cdetail------------------------------------------------
if v_declaration_or_proof='D' then
open v_rfcus80detail for
	select
	 	 coalesce(mst_investment_section.investmentdescription,mst_investment_section.investmentname) componentname

	 ,0 componentvalue
	 ,mst_investment_section.headid,mst_investment_section.id investment_id
	,case when coalesce(investment_amount,0)=0 then 'N/A' else trn_investment.approval_status end  as approval_status
	,coalesce(investment_amount,0)  declr_amount	
	,coalesce(mst_investment_section.max_limit::text,'') max_limit
	from public.mst_investment_section left join public.trn_investment
	on trn_investment.investment_id=mst_investment_section.id
	and  trn_investment.emp_code=v_lastempcode
	and trn_investment.financial_year=p_financial_year
	and trn_investment.isactive='1'
	where mst_investment_section.headid=2;
else
open v_rfcus80detail for
select componentname
	 ,coalesce(componentvalue,0) componentvalue
	 ,headid
	 ,investment_id
	,approval_status
	,coalesce(invamount,0)  declr_amount	
	,coalesce(max_limit::text,'') max_limit
from 
(select
  max(coalesce(mst_investment_section.investmentdescription,mst_investment_section.investmentname)) componentname
 ,sum(coalesce(receipt_amount,0)) componentvalue
 ,mst_investment_section.headid
 ,mst_investment_section.id investment_id
,max(trn_investment_proof.approval_status)  as approval_status
,max(coalesce(mst_investment_section.max_limit::text,'')) max_limit
from public.mst_investment_section left join public.trn_investment_proof
on trn_investment_proof.investment_id=mst_investment_section.id
and  trn_investment_proof.emp_code=v_lastempcode
and trn_investment_proof.financial_year=p_financial_year
and trn_investment_proof.isactive='1'
and approval_status in('A','P')
where mst_investment_section.headid=2
group by  mst_investment_section.headid,mst_investment_section.id) t2
full join (
select 23 as invid, coalesce(v_monthwiseinvestment."NPS 80CCD (i)",0) as invamount Union All
select 24 as invid, coalesce(v_monthwiseinvestment."NPS 80CCD (1B)",0) as invamount Union All
select 25 as invid, coalesce(v_monthwiseinvestment."EPF (80C)",0) as invamount Union All
select 26 as invid, coalesce(v_monthwiseinvestment."VPF (80C)",0) as invamount Union All
select 27 as invid, coalesce(v_monthwiseinvestment."PF Deducted By Prev. Employer(80C)",0) as invamount Union All
select 28 as invid, coalesce(v_monthwiseinvestment."LIC Premium (80C)",0) as invamount Union All
select 29 as invid, coalesce(v_monthwiseinvestment."ULIP (80C)",0) as invamount Union All
select 30 as invid, coalesce(v_monthwiseinvestment."NPS/Pension Scheme Central Govt. (80CCD) (i)",0) as invamount Union All
select 31 as invid, coalesce(v_monthwiseinvestment."PPF (80C)",0) as invamount Union All
select 32 as invid, coalesce(v_monthwiseinvestment."Fixed Deposit (80C)",0) as invamount Union All
select 33 as invid, coalesce(v_monthwiseinvestment."Tution Fee (80C)",0) as invamount Union All
select 34 as invid, coalesce(v_monthwiseinvestment."Repayment of House Loan Principal(80C)",0) as invamount Union All
select 35 as invid, coalesce(v_monthwiseinvestment."NSC (80C)",0) as invamount Union All
select 36 as invid, coalesce(v_monthwiseinvestment."Interest on NSC (80C)",0) as invamount Union All
select 37 as invid, coalesce(v_monthwiseinvestment."Mutual Fund (80C)",0) as invamount Union All
select 38 as invid, coalesce(v_monthwiseinvestment."Pension Fund (80CCC)",0) as invamount Union All
select 39 as invid, coalesce(v_monthwiseinvestment."Sukanya Samridhi Scheme (80C)",0) as invamount Union All
select 40 as invid, coalesce(v_monthwiseinvestment."KVP",0) as invamount Union All
select 41 as invid, coalesce(v_monthwiseinvestment."Others",0) as invamount Union All
select 42 as invid, coalesce(v_monthwiseinvestment."Stamp Duty",0) as invamount
	) tmpdeclr
on t2.investment_id=tmpdeclr.invid;
end if;

return next v_rfcus80detail;

SELECT array_to_json(
	array_agg(row_to_json(X) )
)  
into v_taxsummary FROM (
select coalesce(v_totalincome,0)::text taxableincome
	  ,coalesce(v_taxbeforeus87a,0)::text taxbeforeus87a
 	  ,coalesce(v_us87a12500,0)::text rebateus87a
	  ,coalesce(v_taxafterus87a,0)::text taxafterus87a
  	 ,coalesce(v_surcharge,0)::text surcharge
  	 ,coalesce(v_healtheducess,0)::text educationcess
  	,coalesce(v_netpayabletax,0)::text taxpayable
	,0::text reliefus89
  	,coalesce(v_netpayabletax,0)::text taxpayable
	,(coalesce(v_taxdeducted,0)-coalesce(v_previousemployertax,0))::text as tdssalaryandreimbursement
    ,coalesce(v_previousemployertax,0)::text previousemployertax
  ,coalesce(v_balancetax,0)::text taxpayablerefundable
	)AS X;
	
v_rec:=null;
SELECT * from public.uspmonthwisesalarycoponents(
    p_financialyear=>p_financial_year, 
    p_empcode=>p_emp_code, 
    p_balancetax=>v_balancetax, 
    p_tptype=>'TP', 
    p_customeraccountid=>p_customeraccountid
) into v_rfcquarter;
fetch v_rfcquarter into v_rec;

SELECT array_to_json(
	array_agg(row_to_json(X) )
)  
into v_hracomponents FROM (
select coalesce(v_rentpaid,0)::text as rentpaid,round(coalesce(v_hra,0)+coalesce(v_previousemployerhra,0))::text as actualhra,
	    round(coalesce(v_metrononmetrohra,0))::text metrononmetrohra,
		round(coalesce(v_basic+v_previousemployerbasic,0)*.10)::text as tenpercentofbasic,	
	
coalesce(v_rec.jan_grossearning,'0') jan_grossearning,
coalesce(v_rec.feb_grossearning,'0') feb_grossearning,
coalesce(v_rec.mar_grossearning,'0') mar_grossearning,
coalesce(v_rec.apr_grossearning,'0') apr_grossearning,
coalesce(v_rec.may_grossearning,'0') may_grossearning,
coalesce(v_rec.jun_grossearning,'0') jun_grossearning,
coalesce(v_rec.jul_grossearning,'0') jul_grossearning,
coalesce(v_rec.aug_grossearning,'0') aug_grossearning,
coalesce(v_rec.sep_grossearning,'0') sep_grossearning,
coalesce(v_rec.oct_grossearning,'0') oct_grossearning,
coalesce(v_rec.nov_grossearning,'0') nov_grossearning,
coalesce(v_rec.dec_grossearning,'0') dec_grossearning,
coalesce(v_rec.q1_grossearning,'0') q1_grossearning,
coalesce(v_rec.q2_grossearning,'0') q2_grossearning,
coalesce(v_rec.q3_grossearning,'0') q3_grossearning,
coalesce(v_rec.q4_grossearning,'0') q4_grossearning
	
	)AS X;
	
	--SIDDHARTH BANSAL 23/12/2024

SELECT array_to_json(
	array_agg(row_to_json(X) )
)  
into v_sec_17_components_two 
FROM (
	
SELECT 
    'Other Benefits' AS provision, 
    0 AS gtotal, 
    0 AS exempt, 
    0 AS taxable

UNION ALL

SELECT 
    'Medical Reimbursement' AS provision, 
    0 AS gtotal, 
    0 AS exempt, 
    0 AS taxable

UNION ALL

SELECT 
    'Leave Travel Concession' AS provision, 
    0 AS gtotal, 
    0 AS exempt, 
    0 AS taxable

-- UNION ALL

-- SELECT 
--     'Employee PF' AS provision, 
--     0 AS gtotal, 
--     0 AS exempt, 
--     0 AS taxable

-- UNION ALL

-- SELECT 
--     'Total' AS provision, 
--     0 AS gtotal, 
--     0 AS exempt, 
--     0 AS taxable
)AS X;

SELECT array_to_json(
    array_agg(row_to_json(X))
)  
INTO v_sec_17_components_one
FROM (
    SELECT 
        'CONV' AS provision, 
        coalesce(v_conv,0) AS total, 
        0 AS exempt, 
        coalesce(v_conv,0) AS taxable

    UNION ALL
    
    SELECT 
        'Basic' AS provision, 
        coalesce(v_basic,0) AS total, 
        0 AS exempt, 
        coalesce(v_basic,0) AS taxable

    UNION ALL

    SELECT 
        'HRA' AS provision, 
        coalesce(v_hra,0) AS total, 
        0 AS exempt, 
        coalesce(v_hra,0) AS taxable

    UNION ALL

    SELECT 
        'Special Allowances' AS provision, 
        coalesce(v_allowances,0) AS total, 
        0 AS exempt, 
        coalesce(v_allowances,0) AS taxable

    UNION ALL

    SELECT 
        'Medical' AS provision, 
        coalesce(v_medicalallowance,0) AS total, 
        0 AS exempt, 
        coalesce(v_medicalallowance,0) AS taxable

    UNION ALL

    SELECT 
        'Commission' AS provision, 
        coalesce(v_commission,0) AS total, 
        0 AS exempt, 
        coalesce(v_commission,0) AS taxable

    UNION ALL

    SELECT 
        'Transport Allowance' AS provision, 
        coalesce(v_transport_allowance,0) AS total, 
        0 AS exempt, 
        coalesce(v_transport_allowance,0) AS taxable

    UNION ALL

    SELECT 
        'Travelling Allowance' AS provision, 
        coalesce(v_travelling_allowance,0) AS total, 
        0 AS exempt, 
        coalesce(v_travelling_allowance,0) AS taxable

    UNION ALL

    SELECT 
        'Leave Encashment' AS provision, 
        coalesce(v_leave_encashment,0) AS total, 
        0 AS exempt, 
        coalesce(v_leave_encashment,0) AS taxable

    UNION ALL

    SELECT 
        'Overtime Allowance' AS provision, 
        coalesce(v_overtime_allowance,0) AS total, 
        0 AS exempt, 
        coalesce(v_overtime_allowance,0) AS taxable

    UNION ALL

    SELECT 
        'Notice Pay' AS provision, 
        coalesce(v_notice_pay,0) AS total, 
        0 AS exempt, 
        coalesce(v_notice_pay,0) AS taxable

    UNION ALL

    SELECT 
        'Hold Salary Non-Taxable' AS provision, 
        coalesce(v_hold_salary_non_taxable,0) AS total, 
        0 AS exempt, 
        coalesce(v_hold_salary_non_taxable,0) AS taxable

    UNION ALL

    SELECT 
        'Children Education Allowance' AS provision, 
        coalesce(v_children_education_allowance,0) AS total, 
        0 AS exempt, 
        coalesce(v_children_education_allowance,0) AS taxable

    UNION ALL

    SELECT 
        'Gratuity In Hand' AS provision, 
        coalesce(v_gratuityinhand,0) AS total, 
        0 AS exempt, 
        coalesce(v_gratuityinhand,0) AS taxable

    UNION ALL

    SELECT 
        'Salary Bonus' AS provision, 
        coalesce(v_salarybonus,0) AS total, 
        0 AS exempt, 
        coalesce(v_salarybonus,0) AS taxable
) AS X;

	
open v_rfctaxsummary for
select v_taxsummary as taxsummary,v_hracomponents hracomponents,v_taxslabmaster as taxslabmaster,v_sec_17_components_two as sec_17_components_two,v_sec_17_components_one as sec_17_components_one;	
return next v_rfctaxsummary;

-----------------Flexi Components------------------------------------------------
if v_declaration_or_proof='D' then
open v_rfcflexicomponentsdetail for
with t1 as
(
	select
	 coalesce(mst_investment_section.investmentdescription,mst_investment_section.investmentname) componentname
	 ,0 componentvalue
	 ,mst_investment_section.headid,mst_investment_section.id investment_id
	,case when coalesce(investment_amount,0)=0 then 'N/A' else trn_investment.approval_status end  as approval_status
	,coalesce(investment_amount,0)  declr_amount	
	,coalesce(mst_investment_section.max_limit::text,'') max_limit
	from public.mst_investment_section left join public.trn_investment
	on trn_investment.investment_id=mst_investment_section.id
	and  trn_investment.emp_code=v_lastempcode
	and trn_investment.financial_year=p_financial_year
	and trn_investment.isactive='1'
	where mst_investment_section.headid=10
	and mst_investment_section.isactive='1'
and (
	(isacustomerspecific='Y' and p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	or
	(isacustomerspecific='N' and not p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	)
	)
select * from t1
union all
select
  'No Flexi Component' componentname,null componentvalue
 ,null headid,null investment_id,null  as approval_status,null declr_amount,null max_limit
 where not exists (select 1 from t1);
else
open v_rfcflexicomponentsdetail for
with t1 as
(
select componentname
	 ,coalesce(componentvalue,0) componentvalue
	 ,headid
	 ,investment_id
	,approval_status
	,coalesce(invamount,0)  declr_amount	
	,coalesce(max_limit::text,'') max_limit
from 
(select
    max(coalesce(mst_investment_section.investmentdescription,mst_investment_section.investmentname)) componentname

 ,sum(coalesce(receipt_amount,0)) componentvalue
 ,mst_investment_section.headid
 ,mst_investment_section.id investment_id
,max(trn_investment_proof.approval_status)  as approval_status
,max(coalesce(mst_investment_section.max_limit::text,'')) max_limit
from public.mst_investment_section left join public.trn_investment_proof
on trn_investment_proof.investment_id=mst_investment_section.id
and  trn_investment_proof.emp_code=v_lastempcode
and trn_investment_proof.financial_year=p_financial_year
and trn_investment_proof.isactive='1'
and approval_status in('A','P')
where mst_investment_section.headid=10
and (
	(isacustomerspecific='Y' and p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	or
	(isacustomerspecific='N' and not p_customeraccountid::bigint=any (coalesce(mst_investment_section.customeraccountids,Array[-9999])))
	)
group by  mst_investment_section.headid,mst_investment_section.id) t2
left join (
select 53 as invid, coalesce(v_monthwiseinvestment."Magazine Allowance",0) as invamount Union All
select 54 as invid, coalesce(v_monthwiseinvestment."Uniform Allowance",0) as invamount Union All
select 55 as invid, coalesce(v_monthwiseinvestment."Driver Allowance",0) as invamount Union All
select 56 as invid, coalesce(v_monthwiseinvestment."Fuel Allowance",0) as invamount Union All
select 57 as invid, coalesce(v_monthwiseinvestment."Education Allowance",0) as invamount Union All
select 58 as invid, coalesce(v_monthwiseinvestment."LTA ( 1 Months Basic Salary upto 75000)",0) as invamount
	
/****************change 1.13 starts******************/	
union all	
select ms.id invid,sum(ta.amount) invamount
from public.mst_investment_section ms left join public.tbl_monthwiseflexiinvestment ta
on ta.sectionid=ms.id
and  ta.emp_code=v_lastempcode
and ta.isactive='1'
where ms.headid=10
and ta.parentrowid=v_monthwiseinvestment.id
group by  ms.id	
/****************change 1.13 ends******************/	
	) tmpdeclr
on t2.investment_id=tmpdeclr.invid
	)
select * from t1
union all
select 'No Flexi Component' componentname
	 ,null componentvalue
	 ,null headid
	 ,null investment_id
	,null approval_status
	,null  declr_amount	
	,null max_limit
 where not exists (select 1 from t1);
   Raise Notice 'v_monthwiseinvestment.id=%,v_monthwiseinvestment."Magazine Allowance"=%,v_declaration_or_proof=%,v_proofapplicabledate=%, v_approval_status_value=%',v_monthwiseinvestment.id,v_monthwiseinvestment."Magazine Allowance",v_declaration_or_proof,v_proofapplicabledate,v_approval_status_value;

end if;
return next v_rfcflexicomponentsdetail;

open v_rfcprevincome for
SELECT tbl_migratedcustomerincomedtld.customeraccountid, tbl_migratedcustomerincomedtld.orgempcode, empname, finyear, grossearning, basic, hra, tds, pf, vpf, insurance
	FROM public.tbl_migratedcustomerincomedtld
	inner join openappointments op
	on lower(trim(tbl_migratedcustomerincomedtld.orgempcode))=lower(trim(op.orgempcode))
where tbl_migratedcustomerincomedtld.customeraccountid=p_customeraccountid::bigint
	  and op.emp_code=v_lastempcode
	  and finyear=p_financial_year
and tbl_migratedcustomerincomedtld.isactive='1';
return next v_rfcprevincome;	

end;
$BODY$;

ALTER FUNCTION public.uspcaltaxprojection_components(bigint, character varying, character varying, character varying)
    OWNER TO payrollingdb;

