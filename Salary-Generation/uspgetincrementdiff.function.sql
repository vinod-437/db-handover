-- FUNCTION: public.uspgetincrementdiff(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, bigint, text)

-- DROP FUNCTION IF EXISTS public.uspgetincrementdiff(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, bigint, text);

CREATE OR REPLACE FUNCTION public.uspgetincrementdiff(
	p_mprmonth integer,
	p_mpryear integer,
	p_ordernumber character varying DEFAULT NULL::character varying,
	p_emp_code bigint DEFAULT NULL::bigint,
	p_batch_no character varying DEFAULT NULL::character varying,
	p_action character varying DEFAULT NULL::character varying,
	p_createdby bigint DEFAULT NULL::bigint,
	createdbyip character varying DEFAULT NULL::character varying,
	p_criteria character varying DEFAULT NULL::character varying,
	p_customeraccountid bigint DEFAULT '-9999'::bigint,
	p_current_advance text DEFAULT 'Current'::text)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$

declare
sal refcursor;
v_monthdays int;
v_querytext varchar;
v_querytext2 varchar;
v_pausequery varchar;
--v_otherdeductionsalready numeric(18,2);
--v_othervariablesalready numeric(18,2);

v_challandate varchar(10);

v_currentpaidepf numeric(18,2):=0;
v_currentpaidac_1 numeric(18,2):=0;
v_currentpaidac_10 numeric(18,2):=0;
v_currentpaidac_2 numeric(18,2):=0;
v_currentpaidac_21 numeric(18,2):=0;

v_account1_7q_dues	numeric(18,2);	
v_account10_7q_dues	numeric(18,2);	
v_account2_7q_dues	numeric(18,2);	
v_account21_7q_dues	numeric(18,2);	
v_account1_14b_dues	numeric(18,2);	
v_account10_14b_dues	numeric(18,2);	
v_account2_14b_dues	numeric(18,2);	
v_account21_14b_dues	numeric(18,2);
v_incmonth int;
v_incyear int;
v_incday int;
v_doj date;
v_emp_id int;

	v_year1 int;
	v_mprmonth integer;
	v_mpryear integer;
	v_salstartdate date;
	v_salenddate date;
	v_prevsaldate date;
	v_advancesalstartdate date;
	v_advancesalenddate date;
	v_tptype varchar(10);
v_rfc refcursor;	
v_openappointments openappointments%rowtype;
v_empsalaryregister empsalaryregister%rowtype;
	
begin
/*************************************************************************
Version 	Date 			Change 									Done_by
1.0 		19-Apr-2021 	Initial Version Shiv Kumar
1.2 		11-Aug-2021 	Applying New Variable 					Shiv Kumar
							Condition
1.3			01-Mar-2022		Changing AC_1 and AC_10 Logic	  		Shiv Kumar	
1.4			26-Mar-2022		Variable Part/CTC2 Gross Earning  		Shiv Kumar
1.5			04-Jul-2022		Reverse PF for Current Month	  		Shiv Kumar
1.6			23-Aug-2022		Increment from Effectivedate 	  		Shiv Kumar
1.7			25-Mar-2023		Professional Tax					  	Shiv Kumar
1.8			20-Jul-2023		Changed Inrement Salary Batch Number  	Shiv Kumar
1.9			19-Sep-2023		TP type for TP candidates			  	Shiv Kumar
1.10		03-Jun-2025		Comment Otherledgerarear, 			  	Shiv Kumar
							otherledgerdeductions and otherledherarearwithoutesi
1.11		03-Jun-2025		Add 10 components		 			  	Shiv Kumar
1.12		04-Jun-2025		pfapplicablecomponents	 			  	Shiv Kumar
							esiapplicablecomponents
*************************************************************************/
select * from openappointments where emp_code=p_emp_code into v_openappointments;

if  p_action='Retrieve_Previous_Salary' or p_action='RetrieveVerified_Arear' then
			p_current_advance:=to_char(current_date,'Mon-yyyy');
end if;
		select extract('month' from to_date(p_current_advance,'Mon-yyyy'))::int,
				extract('year' from to_date(p_current_advance,'Mon-yyyy'))::int 
		into v_mprmonth,v_mpryear;

 
select DATE_TRUNC('MONTH', (v_mpryear||'-'||v_mprmonth||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (v_mpryear||'-'||v_mprmonth||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (v_mpryear||'-'||v_mprmonth||'-01')::DATE ) - INTERVAL '1 DAY')::date,
	DATE_TRUNC('MONTH', (v_mpryear||'-'||v_mprmonth||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (v_mpryear||'-'||v_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;

if p_action='RetrieveVerified_Arear' then
v_querytext:='SELECT TO_CHAR(TO_TIMESTAMP ('||p_mprmonth||'::text, ''MM''), ''Mon'')'||'||''-''||'||p_mpryear::text||' AS Mon,tbl_monthlysalary.*
,null dateofjoining
,openappointments.esinumber,openappointments.posting_department,
null ismultilocated,null projectname,
null contractno,null contractcategory,null contracttype
FROM public.tbl_monthlysalary
inner join openappointments on openappointments.emp_code=tbl_monthlysalary.emp_code
and openappointments.appointment_status_id<>13
and tbl_monthlysalary.is_rejected=''0''
WHERE
tbl_monthlysalary.emp_code='||p_emp_code||'
and tbl_monthlysalary.mpryear='||p_mpryear||'
and tbl_monthlysalary.mprmonth='||p_mprmonth||'
and recordscreen=''Increment Arear'' ';

open sal for
execute v_querytext;
return sal;
end if;
/**************************Commented for change 1.4********************************************
select sum(case when coalesce(trn_candidate_otherduction.includedinctc,'N')='Y'
 and coalesce(isvariable,'N')='N'  --change 1.4
 and trn_candidate_otherduction.deduction_id not in (5,6,7,10,12)
 and trn_candidate_otherduction.deduction_frequency in ('Quarterly','Half Yearly','Annually')
  then deduction_amount*paiddays/monthdays else 0 end),
  sum(case when coalesce(trn_candidate_otherduction.includedinctc,'N')='N'
 and trn_candidate_otherduction.deduction_frequency in ('Monthly')
 and trn_candidate_otherduction.deduction_id not in (5,6,7,10,12)
  then deduction_amount*paiddays/monthdays else 0 end)
into v_otherdeductionsalready,v_othervariablesalready
from tbl_monthlysalary inner join trn_candidate_otherduction
on tbl_monthlysalary.salaryid=trn_candidate_otherduction.salaryid
and tbl_monthlysalary.emp_code=p_emp_code
and tbl_monthlysalary.mprmonth=p_mprmonth
and tbl_monthlysalary.mpryear=p_mpryear
and (tbl_monthlysalary.recordscreen in ('Previous Wages','Current Wages','Arear Wages'))
and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1'
;
********************Change 1.4 ends here***********************************/
/********Change 1.5**********/
select sum(epf),sum(ac_1),sum(ac_10),sum(ac_2),sum(ac21)
,sum(account1_7q_dues),sum(account10_7q_dues),sum(account2_7q_dues),sum(account21_7q_dues),sum(account1_14b_dues),sum(account10_14b_dues),sum(account2_14b_dues),sum(account21_14b_dues)
into v_currentpaidepf,v_currentpaidac_1 ,v_currentpaidac_10,v_currentpaidac_2,v_currentpaidac_21
,v_account1_7q_dues,v_account10_7q_dues,v_account2_7q_dues,v_account21_7q_dues,v_account1_14b_dues,v_account10_14b_dues,v_account2_14b_dues,v_account21_14b_dues	
from tbl_monthlysalary 
where emp_code=p_emp_code and mprmonth=p_mprmonth and mpryear=p_mpryear and coalesce(is_rejected,'0')<>'1'
and to_date(left(hrgeneratedon,11),'dd Mon yyyy') between date_trunc('Month',current_date)::date 
 and (date_trunc('Month',current_date)+interval '1' month-interval '1' Day)::date;

v_currentpaidepf :=coalesce(v_currentpaidepf,0);
v_currentpaidac_1:=coalesce(v_currentpaidac_1,0);
v_currentpaidac_10 :=coalesce(v_currentpaidac_10,0);
v_currentpaidac_2 :=coalesce(v_currentpaidac_2,0);
v_currentpaidac_21 :=coalesce(v_currentpaidac_21,0);

v_account1_7q_dues:=coalesce(v_account1_7q_dues,0);
v_account10_7q_dues:=coalesce(v_account10_7q_dues,0);	
v_account2_7q_dues:=coalesce(v_account2_7q_dues,0);	
v_account21_7q_dues:=coalesce(v_account21_7q_dues,0);	
v_account1_14b_dues:=coalesce(v_account1_14b_dues,0);	
v_account10_14b_dues:=coalesce(v_account10_14b_dues,0);
v_account2_14b_dues:=coalesce(v_account2_14b_dues,0);	
v_account21_14b_dues:=coalesce(v_account21_14b_dues,0);

select (extract('Year' from current_date)::text||'-'||lpad(extract('Month' from current_date)::text,2,'0')||'-15')	
		into v_challandate;		
/********Change 1.5********************/
v_monthdays:=date_part('day',DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');
select emp_id from openappointments where emp_code=p_emp_code    into v_emp_id;
/*********************Added for Mid Month Increment****************************************/
select extract('Year' from effectivefrom),extract('Month' from effectivefrom),extract('day' from effectivefrom)
,dateofjoining
from (
select effectivefrom,empsalaryregister.appointment_id,openappointments.dateofjoining from
public.empsalaryregister  inner join public.openappointments
 on empsalaryregister.appointment_id=openappointments.emp_id
         and openappointments.appointment_status_id<>13
 and coalesce(converted,'N')='Y'
 and openappointments.emp_code=p_emp_code
where to_date(v_monthdays::text||lpad(p_mprmonth::text,2,'0')||p_mpryear::text,'ddmmyyyy')
between empsalaryregister.effectivefrom and coalesce(empsalaryregister.effectiveto,current_date)
and id not in (select salaryid from tbl_monthlysalary
where emp_code=p_emp_code and mprmonth=p_mprmonth and mpryear=p_mpryear and coalesce(is_rejected,'0')<>'1')
order by id desc limit 1
) empsalaryregister

into v_incyear,v_incmonth,v_incday,v_doj;
if v_incyear=p_mpryear and v_incmonth=p_mprmonth and v_incday>1 
and v_doj<to_date('01'||'-'||lpad(p_mprmonth::text,2,'0')||'-'||p_mpryear,'dd-mm-yyyy') then
		select public.uspgetmidmincrementdiff(
			p_mprmonth,
			p_mpryear,
			p_ordernumber,
			p_emp_code,
			p_batch_no,
			p_action,
			p_createdby,
			createdbyip,
			p_criteria)
		into sal;
		return sal;
end if;
/**************************************************************/
select case when openappointments.recordsource='HUBTPCRM' then 'TP' else 'NonTP' end as tptype from openappointments where emp_code=p_emp_code into v_tptype;

v_querytext:='select ';

if  p_action='Save_Previous_Salary' then
v_querytext:=v_querytext||p_mprmonth||' mprmonth,'||p_mpryear
    ||' mpryear,batch_no batchid,'||p_createdby||' createdby,current_timestamp createdon,'''||createdbyip||''' createdbyip,';
end if;

if  p_action='Retrieve_Previous_Salary' then
v_querytext:=v_querytext||p_mprmonth||' mprmonth,'||p_mpryear||' mpryear,is_paused,emp_id,'
||'TO_CHAR(TO_TIMESTAMP ('||p_mprmonth||'::text, ''MM''), ''Mon'')'||'||''-''||'||p_mpryear||' AS Mon,dateofjoining,esinumber,posting_department,';
v_querytext:=v_querytext||' projectname,
contractno,
contractcategory,
contracttype,case when activeinbatch=''1'' then ''Active'' else ''Inactive'' end as activeinbatch,appointment_status_id,''Unlocked'' as lockstatus, ';
end if;

v_querytext:=v_querytext||'emp_code,bunit subunit,dateofleaving,totalleavetaken,
emp_name,post_offered,emp_address,email,mobilenum,upper(pancard) pancard,gender,dateofbirth,
fathername,residential_address,pfnumber,uannumber,
     (case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)-(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)  lossofpay,
paiddays paiddays, (case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end) monthdays,
(RateBasic) RateBasic,(RateHRA) RateHRA,(RateCONV) RateCONV,
(RateMedical) RateMedical,(RateSpecialAllowance) RateSpecialAllowance,
(FixedAllowancesTotalRate) FixedAllowancesTotalRate,

(Basic) Basic,(HRA::numeric(18,2)) HRA,
(CONV) CONV,
(Medical) Medical,(SpecialAllowance) SpecialAllowance,
(FixedAllowancesTotal::numeric(18,2)) FixedAllowancesTotal,

(RateBasic_arr) RateBasic_arr,(RateHRA_arr) RateHRA_arr,
(RateCONV_arr) RateCONV_arr,
(RateMedical_arr) RateMedical_arr,(RateSpecialAllowance_arr) RateSpecialAllowance_arr,
(FixedAllowancesTotalRate_arr) FixedAllowancesTotalRate_arr,
(Incentive) Incentive,(Refund) Refund,
((FixedAllowancesTotal)+
(Incentive)+(Refund)+ ( (coalesce(govt_bonus_amt*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0))-coalesce(govt_bonus_amtalreadypaid,0) )+coalesce(otherdeductionswithesi*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0)-coalesce(otherdeductionswithesialreadypaid,0)/*+coalesce(otherledgerarear,0)*/ +coalesce(othervariables,0)/*+coalesce(otherledgerarearwithoutesi,0)*/-coalesce(othervariablesalreadypaid,0))::numeric(18,2) GrossEarning,
case when epf>0 then
case when coalesce(pfcapapplied,''Y'')=''N'' then /*Basic*12.0/100*/
		case when coalesce(pfapplicablecomponents,0)>=0 or current_date<'''||v_challandate||'''::date  
			then (coalesce(pfapplicablecomponents,0))*12.0/100-coalesce(epfalreadydeducted,0)
		else
			greatest((coalesce(pfapplicablecomponents,0))*12.0/100-coalesce(epfalreadydeducted,0),0)
		end
else
case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<15000  then coalesce(pfapplicablecomponents,0)*12.0/100
else greatest(1800-coalesce(epfalreadydeducted,0),0)
end
      end
when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date 
then coalesce('||v_currentpaidepf::text||',0)*-1		
else 0 end epf,
greatest((vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)-coalesce(vpfalreadypaid,0),0) vpf,0+coalesce(employee_esi_incentive_deduction,0) employeeesirate,
(tds) tds,(loan) loan,(lwf) lwf,(Insurance) Insurance,
(Mobile) Mobile,(Advance) Advance,(Other) Other,

( (case when epf>0 then
case when coalesce(pfcapapplied,''Y'')=''N'' then /*Basic*12.0/100*/
		case when coalesce(pfapplicablecomponents,0)>=0 or current_date<'''||v_challandate||'''::date  
			then (coalesce(pfapplicablecomponents,0))*12.0/100-coalesce(epfalreadydeducted,0)
		else
			greatest((coalesce(pfapplicablecomponents,0))*12.0/100-coalesce(epfalreadydeducted,0),0)
		end
else
case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<15000  then coalesce(pfapplicablecomponents,0)*12.0/100
else greatest(1800-coalesce(epfalreadydeducted,0),0)
end
      end
when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date 
then coalesce('||v_currentpaidepf::text||',0)*-1		
else 0 end)+greatest(coalesce(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0)-coalesce(vpfalreadypaid,0),0)+  (coalesce(tds,0))+(coalesce(loan,0))+(coalesce(lwf,0))+ /*case when medicalinsuranceopted=''Y'' then*/ (coalesce(Insurance,0)) /*else 0 end*/+ (coalesce(Advance,0))+ (coalesce(Other,0))+(coalesce(otherdeductions,0)-coalesce(otherdeductionsalreadypaid,0))/*+coalesce(otherledgerdeductions,0)*/)+coalesce(charity_contribution_amount,0) GrossDeduction,
(
case when coalesce(is_special_category,''N'')=''Y'' then (actual_paid_ctc2) else
((FixedAllowancesTotal)+
(Incentive)+(Refund)+ ((coalesce(govt_bonus_amt*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0))-coalesce(govt_bonus_amtalreadypaid,0) )+coalesce(otherdeductionswithesi*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0)-coalesce(otherdeductionswithesialreadypaid,0)/*+coalesce(otherledgerarear,0)*/ +coalesce(othervariables,0)-coalesce(othervariablesalreadypaid,0)
/*+coalesce(otherledgerarearwithoutesi,0)*/)
-( (case when epf>0 then
case when coalesce(pfcapapplied,''Y'')=''N'' then /*Basic*12.0/100*/
		case when coalesce(pfapplicablecomponents,0)>=0 or current_date<'''||v_challandate||'''::date  
			then (coalesce(pfapplicablecomponents,0))*12.0/100-coalesce(epfalreadydeducted,0)
		else
			greatest((coalesce(pfapplicablecomponents,0))*12.0/100-coalesce(epfalreadydeducted,0),0)
		end
else
case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<15000  then coalesce(pfapplicablecomponents,0)*12.0/100
else greatest(1800-coalesce(epfalreadydeducted,0),0)
end
      end
when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date 
then coalesce('||v_currentpaidepf::text||',0)*-1		
else 0 end)+greatest(coalesce(vpf*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0)-coalesce(vpfalreadypaid,0),0)+  (coalesce(tds,0))+(coalesce(loan,0))+(coalesce(lwf,0))+ /*case when medicalinsuranceopted=''Y'' then*/ (coalesce(Insurance,0)) /*else 0 end*/+ (coalesce(Advance,0))+ (coalesce(Other,0))+(coalesce(otherdeductions,0)-coalesce(otherdeductionsalreadypaid,0))/*+coalesce(otherledgerdeductions,0)*/+coalesce(charity_contribution_amount,0))

end)::numeric(18,2)
NetPay,

case when epf>0 then
--------------------
	case when coalesce(pfcapapplied,''Y'')=''N''
		then coalesce(pfapplicablecomponents,0)*0.0367
	when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<=15000 then
		case when coalesce(pfapplicablecomponentsalready,0)<=15000 then coalesce(pfapplicablecomponents,0)*0.0367
			when coalesce(pfapplicablecomponentsalready,0)>15000 then (((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))-15000)*0.0367 end
	else
			greatest(550.5-coalesce(coalesce(pfapplicablecomponentsalready,0)*0.0367,0),0) 
	end
+
--------------------------------------
case when coalesce(epf_pension_opted,''Y'')=''Y'' and coalesce(pfcapapplied,''Y'')=''Y'' then
		0
	when coalesce(epf_pension_opted,''Y'')=''Y'' and coalesce(pfcapapplied,''Y'')=''N'' then
				case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<=15000  
					then 0
				else 
					case when coalesce(pfapplicablecomponentsalready,0)<=15000 then
						((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))*0.0833-1249.5
					else
						coalesce(pfapplicablecomponents,0)*0.0833
					end	
				end
	when coalesce(epf_pension_opted,''Y'')=''N'' and coalesce(pfcapapplied,''Y'')=''Y'' then
				case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<=15000  
					then coalesce(pfapplicablecomponents,0)*0.0833
				else 
					case when coalesce(pfapplicablecomponentsalready,0)<=15000 then
						greatest(1249.5-(coalesce(pfapplicablecomponentsalready,0))*0.0833,0)
					else
						0
					end	
				end
	when coalesce(epf_pension_opted,''Y'')=''N'' and coalesce(pfcapapplied,''Y'')=''N'' then
			coalesce(pfapplicablecomponents,0)*0.0833
	end	
-------------------------------------------------------------------------------
when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date 
then coalesce('||v_currentpaidac_1::text||',0)*-1
else 0 end	Ac_1,
-------------------------------------------------------------------------------	
	case when epf>0 and coalesce(epf_pension_opted,''Y'')=''Y'' then
				case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<15000  then
							case when coalesce(pfapplicablecomponents,0)>=0 or current_date<'''||v_challandate||'''::date  
								then coalesce(pfapplicablecomponents,0)*0.0833
							else
								greatest(((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))*0.0833-coalesce(ac_10alreadydeducted,0),0)
							end	
					else greatest(1249.5-coalesce(ac_10alreadydeducted,0),0) 
				end
when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date 
then coalesce('||v_currentpaidac_10::text||',0)*-1				
	else 0 end	Ac_10,
case when epf>0 then
case when coalesce(pfcapapplied,''Y'')=''N'' then /*coalesce(pfapplicablecomponents,0)*0.005*/
	case when coalesce(pfapplicablecomponents,0)>=0 or current_date<'''||v_challandate||'''::date  
			then coalesce(pfapplicablecomponents,0)*0.005
		else
			greatest(((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))*0.005-coalesce(ac_2alreadydeducted,0),0)
		end
else
case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<15000  then coalesce(pfapplicablecomponents,0)*0.005
else greatest(75-coalesce(ac_2alreadydeducted,0),0)
end
      end
when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date 
then coalesce('||v_currentpaidac_2::text||',0)*-1	  
else 0 end Ac_2,
case when epf>0 then	  
case when coalesce(pfcapapplied,''Y'')=''N'' then coalesce(pfapplicablecomponents,0)*0.005
else
case when ((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))<15000  then /*coalesce(pfapplicablecomponents,0)*0.005*/
	case when coalesce(pfapplicablecomponents,0)>=0 or current_date<'''||v_challandate||'''::date  
			then coalesce(pfapplicablecomponents,0)*0.005
		else
			greatest(((coalesce(pfapplicablecomponents,0)+coalesce(pfapplicablecomponentsalready,0)))*0.005-coalesce(ac_21alreadydeducted,0),0)
		end
else greatest(75-coalesce(ac_21alreadydeducted,0),0)
end
      end
when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date 
then coalesce('||v_currentpaidac_21::text||',0)*-1	  
else 0 end Ac21,
0+coalesce(employer_esi_incentive_deduction,0) employeresirate,
0 LWFContr,(ews) ews,(gratuity) gratuity
,recordtype
,govt_bonus_opted,(coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)-coalesce(govt_bonus_amtalreadypaid,0) govt_bonus_amt';

if p_action='Save_Previous_Salary' then
v_querytext:=v_querytext||
 ',cast(null as integer) modifiedby,cast(null as timestamp) modifiedon,null modifiedbyip';
 end if;  
v_querytext:=v_querytext||',is_special_category,ct2';

 
v_querytext:=v_querytext||',batch_no,(actual_paid_ctc2) actual_paid_ctc2,(ctc) ctc';
v_querytext:=v_querytext||', (ctc_paid_days) ctc_paid_days,(ctc_actual_paid) ctc_actual_paid, (mobile_deduction) mobile_deduction
,salaryid,''Y''  isarear
,coalesce(employeenpsrate,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end employeenpsrate
,coalesce(employernpsrate,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end employernpsrate
,coalesce(insuranceamount,0) insuranceamount
,coalesce(familyinsuranceamount,0) familyinsuranceamount
,bankaccountno, ifsccode, bankname, bankbranch,coalesce(netarear,0) netarear,
arearaddedmonths
,employee_esi_incentive_deduction
,employer_esi_incentive_deduction
,total_esi_incentive_deduction
,salaryindaysopted,salarydays
,/*otherledgerarear*/0 otherledgerarear
,0 otherledgerdeductions

,case when employeeesirate>0 then 
	case when employeeesiratealreadypaid=0 and '||p_mprmonth||' in (4,10) then
	(coalesce(esiapplicablecomponents,0)*0.00750)+((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*.0075)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*.0075 
	else
	(esiapplicablecomponentsTotal*0.00750)+((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(govt_bonus_amtalreadypaid,0))*.0075)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(otherdeductionswithesialreadypaid,0))*.0075 
	end
else 0 end employee_esi_incentive
,case when employeresirate>0 then 
	case when employeeesiratealreadypaid=0 and '||p_mprmonth||' in (4,10) then
	(coalesce(esiapplicablecomponents,0)*0.03250) +((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*0.0325)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*.0325  
	else
	(esiapplicablecomponentsTotal*0.03250) +((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(govt_bonus_amtalreadypaid,0))*0.0325)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(otherdeductionswithesialreadypaid,0))*.0325  
end
else 0 end employer_esi_incentive
,case when employeeesirate>0 then 
	case when employeeesiratealreadypaid=0 and '||p_mprmonth||' in (4,10) then
	(coalesce(esiapplicablecomponents,0)*0.00750)+((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*.0075)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*.0075 
	else
	(esiapplicablecomponentsTotal*0.00750)+((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(govt_bonus_amtalreadypaid,0))*.0075)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(otherdeductionswithesialreadypaid,0))*.0075 
	end
else 0 end 
+case when employeresirate>0 then 
	case when employeeesiratealreadypaid=0 and '||p_mprmonth||' in (4,10) then
	(coalesce(esiapplicablecomponents,0)*0.03250) +((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*0.0325)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end)*.0325  
	else
	(coalesce(esiapplicablecomponentsTotal,0)*0.03250) +((coalesce(govt_bonus_amt,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(govt_bonus_amtalreadypaid,0))*0.0325)+(coalesce(otherdeductionswithesi,0)*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(otherdeductionswithesialreadypaid,0))*.0325  
end
else 0 end total_esi_incentive
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account1_7q_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account1_7q_dues
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account1_14b_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account1_14b_dues
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account10_7q_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account10_7q_dues
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account10_14b_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account10_14b_dues
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account2_7q_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account2_7q_dues
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account2_14b_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account2_14b_dues
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account21_7q_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account21_7q_dues
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then  '||(-1*coalesce(v_account21_14b_dues,0)) ||' else cast(0.00 as numeric(18,2)) end as account21_14b_dues
, pf_due_date
, pf_paid_date
,''Increment Arear'' recordscreen
,''Y'' isarearprocessed
,'||v_mprmonth||' arearprocessmonth
,'||v_mpryear||' arearprocessyear
,attendancemode
,coalesce(othervariables,0)-coalesce(othervariablesalreadypaid,0) othervariables
,coalesce(otherdeductions,0)-coalesce(otherdeductionsalreadypaid,0) otherdeductions
,0 otherledgerarearwithoutesi
--,coalesce(otherdeductionswithesi*totalsalarydays/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0)-coalesce(otherdeductionswithesialreadypaid,0) otherdeductionswithesi
,to_char(to_date('''||p_current_advance||''',''Mon-yyyy'')+interval ''1 month'' ,''dd Mon yyyy hh:mi'') hrgeneratedon
,case when epf=0 and coalesce('||v_currentpaidepf::text||',0)>0 and current_date<'''||v_challandate||'''::date then ''Reverse EPF Case'' else ''No Reverse EPF Case'' end as isReverseEPF
,0 pt
,'''||v_tptype||''' tptype
,commission, transport_allowance, travelling_allowance, leave_encashment, overtime_allowance, notice_pay, hold_salary_non_taxable, children_education_allowance, gratuityinhand, salarybonus
,coalesce(pfapplicablecomponents,0)-coalesce(pfapplicablecomponentsalready,0) pfapplicablecomponents,

coalesce(esiapplicablecomponents,0)-coalesce(esiapplicablecomponentsalready,0) esiapplicablecomponents
,coalesce(charity_contribution_amount,0) charity_contribution_amount
,mealvoucher
from
(
select openappointments.emp_code,bunit bunit,';
if p_action='Retrieve_Previous_Salary' then
v_querytext:=v_querytext||'to_char(dateofleaving,''dd/mm/yyyy'') dateofleaving,emp_id,is_paused,';
elsif  p_action='Save_Previous_Salary' then
v_querytext:=v_querytext||'dateofleaving,';
end if;

v_querytext:=v_querytext||'emp_name,post_offered,emp_address,email,mobile mobilenum,pancard,gender,';

if p_action='Retrieve_Previous_Salary' then
v_querytext:=v_querytext||'to_char(dateofbirth,''dd-Mon-yy'') dateofbirth,coalesce(cmsdownloadedwages.isactive,''0'') activeinbatch';
elsif  p_action='Save_Previous_Salary' then
v_querytext:=v_querytext||'dateofbirth';
end if;
v_querytext:=v_querytext||',fathername,residential_address,pfnumber,uannumber,lossofpay lossofpay,
case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end monthdays,(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)  paiddays,totalleavetaken,
basic RateBasic,hra RateHRA,conveyance_allowance RateCONV,
medical_allowance RateMedical,allowances RateSpecialAllowance,
gross FixedAllowancesTotalRate,

basic*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(basicalreadypaid,0) Basic,
hra*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(hraalreadypaid,0) HRA,
conveyance_allowance*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(convalreadypaid,0) CONV,
medical_allowance*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(medicalalreadypaid,0) Medical,
       allowances*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(specialallowancealreadypaid,0)  SpecialAllowance,
gross*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(fixedallowancestotalalreadypaid,0) FixedAllowancesTotal,
/*************************************************************/
coalesce(commission,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(commissionalreadypaid,0)commission,
coalesce(transport_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(transport_allowancealreadypaid,0) transport_allowance,
coalesce(travelling_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(travelling_allowancealreadypaid,0) travelling_allowance,
coalesce(leave_encashment,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(leave_encashmentalreadypaid,0) leave_encashment,
coalesce(overtime_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(overtime_allowancealreadypaid,0) overtime_allowance,
coalesce(notice_pay,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(notice_payalreadypaid,0) notice_pay,
coalesce(hold_salary_non_taxable,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(hold_salary_non_taxablealreadypaid,0) hold_salary_non_taxable,
coalesce(children_education_allowance,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(children_education_allowancealreadypaid,0) children_education_allowance,
coalesce(gratuityinhand,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(gratuityinhandalreadypaid,0) gratuityinhand,
coalesce(salarybonus,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(salarybonusalreadypaid,0) salarybonus,
coalesce(coalesce(nullif(pfapplicablecomponents,0),basic),0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end pfapplicablecomponents,
coalesce(coalesce(nullif(esiapplicablecomponents,0),gross),0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end esiapplicablecomponents,
	/*************************************************************/	
cast(0.0000 as double precision) RateBasic_arr,cast(0.0000 as double precision) RateHRA_arr,cast(0.0000 as double precision) RateCONV_arr,
cast(0.0000 as double precision) RateMedical_arr,cast(0.0000 as double precision) RateSpecialAllowance_arr,
cast(0.0000 as double precision) FixedAllowancesTotalRate_arr,
cast(0.0000 as double precision) Incentive,cast(0.0000 as double precision) Refund,
   employeeepfrate  epf,(vpfemployee+coalesce(variablevpf,0)) vpf,
employeeesirate,employeresirate,
0 tds,
0 loan,
0 lwf,
(insuranceamount+familyinsuranceamount)*case when openappointments.customeraccountid=653 then 1 else (case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end end -coalesce(Insurancealreadypaid,0) Insurance,
cast(0.0000 as double precision) Mobile,cast(0.0000 as double precision) Advance,(coalesce(ews,0)+coalesce(gratuity,0)+coalesce(bonus,0))-coalesce(Otheralreadypaid,0) Other
,ews*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(ewsalreadypaid,0)  ews
,gratuity*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end -coalesce(gratuityalreadypaid,0) gratuity
,salaryinhand
,case when recordsource =''MIS'' then ''Existing'' else ''NewRecord'' end as recordtype
,openappointments.govt_bonus_opted,govt_bonus_amt
,(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)  totalsalarydays
,to_char(cmsdownloadedwages.dateofjoining,''dd-Mon-yy'') dateofjoining
,openappointments.esinumber,posting_department,batch_no
,tblotherdeductions.otherdeductions*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end otherdeductions
,projectname,
contractno,
contractcategory,
contracttype
,totalpaiddays
,empsalaryregister.is_special_category
,ctc
,empsalaryregister.ct2
,(empsalaryregister.ct2*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end) -coalesce(actual_paid_ctc2alreadypaid,0) actual_paid_ctc2
   ,cast(0.0000 as double precision) ctc_paid_days,
cast(0.0000 as double precision) ctc_actual_paid,
cast(0.0000 as double precision) mobile_deduction
,empsalaryregister.id salaryid
,empsalaryregister.pfcapapplied,
pfopted,esiopted,
monthlyofferedpackage,
employeenpsrate,employernpsrate,
insuranceamount,familyinsuranceamount
,openappointments.bankaccountno
, openappointments.ifsccode, openappointments.bankname, openappointments.bankbranch
,coalesce(public.trn_pf_due_delay.duedate,('''||p_mpryear::text||'-'||p_mprmonth::text||'-15'')::DATE + INTERVAL ''1 MONTH'')::Date pf_due_date
,current_date pf_paid_date
,tmparear.netarear
,tmparear.total_esi_incentive
,tmparear.arearaddedmonths
,tblotherdeductionswithesi.otherdeductionswithesi otherdeductionswithesi
,empsalaryregister.isgroupinsurance medicalinsuranceopted
,employee_esi_incentive_deduction
,employer_esi_incentive_deduction
,total_esi_incentive_deduction
,openappointments.appointment_status_id
,empsalaryregister.salaryindaysopted
,empsalaryregister.salarydays
,coalesce(tblotherledger.otherledgerarear,0)-coalesce(otherledgerarearsalreadypaid,0) otherledgerarear
,coalesce(tblotherledger.otherledgerdeductions,0)-(coalesce(otherledgerdeductionsalreadypaid,0))  otherledgerdeductions
,coalesce(othervariables*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end,0) othervariables
,attendancemode
,epfalreadydeducted
,ac_1alreadydeducted
,ac_10alreadydeducted
,ac_2alreadydeducted
,ac_21alreadydeducted
,basicalreadypaid
,vpfalreadypaid
,insurancealreadypaid
,row_number() over(partition by openappointments.emp_code,cmsdownloadedwages.mprmonth,cmsdownloadedwages.mpryear,cmsdownloadedwages.batch_no order by empsalaryregister.id desc) rn
,govt_bonus_amtalreadypaid
,othervariablesalreadypaid
, otherdeductionsalreadypaid
,otherdeductionswithesialreadypaid*totaldaysalready/monthdays otherdeductionswithesialreadypaid
,variablevpf
,otherledgerarearwithoutesi-coalesce(otherledgerarearwithoutesialready,0) otherledgerarearwithoutesi
,openappointments.epf_pension_opted
,employeeesiratealreadypaid
,gross*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end	newgross
,pfapplicablecomponentsalready
,esiapplicablecomponentsalready
,esiapplicablecomponents*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(employeeesiratealreadypaid,0) esiapplicablecomponentsTotal
,case when coalesce(charity_contribution,''N'')=''Y'' then basic else 0 end*0.001*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(charity_contribution_amountalreadypaid,0)  charity_contribution_amount
,greatest(coalesce(mealvoucher,0)*(case when coalesce(salaryindaysopted,''N'')=''N'' then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,''N'')=''N'' then '||v_monthdays||'  else salarydays end-coalesce(mealvoucheralreadydeducted,0),0) mealvoucher
	from (
select * from
public.empsalaryregister
where appointment_id='||v_emp_id||' and to_date('''||v_monthdays::text||lpad(p_mprmonth::text,2,'0')||p_mpryear::text||''',''ddmmyyyy'')
between empsalaryregister.effectivefrom and coalesce(empsalaryregister.effectiveto,current_date)
and id not in (select salaryid from tbl_monthlysalary
where emp_code='||p_emp_code||' and mprmonth='||p_mprmonth||' and mpryear='||p_mpryear||' and coalesce(is_rejected,''0'')<>''1'')

) empsalaryregister
 inner join public.openappointments
 on empsalaryregister.appointment_id=openappointments.emp_id
         and openappointments.appointment_status_id<>13
 and coalesce(converted,''N'')=''Y''
 and openappointments.customeraccountid='||p_customeraccountid||'
';
if p_action='Save_Previous_Salary' then
v_querytext:=v_querytext||'and openappointments.emp_id not in(select EmpId from ManageTempPausedSalary
WHERE  ManageTempPausedSalary.ProcessYear ='||p_mpryear||'
and ManageTempPausedSalary.ProcessMonth ='||p_mprmonth||'
and ManageTempPausedSalary.IsActive=''1''
and coalesce(ManageTempPausedSalary.PausedStatus,''Enable'')=''Enable'')';
end if;
v_querytext:=v_querytext||' left join trn_pf_due_delay
on openappointments.emp_code=trn_pf_due_delay.emp_code
and trn_pf_due_delay.mprmonth='||p_mprmonth||'
and trn_pf_due_delay.mpryear='||p_mpryear||' ';
if p_action='Retrieve_Previous_Salary' then
v_querytext:=v_querytext||' left join (select empid,pausedstatus  is_paused  
from ManageTempPausedSalary

WHERE  ManageTempPausedSalary.ProcessYear ='||p_mpryear||'
and ManageTempPausedSalary.ProcessMonth ='||p_mprmonth||'
-- and ManageTempPausedSalary.IsActive=''1''
--and coalesce(ManageTempPausedSalary.PausedStatus,''Enable'')=''Enable''
) MTempPausedSalary
on openappointments.emp_id=MTempPausedSalary.empid ';
end if;

v_querytext:=v_querytext||' left join(select tbl_monthlysalary.emp_code,sum(netpay) netarear,sum(total_esi_incentive) total_esi_incentive
,STRING_AGG (tbl_monthlysalary.mprmonth || ''-'' || tbl_monthlysalary.mpryear,'','') arearaddedmonths
,sum(employee_esi_incentive) employee_esi_incentive_deduction
,sum(employer_esi_incentive) employer_esi_incentive_deduction
,sum(total_esi_incentive) total_esi_incentive_deduction
from public.tbl_monthlysalary
where 1=2 and isarear=''Y'' and arearprocessmonth='||p_mprmonth||'
and coalesce(is_rejected,''0'')<>''1''
and recordscreen not in (''Previous Wages'',''Current Wages'')
and arearprocessyear='||p_mpryear||'
and (tbl_monthlysalary.emp_code,trim(tbl_monthlysalary.mprmonth || ''-'' || tbl_monthlysalary.mpryear))
not in (select  arrs.emp_code,trim(regexp_split_to_table(arrs.arearaddedmonths,'',''))
from tbl_monthlysalary arrs where coalesce(arrs.is_rejected,''0'')<>''1'')
group by tbl_monthlysalary.emp_code) tmparear
on tmparear.emp_code=openappointments.emp_code';

v_querytext:=v_querytext||' inner join
(select mprmonth
 ,mpryear
 ,empcode
 ,max(dateofjoining) dateofjoining
,max(bunit)bunit
,max(dateofleaving)dateofleaving
,max(totalleavetaken)totalleavetaken
,0 totalsalarydays
,sum(totalpaiddays)totalpaiddays
,max(lossofpay)lossofpay
,max(isactive::int)::bit isactive
,to_char(current_timestamp,''ddmmyyyyhh24miss'')||''_Increment'' batch_no
--,string_agg(batch_no,'','') batch_no
,string_agg(projectname,'','')projectname
,string_agg(contractno,'','')contractno
,string_agg(contractcategory,'','')contractcategory
,string_agg(contracttype,'','')contracttype
,max(attendancemode)attendancemode
 from public.cmsdownloadedwages
 where cmsdownloadedwages.isactive=''1''
 and cmsdownloadedwages.empcode =case when '''||p_criteria||'''=''Employee'' then '''||p_emp_code||'''  else
cmsdownloadedwages.empcode end
and cmsdownloadedwages.mpryear='||p_mpryear||'
and cmsdownloadedwages.mprmonth='||p_mprmonth||'
and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''''),''Y'')<>''N''
--and (cmsdownloadedwages.mprmonth, cmsdownloadedwages.mpryear, cmsdownloadedwages.empcode::bigint) not in
--(select m5.mprmonth, m5.mpryear,  m5.emp_code from tbl_monthlysalary m5 where coalesce(m5.is_rejected,''0'')<>''1''  and recordscreen=''Increment Arear'')
group by mprmonth,mpryear,empcode
) cmsdownloadedwages
on upper(cmsdownloadedwages.empcode)=upper(openappointments.emp_code::varchar) ';

--if nullif(trim(p_batch_no),'') is not null then
--v_querytext=v_querytext||' and cmsdownloadedwages.batch_no='''||p_batch_no||'''';
--end if;
v_querytext:=v_querytext||' left join (select salaryid,candidate_id,sum(deduction_amount) otherdeductions
  from public.trn_candidate_otherduction
  where --public.trn_candidate_otherduction.active=''Y'' and
 coalesce(trn_candidate_otherduction.includedinctc,''N'')=''Y''  
 and coalesce(isvariable,''N'')=''N''  --change 1.4
 and trn_candidate_otherduction.deduction_id not in (5,6,7,10,12) 
 and trn_candidate_otherduction.deduction_id<>134 --Meal Voucher ID, Change for Production
 and trn_candidate_otherduction.deduction_frequency in (''Quarterly'',''Half Yearly'',''Annually'')
 group by salaryid,public.trn_candidate_otherduction.candidate_id) tblotherdeductions
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
		and trn_candidate_otherduction.deduction_id<>134 --Meal Voucher ID, Change for Production
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
,sum(tdsadjustment) tdsadjustment from (
select emp_code,sum(case when amount>0 and headid in (5,6) then amount else 0 end) otherledgerarear
						,sum(case when amount<0 and headid not in (12) then amount else 0 end)*-1 otherledgerdeductions
						,sum(case when amount>0 and headid not in (5,6,12) then amount else 0 end) otherledgerarearwithoutesi
						,sum(case when headid =12 then amount else 0 end) tdsadjustment
				   from tbl_employeeledger
				   where tbl_employeeledger.isactive=''1'' 
				  and processmonth='||p_mprmonth||'
				  and processyear='||p_mpryear||'
				  and headid not in (19,39)
				  group by emp_code
			union all
		/*Below code for security amount dated 04-July2021*/
			select 
			emp_code,sum(case when deduction_amount>0 then deduction_amount else 0 end) otherledgerarear
					,sum(case when deduction_amount<0 then deduction_amount else 0 end)*-1 otherledgerdeductions
					,0 otherledgerarearwithoutesi
					,0 tdsadjustment
				   from public.trn_candidate_otherduction inner join openappointments
				   on trn_candidate_otherduction.candidate_id= openappointments.emp_id
				   where public.trn_candidate_otherduction.active=''Y''
				  and trn_candidate_otherduction.deduction_id =7
				  group by emp_code
				  	/*Below code for security amount dated 04-July2021 ends here*/
				  ) tblotherledger1 group by emp_code
				  ) tblotherledger
		          on cmsdownloadedwages.empcode::bigint=tblotherledger.emp_code  	    
----------------------------------------------------------------------
left join (select salaryid,candidate_id,sum(deduction_amount) othervariables
	,string_agg(deduction_name||'':''||deduction_amount,'','') customnontaxablecomponents
				   from public.trn_candidate_otherduction
				   inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
				   where public.trn_candidate_otherduction.active=''Y''
				   and motd.deduction_name not in (''Conveyance'')
				   and deduction_amount>0
and trn_candidate_otherduction.deduction_id<>134 --Meal Voucher ID
				  --and coalesce(trn_candidate_otherduction.includedinctc,''N'')=''N'' 
				  and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				  and trn_candidate_otherduction.deduction_id not in (5,6,7,10)
				  and coalesce(trn_candidate_otherduction.is_taxable,''N'')=''N''
				  group by salaryid,public.trn_candidate_otherduction.candidate_id) tblothervariables
         on openappointments.emp_id=tblothervariables.candidate_id
 and empsalaryregister.id=tblothervariables.salaryid
-------------------------------------------------------------------------
---------------Added Meal Voucher --------------------------					  
left join (select salaryid,candidate_id,sum(deduction_amount) mealvoucher
				   from public.trn_candidate_otherduction
				   inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
				   where public.trn_candidate_otherduction.active=''Y'' 
				   and deduction_amount>0
				  --and trn_candidate_otherduction.deduction_frequency in (''Monthly'')
				  and motd.id=134 --Meal Voucher ID, Change for Production
				  group by salaryid,public.trn_candidate_otherduction.candidate_id) tblmealvoucher
		          on openappointments.emp_id=tblmealvoucher.candidate_id
				  and empsalaryregister.id=tblmealvoucher.salaryid 				  
----------------------------------------------------------------------		
inner join (select emp_code,max(salaryid) alreadysalid,sum(paiddays) totaldaysalready,max(monthdays) monthdays
,sum(basic) basicalreadypaid
,sum(hra)  hraalreadypaid
,sum(conv)  convalreadypaid
,sum(medical)  medicalalreadypaid
,sum(specialallowance)  specialallowancealreadypaid
,sum(fixedallowancestotal)  fixedallowancestotalalreadypaid
,sum(epf) epfalreadydeducted
,sum(vpf) vpfalreadypaid
,sum(Insurance) Insurancealreadypaid
,sum(coalesce(Ac_1,0)) Ac_1alreadydeducted
,sum(coalesce(Ac_10,0)) ac_10alreadydeducted
,sum(coalesce(Ac_2,0)) ac_2alreadydeducted
,sum(coalesce(Ac21,0)) ac_21alreadydeducted
,sum( ctc2)  ctc2alreadypaid
,sum(actual_paid_ctc2) actual_paid_ctc2alreadypaid
,sum(ctc) ctcalreadypaid
,sum(ctc_paid_days) ctc_paid_daysalreadypaid
,sum(ctc_actual_paid) ctc_actual_paidalreadypaid
,sum(mobile_deduction) mobile_deductionalreadypaid
,sum(ews) ewsalreadypaid
,sum(gratuity) gratuityalreadypaid
,sum(govt_bonus_amt) govt_bonus_amtalreadypaid
,sum(otherledgerarears) otherledgerarearsalreadypaid
,sum(coalesce(otherledgerdeductions,0)+coalesce(case when refund<0 then refund*-1 else 0 end,0)) otherledgerdeductionsalreadypaid
,sum(Other) Otheralreadypaid
,sum(otherledgerarearwithoutesi) otherledgerarearwithoutesialready
	
,sum(coalesce(coalesce(nullif(pfapplicablecomponents,0),basic),0)) pfapplicablecomponentsalready	
,sum(coalesce(coalesce(nullif(esiapplicablecomponents,0),fixedallowancestotal),0)) esiapplicablecomponentsalready		
-----------1.4------------------------	
,sum(othervariables) othervariablesalreadypaid	 
,sum(otherdeductions) 	otherdeductionsalreadypaid
,sum(employeeesirate) employeeesiratealreadypaid	
----------1.4 ends-------------------	
,sum(commission)commissionalreadypaid
,sum( transport_allowance) transport_allowancealreadypaid
,sum( travelling_allowance) travelling_allowancealreadypaid
,sum( leave_encashment) leave_encashmentalreadypaid
,sum( overtime_allowance) overtime_allowancealreadypaid
,sum( notice_pay) notice_payalreadypaid
,sum( hold_salary_non_taxable) hold_salary_non_taxablealreadypaid
,sum( children_education_allowance) children_education_allowancealreadypaid
,sum( gratuityinhand) gratuityinhandalreadypaid
,sum( salarybonus) salarybonusalreadypaid
,sum( charity_contribution_amount) charity_contribution_amountalreadypaid
,sum(mealvoucher) mealvoucheralreadydeducted
-------------------------------------
from tbl_monthlysalary
where mprmonth='||p_mprmonth||'
and mpryear='||p_mpryear||'
and coalesce(is_rejected,''0'')<>''1''
group by emp_code) tblalreadypf
on tblalreadypf.emp_code=openappointments.emp_code
------------------------------------------------------------------------------------------------
left join (select salaryid,candidate_id,sum(deduction_amount) otherdeductionswithesialreadypaid
  from public.trn_candidate_otherduction
  where  /*trn_candidate_otherduction.active=''Y''
 and*/ trn_candidate_otherduction.deduction_id in (5,6)
 group by salaryid,public.trn_candidate_otherduction.candidate_id) tblotherdeductionswithesialready
         on tblalreadypf.alreadysalid=tblotherdeductionswithesialready.salaryid  
----------------------------------------------------------------------------------------------------
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

  v_querytext:=v_querytext||' 
and (cmsdownloadedwages.mprmonth, cmsdownloadedwages.mpryear, openappointments.emp_code,empsalaryregister.id) not in
(select m.mprmonth, m.mpryear,  m.emp_code,m.salaryid from tbl_monthlysalary m where coalesce(m.is_rejected,''0'')<>''1'' and recordscreen=''Increment Arear'')

) tmp where rn=1';
-----To print dynamic Query----------------------
raise notice 'Query: % ', v_querytext;
-----To print dynamic Query----------------------
v_querytext2='CREATE TEMP TABLE tmp_sal_incr ON COMMIT DROP as '||v_querytext;
 execute v_querytext2;
--raise notice 'Query: % ', v_querytext2;
update tmp_sal_incr set ctc_paid_days=round((actual_paid_ctc2/ctc)*monthdays)
where is_special_category='Y';
/*********Change 1.3***************************************
update tmp_sal_incr
set ac_10=case when coalesce(o.epf_pension_opted,'Y')='Y' then round(least(ac_10,1249.5)::numeric(18,2),2) else 0.0 end,
    ac_1=case  when coalesce(o.epf_pension_opted,'Y')='Y' then round((ac_1+(greatest(ac_10-least(ac_10,1249.5),0)))::numeric(18,2),2) else round((coalesce(ac_1,0)+coalesce(ac_10,0))::numeric(18,2),2) end
from openappointments o
where tmp_sal_incr.emp_code=o.emp_code 
and o.appointment_status_id<>13;
***********Change 1.3 ends here*****************************/
update tmp_sal_incr set ctc_actual_paid=(ctc*ctc_paid_days/monthdays),
mobile_deduction=(ctc*ctc_paid_days/monthdays)-actual_paid_ctc2
   where is_special_category='Y';
if v_openappointments.jobtype='Independent Contractors' then
select * from empsalaryregister  where  id=(select tmp_sal_incr.salaryid from tmp_sal_incr) into v_empsalaryregister;
	update tmp_sal_incr
	set tds=grossearning*coalesce(v_empsalaryregister.customtaxpercent/100.0,.01),--atds=grossearning*coalesce(v_empsalaryregister.customtaxpercent/100.0,.01),
	grossdeduction=grossdeduction+grossearning*coalesce(v_empsalaryregister.customtaxpercent/100.0,.01),
	netpay=netpay-grossearning*coalesce(v_empsalaryregister.customtaxpercent/100.0,.01);
end if;
/*
if (select  isReverseEPF from tmp_sal_incr)<>'Reverse EPF Case' then
	update tmp_sal_incr set account1_7q_dues=coalesce(Ac_1,0.0)*12*case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00,
	account10_7q_dues=coalesce(Ac_10,0.0)*12*case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00,
	account2_7q_dues=coalesce(Ac_2,0.0)*12*case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00,
	account21_7q_dues=coalesce(Ac21,0.0)*12*case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00;

	update tmp_sal_incr set account1_14b_dues=coalesce(Ac_1,0.0)*case when pf_paid_date>=pf_due_date+ INTERVAL '6 MONTH' then 25 when pf_paid_date>=pf_due_date+ INTERVAL '4 MONTH' then 15 when pf_paid_date>=pf_due_date+ INTERVAL '2 MONTH' then 5 when pf_paid_date>pf_due_date then 5 else 0 end *case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00,
	account10_14b_dues=coalesce(Ac_10,0.0)*case when pf_paid_date>=pf_due_date+ INTERVAL '6 MONTH' then 25 when pf_paid_date>=pf_due_date+ INTERVAL '4 MONTH' then 15 when pf_paid_date>=pf_due_date+ INTERVAL '2 MONTH' then 5 when pf_paid_date>pf_due_date then 5 else 0 end *case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00,
	account2_14b_dues=coalesce(Ac_2,0.0)*case when pf_paid_date>=pf_due_date+ INTERVAL '6 MONTH' then 25 when pf_paid_date>=pf_due_date+ INTERVAL '4 MONTH' then 15 when pf_paid_date>=pf_due_date+ INTERVAL '2 MONTH' then 5 when pf_paid_date>pf_due_date then 5 else 0 end *case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00,
	account21_14b_dues=coalesce(Ac21,0.0)*case when pf_paid_date>=pf_due_date+ INTERVAL '6 MONTH' then 25 when pf_paid_date>=pf_due_date+ INTERVAL '4 MONTH' then 15 when pf_paid_date>=pf_due_date+ INTERVAL '2 MONTH' then 5 when pf_paid_date>pf_due_date then 5 else 0 end *case when pf_due_date<pf_paid_date then (pf_paid_date-pf_due_date) else 0 end/36500.00;
end if;
	
update tmp_sal_incr set netpay=netpay-coalesce(account1_7q_dues,0)-coalesce(account10_7q_dues,0)-coalesce(account2_7q_dues,0)-coalesce(account21_7q_dues,0)-coalesce(account1_14b_dues,0)-coalesce(account10_14b_dues,0)-coalesce(account2_14b_dues,0)-coalesce(account21_14b_dues,0)
  ,GrossDeduction=GrossDeduction+coalesce(account1_7q_dues,0)+coalesce(account10_7q_dues,0)+coalesce(account2_7q_dues,0)+coalesce(account21_7q_dues,0)+coalesce(account1_14b_dues,0)+coalesce(account10_14b_dues,0)+coalesce(account2_14b_dues,0)+coalesce(account21_14b_dues,0);
*/
update tmp_sal_incr set ctc_actual_paid=(ctc*ctc_paid_days/monthdays),
       netpay=netpay+coalesce(otherledgerarear,0)-coalesce(grossdeduction,0)+coalesce(otherledgerarearwithoutesi,0)
   where is_special_category='Y'; 
   
 update tmp_sal_incr  
	set mobile_deduction=case when ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0)) >0 then ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0))  else 0 end
	             ,mobile=case when ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0)) >0 then ((grossearning-coalesce(grossdeduction,0.0))-coalesce(netpay,0.0))  else 0 end
	            ,incentive=case when (coalesce(netpay,0.0)-(grossearning-coalesce(grossdeduction,0.0))) >0 then (coalesce(netpay,0.0)-(grossearning-coalesce(grossdeduction,0.0)))  else 0 end
where is_special_category='Y'; 	

	/***************************Changes for 1.7****************/
with tmpexgrossearning as
(
select emp_code,sum(grossearning) grossearning,sum(professionaltax) pt from tbl_monthlysalary
	where emp_code in (select emp_code from tmp_sal_incr) and
	  (
			to_date(left(hrgeneratedon,11),'dd Mon yyyy')
				between v_salstartdate  and v_salenddate	 
			or
				(
				to_date(left(hrgeneratedon,11),'dd Mon yyyy')
				between v_advancesalstartdate  and v_advancesalenddate		 
				and mprmonth=v_mprmonth and mpryear=v_mpryear
				 )
			)
	and is_rejected='0'
	and istaxapplicable='1'
	group by emp_code
)
update tmp_sal_incr 
	set pt=tbl1.professionaltax,grossdeduction=grossdeduction+coalesce(tbl1.professionaltax,0)
	,netpay=netpay-coalesce(tbl1.professionaltax,0)
	from (select op.emp_code,e.id,mst_statewiseprofftax.ptamount professionaltax,te.grossearning,mst_statewiseprofftax.lowerlimit,mst_statewiseprofftax.upperlimit,te.pt
		  from  openappointments op 
	inner join empsalaryregister e on e.appointment_id=op.emp_id
		  inner join tmp_sal_incr on op.emp_code=tmp_sal_incr.emp_code and e.id=tmp_sal_incr.salaryid
		  inner join vw_mst_statewiseprofftax mst_statewiseprofftax on mst_statewiseprofftax.ptid=e.ptid 
		  and extract ('month' from (current_date-interval '1 month'))=mst_statewiseprofftax.ptmonth 
		  and lower(case when op.gender='M' then 'Male' when op.gender='F' then  'Female' else op.gender end)=lower(mst_statewiseprofftax.ptgender)
		  and mst_statewiseprofftax.isactive='1'
		  --and (date_trunc('month',current_date)-interval '1 month')::date  between mst_statewiseprofftax.ptapplicablefrom and mst_statewiseprofftax.ptapplicableto
		 left join tmpexgrossearning te on te.emp_code=op.emp_code) tbl1
	where tmp_sal_incr.emp_code=tbl1.emp_code and tbl1.professionaltax>0
	and (coalesce(tbl1.grossearning,0)+coalesce(tmp_sal_incr.grossearning,0)) between tbl1.lowerlimit and tbl1.upperlimit
	and coalesce(tbl1.pt,0)<=0;
/***************************Changes for 1.7 end here****************/	
alter table tmp_sal_incr drop column isReverseEPF;	
if p_action='Retrieve_Previous_Salary' then
open sal for
select tmp_sal_incr.*,case when m.emp_code is null then 'Not Verified'
when coalesce(m.is_rejected,'0')='1' then 'Rejected'
when m.emp_code is not null then 'Verified'
end verificationstatus
, 'No Arear'  as hasarrear
,case when m.is_rejected='1' then 'Rejected' else 'Not Rejected' end as rejectstatus
,to_char(m.createdon,'dd-Mon-yyyy') processedon
,case when invpddays_empcode is null then 'Valid' else 'Invalid' end as paiddaysstatus
,'IncrementDiff' calcrowtype
from  tmp_sal_incr
tmp_sal_incr left join tbl_monthlysalary m
on tmp_sal_incr.emp_code=m.emp_code
and tmp_sal_incr.mpryear=m.mpryear
and tmp_sal_incr.mprmonth=m.mprmonth
and tmp_sal_incr.batch_no=m.batchid
and coalesce(m.is_rejected,'0')<>'1'
and m.recordscreen not in ('Increment Arear')
/*left join (select distinct empcode
 from cmsdownloadedwages
where to_date('01'||lpad(cmsdownloadedwages.mprmonth::text,2,'0')||cmsdownloadedwages.mpryear::text,'ddmmyyyy')<
to_date('01'||lpad(p_mprmonth::text,2,'0')||p_mpryear::text,'ddmmyyyy')
and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y')<>'N'
  and cmsdownloadedwages.isactive='1'
 and (cmsdownloadedwages.empcode::bigint,cmsdownloadedwages.mprmonth,cmsdownloadedwages.mpryear)
 not in (select m3.emp_code,m3.mprmonth,m3.mpryear
 from tbl_monthlysalary m3
 where coalesce(m3.is_rejected,'0')<>'1'
)
 ) tblhasarear
on tmp_sal_incr.emp_code=tblhasarear.empcode::bigint*/
left join (select empcode invpddays_empcode,sum(coalesce(totalpaiddays,0)+coalesce(totalleavetaken,0))
from cmsdownloadedwages
where mprmonth=p_mprmonth
and mpryear=p_mpryear
 and isactive='1'
 and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y')<>'N' 		   
group by empcode
 having sum(coalesce(totalpaiddays,0)+coalesce(totalleavetaken,0))>v_monthdays) m4
 on tmp_sal_incr.emp_code=m4.invpddays_empcode::bigint;
return sal;
end if;

if p_action='Save_Previous_Salary' then
	
alter table tmp_sal_incr add column arearprocessedby bigint;
alter table tmp_sal_incr add column arearprocessedon timestamp;
alter table tmp_sal_incr add column arearprocessedbyip varchar(150);

update tmp_sal_incr
	set arearprocessedby=p_createdby,
	arearprocessedon=current_timestamp,
	arearprocessedbyip=tmp_sal_incr.createdbyip;

	
v_querytext:='insert into tbl_monthlysalary ( mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2,batch_no,actual_paid_ctc2,ctc,ctc_paid_days,ctc_actual_paid,mobile_deduction,salaryid,isarear,employeenps,employernps,insuranceamount,familyinsurance,bankaccountno, ifsccode, bankname, bankbranch,totalarear,arearaddedmonths,employee_esi_incentive_deduction,employer_esi_incentive_deduction,total_esi_incentive_deduction,salaryindaysopted,mastersalarydays,otherledgerarears,otherledgerdeductions,employee_esi_incentive,employer_esi_incentive,total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date,recordscreen,isarearprocessed,arearprocessmonth,arearprocessyear,attendancemode,othervariables,otherdeductions,otherledgerarearwithoutesi,hrgeneratedon,professionaltax,tptype,commission, transport_allowance, travelling_allowance, leave_encashment, overtime_allowance, notice_pay, hold_salary_non_taxable, children_education_allowance, gratuityinhand, salarybonus,pfapplicablecomponents,esiapplicablecomponents,charity_contribution_amount,mealvoucher,arearprocessedby,arearprocessedon,arearprocessedbyip,is_advice)
	
	select *,''Y'' from tmp_sal_incr
where (tmp_sal_incr.mprmonth, tmp_sal_incr.mpryear, tmp_sal_incr.emp_code,tmp_sal_incr.salaryid) not in
(select m.mprmonth, m.mpryear,  m.emp_code,m.salaryid from tbl_monthlysalary m where coalesce(m.is_rejected,''0'')<>''1'' and recordscreen=''Increment Arear'')
	';
execute v_querytext;
	
/*	
select public.uspgetorderwisewages(
	p_mprmonth =>v_mprmonth,
	p_mpryear =>v_mpryear,
	p_ordernumber =>''::character varying,
	p_emp_code =>p_emp_code::bigint,
	p_batch_no =>''::character varying,
	p_action =>'Save_Salary'::character varying,
	p_createdby =>p_createdby::bigint,
	createdbyip =>createdbyip::character varying,
	p_criteria =>'Employee'::character varying,
	p_process_status =>'NotProcessed'::character varying,
	p_issalaryorliability =>'S'::character varying,
	p_tptype => 'TP'::character varying,
	p_companycode =>''::character varying,
	p_payment_recordid =>- (9999)::bigint
)
	into v_rfc;
*/	
open sal for select 1 as cnt;
return sal;
end if;
-- exception when others then
 raise notice 'Query: % ', v_querytext;
-- open sal for select 0 as cnt;
-- return sal;
end;

$BODY$;

ALTER FUNCTION public.uspgetincrementdiff(integer, integer, character varying, bigint, character varying, character varying, bigint, character varying, character varying, bigint, text)
    OWNER TO payrollingdb;

