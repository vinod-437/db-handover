-- FUNCTION: public.uspcalculatetaxonsalary(bigint, character varying, character varying, double precision, double precision, double precision, double precision, integer, integer, text, double precision, double precision, double precision, double precision, double precision)

-- DROP FUNCTION IF EXISTS public.uspcalculatetaxonsalary(bigint, character varying, character varying, double precision, double precision, double precision, double precision, integer, integer, text, double precision, double precision, double precision, double precision, double precision);

CREATE OR REPLACE FUNCTION public.uspcalculatetaxonsalary(
	p_emp_code bigint,
	p_financial_year character varying,
	p_regime character varying,
	p_currentgrossearning double precision,
	p_currentotherdeductions double precision,
	p_currentbasic double precision,
	p_currenthra double precision,
	p_month integer,
	p_year integer,
	p_batchid text,
	p_currentpf double precision DEFAULT 0.0,
	p_currentvpf double precision DEFAULT 0.0,
	p_currentinsurance double precision DEFAULT 0.0,
	p_currentprofessionaltax double precision DEFAULT 0.0,
	p_currentmealvoucher double precision DEFAULT 0.0)
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
v_currentmonthtaxdeducted numeric(18,2):=0;
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
v_approval_status_value varchar(1):='P';
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
	
v_pancard varchar(10);

v_pf   numeric(18,2);
v_vpf   numeric(18,2);
v_insurance   numeric(18,2);
v_professionaltax  numeric(18,2):=0;

v_existingpf   numeric(18,2);
v_existingvpf   numeric(18,2);
v_existinginsurance   numeric(18,2);
v_existingprofessionaltax  numeric(18,2):=0;
v_marginal_relief   numeric(18,2):=0;
v_presurcharge numeric(18,2):=0;
v_marginal_reliefsmall   numeric(18,2):=0;
v_empsalaryregister empsalaryregister%rowtype;
v_genesyspreviouspf numeric(18,2);
v_variablevpf numeric(18,2):=0;

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
v_finyearenddate date;

v_salary_head_text text;
v_rec_component record;
v_sql text;
v_sum_list text;
begin
/*************************************************************************
Version 	Date			Change								Done_by
1.1			25-Feb-2022		Added for Left Candidates			Shiv Kumar
1.2			05-Mar-2022		Only Approved Declarations			Shiv Kumar
1.3 		28-March-2022 	Current Month Tax Refund			Shiv Kumar
1.4			30-May-2022		Tax at hrgenerated					Shiv Kumar
1.5			07-Nov-2022		Tax on Pancard						Shiv Kumar
1.6			21-Apr-2023		Marginal Relief						Shiv Kumar	
1.7			31-May-2023		Marginal Relief for earners			Shiv Kumar
							with earning more than 750000
1.8			19-Sep-2023		Add projected PF,VPF and Insurance	Shiv Kumar
1.9			02-Oct-2023		Club Insurance and External			Shiv Kumar
						 	Health Insurance
1.10		24-Sep-2024		New Regime 2024-2025 changes

1.11		23-Oct-2024		Regenesys existing PF				Shiv Kumar	
1.12		06-Nov-2024		Migrated Clients Data				Shiv Kumar												 
1.13		20-Jan-2025		Flexi Allowance						Shiv Kumar
1.14		01-Apr-2025		Dynamic Tax Configuration
							based on uspcalculatetaxprojection Siddharth Bansal
1.15		23-Apr-2025		Adding Ten components   			Shiv Kumar	
							from commisiion to Bonus
1.16		04-Jul-2025		Meal Voucher						Shiv Kumar	
1.17		11-Nov-2025		Additional Income TDS next/current	Shiv Kumar	
1.18		20-Feb-2026		Flexi Components Min. Check			Shiv Kumar
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
select declaration_or_proof,financialyear,proofapplicabledate,is_fianncialyearcompleted into v_declaration_or_proof,v_financial_year,v_proofapplicabledate,v_is_fianncialyearcompleted from public.inv_declr_duration where financialyear=p_financial_year
	and customeraccountid=(select customeraccountid from openappointments where emp_code=p_emp_code);

if v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then
v_approval_status_value:='A';
ELSE
v_approval_status_value:='P';
end if;
select coalesce(left_flag,'N'),nullif(trim(pancard),'') into v_leftflag,v_pancard from openappointments where emp_code=p_emp_code;

v_year1:=left(p_financial_year,4)::int;
v_year2:=right(p_financial_year,4)::int;

/****************change 1.4*******************************/
v_startdate:=to_date(v_year1::text||'-05-01','yyyy-mm-dd');
v_enddate:=to_date(v_year2::text||'-04-30','yyyy-mm-dd');

v_advancestartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_advanceenddate:=to_date(v_year1::text||'-04-30','yyyy-mm-dd');
v_finyearenddate:=to_date(v_year2::text||'-03-31','yyyy-mm-dd');
 select DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE ) - INTERVAL '1 DAY')::date,
	DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;
/****************change 1.4 ends here*******************************/
select emp_id,gender
into v_empid,v_gender
from openappointments
where emp_code=p_emp_code
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
pf   numeric(18,2),
vpf   numeric(18,2),
insurance   numeric(18,2),
professionaltax   numeric(18,2),
salaryids varchar(500),
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
mealvoucher numeric(18,2)
) on commit drop;
/*********Line added for Change 1.8********/
select *
from public.empsalaryregister
	where isactive='1'
and appointment_id=v_empid
	order by id desc limit 1
into v_empsalaryregister;

select sum(deduction_amount)
	from public.trn_candidate_otherduction
where trn_candidate_otherduction.candidate_id=v_empid
	and trn_candidate_otherduction.active='Y'
	and trn_candidate_otherduction.deduction_id =10
	and trn_candidate_otherduction.salaryid=v_empsalaryregister.id
into v_variablevpf;
	v_variablevpf:=coalesce(v_variablevpf,0); 
	/***Line added for Change 1.8 end here***/
insert into tmpsalstructure
select basic,hra,allowances,conveyance_allowance,medical_allowance,effectivefrom,effectiveto,12,locationtype
,(select sum(deduction_amount) from trn_candidate_otherduction where candidate_id=v_empid 
  and trn_candidate_otherduction.salaryid=empsalaryregister.id
  and coalesce(includedinctc,'N')='Y'
	and deduction_id not in(5,6,7,12,134)--134 Meal Voucher ID
	and coalesce(isvariable,'N')='N'
	and deduction_frequency in ('Quarterly','Half Yearly','Annually')) as otherdeductions
	,coalesce(employeeepfrate,0)
	,coalesce(vpfemployee,0)+coalesce(v_variablevpf,0)
	,(coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))
	,coalesce(professionaltax,0)
	,id::text
	,commission, transport_allowance, travelling_allowance, leave_encashment, overtime_allowance, notice_pay, hold_salary_non_taxable, children_education_allowance, gratuityinhand, salarybonus
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
and appointment_id=v_empid
order by id desc
limit 1;

--v_mon1:=extract (month from current_date);   -- Commented date 28Oct 2021 due to two salary pay in same month

if p_month = 12 then
	v_mon1:=1;
else
	v_mon1:=p_month+1;
end if;
if v_mon1 between 5 and 12 then
	v_mon1:=(12-v_mon1)+4;
else
	v_mon1:=(3-v_mon1)+1;
end if;
--Change 1.1 
if extract (month from current_date)=4 then
	if extract (year from current_date)<v_year2 then
		v_mon1:=11;
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
update tmpsalstructure set totalmonths=v_mon1;

select salaryids into v_activesalaryid from tmpsalstructure;

select  sum(basic+coalesce(incrementarear_basic,0)),
		sum(hra+coalesce(incrementarear_hra,0)), 
		sum(coalesce(epf,0))+p_currentpf,
		sum(coalesce(vpf,0))+p_currentvpf,
		sum(coalesce(insurance,0))+p_currentinsurance,
		sum(coalesce(professionaltax,0))+p_currentprofessionaltax  
		,sum(mealvoucher)
		into v_existingbasic,
		v_existinghra,
		v_existingpf,
		v_existingvpf,
		v_existinginsurance,
		v_existingprofessionaltax
		,v_existingmealvoucher
from (select emp_code,basic,incrementarear_basic,hra,incrementarear_hra,isarear,recordscreen,hrgeneratedon,is_rejected, epf,vpf,insurance,professionaltax
	 ,mealvoucher
	   from tbl_monthlysalary
	 	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y'))  and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1' and
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
		and (tdsdeductionmonth='current' or make_date(p_year,p_month,1)>make_date(mpryear,mprmonth,1)) --change 1.18
	  union all
	  select emp_code,basic,incrementarear_basic,hra,incrementarear_hra,isarear,recordscreen,hrgeneratedon,is_rejected,epf,vpf,insurance,professionaltax
	 ,mealvoucher
from tbl_monthly_liability_salary
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and 
	  coalesce(salary_remarks,'')<>'Invalid Paid Days'
	and coalesce(is_rejected,'0')='0'
----------------------------------------------------------------------------------------------------	  
	 and (emp_code,mprmonth, mpryear, batchid) not in(select p_emp_code,p_month,p_year,p_batchid)
	 and (emp_code,mprmonth, mpryear, batchid||transactionid) not in (select p_emp_code,p_month, p_year, p_batchid) 
----------------------------------------------------------------------------------------------------------------	  
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
	 where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and (
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
		 from tbl_monthlysalary where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and (
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
	 from tbl_monthlysalary m where (m.emp_code=p_emp_code or  m.emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and coalesce(m.is_rejected,'0')='0'
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
----------------------------------------------------------
and (emp_code,mprmonth, mpryear, batchid) not in
	(select p_emp_code,p_month, p_year, p_batchid) 	
and (emp_code,mprmonth, mpryear, batchid||transactionid) not in
	(select p_emp_code,p_month, p_year, p_batchid) 		  
----------------------------------------------------------	  
	 )tbl_monthlysalary
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y'))
and (isarear<>'Y' or recordscreen in ('Previous Wages','Arear Wages','Increment Arear'))
/*and to_date('01'||lpad(mprmonth::text,2,'0')||mpryear::text,'ddmmyyyy')
between to_date(v_year1||'-04-01','yyyy-mm-dd') and least((DATE_TRUNC('MONTH', current_date) - INTERVAL '1 DAY'),to_date(v_year2||'-03-31','yyyy-mm-dd')) 
*/
and coalesce(is_rejected,'0')<>'1';

select sum(tds)
,sum(case when 
	 ((
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
	   and attendancemode<>'Ledger'
	   )
		or(to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')	between v_advancestartdate  and v_finyearenddate and attendancemode='Ledger')	  
	 )
	 then tds else 0 end) 
,sum(grossearning-coalesce(voucher_amount,0)/*+coalesce(vpf,0)*/)   -- Added on 23 Oct 2021 with disucssion with Account Team
,sum(otherdeductions)
into v_taxdeducted
,v_currentmonthtaxdeducted  --change 1.3
,v_existinggrossearning,
v_existingotherdeductions
from (select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear,attendancemode
	  from tbl_monthlysalary
	 where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y'))   and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1' 
	  and (((
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
		
	   and attendancemode<>'Ledger'
	   )
		or(to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')	between v_advancestartdate  and v_finyearenddate and attendancemode='Ledger')	  
	 )
	 -- added new dated 21-11-2025
		and (tdsdeductionmonth='current' or make_date(p_year,p_month,1)>make_date(mpryear,mprmonth,1)) --change 1.18
		--
	 union all
	  select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear,attendancemode
	from tbl_monthly_liability_salary
	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and coalesce(salary_remarks,'')<>'Invalid Paid Days'
	and coalesce(is_rejected,'0')='0'
---------------------------------------------------------------------------------------------------------------------	
	and (emp_code,mprmonth, mpryear, batchid) not in(select p_emp_code,p_month,p_year,p_batchid)  
	and (emp_code,mprmonth, mpryear, batchid||transactionid) not in (select p_emp_code,p_month, p_year, p_batchid)
----------------------------------------------------------------------------------------------------------------------	  
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
	 	where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and (
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
		 from tbl_monthlysalary where  (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and(
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
	 from tbl_monthlysalary m where (m.emp_code=p_emp_code or  m.emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y')) and coalesce(m.is_rejected,'0')='0'
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
where (emp_code=p_emp_code or  emp_code in(select emp_code from openappointments where pancard=v_pancard  and appointment_status_id=11 and converted='Y'))
--and (isarear<>'Y' or recordscreen ='Previous Wages')
/*and to_date('01'||lpad(mprmonth::text,2,'0')||mpryear::text,'ddmmyyyy')
between to_date(v_year1||'-04-01','yyyy-mm-dd') and least((DATE_TRUNC('MONTH', current_date) - INTERVAL '1 DAY'),to_date(v_year2||'-03-31','yyyy-mm-dd'))*/  
and coalesce(is_rejected,'0')<>'1';

v_taxdeducted:=coalesce(v_taxdeducted,0);

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
+coalesce(mealvoucher,0)
)*totalmonths
)+coalesce(v_existinggrossearning,0)-
coalesce(v_existingotherdeductions,0)
+coalesce(p_currentgrossearning,0)-
coalesce(p_currentotherdeductions,0)
+ COALESCE(v_existingmealvoucher , 0),
sum(basic*totalmonths)+coalesce(v_existingbasic,0)+coalesce(p_currentbasic,0),sum(hra*totalmonths)+coalesce(v_existinghra,0)+coalesce(p_currenthra,0),max(locationtype),
sum(coalesce(pf,0)*totalmonths)+coalesce(v_existingpf,0),
sum(coalesce(vpf,0)*totalmonths)+coalesce(v_existingvpf,0),
sum(coalesce(insurance,0)*totalmonths)+coalesce(v_existinginsurance,0),
coalesce(v_existingprofessionaltax,0),
SUM(coalesce(mealvoucher,0) * totalmonths) + COALESCE(v_existingmealvoucher , 0)
into v_totalincome,v_basic,v_hra,v_locationtype,v_pf,v_vpf,v_insurance,v_professionaltax
,v_mealvoucher
from tmpsalstructure;

v_metrononmetrohra:=case when upper(v_locationtype)='METRO' then v_basic*0.5 else v_basic*0.4 end;
/***************Populate EPF, VPF, Insurance and professional Tax in Investment table****************************/
--select * from mst_investment_section where id in (5,25,26,50) order by id;
--select * from trn_investment  limit 1;
	/********Update Insurance************/
v_insurance:=coalesce(v_insurance,0);

if exists(select * from public.trn_investment where headid=1 and financial_year=p_financial_year and investment_id=5  and emp_code=p_emp_code and isactive='1') then
	update public.trn_investment
	set investment_amount=v_insurance
		,approval_status='A'
		,approvedon=current_timestamp
		,approvedby='-9999'
		,approvedbyip='System'
	where headid=1 and financial_year=p_financial_year and investment_id=5  and emp_code=p_emp_code and isactive='1';	
else
	INSERT INTO public.trn_investment(
	headid, financial_year, investment_id, emp_code, emp_id, investment_amount, investment_comment, createdby, createdon, createdbyip, isactive, approval_status, approvedon, approvedby, approvedbyip)
	VALUES (1,p_financial_year,5,p_emp_code,v_empid,v_insurance,'Insurance Investment Inserted by Current Salary generation',-9999,current_timestamp,'System','1','A',current_timestamp,-9999,'System');

end if;

	/********Update EPF************/
	/*****************************change 1.8 starts*******************************************/
select 
coalesce(nullif(pf_apr2024,'')::numeric(18),0)+
coalesce(nullif(pf_may2024,'')::numeric(18),0)+
coalesce(nullif(pf_jun2024,'')::numeric(18),0)+
coalesce(nullif(pf_jul2024,'')::numeric(18),0)+
coalesce(nullif(pf_aug2024,'')::numeric(18),0)
from regenesyspreviousincome rp inner join openappointments op
on rp.employee_code=op.orgempcode
and p_financial_year='2024-2025'
and op.emp_code=p_emp_code
and op.customeraccountid=5484 --Regenesys Employee Apr2024 to Aug2024 PF due to mid Finyear Data Migration
into v_genesyspreviouspf;
v_pf:=coalesce(v_pf,0)+coalesce(v_genesyspreviouspf,0);
Raise Notice 'v_totalincome=%',v_totalincome;

/*****************************change 1.8 ends*******************************************/
if exists(select * from public.trn_investment where headid=2 and financial_year=p_financial_year and investment_id=25  and emp_code=p_emp_code and isactive='1') then
	update public.trn_investment
	set investment_amount=v_pf
		,approval_status='A'
		,approvedon=current_timestamp
		,approvedby='-9999'
		,approvedbyip='System'
	where headid=2 and financial_year=p_financial_year and investment_id=25  and emp_code=p_emp_code and isactive='1';	
else
	INSERT INTO public.trn_investment(
	headid, financial_year, investment_id, emp_code, emp_id, investment_amount, investment_comment, createdby, createdon, createdbyip, isactive, approval_status, approvedon, approvedby, approvedbyip)
	VALUES (2,p_financial_year,25,p_emp_code,v_empid,v_PF,'PF Investment Inserted by Current Salary generation',-9999,current_timestamp,'System','1','A',current_timestamp,-9999,'System');

end if;
	/********Update VPF************/
if exists(select * from public.trn_investment where headid=2 and financial_year=p_financial_year and investment_id=26  and emp_code=p_emp_code and isactive='1') then
	update public.trn_investment
	set investment_amount=v_vpf
		,approval_status='A'
		,approvedon=current_timestamp
		,approvedby='-9999'
		,approvedbyip='System'
	where headid=2 and financial_year=p_financial_year and investment_id=26  and emp_code=p_emp_code and isactive='1';	
else
	INSERT INTO public.trn_investment(
	headid, financial_year, investment_id, emp_code, emp_id, investment_amount, investment_comment, createdby, createdon, createdbyip, isactive, approval_status, approvedon, approvedby, approvedbyip)
	VALUES (2,p_financial_year,26,p_emp_code,v_empid,v_vPF,'VPF Investment Inserted by Current Salary generation',-9999,current_timestamp,'System','1','A',current_timestamp,-9999,'System');

end if;
	/********Update Professional Tax************/
if v_customeraccountid<>5484 then
if exists(select * from public.trn_investment where headid=8 and financial_year=p_financial_year and investment_id=50  and emp_code=p_emp_code and isactive='1') then
	update public.trn_investment
	set investment_amount=v_professionaltax
		,approval_status='A'
		,approvedon=current_timestamp
		,approvedby='-9999'
		,approvedbyip='System'
	where headid=8 and financial_year=p_financial_year and investment_id=50  and emp_code=p_emp_code and isactive='1';	
else
	INSERT INTO public.trn_investment(
	headid, financial_year, investment_id, emp_code, emp_id, investment_amount, investment_comment, createdby, createdon, createdbyip, isactive, approval_status, approvedon, approvedby, approvedbyip)
	VALUES (8,p_financial_year,50,p_emp_code,v_empid,v_professionaltax,'Professional Tax Investment Inserted by Current Salary generation',-9999,current_timestamp,'System','1','A',current_timestamp,-9999,'System');

end if;
end if;
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
/***************Populate EPF, VPF, Insurance and professional Tax in Investment table ends****************************/
-----------Condition commented for change 1.2----------------------
-- if exists(select *
-- 	from empdeclaration_rentdetails
-- 	where emp_code=p_emp_code
--  	and financial_year=p_financial_year
--  	and isactive='1'
--  	and approval_status='A') 
-- then

	select sum(rentpaid) into v_rentpaid
	from empdeclaration_rentdetails
	where emp_code=p_emp_code
	 and financial_year=p_financial_year
	 and isactive='1'
	 and coalesce(approval_status,'P')=case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then 'A' else coalesce(approval_status,'P') end;
--  else
-- 	select sum(rentpaid) into v_rentpaid
-- 	from empdeclaration_rentdetails
-- 	where emp_code=p_emp_code
-- 	 and financial_year=p_financial_year
-- 	 and isactive='1';

-- end if;
----------------------------------------------------------

v_hraexemption:=least((v_hra+v_previousemployerhra+coalesce(v_rec.hra,0)),v_metrononmetrohra,greatest(v_rentpaid-(v_basic+v_previousemployerbasic+coalesce(v_rec.basic,0))*.10,0));
raise notice 'v_hraexemption=%',v_hraexemption;
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
 where emp_code=p_emp_code
 and financial_year=p_financial_year
 and active='1';
 
 
 select interest_on_borrowed_capital,isbefore01apr1999
 into v_lossonproperty,v_isbefore01apr1999
 from public.empdeclr_homeloan
 where emp_code=p_emp_code
 and financial_year=p_financial_year
 and active='1'
 and coalesce(approval_status,'P')=case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then 'A' else coalesce(approval_status,'P') end;--Added for change 1.2
 
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
where emp_code=p_emp_code
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
if v_customeraccountid=7416 then
-----------------------------------------------
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
    if v_sql is not null then
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
    else
        create temporary table tmp2 on commit drop as select ''::text as componentname, ''::text as newcomponentname, 0::numeric as total_amount where false;
    end if;
 /********change 1.13 starts***************/
select
sum(least(coalesce(total_amount,0),coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0)))
into v_flexocomponents
from trn_investment
inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and trn_investment.headid=10
and trn_investment.isactive='1'
and trn_investment.emp_code=p_emp_code
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
and trn_investment.emp_code=p_emp_code
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id<>58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
--group by investment_id
	;
end if;	
 raise notice 'v_hraexemption=%',v_flexocomponents;

v_flexocomponents:=coalesce(v_flexocomponents,0);

select
sum(least(coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0)))
into v_lta
from trn_investment
inner join public.mst_investment_section
on trn_investment.investment_id=mst_investment_section.id
and trn_investment.headid=10
and trn_investment.isactive='1'
and trn_investment.emp_code=p_emp_code
and trn_investment.financial_year=v_financial_year
and mst_investment_section.id=58  /*******LTA******/ 
and coalesce(approval_status,'P')= case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate  then 'A' else coalesce(approval_status,'P') end
group by investment_id;
 
v_projectedalaryids:=v_projectedalaryids||coalesce(','||v_activesalaryid,'');
Raise notice 'v_projectedalaryids=%',v_projectedalaryids;
select basic from empsalaryregister where id =v_activesalaryid
into v_onemonthbasic;
v_onemonthbasic:=coalesce(v_onemonthbasic,0);
v_lta:=coalesce(v_lta,0);
v_lta:=least(v_lta,v_basic,v_onemonthbasic);
 raise notice 'lta=%',v_lta;

v_flexocomponents:=v_flexocomponents+v_lta;
  /********Added for change 1.13 ends***************/

 /********Added for change 1.9***************/
select
sum(case when mst_investment_section.id in (11,52) then coalesce(investment_amount,0)
   when mst_investment_section.id =51 then coalesce(investment_amount,0)*.50
   when mst_investment_section.id =5 then least(coalesce(investment_amount,0)+coalesce(v_rec.insurance,0),coalesce(max_limit,coalesce(investment_amount,0)+coalesce(v_rec.insurance,0),0))
	else
	least(coalesce(investment_amount,0),coalesce(max_limit,investment_amount,0))
   end) into v_chapter6deductions
from( select investment_id,sum(investment_amount) investment_amount
	 from (select case when  investment_id=1 then 5 else investment_id end as investment_id,investment_amount
	   from trn_investment
where  trn_investment.emp_code=p_emp_code
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
  /********Added for change 1.9 ends***************/
 v_chapter6deductions:=coalesce(v_chapter6deductions,0);
 
 
select sum(investment_amount)
into v_us80cdeductions
from public.trn_investment
where  headid=2
and emp_code=p_emp_code
and financial_year=p_financial_year
and isactive='1'
and trn_investment.investment_id not in (23,24) --Added on 02-Apr-2022
and coalesce(approval_status,'P')=case when trn_investment.investment_id in (25,26) then 'A' else case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then 'A' else coalesce(approval_status,'P') end end;--Added for change 1.2
--Added for 80ccd dated 22 oct2021
select sum(investment_amount)
into v_us80ccd_deductions
from public.trn_investment
where  headid=2
and emp_code=p_emp_code
and financial_year=p_financial_year
and isactive='1'
and trn_investment.investment_id=24
and coalesce(approval_status,'P')=case when v_declaration_or_proof='P' and current_date>=v_proofapplicabledate then 'A' else coalesce(approval_status,'P') end;--Added for change 1.2
--Added for 80ccd dated 22 oct2021 end here

v_us80ccd_deductions:=case when coalesce(v_us80ccd_deductions,0)>50000 then 50000 else coalesce(v_us80ccd_deductions,0) end;--Added on 02-Apr-2022

v_us80cdeductions:=coalesce(v_us80cdeductions,0)+coalesce(v_rec.pf,0);

v_us80cdeductions:=least(coalesce(v_us80cdeductions,0),150000);

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
v_mealvoucher=coalesce(v_mealvoucher,0)+coalesce(p_currentmealvoucher,0);
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

open v_rfctaxproj for
select v_totalincome totalincome,
	  v_totalsavings totalsavings,
      v_taxableincome taxableincome,
	  v_netpayabletax netpayabletax,
	  v_taxdeducted taxdeducted,
	  v_balancetax balancetax,
	  v_taxslab taxslab
	  ,v_currentmonthtaxdeducted currentmonthtaxdeducted;  --change 1.3
return v_rfctaxproj;
end;
$BODY$;

ALTER FUNCTION public.uspcalculatetaxonsalary(bigint, character varying, character varying, double precision, double precision, double precision, double precision, integer, integer, text, double precision, double precision, double precision, double precision, double precision)
    OWNER TO payrollingdb;

