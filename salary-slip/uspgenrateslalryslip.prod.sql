-- FUNCTION: public.uspgeneratesalaryslip(bigint, integer, integer, text, text)

-- DROP FUNCTION IF EXISTS public.uspgeneratesalaryslip(bigint, integer, integer, text, text);

CREATE OR REPLACE FUNCTION public.uspgeneratesalaryslip(
	p_emp_code bigint,
	p_month integer,
	p_year integer,
	p_origin text DEFAULT 'Employee'::text,
	p_salaryslipmode text DEFAULT 'Actual'::text)
    RETURNS SETOF refcursor 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
/***********************************************************************************************************
S.No. 	Date			Remarks 											Done By						
1.0						Initial Version										Shiv Kumar						
1.1		24-Aug-2024		Hide Salary slip for CTC<=22000 for JIVO(2719)		Shiv Kumar						
1.2		30-Sep-2024		Hide Salary slip for CTC<=8000 for Kateba(4643)	Shiv Kumar
						As per mail Dates 27-Sep-2024 Fwd: Regarding Tankha pay not generating salary slip
1.3		12-Nov-2024		Remove 01/01/1950 dateofbirth  from salary slip	Parveen Kumar
1.4		13-Jan-2025		Add netpay_in_words in salary slip response			Parveen Kumar
1.5		19-Feb-2025		Hide salary slip for Cloudone Systems Private Limite Shiv Kumar
1.6		01-April-2025	Add salary slip data show/hide functionality			Parveen Kumar
1.7		13-Jun-2025		Add v_logopathtwo in salary slip response			Parveen Kumar
1.8		10-Sep-2025		deduct exit days from LOP							Shiv Kumar	
1.9		26-Sep-2025		Add NULLIF(mtd_designation.designationname, '') in response 	Parveen Kumar	
2.0		26-Sep-2025		Jobrole for self and hybrid 						Shiv Kumar	
2.2 	19-Dec-2025		Bifurcate Vouchers and Deductions					Shiv Kumar
*************************************************************************************************************/
declare
	v_rfcsalary refcursor;
	v_refsalaryslip refcursor;
	v_deductions refcursor;
	v_variables refcursor;
	v_ledgervariables refcursor;
	v_ledgerdeductions refcursor;
	v_pancarddetaild refcursor;
	v_rec record;
	v_paiddays double precision;
	v_monthdays double precision;
	v_lopdays double precision;

	v_salstartdate date;
	v_salenddate date;
	v_prevsaldate date;
	v_advancesalstartdate date;
	v_advancesalenddate date;
	v_tptype character varying:='NonTP'::character varying;

	/********************************|| START - Parveen on 15 May 2023||********************************/
	v_principal_employer_name character varying:=''::character varying;
	/********************************|| END - Parveen on 15 May 2023||********************************/
    v_employername character varying(500);
    v_address character varying(500);
    v_logopath character varying(255);
    v_logopathtwo character varying(255);
	v_customeraccountid bigint;
	v_payoutmodetype varchar(10);
	v_ctc numeric(18,2);
	v_dynamicearningheads refcursor;
	v_dynamicdeductionheads refcursor;
	v_view_salary_slip VARCHAR(1);
	v_emp_address varchar(500);
	v_residential_address varchar(500);
	v_show_employee_address varchar(1)='N';
	v_mealamount numeric(18,2);
	v_rfcmealvoucher refcursor;
	v_rfcblank refcursor;
	v_leavebalance numeric(18,2);
	v_emp_id bigint;
	v_posting_department varchar(1000);
	v_lrelievingdays int:=0;
	v_openappointments openappointments%rowtype;
	v_fullmonthdays int;
begin
	select mealamount from  trnmealvoucher where emp_code=p_emp_code and mealmonth=p_month and mealyear=p_year and isactive='1' into v_mealamount;
	v_mealamount:=coalesce(v_mealamount,0);
	select payout_mode_type,emp_address,residential_address,emp_id,posting_department
	from  openappointments op
	inner join tbl_account ta on op.customeraccountid=ta.id and op.emp_code=p_emp_code
	into v_payoutmodetype,v_emp_address,v_residential_address,v_emp_id,v_posting_department;

v_fullmonthdays:=date_part('day',DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');

    select DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE ) - INTERVAL '1 DAY')::date,
	DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;
/*********************************************************************************/
if p_origin='Employee' and exists(select * from tbl_monthlysalary t inner join openappointments op 
		  on t.emp_code=op.emp_code
		  and t.emp_code=p_emp_code
		  inner join empsalaryregister e on t.salaryid=e.id
		  where e.is_special_category='Y'
			and coalesce(is_rejected,'0')<>'1'
			and mprmonth=p_month and mpryear=p_year
		  ) then

open v_refsalaryslip for select 'x' as nodata where 1=2;
return next v_refsalaryslip;

else
	if (select recordsource from openappointments where emp_code=p_emp_code)='HUBTPCRM' then
		v_tptype:='TP';	
	else
		v_tptype:='NonTP';
	end if;
/********************************|| START - Parveen on 15 May 2023||********************************/
select (string_to_array(accountname::varchar,'#'))[1]::varchar(200),ta.id
from tbl_account ta inner join openappointments op
on ta.id=op.customeraccountid and op.emp_code=p_emp_code
into v_principal_employer_name,v_customeraccountid;

-- vinod dated. 15.05.2025
IF v_customeraccountid in ( 6488)  then --CMSAE CREDITORS MANAGEMENT SOLUTIONS PRIVATE LIMITED#09AALCC3796P1ZN-20250107 12:01:39
	v_show_employee_address:= 'Y';
END if;
-- end 
/********************************|| END - Parveen on 15 May 2023||********************************/

-- START - Change [1.6]
	SELECT salary_flag FROM tbl_tp_emp_app_settings WHERE active = '1' AND customeraccountid = v_customeraccountid ORDER BY id DESC LIMIT 1 INTO v_view_salary_slip;
	v_view_salary_slip := COALESCE(v_view_salary_slip, 'N');
	RAISE NOTICE 'customeraccountid %' , v_customeraccountid;
	RAISE NOTICE 'v_view_salary_slip %' , v_view_salary_slip;

	-- As Discussed with Chandra Mohan Sir --> [Y - Hide Salary Slip], [N - Show Salary Slip]
	IF v_view_salary_slip = 'Y' AND p_origin = 'Employee' THEN
		OPEN v_refsalaryslip FOR
			SELECT 'x' AS nodata WHERE 1 = 2;
		RETURN NEXT v_refsalaryslip;
	END IF;
-- END - Change [1.6]

 select
	employername,COALESCE(NULLIF(address_html, ''), address),
	COALESCE(NULLIF(logopath_one, ''), logopath) logopath,
	logopath_two
 from employer 
 where account_id=v_customeraccountid
 into v_employername,v_address,v_logopath, v_logopathtwo; -- Changes [1.7]
 v_principal_employer_name := v_employername;
/*********************************************************************************/
select sum(paiddays),max(monthdays),max(monthdays)-sum(paiddays)
into v_paiddays, v_monthdays ,v_lopdays
from tbl_monthlysalary 
where emp_code=p_emp_code
 and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1' 
and mprmonth=p_month
and mpryear=p_year
and recordscreen='Current Wages'
and is_rejected<>'1';
/*********************Change 1.8 starts**********************/
	select * from openappointments where emp_code=p_emp_code into v_openappointments;
	if v_openappointments.left_flag='Y' and date_trunc('month',v_openappointments.dateofrelieveing)=make_date(p_year,p_month,1) then
		v_lrelievingdays:=(extract('day' from v_advancesalenddate) -extract('day' from v_openappointments.dateofrelieveing))::int;
	end if;
	v_lopdays:=greatest(v_lopdays-v_lrelievingdays,0);
/*************88Change 1.8 ends********************************/

				select * into v_rfcsalary 
				from uspmonthwisebilling(
						p_rptyear =>p_year,
						p_rptmonth =>p_month,
						p_action =>'GetMonthBilling',
						p_empcode=>p_emp_code,
						p_tptype=>v_tptype
						);

create temporary table  tmpsalslip 
(
	mon	varchar(100),
	employee	Bigint,
	employee_name	varchar(100),
	father_husband_name	varchar(100),
	designation	varchar(100),
	department	varchar(1000),
	subunit	varchar(100),
	dateofjoining	varchar(100),
	dateofbirth	varchar(100),
	esinumber	varchar(40),
	pan_number	varchar(100),
	uannumber	varchar(100),
	subunit_2	varchar(100),
	employee_2	Bigint,
	email	varchar(100),
	aadharcard	varchar(100),
	dateofleaving	varchar(100),
	arrear_days	Numeric (18,2),
	loss_off_pay	Numeric (18,2),
	total_paid_days	Numeric (18,2),
	ratebasic	Numeric (18,2),
	ratehra	Numeric (18,2),
	rateconv	Numeric (18,2),
	ratemedical	Numeric (18,2),
	ratespecial_allowance	Numeric (18,2),
	fixedallowancestotalrate	Numeric (18,2),
	basic	Numeric (18,2),
	hra	Numeric (18,2),
	conv	Numeric (18,2),
	medical	Numeric (18,2),
	specialallowance	Numeric (18,2),
	arr_basic	Numeric (18,2),
	arr_hra	Numeric (18,2),
	arr_conv	Numeric (18,2),
	arr_medical	Numeric (18,2),
	arr_specialallowance	Numeric (18,2),
	incentive	Numeric (18,2),
	refund	Numeric (18,2),
	monthly_bonus	Numeric (18,2),
	grossearning	Numeric (18,2),
	epf	Numeric (18,2),
	vpf	Numeric (18,2),
	esi	Numeric (18,2),
	tds	Numeric (18,2),
	loan	Numeric (18,2),
	lwf	Numeric (18,2),
	insurance	Numeric (18,2),
	mobile	Numeric (18,2),
	advance	Numeric (18,2),
	other	Numeric (18,2),
	grossdeduction	Numeric (18,2),
	netpay	Numeric (18,2),
	ac_1	Numeric (18,2),
	ac_10	Numeric (18,2),
	ac_2	Numeric (18,2),
	ac21	Numeric (18,2),
	employer_esi_contr	Numeric (18,2),
	salarystatus	varchar(100),
	arearaddedmonths	varchar(100),
	monthdays	Numeric (18,2),
	salaryid	bigint,
	banktransferstatus	varchar(100),
	atds	Numeric (18,2),
	voucher_amount	Numeric (18,2),
	ews	Numeric (18,2),
	gratuity	Numeric (18,2),
	bonus	Numeric (18,2),
	employeenps	Numeric (18,2),
	damagecharges	Numeric (18,2),
	otherledgerarears	Numeric (18,2),
	otherledgerdeductions	Numeric (18,2),
	othervariables	Numeric (18,2),
	otherdeductions	Numeric (18,2),
	otherledgerarearwithoutesi	Numeric (18,2),
	otherbonuswithesi	Numeric (18,2),
	totalarear	Numeric (18,2),
	lwf_employer	Numeric (18,2),
	insurancetype	varchar(100),
	ordercol	varchar(100),
	current_govt_bonus_amt 	Numeric (18,2),
	arear_govt_bonus_amt 	Numeric (18,2),
	refunddeduction Numeric (18,2),
	professionaltax Numeric (18,2),
	ratecommission NUMERIC(18,2),
	ratetransport_allowance NUMERIC(18,2),
	ratetravelling_allowance NUMERIC(18,2),
	rateleave_encashment NUMERIC(18,2),
	rateovertime_allowance NUMERIC(18,2),
	ratenotice_pay NUMERIC(18,2),
	ratehold_salary_non_taxable NUMERIC(18,2),
	ratechildren_education_allowance NUMERIC(18,2),
	rategratuityinhand NUMERIC(18,2),
	commission NUMERIC(18,2),
	transport_allowance NUMERIC(18,2),
	travelling_allowance NUMERIC(18,2),
	leave_encashment NUMERIC(18,2),
	overtime_allowance NUMERIC(18,2),
	notice_pay NUMERIC(18,2),
	hold_salary_non_taxable NUMERIC(18,2),
	children_education_allowance NUMERIC(18,2),
	gratuityinhand NUMERIC(18,2),
	ratesalarybonus NUMERIC(18,2),
	salarybonus NUMERIC(18,2),
	ctc  NUMERIC(18,2),
	tea_allowance Numeric (18,2),
	commission_arear	numeric,
	transport_allowance_arear	numeric,
	travelling_allowance_arear	numeric,
	leave_encashment_arear	numeric,
	overtime_allowance_arear	numeric,
	notice_pay_arear	numeric,
	hold_salary_non_taxable_arear	numeric,
	children_education_allowance_arear	numeric,
	gratuityinhand_arear	numeric,
	salarybonus_arear	numeric,
	disbursedledgerids text,
	charity_contribution_amount numeric(18,2),
	charity_contribution_amount_arear numeric(18,2),
	mealvoucher  numeric(18,2),
	leavetaken NUMERIC(18,2),
	salaryjson text,
	salid1 bigint,
	salid2 bigint,
	salid3 bigint
) on commit drop;

 LOOP 
     FETCH v_rfcsalary INTO v_rec; 
     EXIT WHEN NOT FOUND; 

insert into tmpsalslip(mon,employee,employee_name,father_husband_name,designation,department,
	subunit,dateofjoining,dateofbirth,esinumber,pan_number,uannumber,subunit_2,employee_2,email,aadharcard,
	dateofleaving,arrear_days,loss_off_pay,total_paid_days,ratebasic,ratehra,rateconv,ratemedical,ratespecial_allowance,
	fixedallowancestotalrate,basic,hra,conv,medical,specialallowance,arr_basic,arr_hra,arr_conv,arr_medical,
	arr_specialallowance,incentive,refund,monthly_bonus,grossearning,epf,vpf,esi,tds,loan,lwf,insurance,
	mobile,advance,other,grossdeduction,netpay,ac_1,ac_10,ac_2,ac21,employer_esi_contr,salarystatus,
	arearaddedmonths,monthdays,salaryid,banktransferstatus,atds,voucher_amount,ews,gratuity,bonus,
	employeenps,damagecharges,otherledgerarears,otherledgerdeductions,othervariables,otherdeductions,
	otherledgerarearwithoutesi,otherbonuswithesi,totalarear,lwf_employer,insurancetype,ordercol,current_govt_bonus_amt,arear_govt_bonus_amt,refunddeduction, professionaltax,
	ratesalarybonus,	ratecommission,	ratetransport_allowance,	ratetravelling_allowance,	rateleave_encashment,	rateovertime_allowance,	ratenotice_pay,	ratehold_salary_non_taxable,	ratechildren_education_allowance,	rategratuityinhand,	salarybonus,	commission,	transport_allowance,	travelling_allowance,	leave_encashment,	overtime_allowance,	notice_pay,	hold_salary_non_taxable,	children_education_allowance,	gratuityinhand
	,ctc,tea_allowance
	,commission_arear
	,transport_allowance_arear
	,travelling_allowance_arear
	,leave_encashment_arear
	,overtime_allowance_arear
	,notice_pay_arear
	,hold_salary_non_taxable_arear
	,children_education_allowance_arear
	,gratuityinhand_arear
	,salarybonus_arear
	,disbursedledgerids
	,charity_contribution_amount
	,charity_contribution_amount_arear
	,mealvoucher,leavetaken,
	salaryjson,
	salid1,salid2,salid3)
select v_rec.mon,v_rec.employee,v_rec.employee_name,v_rec.father_husband_name,v_rec.designation,v_rec.department,v_rec.
	subunit,v_rec.dateofjoining,v_rec.dateofbirth,v_rec.esinumber,v_rec.pan_number,v_rec.uannumber,v_rec.subunit_2,v_rec.employee_2,v_rec.email,v_rec.aadharcard,v_rec.
	dateofleaving,v_rec.arrear_days,v_rec.loss_off_pay,v_rec.total_paid_days,v_rec.ratebasic,v_rec.ratehra,v_rec.rateconv,v_rec.ratemedical,v_rec.ratespecial_allowance,v_rec.
	fixedallowancestotalrate,v_rec.basic,v_rec.hra,v_rec.conv,v_rec.medical,v_rec.specialallowance,v_rec.arr_basic,v_rec.arr_hra,v_rec.arr_conv,v_rec.arr_medical,v_rec.
	arr_specialallowance,v_rec.incentive,v_rec.refund,v_rec.monthly_bonus,v_rec.grossearning,v_rec.epf,v_rec.vpf,v_rec.esi,v_rec.tds,v_rec.loan,v_rec.lwf,v_rec.insurance,v_rec.
	mobile,v_rec.advance,v_rec.other,v_rec.grossdeduction,round(v_rec.netpay),v_rec.ac_1,v_rec.ac_10,v_rec.ac_2,v_rec.ac21,v_rec.employer_esi_contr,v_rec.salarystatus,v_rec.
	arearaddedmonths,v_rec.monthdays,v_rec.salaryid,v_rec.banktransferstatus,v_rec.atds,v_rec.voucher_amount,v_rec.ews,v_rec.gratuity,v_rec.bonus,v_rec.
	employeenps,v_rec.damagecharges,v_rec.otherledgerarears,v_rec.otherledgerdeductions,v_rec.othervariables,v_rec.otherdeductions,v_rec.
	otherledgerarearwithoutesi,v_rec.otherbonuswithesi,v_rec.totalarear,v_rec.lwf_employer,v_rec.insurancetype,v_rec.ordercol,v_rec.current_govt_bonus_amt,v_rec.arear_govt_bonus_amt,v_rec.refunddeduction, v_rec.professionaltax,
	v_rec.ratesalarybonus,v_rec.ratecommission,v_rec.ratetransport_allowance,v_rec.ratetravelling_allowance,v_rec.rateleave_encashment,v_rec.rateovertime_allowance,v_rec.ratenotice_pay,v_rec.ratehold_salary_non_taxable,v_rec.ratechildren_education_allowance,v_rec.rategratuityinhand,v_rec.salarybonus,v_rec.commission,v_rec.transport_allowance,v_rec.travelling_allowance,v_rec.leave_encashment,v_rec.overtime_allowance,v_rec.notice_pay,v_rec.hold_salary_non_taxable,v_rec.children_education_allowance,v_rec.gratuityinhand
	,v_rec.ctc,v_rec.tea_allowance
	,v_rec.commission_arear
	,v_rec.transport_allowance_arear
	,v_rec.travelling_allowance_arear
	,v_rec.leave_encashment_arear
	,v_rec.overtime_allowance_arear
	,v_rec.notice_pay_arear
	,v_rec.hold_salary_non_taxable_arear
	,v_rec.children_education_allowance_arear
	,v_rec.gratuityinhand_arear
	,v_rec.salarybonus_arear
	,v_rec.disbursedledgerids	
	,v_rec.charity_contribution_amount
	,v_rec.charity_contribution_amount_arear
	,v_rec.mealvoucher,v_rec.leavetaken,
	v_rec.salaryjson
	,v_rec.salid1,v_rec.salid2,v_rec.salid3;
END LOOP;	 

update tmpsalslip set rateovertime_allowance=overtime_allowance where coalesce(rateovertime_allowance,0)=0 and overtime_allowance>0;
create temporary table   tmp_monsalslip on commit drop
as
with tmp as
(
	select replace(trim(regexp_split_to_table(disbursedledgerids,',')),',','') ledgerid from tmpsalslip
),
tmp2 as
(
	select coalesce(sum(t1.amount),0.0)::numeric(18,2) amt from tbl_employeeledger t1 inner join tmp as t2
		on t1.id=nullif(t2.ledgerid::text,'')::int
	where 	t1.amount>0
)
select
employee as empcode,
round(sum(coalesce(basic,0))) basic,
round(sum(coalesce(hra,0))) hra,
round(sum(coalesce(specialallowance,0))) allowance,
round(max(tmprate.fixedallowancestotalrate)/*+coalesce(max(rateconv),0)*/) rategross,
round((coalesce(sum(epf),0))::numeric(18,2)) pf,
round(sum(coalesce(esi,0))) employeeesirate,
round((coalesce(sum(employeenps),0))::numeric(18,2)) nps,
round(coalesce(sum(insurance),0)::numeric(18,2)) insurance,
round(sum(coalesce(other,0)+coalesce(mobile,0))::numeric(18,2))	other,
round((coalesce(sum(grossdeduction),0))::numeric(18,2)) grossdeduction,
round(/*coalesce(sum(totalarear),0)+*/sum(coalesce(basic,0))+sum(coalesce(hra,0))+sum(coalesce(specialallowance,0))+sum(coalesce(current_govt_bonus_amt,0.0))+sum(coalesce(incentive,0.0))+sum(coalesce(conv,0.0))+sum(coalesce(medical,0.0))+sum(coalesce(salarybonus,0.0))+sum(coalesce(commission,0.0))+sum(coalesce(transport_allowance,0.0))+sum(coalesce(travelling_allowance,0.0))+sum(coalesce(leave_encashment,0.0))+sum(coalesce(overtime_allowance,0.0))+sum(coalesce(notice_pay,0.0))+sum(coalesce(hold_salary_non_taxable,0.0))+sum(coalesce(children_education_allowance,0.0))+sum(coalesce(gratuityinhand,0.0))+sum(coalesce(case when refunddeduction<0 then refunddeduction else 0.0 end,0.0)))+coalesce((select amt from tmp2),0)+sum(coalesce(mealvoucher,0)) grossearning,
round(coalesce(sum(coalesce(netpay,0))-v_mealamount,0)::numeric(18,2)) netpay,
round((coalesce(sum(current_govt_bonus_amt),0))::numeric(18,2)) govt_bonus_amt,
v_paiddays paid_days,
v_lopdays lopdays,
round((coalesce(sum(tds),0))::numeric(18,2)) taxes,
/*round((coalesce(sum(totalarear),0))::numeric(18,2))*/0  totalarear,
max(monthdays) monthdays,
max(coalesce(coalesce(tmprate.ratebasic,0),nullif(tmpsalslip.ratebasic,0.0),0.0)) ratebasic,
max(round(coalesce(tmprate.ratehra,nullif(tmpsalslip.ratehra,0.0),0.0)::numeric(18,2))) ratehra,
max(round(coalesce(tmprate.ratespecial_allowance,nullif(tmpsalslip.ratespecial_allowance,0.0),0.0)::numeric(18,2))) ratespecialallowance,
round(coalesce(sum(arr_basic),0)::numeric(18,2)) arearbasic,
round(coalesce(sum(arr_hra),0)::numeric(18,2)) arearhra,
round(coalesce(sum(arr_specialallowance),0)::numeric(18,2)) arearallowance,
round(
(coalesce(sum(arr_basic),0)
+coalesce(sum(arr_hra),0)
+coalesce(sum(arr_specialallowance),0)
+coalesce(sum(arr_conv),0)
+coalesce(sum(arr_medical),0)	   	   
+coalesce(sum(commission_arear),0)
+coalesce(sum(transport_allowance_arear),0)
+coalesce(sum(travelling_allowance_arear),0)
+coalesce(sum(leave_encashment_arear),0)
+coalesce(sum(overtime_allowance_arear),0)
+coalesce(sum(notice_pay_arear),0)
+coalesce(sum(hold_salary_non_taxable_arear),0)
+coalesce(sum(children_education_allowance_arear),0)
+coalesce(sum(gratuityinhand_arear),0)
+coalesce(sum(salarybonus_arear),0)	 
)::numeric(18,2)) areargross,
(select string_agg(distinct bankaccountno,',') from tbl_monthlysalary 
 where emp_code=p_emp_code 
 and coalesce(NULLIF(arearprocessmonth, 0),mprmonth)=p_month
 and coalesce(NULLIF(arearprocessyear, 0),mpryear)=p_year
 and recordscreen in ('Current Wages','Previous Wages')
and is_rejected<>'1') bankaccountno,
(select string_agg(distinct ifsccode,',') from tbl_monthlysalary 
 where emp_code=p_emp_code 
 and coalesce(NULLIF(arearprocessmonth, 0),mprmonth)=p_month
 and coalesce(NULLIF(arearprocessyear, 0),mpryear)=p_year
 and recordscreen in ('Current Wages','Previous Wages')
and is_rejected<>'1') ifsccode
,sum(coalesce(case when refunddeduction<0 then refunddeduction else 0.0 end,0.0)) refunddeduction
,coalesce(sum(professionaltax),0.0) professionaltax
,v_principal_employer_name principal_employer_name
,coalesce(max(rateconv),0) rateconv
,coalesce(sum(conv),0) conv
,coalesce(max(ratemedical),0) ratemedical
,coalesce(sum(medical),0) medical
,max(coalesce(coalesce(tmprate.ratesalarybonus,0),nullif(tmpsalslip.ratesalarybonus,0.0),0.0)) ratesalarybonus
,max(coalesce(coalesce(tmprate.ratecommission,0),nullif(tmpsalslip.ratecommission,0.0),0.0)) ratecommission
,max(coalesce(coalesce(tmprate.ratetransport_allowance,0),nullif(tmpsalslip.ratetransport_allowance,0.0),0.0)) ratetransport_allowance
,max(coalesce(coalesce(tmprate.ratetravelling_allowance,0),nullif(tmpsalslip.ratetravelling_allowance,0.0),0.0)) ratetravelling_allowance
,max(coalesce(coalesce(tmprate.rateleave_encashment,0),nullif(tmpsalslip.rateleave_encashment,0.0),0.0)) rateleave_encashment
,max(coalesce(coalesce(tmprate.rateovertime_allowance,0),nullif(tmpsalslip.rateovertime_allowance,0.0),0.0)) rateovertime_allowance
,max(coalesce(coalesce(tmprate.ratenotice_pay,0),nullif(tmpsalslip.ratenotice_pay,0.0),0.0)) ratenotice_pay
,max(coalesce(coalesce(tmprate.ratehold_salary_non_taxable,0),nullif(tmpsalslip.ratehold_salary_non_taxable,0.0),0.0)) ratehold_salary_non_taxable
,max(coalesce(coalesce(tmprate.ratechildren_education_allowance,0),nullif(tmpsalslip.ratechildren_education_allowance,0.0),0.0)) ratechildren_education_allowance
,max(coalesce(coalesce(tmprate.rategratuityinhand,0),nullif(tmpsalslip.rategratuityinhand,0.0),0.0)) rategratuityinhand
,/*round*/(sum(coalesce(salarybonus,0)))salarybonus
,/*round*/(sum(coalesce(commission,0)))commission
,/*round*/(sum(coalesce(transport_allowance,0)))transport_allowance
,/*round*/(sum(coalesce(travelling_allowance,0)))travelling_allowance
,/*round*/(sum(coalesce(leave_encashment,0)))leave_encashment
,/*round*/(sum(coalesce(overtime_allowance,0)))overtime_allowance
,/*round*/(sum(coalesce(notice_pay,0)))notice_pay
,/*round*/(sum(coalesce(hold_salary_non_taxable,0)))hold_salary_non_taxable
,/*round*/(sum(coalesce(children_education_allowance,0)))children_education_allowance
,/*round*/(sum(coalesce(gratuityinhand,0)))gratuityinhand
,min(ctc) ctc
,round(coalesce(sum(tea_allowance),0)) tea_allowance
,round(coalesce(sum(commission_arear),0)::numeric(18,2))	commission_arear
,round(coalesce(sum(transport_allowance_arear),0)::numeric(18,2))	transport_allowance_arear
,round(coalesce(sum(travelling_allowance_arear),0)::numeric(18,2))	travelling_allowance_arear
,round(coalesce(sum(leave_encashment_arear),0)::numeric(18,2))	leave_encashment_arear
,round(coalesce(sum(overtime_allowance_arear),0)::numeric(18,2))	overtime_allowance_arear
,round(coalesce(sum(notice_pay_arear),0)::numeric(18,2))	notice_pay_arear
,round(coalesce(sum(hold_salary_non_taxable_arear),0)::numeric(18,2))	hold_salary_non_taxable_arear
,round(coalesce(sum(children_education_allowance_arear),0)::numeric(18,2))	children_education_allowance_arear
,round(coalesce(sum(gratuityinhand_arear),0)::numeric(18,2))	gratuityinhand_arear
,round(coalesce(sum(salarybonus_arear),0)::numeric(18,2))	salarybonus_arear
,round(coalesce(sum(charity_contribution_amount),0)::numeric(18,2))	charity_contribution_amount
,round(coalesce(sum(charity_contribution_amount_arear),0)::numeric(18,2))	charity_contribution_amount_arear
,coalesce(sum(arr_conv),0) arr_conv
,coalesce(sum(arr_medical),0) arr_medical
,sum(leavetaken) leavetaken
,round(sum(coalesce(ac_1,0.0)+coalesce(ac_2,0.0)+coalesce(ac_10,0.0)+coalesce(ac21,0.0))::numeric(18,2)) as employerepf
,round(sum(coalesce(employer_esi_contr,0.0))::numeric(18,2)) employeresi
,jsonb_agg(coalesce(tmpsalslip.salaryjson,'[]')) salaryjson,
string_agg(salid1::text,'1') salid1,
string_agg(salid2::text,'1') salid2,
string_agg(salid3::text,'1') salid3
from tmpsalslip
left join (select employee emp_code,ratebasic,ratehra, ratespecial_allowance ratespecial_allowance
		   ,fixedallowancestotalrate
		   ,ratesalarybonus,ratecommission,ratetransport_allowance,ratetravelling_allowance,rateleave_encashment,rateovertime_allowance,ratenotice_pay,ratehold_salary_non_taxable,ratechildren_education_allowance,rategratuityinhand
		   from tmpsalslip 
		   --where coalesce(ratebasic,0.0)>0.0
order by salaryid desc limit 1) tmprate
on tmpsalslip.employee=tmprate.emp_code
where banktransferstatus='Transferred'
group by employee;
-------------Return heads--------------------------------------------------

select coalesce(balance_tot,'0')::numeric(18,2) 
from get_leave_balance_by_account(
     p_account_id =>v_customeraccountid::text,
    p_att_month =>p_month::text,
    p_att_year =>p_year::text,
    p_emp_id=>v_emp_id::text
 ) into v_leavebalance;
/******************change 1.1 starts*******************************/
select coalesce(ctc,0) from tmp_monsalslip into v_ctc;
v_ctc:=coalesce(v_ctc,0);
Raise notice 'ctc=%',v_ctc;
if ((v_customeraccountid=2719 and v_ctc<=22000) or (v_customeraccountid=4643 and v_ctc<=8000)
or (v_customeraccountid=6090 and p_origin='Employee')
) then
	open v_refsalaryslip for
		select 'x' as nodata where 1=2;
	return next v_refsalaryslip;
else	
/******************change 1.1 ends*********************************/
open v_refsalaryslip for
	with tmp_jobrole as (
		select 
			empcode,
			LAST_VALUE (jobrole) OVER (PARTITION BY empcode  ORDER BY deputeddate  DESC) as jobrole,
			LAST_VALUE (cjcode)  OVER (PARTITION BY empcode  ORDER BY deputeddate  DESC) as cjcode,
			max (deputeddate)  OVER (PARTITION BY empcode  ORDER BY deputeddate  DESC) deputeddate					 
		from public.cmsdownloadedwages
		where mprmonth=p_month	 and mpryear=p_year and empcode=p_emp_code::text
			-- and cmsdownloadedwages.attendancemode='MPR'
			and isactive='1' and nullif(trim(jobrole),'') is not null
			and (
			(
				(cmsdownloadedwages.empcode::bigint,cmsdownloadedwages.batch_no,cmsdownloadedwages.mprmonth,cmsdownloadedwages.mpryear)
				in (
					select emp_code,batchcode,salmonth,salyear
					from public.banktransfers
					where coalesce(isrejected,'0')<>'1'
					-- and banktransfers.salmonth=p_month
					-- and banktransfers.salyear=p_year
					and banktransfers.emp_code=p_emp_code
				)
				or (cmsdownloadedwages.empcode::bigint,cmsdownloadedwages.batch_no||cmsdownloadedwages.transactionid,cmsdownloadedwages.mprmonth,cmsdownloadedwages.mpryear)
				in (
					select emp_code,batchcode,salmonth,salyear
					from public.banktransfers
					where coalesce(isrejected,'0')<>'1'
					-- and banktransfers.salmonth=p_month
					-- and banktransfers.salyear=p_year
					and banktransfers.emp_code=p_emp_code
				)		
			)
			or (v_payoutmodetype in ('self','hybrid') and
			(cmsdownloadedwages.empcode::bigint,cmsdownloadedwages.batch_no,cmsdownloadedwages.mprmonth,cmsdownloadedwages.mpryear)
				in (
					select emp_code,batch_no,mprmonth,mpryear
					from public.tbl_monthlysalary
					where coalesce(is_rejected,'0')<>'1'
					and tbl_monthlysalary.attendancemode in ('MPR','Ledger')
					and tbl_monthlysalary.emp_code=p_emp_code
				)	
				)

			)
			LIMIT 1
		)
		select
			t1.emp_code emp_code,t1.emp_name,
			coalesce(NULLIF(tmp_jobrole.jobrole, ''), NULLIF(mtd_designation.designationname, ''), NULLIF(t1.post_offered, '')) post_offered, -- Changes [1.9]
			to_char(case when t1.jobtype='Contractual' then coalesce(tmp_jobrole.deputeddate,t1.dateofjoining) else t1.dateofjoining end,'dd/mm/yyyy') doj, t1.esinumber,t1.pfnumber,t1.uannumber,
			t2.lopdays,t2.bankaccountno bankaccount,
			t2.*,
			coalesce(NULLIF(t1.orgempcode, ''), t1.cjcode) cjcode
			-- ,case when t1.jobtype='Contractual' then coalesce(tmp_jobrole.cjcode,t1.cjcode)  else null end as cjcode
			,case when t1.jobtype='Apprentice' then 'Regular' else t1.jobtype end jobtype
			,CASE WHEN to_char(t1.dateofbirth,'dd/mm/yyyy') = '01/01/1950' THEN '' ELSE to_char(t1.dateofbirth,'dd/mm/yyyy') END dateofbirth
			,coalesce(t1.pancard,'') pancardnumber
			--, t1.professionaltax
			,'temp message' incentivemessage
			,v_employername companyname,v_address companyaddress,v_logopath companylogo,
			v_logopathtwo companylogotwo -- Changes [1.7]
			,coalesce(nullif(fnnumbertowords(round((t2.netpay)::numeric(18,2))),''),'Zero') netpay_in_words -- Change [1.2]
			,CASE
			    WHEN t1.recordsource IN ('HUBTPCRM','TPCRM') AND COALESCE(REPLACE(t1.emp_address, '<br>', ''), '') <> '' THEN
			        CONCAT_WS
			        (
			            ',',
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'house', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'landmark', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'street', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'po', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'vtc', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'loc', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'subdist', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'dist', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'state', ''),
			            NULLIF((REPLACE(t1.emp_address, '<br>', '')::jsonb)->>'country', '')
			        )
			ELSE
			    REPLACE(t1.emp_address, '<br>', '')
			END emp_address
			,v_residential_address residential_address,
			v_show_employee_address show_employee_address
			,v_leavebalance leavebalance
			,v_posting_department posting_department
		from openappointments t1
		inner join tmp_monsalslip t2 on t1.emp_code=t2.empcode and t1.appointment_status_id<>13 
		left join tmp_jobrole on tmp_jobrole.empcode::bigint=t1.emp_code
		LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = t1.designation_id; -- Changes [1.9]
		return next v_refsalaryslip;
	end if;
end if;
------------Find days for deductions and variables----------------------------
------------Find and return deductions----------------------------
open v_deductions for
with tmp as
(
select replace(trim(regexp_split_to_table(disbursedledgerids,',')),',','') ledgerid from tmpsalslip
),
tmp2 as
(
select t1.headname as deduction_name,(coalesce(round(t1.amount),0.0)::numeric(18,2))*-1 amt from tbl_employeeledger t1 inner join tmp as t2
	on t1.id=nullif(t2.ledgerid::text,'')::int
where 	t1.amount<0
),
otherdeductions as(
select mt.deduction_name, deduction_amount*t2.paiddays/(case when coalesce(e.salaryindaysopted,'N')='N' or e.salarydays=1 or coalesce(e.flexiblemonthdays,'N')='Y' then v_fullmonthdays else e.salarydays end) as amt 
from tmpsalslip t1 inner join tbl_monthlysalary t2 on t1.employee=t2.emp_code
and t2.recordscreen<>'Increment Arear'
and (t2.id::text=ANY(string_to_array(salid1::text, ',')) or t2.id::text=ANY(string_to_array(salid2::text, ',')) or t2.id::text=ANY(string_to_array(salid3::text, ',')))
inner join empsalaryregister e on t1.salaryid=e.id
inner join trn_candidate_otherduction tc on tc.salaryid=e.id
inner join mst_otherduction mt on mt.id=tc.deduction_id
		and ( 
				-- (tc.active='Y'
				--   and coalesce(tc.includedinctc,'N')='Y' 
				--   and coalesce(tc.isvariable,'N')='N'
				--   and tc.deduction_id not in (7,10)
				--   and tc.deduction_id<>323 --Meal Voucher ID, Must Change for Production
				--   and tc.deduction_frequency in ('Quarterly','Half Yearly','Annually')
				--   )
				-- or		
				(	
					tc.active='Y'
				   and tc.deduction_amount>0
				  and tc.deduction_frequency in ('Monthly')
				  and tc.deduction_id not in (5,6,7,10)
				  and coalesce(tc.is_taxable,'N')='N'
				  and mt.id<>323 --Meal Voucher ID, Must Change for Production)
				  )
			)
	)
	select * from
	(
		select 'LWF' deduction_name,coalesce(round(lwf),0.0) amt from tmpsalslip where lwf>0
		union all
			select 'VPF' deduction_name,coalesce(vpf,0.0) amt from tmpsalslip where vpf>0
		--union
		--	select 'Loan' deduction_name,coalesce(loan,0.0) amt from tmpsalslip where loan>0
		--union all
		--	select 'Advance' deduction_name,coalesce(advance,0.0) amt from tmpsalslip where advance>0
		--union all
			--select 'Professional Tax' deduction_name,coalesce(professionaltax,0.0) amt from tmpsalslip where coalesce(professionaltax,0)>0
		union all
		select deduction_name,amt from tmp2
		union all
			select 'Charity Contribution by Employee' deduction_name,coalesce(charity_contribution_amount,0.0)+coalesce(charity_contribution_amount_arear,0.0) amt from tmpsalslip 
		where coalesce(charity_contribution_amount,0.0)+coalesce(charity_contribution_amount_arear,0.0)>0
	-- union all
	-- 	select 'Meal Voucher' deduction_name,coalesce(mealvoucher,0.0) amt from tmpsalslip where mealvoucher>0
	union all
	select deduction_name,amt from otherdeductions
	) tmp where amt>0.0;
return next v_deductions;
------------Find and return variables----------------------------
open v_variables for
with tmp as
(
select trim(regexp_split_to_table(disbursedledgerids,',')) ledgerid from tmpsalslip
),
tmp2 as
(
select t1.headname as deduction_name,coalesce(round(t1.amount),0.0)::numeric(18,2) amt from tbl_employeeledger t1 inner join tmp as t2
	on t1.id=nullif(t2.ledgerid::text,'')::int
where 	t1.amount>0
)
	select 'Incentive' variable_name,coalesce(round(incentive),0.0) amt from tmpsalslip where incentive>0 and banktransferstatus='Transferred'
	union all
	select 'Refund' variable_name,coalesce(round(refund),0.0) amt from tmpsalslip where refund>0 and banktransferstatus='Transferred'
	union all
	select 'Refund' variable_name,coalesce(round(refunddeduction),0.0) amt from tmpsalslip where refunddeduction<0 and banktransferstatus='Transferred'
	--union all
	--select 'Overtime' variable_name,coalesce(round(overtime_allowance),0.0) amt from tmpsalslip where overtime_allowance>0 and banktransferstatus='Transferred'
	union all
	select deduction_name,amt from tmp2
	--union all
		--select 'Meal Voucher' deduction_name,coalesce(v_mealamount,0.0) amt  where v_mealamount>0
		;
return next v_variables;
------------------------------------------------------------------------
open v_pancarddetaild for
select pancard from openappointments
where emp_code=p_emp_code;
return next v_pancarddetaild;
------------------------------------------------------------------------
select public.uspgetreportfields
(
	p_reportname =>'Salary Slip',
	p_customeraccountid =>v_customeraccountid,
	p_fieldtype => 'Earning'::character varying
) into v_dynamicearningheads;
return next v_dynamicearningheads;

select public.uspgetreportfields(
	p_reportname =>'Salary Slip',
	p_customeraccountid =>v_customeraccountid,
	p_fieldtype => 'Deduction'::character varying)
into v_dynamicdeductionheads;
return next v_dynamicdeductionheads;

open v_rfcblank for 
select null as colname where 1=2;
return next v_rfcblank;

open v_rfcmealvoucher for
select 'Meal Voucher' deduction_name,coalesce(v_mealamount,0.0) amt  where v_mealamount>0;
return next v_rfcmealvoucher;
end;
$BODY$;

ALTER FUNCTION public.uspgeneratesalaryslip(bigint, integer, integer, text, text)
    OWNER TO payrollingdb;

