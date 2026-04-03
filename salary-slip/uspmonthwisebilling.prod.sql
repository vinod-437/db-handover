-- FUNCTION: public.uspmonthwisebilling(integer, integer, text, bigint, text, character varying)

-- DROP FUNCTION IF EXISTS public.uspmonthwisebilling(integer, integer, text, bigint, text, character varying);

CREATE OR REPLACE FUNCTION public.uspmonthwisebilling(
	p_rptmonth integer,
	p_rptyear integer,
	p_action text,
	p_empcode bigint DEFAULT '-9999'::integer,
	p_disbursementmode text DEFAULT 'Salary'::text,
	p_tptype character varying DEFAULT 'NonTP'::character varying)
    RETURNS SETOF refcursor 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
declare 
	v_rfc refcursor;
	v_rfcsal refcursor;
	v_rec record;
	v_jobrole varchar(200);
	
	v_salstartdate date;
	v_salenddate date;
	v_prevsaldate date;
-- 	v_rfcsalprevious refcursor;
v_rfctotalattendance refcursor;
v_rfcunprocessedAttendance refcursor;
v_processedasarear int;
v_processedasprevious int;
v_processedascurrent int;
v_uniquemultipermerbatch int;
v_uniquenonmultipermerbatch int;
v_message text;
v_rfcesic_challan refcursor;
v_rfcpf_challan refcursor;
v_rateconveyance numeric(18,2);
v_conveyance numeric(18,2);
begin
/**********************************************************************************************
Version Date			Change						 Done_by
1.0		01-Dec-2023		Initial Version				Shiv Kumar
1.1		31-May-2024		Add 10 Static components	Shiv Kumar
1.2		22-Jul-2024		Variable Conveyance			Shiv Kumar
1.3		05-Sep-2024		Add Tea Allowance			Shiv Kumar
1.5 	05-Dec-2025		Bifurcate Vouchers and Deductions							Shiv Kumar
***********************************************************************************************/
/**************************change 1.2 starts**********************************/
select /*op.customeraccountid,op.emp_code,max(salarydays),sum(paiddays) paiddays,*/coalesce(max(tr.deduction_amount),0) as rateconveyance,coalesce(sum(tbl_monthlysalary.paiddays*tr.deduction_amount/tbl_monthlysalary.monthdays),0) conveyance
			   from tbl_monthlysalary  inner join openappointments op on op.emp_code=tbl_monthlysalary.emp_code
			   	inner join empsalaryregister e on tbl_monthlysalary.salaryid=e.id
			   and tbl_monthlysalary.emp_code= p_empcode and
			   	 mprmonth=p_rptmonth and mpryear=p_rptyear
				and coalesce(is_rejected,'0')<>'1'
			   inner join trn_candidate_otherduction tr
			   on e.id=tr.salaryid and tr.active='Y'
				inner join mst_otherduction motd on motd.id=tr.deduction_id
			   and  motd.deduction_name = 'Conveyance Allowance'
			   and tr.is_taxable='Y'
			   having coalesce(sum(tbl_monthlysalary.paiddays*tr.deduction_amount),0)>0
			   into v_rateconveyance,v_conveyance;
			   v_rateconveyance:=coalesce(v_rateconveyance,0);
			   v_conveyance:=coalesce(v_conveyance,0);
/**************************change 1.2 ends************************************/	
/**************************Calc dates************************************/	
    select DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE ) - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate;
	v_message:='Compiled Report for Attendance between '||v_salstartdate|| ' and '||v_salenddate;
/**************************Calc dates ends here****************************/	
if p_action='GetMonthBilling' then
	Raise Notice 'v_salstartdate=%,v_salenddate=%,v_prevsaldate=%',v_salstartdate,v_salenddate,v_prevsaldate;
	
	
    create temporary table tmpbilling on commit drop
	as
	select TO_CHAR(TO_TIMESTAMP (t1.mprmonth::text, 'MM'), 'Mon')||'-'||t1.mpryear::text||'[Downloaded]' as Mon,
	t1.emp_code Employee,
	op.emp_name as Employee_Name,op.fathername as Father_Husband_Name,
	--coalesce(tmpjobrole.jobrole,op.post_offered) Designation,
	op.post_offered Designation,
	op.posting_department Department,
	t1.subunit SubUnit,
	to_char(op.dateofjoining,'dd-Mon-yy') DateofJoining,
	to_char(op.dateofbirth,'dd-Mon-yy') dateofbirth,	
	op.esinumber, op.pancard pan_number,
	op.uannumber,
	t1.subunit SubUnit_2,
	op.emp_code Employee_2,
	op.email,
	op.aadharcard,
	to_char(dateofleaving,'dd-Mon-yyyy') dateofleaving,
	coalesce(t2.paiddays,0)+coalesce(t3.paiddays,0) Arrear_Days,	
	--t1.monthdays-t1.PaidDays Loss_Off_Pay,
	case when t1.recordscreen ='Current Wages' then  t1.monthdays-(t1.PaidDays/*+coalesce(t5.paiddays,0)*/) else 0.0 end Loss_Off_Pay,
	--t1.paiddays Total_Paid_Days,
	case when t1.recordscreen ='Current Wages' then (t1.paiddays/*+coalesce(t5.paiddays,0.0)*/) else 0.0 end Total_Paid_Days,
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratebasic end RateBasic,	
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratehra end RateHRA,
	case when t1.recordscreen ='Previous Wages' then 0.0 else coalesce(t1.rateconv,0)+v_rateconveyance end RateCONV,
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratemedical end RateMedical,
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratespecialallowance end RateSpecial_Allowance,
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.fixedallowancestotalrate end FixedAllowancesTotalRate,
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.basic+coalesce(t1.incrementarear_basic,0.0) end basic,	
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.hra+coalesce(t1.incrementarear_hra,0.0) end HRA,
	case when t1.recordscreen ='Previous Wages' then 0.0 else coalesce(t1.conv,0)+v_conveyance end CONV,
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.medical end Medical,
	case when t1.recordscreen ='Previous Wages' then 0.0 else t1.specialallowance+coalesce(t1.incrementarear_allowance,0.0) end SpecialAllowance,
	coalesce(case when t1.recordscreen ='Previous Wages' then t1.basic else 0.0 end,0.0)+ coalesce(t2.arr_basic,0.0)+coalesce(t3.arr_basic,0.0) as Arr_Basic,
	coalesce(case when t1.recordscreen ='Previous Wages' then t1.hra else 0.0 end,0.0)+coalesce(t2.Arr_HRA,0.0)+coalesce(t3.Arr_HRA,0.0) as Arr_HRA,
	coalesce(case when t1.recordscreen ='Previous Wages' then t1.conv else 0.0 end,0.0)+coalesce(t2.Arr_CONV,0)+coalesce(t3.Arr_CONV,0) Arr_CONV,
	coalesce(case when t1.recordscreen ='Previous Wages' then t1.medical else 0.0 end,0.0)+coalesce(t2.Arr_Medical,0)+coalesce(t3.Arr_Medical,0) Arr_Medical,
	coalesce(case when t1.recordscreen ='Previous Wages' then t1.SpecialAllowance else 0.0 end,0.0)+coalesce(t2.Arr_SpecialAllowance,0.0)+coalesce(t3.Arr_SpecialAllowance,0.0) Arr_SpecialAllowance,
	coalesce(case when t1.recordscreen ='Previous Wages' then t1.incentive else 0.0 end,0.0)+coalesce(t1.Incentive,0.0)+coalesce(t2.Incentive,0.0)+coalesce(t3.Incentive,0.0)
    +(coalesce(case when t1.othervariables>0 then  t1.othervariables else 0.0 end,0.0) +coalesce(t2.othervariables,0.0) +coalesce(t3.othervariables,0.0))
    --+coalesce(t1.otherledgerarears,0.0) +coalesce(t2.otherledgerarears,0.0) +coalesce(t3.otherledgerarears,0.0)
    /*+coalesce(t1.otherledgerarearwithoutesi,0.0) +coalesce(t2.otherledgerarearwithoutesi,0.0) +coalesce(t3.otherledgerarearwithoutesi,0.0)*/ 
    +coalesce(t1.otherbonuswithesi,0.0) +coalesce(t2.otherbonuswithesi,0.0) +coalesce(t3.otherbonuswithesi,0.0)
   	+case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))) <0 then ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))*-1  else 0 end
	-v_conveyance
	Incentive,
	coalesce(case when t1.recordscreen ='Previous Wages' then t1.refund else 0.0 end,0.0)+coalesce(t1.Refund,0.0) +coalesce(t2.Refund,0.0)+coalesce(t3.Refund,0.0) Refund,
	coalesce(t1.govt_bonus_amt,0.0)+coalesce(t2.govt_bonus_amt,0.0)+coalesce(t3.govt_bonus_amt,0.0) Monthly_Bonus,
	case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))) <0 then ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))*-1  else 0 end+
	coalesce(t1.GrossEarning,0)+coalesce(t2.GrossEarning,0)/*+coalesce(t3.GrossEarning,0)*/
	+coalesce(case when t1.othervariables<0 then  t1.othervariables*-1 else 0.0 end,0.0)
	GrossEarning,	
   	coalesce(t1.EPF,0)+coalesce(t2.arrear_epf,0)+coalesce(t3.arrear_epf,0) as epf,
	--coalesce(t1.EPF,0)+coalesce(t2.arrear_epf,0)+coalesce(t3.arrear_epf,0)+coalesce(t2.arrear_damagecharges,0)+coalesce(t3.arrear_damagecharges,0) as epf,
	coalesce(t1.VPF,0)+coalesce(t2.arrear_vpf,0)+coalesce(t3.arrear_vpf,0) vpf,
	coalesce(t1.employeeesirate,0.0)+coalesce(incrementarear_employeeesi,0.0) ESI,
	coalesce(t1.TDS,0) +coalesce(t2.TDS,0) +coalesce(t3.TDS,0) tds,
	coalesce(t1.Loan,0.0)+coalesce(t2.Loan,0.0) +coalesce(t3.Loan,0.0) loan,
	coalesce(t1.LWF,0)+coalesce(t2.LWF,0)+coalesce(t3.LWF,0)/*+coalesce(t5.lwf_employee,0)*/ as lwf,
	coalesce(case when empsalaryregister.isgroupinsurance='Y' then t1.insurance else 0 end,0,0)+coalesce(t2.Insurance,0.0)+coalesce(t3.Insurance,0.0)/*+coalesce(t5.insurance,0.0)*/ Insurance,
    case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))>0 then (t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))  else 0 end+
	(coalesce(account1_7q_dues,0)
						+coalesce(account1_14b_dues,0)
						+coalesce(account10_7q_dues,0)
						+coalesce(account10_14b_dues,0)
						+coalesce(account2_7q_dues,0)
						+coalesce(account2_14b_dues,0)
						+coalesce(account21_7q_dues,0)
						+coalesce(account21_14b_dues,0)
						) +coalesce(t2.arrear_damagecharges,0.0) +coalesce(t3.arrear_damagecharges,0.0)+coalesce(t2.mobile,0.0) Mobile,
	coalesce(t1.Advance,0.0)+coalesce(t2.Advance,0.0)+coalesce(t3.Advance,0.0) Advance,
	coalesce(case when t1.othervariables<0 then t1.othervariables*-1 else 0.0 end,0.0)+
	coalesce(t1.Other,0.0)+coalesce(t2.Other,0.0)+coalesce(t3.Other,0.0)
	/*+coalesce(t1.otherledgerdeductions,0.0) +coalesce(t2.otherledgerdeductions,0.0) +coalesce(t3.otherledgerdeductions,0.0)*/
	/*+coalesce(t1.otherdeductions,0.0) +coalesce(t2.otherdeductions,0.0) +coalesce(t3.otherdeductions,0.0)*/ --commented on 19-Dec-2025
	other,
	case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))) >0 then ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))  else 0 end+
	coalesce(t1.GrossDeduction,0)+coalesce(t2.GrossDeduction,0)+coalesce(t3.GrossDeduction,0)
	+coalesce(case when t1.othervariables<0 then  t1.othervariables*-1 else 0.0 end,0.0)
    GrossDeduction,
	t1.NetPay,
	coalesce(t1.ac_1,0.0)+coalesce(t2.arrear_ac_1,0.0)+coalesce(t3.arrear_ac_1,0.0) ac_1,
	coalesce(t1.ac_10,0.0)+coalesce(t2.arrear_ac_10,0.0)+coalesce(t3.arrear_ac_10,0.0) ac_10,
	coalesce(t1.ac_2,0.0)+coalesce(t2.arrear_ac_2,0.0)+coalesce(t3.arrear_ac_2,0.0) ac_2,
	coalesce(t1.ac21,0.0)+coalesce(t2.arrear_ac21,0.0)+coalesce(t3.arrear_ac21,0.0) ac21,
	coalesce(t1.employeresirate,0.0)+coalesce(incrementarear_employeresi,0.0) Employer_ESI_Contr,
    'Processed' as salarystatus,
		t1.arearaddedmonths,
	t1.monthdays,
	t1.salaryid,
	case when banktransfers.emp_code is not null or ta.payout_mode_type in ('self','hybrid')then 'Transferred' else 'Not Transferred' end banktransferstatus,
	coalesce(t1.aTDS,0) +coalesce(t2.aTDS,0) +coalesce(t3.aTDS,0) atds,
	coalesce(t1.voucher_amount,0.0) +coalesce(t2.voucher_amount,0.0) +coalesce(t3.voucher_amount,0.0) voucher_amount	
-----------Change for Additional fields---------------------------------	
	,coalesce(t1.ews,0.0) +coalesce(t2.ews,0.0) +coalesce(t3.ews,0.0)  ews,
	coalesce(t1.gratuity,0.0) +coalesce(t2.gratuity,0.0) +coalesce(t3.gratuity,0.0) gratuity ,
	coalesce(t1.bonus,0.0) +coalesce(t2.bonus,0.0) +coalesce(t3.bonus,0.0) bonus ,
	coalesce(t1.employeenps,0.0) +coalesce(t2.employeenps,0.0) +coalesce(t3.employeenps,0.0) employeenps ,
						(coalesce(account1_7q_dues,0)
						+coalesce(account1_14b_dues,0)
						+coalesce(account10_7q_dues,0)
						+coalesce(account10_14b_dues,0)
						+coalesce(account2_7q_dues,0)
						+coalesce(account2_14b_dues,0)
						+coalesce( account21_7q_dues,0)
						+coalesce(account21_14b_dues,0)
						) +coalesce(t2.arrear_damagecharges,0.0) +coalesce(t3.arrear_damagecharges,0.0) damagecharges ,
	coalesce(t1.otherledgerarears,0.0) +coalesce(t2.otherledgerarears,0.0) +coalesce(t3.otherledgerarears,0.0) otherledgerarears ,
	coalesce(t1.otherledgerdeductions,0.0) +coalesce(t2.otherledgerdeductions,0.0) +coalesce(t3.otherledgerdeductions,0.0) otherledgerdeductions ,
    coalesce(case when t1.othervariables>0 then t1.othervariables else 0.0 end,0.0) +coalesce(t2.othervariables,0.0) +coalesce(t3.othervariables,0.0) othervariables ,
    coalesce(t1.otherdeductions,0.0) +coalesce(t2.otherdeductions,0.0) +coalesce(t3.otherdeductions,0.0) otherdeductions ,
	coalesce(t1.otherledgerarearwithoutesi,0.0) +coalesce(t2.otherledgerarearwithoutesi,0.0) +coalesce(t3.otherledgerarearwithoutesi,0.0) otherledgerarearwithoutesi , 
	coalesce(t1.otherbonuswithesi,0.0) +coalesce(t2.otherbonuswithesi,0.0) +coalesce(t3.otherbonuswithesi,0.0) otherbonuswithesi 
	,coalesce(case when t1.recordscreen ='Previous Wages' then /*t1.netpay*/0 else t1.totalarear end ,0.0)/*+coalesce(t1.otherledgerarears,0.0) +coalesce(t2.otherledgerarears,0.0) +coalesce(t3.otherledgerarears,0.0)*/ as totalarear
	,coalesce(t1.lwf_employer,0.0)+coalesce(t2.arr_lwf_employer,0.0)+coalesce(t3.arr_lwf_employer,0.0)/*+coalesce(t5.lwf_employer,0)*/  as lwf_employer
	,case when empsalaryregister.isgroupinsurance='E' then 'excluded' when empsalaryregister.isgroupinsurance='Y' then 'Yes' else 'No' end as insurancetype 
	,1 as ordercol
	,case when t1.recordscreen ='Previous Wages' then 0.0 else coalesce(t1.govt_bonus_amt,0.0) end current_govt_bonus_amt
	,case when t1.recordscreen ='Current Wages' then 0.0 else coalesce(t1.govt_bonus_amt,0.0) end +coalesce(t2.govt_bonus_amt,0.0)+coalesce(t3.govt_bonus_amt,0.0) arear_govt_bonus_amt
	,t1.attendancemode||'-'||t1.recordscreen attendancemode			   
-----------Change for Additional fields---------------------------------
,coalesce(case when t1.refund<0 then t1.refund else 0.0 end,0.0) refunddeduction
,coalesce(t1.professionaltax,0)+coalesce(t2.professionaltax,0)+coalesce(t3.professionaltax,0) professionaltax
/*********************************************************************/
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratesalarybonus	 end	ratesalarybonus
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratecommission	 end	ratecommission
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratetransport_allowance	 end	ratetransport_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratetravelling_allowance	 end	ratetravelling_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.rateleave_encashment	 end	rateleave_encashment
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.rateovertime_allowance	 end	rateovertime_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratenotice_pay	 end	ratenotice_pay
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratehold_salary_non_taxable	 end	ratehold_salary_non_taxable
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.ratechildren_education_allowance	 end	ratechildren_education_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.rategratuityinhand	 end	rategratuityinhand
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.salarybonus	 end	salarybonus
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.commission	 end	commission
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.transport_allowance	 end	transport_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.travelling_allowance	 end	travelling_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.leave_encashment	 end	leave_encashment
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.overtime_allowance	 end	overtime_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.notice_pay	 end	notice_pay
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.hold_salary_non_taxable	 end	hold_salary_non_taxable
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.children_education_allowance	 end	children_education_allowance
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.gratuityinhand	 end	gratuityinhand
,empsalaryregister.ctc
/*********************************************************************/
,coalesce(t1.tea_allowance,0.0) tea_allowance,

/*********************************************************************/
coalesce(case when t1.recordscreen ='Previous Wages' then t1.commission else 0.0 end,0.0)+ coalesce(t2.arr_commission,0.0)+coalesce(t3.arr_commission,0.0) commission_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.transport_allowance else 0.0 end,0.0)+ coalesce(t2.arr_transport_allowance,0.0)+coalesce(t3.arr_transport_allowance,0.0) transport_allowance_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.travelling_allowance else 0.0 end,0.0)+ coalesce(t2.arr_travelling_allowance,0.0)+coalesce(t3.arr_travelling_allowance,0.0) travelling_allowance_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.leave_encashment else 0.0 end,0.0)+ coalesce(t2.arr_leave_encashment,0.0)+coalesce(t3.arr_leave_encashment,0.0) leave_encashment_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.overtime_allowance else 0.0 end,0.0)+ coalesce(t2.arr_overtime_allowance,0.0)+coalesce(t3.arr_overtime_allowance,0.0) overtime_allowance_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.notice_pay else 0.0 end,0.0)+ coalesce(t2.arr_notice_pay,0.0)+coalesce(t3.arr_notice_pay,0.0) notice_pay_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.hold_salary_non_taxable else 0.0 end,0.0)+ coalesce(t2.arr_hold_salary_non_taxable,0.0)+coalesce(t3.arr_hold_salary_non_taxable,0.0) hold_salary_non_taxable_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.children_education_allowance else 0.0 end,0.0)+ coalesce(t2.arr_children_education_allowance,0.0)+coalesce(t3.arr_children_education_allowance,0.0) children_education_allowance_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.gratuityinhand else 0.0 end,0.0)+ coalesce(t2.arr_gratuityinhand,0.0)+coalesce(t3.arr_gratuityinhand,0.0) gratuityinhand_arear,
coalesce(case when t1.recordscreen ='Previous Wages' then t1.salarybonus else 0.0 end,0.0)+ coalesce(t2.arr_salarybonus,0.0)+coalesce(t3.arr_salarybonus,0.0) salarybonus_arear,
/*********************************************************************/
coalesce(t1.disbursedledgerids,'')||coalesce(','||t2.disbursedledgerids,'')||coalesce(','||t3.disbursedledgerids,'') disbursedledgerids
,case when t1.recordscreen ='Previous Wages' then 0.0 else t1.charity_contribution_amount	 end	charity_contribution_amount
,case when t1.recordscreen ='Previous Wages' then t1.charity_contribution_amount else 0.0 end+ coalesce(t2.charity_contribution_amount,0.0)+coalesce(t3.charity_contribution_amount,0.0)	charity_contribution_amount_arear
,coalesce(t1.mealvoucher,0.0) +coalesce(t2.mealvoucher,0.0) +coalesce(t3.mealvoucher,0.0) mealvoucher	
,coalesce(t1.totalleavetaken,0.0) leavetaken
,nullif(t1.salaryjson,'') salaryjson,
t1.id as salid1,
t2.id as salid2,
t3.id as salid3
from tbl_monthlysalary t1
/*	left join (select emp_code,sum(case when empsalaryregister.isgroupinsurance='Y' then tbl_monthlysalary.insurance else 0 end) insurance
			   ,sum(lwf_employee) lwf_employee
			   ,sum(lwf_employer) lwf_employer
			   ,sum(paiddays) paiddays
			   from tbl_monthlysalary 
			   	left join empsalaryregister on tbl_monthlysalary.salaryid=empsalaryregister.id
			   where tbl_monthlysalary.tptype= p_tptype and
			   /*************Change 1.6******************************************/
					tbl_monthlysalary.emp_code= coalesce(nullif(p_empcode,-9999),tbl_monthlysalary.emp_code) and
				/**************Change 1.6 ends***********************************/
			   mprmonth=p_rptmonth and mpryear=p_rptyear
					and recordscreen ='Current Wages'
					and isarear='Y'
					and coalesce(is_rejected,'0')<>'1'
			  group by emp_code ) t5
	on 	t1.emp_code=t5.emp_code
*/	
	left join empsalaryregister on t1.salaryid=empsalaryregister.id
	left join banktransfers on t1.emp_code=banktransfers.emp_code and t1.mprmonth=banktransfers.salmonth and t1.mpryear=banktransfers.salyear and t1.batch_no=banktransfers.batchcode and coalesce(banktransfers.isrejected,'0')<>'1'
	 inner join openappointments op
	 on t1.emp_code=op.emp_code
	 and op.appointment_status_id<>13 
	 and t1.disbursementmode=p_disbursementmode
	 and t1.issalaryorliability='S'
	 and op.recordsource= case when p_tptype='TP' then 'HUBTPCRM' else nullif(op.recordsource,'HUBTPCRM') end
left join tbl_account ta on op.customeraccountid=ta.id	 
	left join 
	(select emp_code,tmp.id,tmp.mprmonth,tmp.mpryear,sum(basic) arr_basic,

					 sum(hra) arr_hra,
					 sum(conv) arr_conv,
					sum(medical) arr_medical,
					sum(specialallowance) arr_specialallowance,
					sum(fixedallowancestotal) arr_gross,
					sum(epf) arrear_epf,
					sum(vpf) arrear_vpf,
					sum(ac_1) arrear_ac_1,
					sum(ac_2) arrear_ac_2,
					sum(ac_10) arrear_ac_10,
					sum(ac21) arrear_ac21,
					sum(coalesce(account1_7q_dues,0)
						+coalesce(account1_14b_dues,0)
						+coalesce(account10_7q_dues,0)
						+coalesce(account10_14b_dues,0)
						+coalesce(account2_7q_dues,0)
						+coalesce(account2_14b_dues,0)
						+coalesce( account21_7q_dues,0)
						+coalesce(account21_14b_dues,0)
						) arrear_damagecharges,
						sum(paiddays) paiddays,
						sum(tds) tds
	 					,sum(atds) atds
						,sum(lwf) lwf
						,sum(coalesce(other,0.0)+coalesce(case when othervariables<0 then othervariables*-1 else 0.0 end,0.0))  other
						,sum(coalesce(grossearning,0.0)+coalesce(case when othervariables<0 then othervariables*-1 else 0.0 end,0.0)) grossearning
						,sum(grossdeduction)+sum(coalesce(case when othervariables<0 then othervariables*-1 else 0.0 end,0.0))
	 					+coalesce(SUM(case when is_special_category='Y' and ((grossearning-coalesce(grossdeduction,0.0))-(coalesce(netpay,0.0)-coalesce(totalarear,0.0)))>0 then (grossearning-coalesce(grossdeduction,0.0))-(coalesce(netpay,0.0)-coalesce(totalarear,0.0))  else 0 end),0.0) grossdeduction
	 					,sum(case when empsalaryregister.isgroupinsurance='Y' 
			or(empsalaryregister.isgroupinsurance='E'
			and round(coalesce(epf,0)+coalesce(vpf,0) +coalesce(coalesce(account1_7q_dues,0)
							+coalesce(account10_7q_dues,0)+coalesce(account1_14b_dues,0)+coalesce(account10_14b_dues,0)+coalesce(account2_7q_dues,0)
							+coalesce(account2_14b_dues,0)+coalesce( account21_7q_dues,0)+coalesce(account21_14b_dues,0)) +coalesce(atds,0) +coalesce(lwf,0)+coalesce(other,0.0)
							 +coalesce(insurance,0.0))=round(coalesce(grossdeduction,0.0)))then tbl_monthlysalary.insurance else 0 end) Insurance
	 					,sum(otherdeductions) otherdeductions
	 ,sum(vpf) vpf
	 ,sum(voucher_amount) voucher_amount
--------------------------------------------------------------------------------------
	,sum(Incentive) Incentive,
	sum(Loan) Loan,
	sum(Refund) Refund,
	sum(coalesce(Mobile,0.0))
    +coalesce(SUM(case when is_special_category='Y' and ((grossearning-coalesce(grossdeduction,0.0))-(coalesce(netpay,0.0)-coalesce(totalarear,0.0)))>0 then (grossearning-coalesce(grossdeduction,0.0))-(coalesce(netpay,0.0)-coalesce(totalarear,0.0))  else 0 end),0.0)
	Mobile
	,
	sum(Advance) Advance,
	sum(case when round(coalesce(govt_bonus_amt,0)+coalesce(fixedallowancestotal,0))=round(grossearning) 	 
						then coalesce(govt_bonus_amt,0.0) else 0.0 end)	 govt_bonus_amt,
	sum(ews)  ews,
	sum(gratuity) gratuity ,
	sum(bonus) bonus ,
	sum(employeenps) employeenps ,
	sum(otherledgerarears) otherledgerarears ,
	sum(otherledgerdeductions)  otherledgerdeductions ,
    sum(case when othervariables>0 then othervariables else 0.0 end)  othervariables ,
	sum(otherledgerarearwithoutesi) otherledgerarearwithoutesi , 
	sum(otherbonuswithesi) otherbonuswithesi,
	sum(coalesce(lwf_employer,0.0)) as arr_lwf_employer
	,sum(professionaltax) professionaltax
	 ----------------------------------------------------------------------------------------
,sum(commission) arr_commission
,sum(transport_allowance) arr_transport_allowance
,sum(travelling_allowance) arr_travelling_allowance
,sum(leave_encashment) arr_leave_encashment
,sum(overtime_allowance) arr_overtime_allowance
,sum(notice_pay) arr_notice_pay
,sum(hold_salary_non_taxable) arr_hold_salary_non_taxable
,sum(children_education_allowance) arr_children_education_allowance
,sum(gratuityinhand) arr_gratuityinhand
,sum(salarybonus) arr_salarybonus
,string_agg(tbl_monthlysalary.disbursedledgerids::text,',') as disbursedledgerids
,sum(charity_contribution_amount) charity_contribution_amount
,sum(mealvoucher) mealvoucher
	from public.tbl_monthlysalary
	left join (select id,isgroupinsurance from empsalaryregister) empsalaryregister on tbl_monthlysalary.salaryid=empsalaryregister.id
	 inner join ( select arrs.id, arrs.emp_code ecode,arearaddedmonths,trim(regexp_split_to_table(arrs.arearaddedmonths,',')) arearmonth
				,'P' as processscreen,arearprocessmonth,arearprocessyear,mprmonth,mpryear				
				 from tbl_monthlysalary arrs 
			 						where coalesce(arrs.is_rejected,'0')<>'1'
			 						and recordscreen='Previous Wages'
									and arearprocessmonth=p_rptmonth 
			 						and arearprocessyear=p_rptyear
				 					and arrs.arearaddedmonths is not null
				 					and arrs.tptype= p_tptype
		 union
		select arrs2.id,	arrs2.emp_code ecode,arearaddedmonths,trim(regexp_split_to_table(arrs2.arearaddedmonths,',')) arearmonth
				,'C' as processscreen,arearprocessmonth,arearprocessyear,mprmonth,mpryear	
				 from tbl_monthlysalary arrs2 
			 					where coalesce(arrs2.is_rejected,'0')<>'1'
			 					and arrs2.recordscreen='Current Wages'
								and arrs2.mprmonth=p_rptmonth 
			 					and arrs2.mpryear=p_rptyear
				 				and arrs2.arearaddedmonths is not null
				 				and arrs2.tptype= p_tptype) tmp
	 on tbl_monthlysalary.emp_code=tmp.ecode
	 and ((tmp.mprmonth=tbl_monthlysalary.arearprocessmonth  and tmp.mpryear=tbl_monthlysalary.arearprocessyear) )
	  	and recordscreen in ('Arear Wages')
		and (tbl_monthlysalary.mprmonth || '-' || tbl_monthlysalary.mpryear)=tmp.arearmonth
	 and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1'
	  and tmp.arearaddedmonths is not null
and not(netpay=0 and grossearning<0) 
/*************Change 1.6******************************************/
and tbl_monthlysalary.emp_code= coalesce(nullif(p_empcode,-9999),tbl_monthlysalary.emp_code) 
/**************Change 1.6 ends***********************************/ 
where tbl_monthlysalary.disbursementmode=p_disbursementmode
	 and tbl_monthlysalary.issalaryorliability='S'
	 and tbl_monthlysalary.tptype= p_tptype
	 group by emp_code,tmp.id,tmp.mprmonth,tmp.mpryear
	) t2
	on t1.id=t2.id
-- 	on t1.emp_code=t2.emp_code
-- 	and t1.arearaddedmonths is not null
-- 	and t1.mprmonth=t2.mprmonth and t1.mpryear=t2.mpryear
	left join 
	(select tmp.id,emp_code,tmp.mprmonth,tmp.mpryear,sum(basic) arr_basic,

					 sum(hra) arr_hra,
					 sum(conv) arr_conv,
					sum(medical) arr_medical,
					sum(specialallowance) arr_specialallowance,
					sum(fixedallowancestotal) arr_gross,
					sum(epf) arrear_epf,
					sum(vpf) arrear_vpf,
					sum(ac_1) arrear_ac_1,
					sum(ac_2) arrear_ac_2,
					sum(ac_10) arrear_ac_10,
					sum(ac21) arrear_ac21,
					sum(coalesce(account1_7q_dues,0)
						+coalesce(account1_14b_dues,0)
						+coalesce(account10_7q_dues,0)
						+coalesce(account10_14b_dues,0)
						+coalesce(account2_7q_dues,0)
						+coalesce(account2_14b_dues,0)
						+coalesce( account21_7q_dues,0)
						+coalesce(account21_14b_dues,0)
						) arrear_damagecharges,
						sum(paiddays) paiddays,
						sum(tds) tds
	 					,sum(atds) atds
						,sum(lwf) lwf
						,sum(coalesce(other,0.0)+coalesce(case when othervariables<0 then othervariables*-1 else 0.0 end,0.0)) other
						,sum(coalesce(grossearning,0.0)) grossearning
						,sum(grossdeduction)+sum(coalesce(case when othervariables<0 then othervariables*-1 else 0.0 end,0.0)) grossdeduction
	 					,sum(case when empsalaryregister.isgroupinsurance='Y' then tbl_monthlysalary.insurance else 0 end) Insurance
	 					,sum(otherdeductions) otherdeductions
	 ,sum(vpf) vpf
	 ,sum(voucher_amount) voucher_amount
--------------------------------------------------------------------------------------
	,sum(Incentive) Incentive,
	sum(Loan) Loan,
	sum(Refund) Refund,
	sum(Mobile) Mobile,
	sum(Advance) Advance,
	sum(case when round(coalesce(govt_bonus_amt,0)+coalesce(fixedallowancestotal,0))=round(grossearning) 	 
						then coalesce(govt_bonus_amt,0.0) else 0.0 end)	 govt_bonus_amt,
	sum(ews)  ews,
	sum(gratuity) gratuity ,
	sum(bonus) bonus ,
	sum(employeenps) employeenps ,
	sum(otherledgerarears) otherledgerarears ,
	sum(otherledgerdeductions)  otherledgerdeductions ,
    sum(case when othervariables>0 then othervariables else 0.0 end)  othervariables ,
	sum(otherledgerarearwithoutesi) otherledgerarearwithoutesi , 
	sum(otherbonuswithesi) otherbonuswithesi,
	sum(coalesce(lwf_employer,0.0)) as arr_lwf_employer
	,sum(professionaltax) professionaltax
	 ----------------------------------------------------------------------------------------
,sum(commission) arr_commission
,sum(transport_allowance) arr_transport_allowance
,sum(travelling_allowance) arr_travelling_allowance
,sum(leave_encashment) arr_leave_encashment
,sum(overtime_allowance) arr_overtime_allowance
,sum(notice_pay) arr_notice_pay
,sum(hold_salary_non_taxable) arr_hold_salary_non_taxable
,sum(children_education_allowance) arr_children_education_allowance
,sum(gratuityinhand) arr_gratuityinhand
,sum(salarybonus) arr_salarybonus
,string_agg(tbl_monthlysalary.disbursedledgerids::text,',') as disbursedledgerids
,sum(charity_contribution_amount) charity_contribution_amount
,sum(mealvoucher) mealvoucher

	from public.tbl_monthlysalary
	 left join (select id,isgroupinsurance from empsalaryregister) empsalaryregister on tbl_monthlysalary.salaryid=empsalaryregister.id
	 inner join ( select arrs.id, arrs.emp_code ecode,arearaddedmonths,trim(regexp_split_to_table(arrs.arearaddedmonths,',')) arearmonth
				,'P' as processscreen,arearprocessmonth,arearprocessyear,mprmonth,mpryear				
				 from tbl_monthlysalary arrs 
			 						where coalesce(arrs.is_rejected,'0')<>'1'
			 						and recordscreen='Previous Wages'
									and arearprocessmonth=p_rptmonth 
			 						and arearprocessyear=p_rptyear
				 					and arearaddedmonths is not null
	 								and arrs.tptype= p_tptype
		 union
		select 	arrs2.id,arrs2.emp_code ecode,arearaddedmonths,trim(regexp_split_to_table(arrs2.arearaddedmonths,',')) arearmonth
				,'C' as processscreen,arearprocessmonth,arearprocessyear,mprmonth,mpryear	
				 from tbl_monthlysalary arrs2 
			 					where coalesce(arrs2.is_rejected,'0')<>'1'
			 					and arrs2.recordscreen='Current Wages'
								and arrs2.mprmonth=p_rptmonth 
			 					and arrs2.mpryear=p_rptyear
				 				and arearaddedmonths is not null
	 							and arrs2.tptype= p_tptype) tmp
	 on tbl_monthlysalary.emp_code=tmp.ecode
	 and ((tmp.mprmonth=tbl_monthlysalary.arearprocessmonth /*and tmp.processscreen='C'*/ and tmp.mpryear=tbl_monthlysalary.arearprocessyear)
-- 		or
-- 		  (tmp.mprmonth=tbl_monthlysalary.arearprocessmonth and tmp.processscreen='P' and tmp.mpryear=tbl_monthlysalary.arearprocessyear)
		  )
	  	and recordscreen in ('Increment Arear') and coalesce(is_advice,'N')='N'
      and (tbl_monthlysalary.mprmonth || '-' || tbl_monthlysalary.mpryear)=tmp.arearmonth
	 and coalesce(tbl_monthlysalary.is_rejected,'0')<>'1'
and not(netpay=0 and grossearning<0) 	
/*************Change 1.6******************************************/
and tbl_monthlysalary.emp_code= coalesce(nullif(p_empcode,-9999),tbl_monthlysalary.emp_code) 
where tbl_monthlysalary.disbursementmode=p_disbursementmode	
	 and tbl_monthlysalary.issalaryorliability='S'
	 and tbl_monthlysalary.tptype= p_tptype
/**************Change 1.6 ends***********************************/	 
	 group by emp_code,tmp.id,tmp.mprmonth,tmp.mpryear
	) t3
	on t1.id=t3.id
-- 	on t1.emp_code=t3.emp_code
-- 	and t1.arearaddedmonths is not null
-- 	and t1.mprmonth=t3.mprmonth and t1.mpryear=t3.mpryear
	where t1.tptype=p_tptype and
	/*************Change 1.6******************************************/
	t1.emp_code= coalesce(nullif(p_empcode,-9999),t1.emp_code) and
	/**************Change 1.6 ends***********************************/
	((t1.mprmonth=p_rptmonth and t1.mpryear=p_rptyear and (t1.attendancemode='MPR' or coalesce(t1.loan,0)<>0 or coalesce(t1.advance,0)<>0))
	or
	(date_trunc('month',(to_date(left(t1.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month'))::date=make_date(p_rptyear,p_rptmonth,1)  and (t1.attendancemode='Ledger' and coalesce(t1.loan,0)=0 and coalesce(t1.advance,0)=0))
	 or
    (t1.attendancemode='Manual' and date_trunc('month',(to_date(left(t1.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month'))::date=make_date(p_rptyear,p_rptmonth,1))	 	 
	 )
	and coalesce(t1.is_rejected,'0')<>'1'
	and t1.recordscreen in ('Current Wages','Previous Wages')
	and (t1.isarear,t1.recordscreen) not in (select 'Y','Current Wages')
	ORDER BY t1.mpryear, t1.mprmonth DESC;
if p_empcode=-9999 then	/****************Added for change 1.6*************/	
select * into v_rfcsal from public.uspgetorderwisewages_for_current(
	p_mprmonth=>p_rptmonth,
	p_mpryear=>p_rptyear,
	p_ordernumber =>'',
	p_emp_code =>-9999,
	p_batch_no =>'',
	p_action =>'Retrieve_Salary',
	p_createdby =>1,
	createdbyip =>'::1',
	p_criteria =>'',
	p_process_status =>'NotProcessed');

  LOOP 
     FETCH v_rfcsal INTO v_rec; 
     EXIT WHEN NOT FOUND; 
	 
		 select jobrole		
		 into v_jobrole
		  from public.cmsdownloadedwages
		  where mprmonth=p_rptmonth
		  and mpryear=p_rptyear
		  and empcode=v_rec.emp_code::text
		  and isactive='1'
		  and batch_no=v_rec.batch_no
		  limit 1;
		  RAISE NOTICE 'v_jobrole :: %.', v_jobrole;
     insert into tmpbilling
	 (mon,	employee,	employee_name,	father_husband_name,		designation,	department,	subunit,						dateofjoining,	dateofbirth,	esinumber,	pan_number,	uannumber,	subunit_2,	employee_2,	email,	
	  aadharcard,	dateofleaving,	arrear_days,	loss_off_pay,	total_paid_days,
	  ratebasic,	ratehra,	rateconv,	ratemedical,	ratespecial_allowance,	
	  fixedallowancestotalrate,	basic,	hra,	conv,	medical,	specialallowance,	
	  arr_basic,	arr_hra,	arr_conv,	arr_medical,	arr_specialallowance,	
	  incentive,
	  refund,	monthly_bonus,	grossearning,	epf,	vpf,	
	  esi,	tds,	loan,	lwf,	insurance,	mobile,	advance,	other,	
	  grossdeduction,	netpay,	ac_1,	ac_10,	ac_2,	ac21,	
	  employer_esi_contr,	/*increment_arear_basic,	increment_arear_hra,	increment_arear_conv,	increment_arear_medical,	increment_arear_specialallowance,	increment_arear_gross,	increment_arear_epf,	increment_arear_vpf,	increment_arear_ac_1,	increment_arear_ac_2,	increment_arear_ac_10,	increment_arear__21,	increment_arear_damagecharges,	increment_arear_paiddays,	increment_arear_tds,	increment_arear_lwf,	*/salarystatus
	 ,arearaddedmonths,monthdays,salaryid,banktransferstatus,atds,voucher_amount
	 ,ews,gratuity,bonus,employeenps,otherledgerarears,otherledgerdeductions,othervariables,otherledgerarearwithoutesi,otherbonuswithesi
	 ,totalarear,lwf_employer,insurancetype,ordercol)
	 select 
	 v_rec.mon||'[Not Downloaded]' as mon,v_rec.emp_code,	v_rec.emp_name,	v_rec.fathername,	coalesce(v_jobrole,v_rec.post_offered),	v_rec.posting_department,	v_rec.subunit,	v_rec.dateofjoining,	v_rec.dateofbirth,	v_rec.esinumber,	v_rec.pancard,	v_rec.uannumber,	v_rec.subunit,	v_rec.emp_code,	v_rec.email,	
	 null,	v_rec.dateofleaving,	0,	v_rec.lossofpay,	v_rec.paiddays,
	 v_rec.ratebasic,	v_rec.ratehra,	v_rec.rateconv,	v_rec.ratemedical,	v_rec.ratespecialallowance,	
	 v_rec.fixedallowancestotalrate,	v_rec.basic,	v_rec.hra,	v_rec.conv,	v_rec.medical,	v_rec.specialallowance,
	 v_rec.RateBasic_arr,v_rec.RateHRA_arr,	v_rec.RateCONV_arr,	v_rec.RateMedical_arr,	v_rec.RateSpecialAllowance_arr,	
	 coalesce(v_rec.incentive,0.0)+coalesce(v_rec.othervariables,0.0) +coalesce(v_rec.otherledgerarear,0.0) +coalesce(v_rec.otherledgerarearwithoutesi,0.0) +coalesce(v_rec.otherdeductionswithesi,0.0) incentive ,	
	 v_rec.refund,	v_rec.govt_bonus_amt,	v_rec.grossearning-coalesce(v_rec.otherdeductions,0),	v_rec.epf,	v_rec.vpf,	
	 v_rec.employeeesirate,	v_rec.tds,	v_rec.loan,	v_rec.lwf,	v_rec.insurance,	v_rec.mobile,	v_rec.advance,	v_rec.other,
	 v_rec.grossdeduction,	v_rec.netpay,	v_rec.ac_1,	v_rec.ac_10,	v_rec.ac_2,	v_rec.ac21,
	 v_rec.employeresirate,	/*0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,*/	'UnProcessed',
	 v_rec.arearaddedmonths,
	v_rec.monthdays,
	v_rec.salaryid,'Not Transferred',v_rec.atds,0.0 voucher_amount
	,v_rec.ews,v_rec.gratuity,v_rec.bonus,
	v_rec.employeenpsrate,	v_rec.otherledgerarear ,	v_rec.otherledgerdeductions ,
	v_rec.othervariables ,	v_rec.otherledgerarearwithoutesi ,	v_rec.otherdeductionswithesi
	,v_rec.netarear,v_rec.lwf_employer,(select case when empsalaryregister.isgroupinsurance='E' then 'excluded' when empsalaryregister.isgroupinsurance='Y' then 'Yes' else 'No' end from empsalaryregister where id=v_rec.salaryid),2;

   END LOOP; 
   
 insert into tmpbilling
 select 'Total' mon,
Null employee,
Null employee_name,
Null father_husband_name,
Null designation,
Null department,
Null subunit,
Null dateofjoining,
Null dateofbirth,
Null esinumber,
Null pan_number,
Null uannumber,
Null subunit_2,
Null employee_2,
Null email,
Null aadharcard,
Null dateofleaving,
Null arrear_days,
Null loss_off_pay,
Null total_paid_days,
Null ratebasic,
Null ratehra,
Null rateconv,
Null ratemedical,
Null ratespecial_allowance,
Null fixedallowancestotalrate,
sum(basic) basic,
sum(hra) hra,
sum(conv) conv,
sum(medical) medical,
sum(specialallowance) specialallowance,
sum(arr_basic) arr_basic,
sum(arr_hra) arr_hra,
sum(arr_conv) arr_conv,
sum(arr_medical) arr_medical,
sum(arr_specialallowance) arr_specialallowance,
sum(incentive) incentive,
sum(refund) refund,
sum(monthly_bonus) monthly_bonus,
sum(grossearning) grossearning,
sum(epf) epf,
sum(vpf) vpf,
sum(esi) esi,
sum(tds) tds,
sum(loan) loan,
sum(lwf) lwf,
sum(insurance) insurance,
sum(mobile) mobile,
sum(advance) advance,
sum(other) other,
sum(grossdeduction) grossdeduction,
sum(netpay) netpay,
sum(ac_1) ac_1,
sum(ac_10) ac_10,
sum(ac_2) ac_2,
sum(ac21) ac21,
Null employer_esi_contr,
Null salarystatus,
Null arearaddedmonths,
Null monthdays,
Null salaryid,
Null banktransferstatus,
sum(atds) atds,
sum(voucher_amount) voucher_amount,
sum(ews) ews,
sum(gratuity) gratuity,
sum(bonus) bonus,
sum(employeenps) employeenps,
sum(damagecharges) damagecharges,
sum(otherledgerarears) otherledgerarears,
sum(otherledgerdeductions) otherledgerdeductions,
sum(othervariables) othervariables,
sum(otherdeductions) otherdeductions,
sum(otherledgerarearwithoutesi) otherledgerarearwithoutesi,
sum(otherbonuswithesi) otherbonuswithesi,
sum(totalarear) totalarear,
sum(lwf_employer) lwf_employer,
Null insurancetype,
3 ordercol
from tmpbilling;

end if;
   
   	open v_rfc for
	select * from tmpbilling
	order by ordercol;

	return next v_rfc;
/***********************Total Salary Count*******************************/	
end if;

if p_action='GetArrearBilling' then

  	select * into v_rfc from public.uspmonthwiseiablityreport(
	p_rptmonth,
	p_rptyear,
	'GetDetailedLiability',
	p_empcode,
	'Liability',
	 null,
	'Both',
	p_tptype);

	return next v_rfc;	
	
		
   	open v_rfctotalattendance for
	select 0 as totalattendancecount,
	       0 as multiperformercount,
		   0 as nonmultiperformercount,
		   
		   0 processedasarear,
		   0 processedascurrent,
		   0 processedasprevious,
		   0 uniquemultipermerbatch,0 uniquenonmultipermerbatch,
		  v_message as compilereportmessage;
	return next v_rfctotalattendance;
end if;	

end;
$BODY$;

ALTER FUNCTION public.uspmonthwisebilling(integer, integer, text, bigint, text, character varying)
    OWNER TO payrollingdb;

