-- FUNCTION: public.uspmonthwiseiablityreport(integer, integer, text, bigint, text, character varying, character varying, character varying, character varying, character varying, integer, text, text, text, character varying)

-- DROP FUNCTION IF EXISTS public.uspmonthwiseiablityreport(integer, integer, text, bigint, text, character varying, character varying, character varying, character varying, character varying, integer, text, text, text, character varying);

CREATE OR REPLACE FUNCTION public.uspmonthwiseiablityreport(
	p_rptmonth integer,
	p_rptyear integer,
	p_action text,
	p_empcode bigint DEFAULT '-9999'::integer,
	p_reporttype text DEFAULT 'Liability'::text,
	p_contractno character varying DEFAULT NULL::character varying,
	p_disbursementmode character varying DEFAULT 'Both'::character varying,
	p_tptype character varying DEFAULT 'NonTP'::character varying,
	p_customeraccountid character varying DEFAULT '-9999'::character varying,
	p_ou_ids character varying DEFAULT NULL::character varying,
	p_geofenceid integer DEFAULT 0,
	p_post_offered text DEFAULT ''::text,
	p_posting_department text DEFAULT ''::text,
	p_unitparametername text DEFAULT ''::text,
	p_showhold character varying DEFAULT 'N'::character varying)
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
	v_rfc_disbursment refcursor;
	v_rfc_disbursmentdetails refcursor;
	v_advancesalstartdate date;
	v_advancesalenddate date;
	v_fullmonthdays int;
begin
/**********************************************************************************************
Version Date			Change												Done_by
1.1		18-Jan-2022		Initial Version										Shiv Kumar
1.2		21-Feb-2022		Change for taxable Ledger Arrears					Shiv Kumar
1.3		29-Mar-2022		Change Liability Salary with Transaction			Shiv Kumar
1.4 	04-Oct-2022		Bifurcation of Salary and Reimbursement				Shiv Kumar
1.5 	06-Oct-2022		Moving mobile deduction to other					Shiv Kumar
1.6 	22-Apr-2022		Add OR condition in attendance 						Parveen Kumar
1.7 	16-Jun-2023		Add Increment Records for voucherBilling			Shiv Kumar
1.8 	26-Oct-2023		Add Customeraccountid criteria						Shiv Kumar
1.9     4-Nov-2023		Added action DisbursementSummary and 				Siddharth Bansal
						DisbursementDetails
1.10    02-Feb-2024		Separate Advance and Advance Recovery 				Shiv Kumar
1.11    22-Apr-2024     Geo Fence ID Filter in actions 						SIDDHARTH BANSAL
						GetMonthLiability , DisbursementDetails
						and DisbursementSummary
1.12    01-Aug-2024     OU ID Filter in actions 							SIDDHARTH BANSAL
						GetMonthLiability , DisbursementDetails
						and DisbursementSummary
1.13 	27-Aug-2024		TP code and otgempcode								Shiv Kumar
1.14 	05-Sep-2024		Add Tea Allowance									Shiv Kumar
1.15 	05-Oct-2024		Add Unit Parameters									Shiv Kumar
1.16 	17-Oct-2024		Add Filter for Des,Dep and Unit Names				Siddharth Bansal
1.17 	23-May-2025		Add vendor_name, project_name, salary_book_project and assigned_ou_names in response				Parveen Kumar
1.18 	10-May-2025		Adding Employer Compliance Rate						Shiv Kumar
1.19 	02-Jul-2025		Adding Meal Voucher									Shiv Kumar
1.20 	02-Jul-2025		Adding Arrear components							Shiv Kumar
1.21 	23-Jul-2025		Rate Employer LWF change							Shiv Kumar
1.22	13-Sep-2025		Work flow integration								Shiv Kumar
1.23	17-Oct-2025		Add designation master								vinod Kumar
1.24	30-Oct-2025		Smart Payrolling									Shiv Kumar
***********************************************************************************************/
/**************************Calc dates************************************/
--v_fullmonthdays:=date_part('day',DATE_TRUNC('MONTH', make_date(p_rptyear,p_rptmonth,1)::DATE + INTERVAL '1 MONTH -1 DAY'));
v_fullmonthdays:=date_part('day',make_date(p_rptyear,p_rptmonth,1)::DATE + INTERVAL '1 MONTH -1 DAY');

    select DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE + INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE + INTERVAL '2 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE ) - INTERVAL '1 DAY')::date,
	DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_rptyear||'-'||p_rptmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;
	v_message:='Liability Report for Attendance between '||v_salstartdate|| ' and '||v_salenddate;
/**************************Calc dates ends here****************************/
if p_action='GetMonthLiability' or p_action='GetDetailedLiability' or p_action='DisbursementSummary' or p_action='DisbursementDetails'  or p_action='ArrearDisbursementDetails' then
	Raise Notice 'v_salstartdate=%,v_salenddate=%,v_prevsaldate=%,advancesalstartdate=%,advancesalenddate=%',v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;
	Raise Notice 'Inside Liability Part1 at %',TIMEOFDAY();
	
    create temporary table tmpbilling on commit drop
	as
	select  Mon,
	t1.emp_code Employee,
	op.emp_name as Employee_Name,op.fathername as Father_Husband_Name,
	case when op.jobtype='Unit Parameter' then t1.designationname else COALESCE(NULLIF(mtd_designation.designationname, ''), op.post_offered) end as Designation,
	--case when op.jobtype='Unit Parameter' then t1.designationname else op.post_offered end as Designation,
	case when op.jobtype='Unit Parameter' then t1.departmentname else (string_to_array(op.posting_department,'#'))[1]::varchar end as posting_department, op.jobtype jobtype, -- SIDDHARTH BANSAL 19/10/2024
	--coalesce(t1.unitname,'') unitparametername,
	COALESCE(
    NULLIF(unitname, ''),
    (
      SELECT STRING_AGG(ton.org_unit_name, ', ')
      FROM public.tbl_org_unit_geofencing ton
      INNER JOIN (
        SELECT unnest(string_to_array(op.assigned_ou_ids, ','))::int AS id
      ) t1 ON t1.id = ton.id
    )
  ) AS unitparametername,
	tbldepartment.departentname Department,
	t1.subunit SubUnit,
	to_char(op.dateofjoining,'dd-Mon-yy') DateofJoining,
	to_char(op.dateofbirth,'dd-Mon-yy') dateofbirth,	
	op.esinumber, op.pancard pan_number,
	op.uannumber,
-- 	t1.subunit SubUnit_2,
-- 	op.emp_code Employee_2,
	op.email,
	op.mobile mobilenumber,
	--op.aadharcard,
	to_char(dateofleaving,'dd-Mon-yyyy') dateofleaving,
	case when t1.recordscreen <>'Current Wages' then (t1.paiddays+coalesce(t5.paiddays,0.0)) else 0.0 end Arrear_Days,	
	case when t1.recordscreen ='Current Wages' then  t1.monthdays-(t1.PaidDays+coalesce(t5.paiddays,0)) else 0.0 end Loss_Off_Pay,
	--t1.paiddays Total_Paid_Days,
	case when t1.recordscreen ='Current Wages' then (t1.paiddays+coalesce(t5.paiddays,0.0)) else 0.0 end Total_Paid_Days,
	t1.ratebasic RateBasic,	
	t1.ratehra RateHRA,
	t1.rateconv RateCONV,
	t1.ratemedical RateMedical,
	t1.ratespecialallowance  RateSpecial_Allowance,
	t1.fixedallowancestotalrate FixedAllowancesTotalRate,
	case when t1.recordscreen <>'Current Wages' then 0.0 else t1.basic+coalesce(t1.incrementarear_basic,0.0) end basic,	
	case when t1.recordscreen <>'Current Wages' then 0.0 else t1.hra+coalesce(t1.incrementarear_hra,0.0) end HRA,
	case when t1.recordscreen <>'Current Wages' then 0.0 else t1.conv end CONV,
	case when t1.recordscreen <>'Current Wages' then 0.0 else t1.medical end Medical,
	case when t1.recordscreen <>'Current Wages' then 0.0 else t1.specialallowance+coalesce(t1.incrementarear_allowance,0.0) end SpecialAllowance,
	coalesce(case when t1.recordscreen <>'Current Wages' then t1.basic else 0.0 end,0.0) as Arr_Basic,
	coalesce(case when t1.recordscreen <>'Current Wages' then t1.hra else 0.0 end,0.0) as Arr_HRA,
	coalesce(case when t1.recordscreen <>'Current Wages' then t1.conv else 0.0 end,0.0) Arr_CONV,
	coalesce(case when t1.recordscreen <>'Current Wages' then t1.medical else 0.0 end,0.0) Arr_Medical,
	coalesce(case when t1.recordscreen <>'Current Wages' then t1.SpecialAllowance else 0.0 end,0.0) Arr_SpecialAllowance,
	--coalesce(case when t1.recordscreen <>'Current Wages' then t1.incentive else 0.0 end,0.0)
    coalesce(t1.incentive,0.0)
    +(coalesce(case when t1.othervariables>0 or t1.recordscreen='Increment Arear' then  t1.othervariables else 0.0 end,0.0) )
    +coalesce(t1.otherledgerarears,0.0) 
    +coalesce(t1.otherledgerarearwithoutesi,0.0)
    +coalesce(t1.otherbonuswithesi,0.0)
   +case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))) <0 then ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))*-1  else 0 end
	Incentive,
	coalesce(case when t1.recordscreen <>'Current Wages' then t1.refund else 0.0 end,0.0)+coalesce(t1.Refund,0.0)  Refund,
	case when t1.recordscreen<>'Increment Arear' or round(coalesce(t1.govt_bonus_amt,0)+coalesce(t1.fixedallowancestotal,0))=round(t1.grossearning) 	 
						then coalesce(t1.govt_bonus_amt,0.0) else 0.0 end
	 Monthly_Bonus,
	case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))) <0 then ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))*-1  else 0 end+
	coalesce(t1.GrossEarning,0)
	+coalesce(case when t1.othervariables<0 and t1.recordscreen<>'Increment Arear' then  t1.othervariables*-1 else 0.0 end,0.0)
	+coalesce(t1.mealvoucher ,0)
	GrossEarning,	
    --round(coalesce(t1.EPF,0)::numeric) as epf,
	 case when t1.recordscreen <>'Current Wages' then 0.0 else round(coalesce(t1.EPF,0)::numeric)	 end	epf
	,case when t1.recordscreen <>'Current Wages' then round(coalesce(t1.EPF,0)::numeric) else 0.0	 end	epf_arear
   --coalesce(t1.VPF,0)vpf,
   	,case when t1.recordscreen <>'Current Wages' then 0.0 else round(coalesce(t1.VPF,0)::numeric)	 end	vpf
	,case when t1.recordscreen <>'Current Wages' then round(coalesce(t1.VPF,0)::numeric) else 0.0	 end	vpf_arear
	--,ceil((coalesce(t1.employeeesirate,0.0)+coalesce(incrementarear_employeeesi,0.0))::numeric) ESI
	,case when t1.recordscreen <>'Current Wages' then 0.0 else ceil((coalesce(t1.employeeesirate,0.0))::numeric) end ESI
	,case when t1.recordscreen <>'Current Wages' then ceil((coalesce(t1.employeeesirate,0.0)+coalesce(incrementarear_employeeesi,0.0))::numeric)
	else 0.0 end ESI_arear
	--coalesce(t1.TDS,0) tds,
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.TDS ,0)	 end	tds
	,case when t1.recordscreen <>'Current Wages' then coalesce(t1.TDS ,0) else 0.0	 end	tds_arear
	,coalesce(t1.Loan,0.0) loan
	--coalesce(t1.LWF,0)+coalesce(t5.lwf_employee,0) as lwf,
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.LWF,0)+coalesce(t5.lwf_employee,0)	 end	lwf
	,case when t1.recordscreen <>'Current Wages' then coalesce(t1.LWF,0)+coalesce(t5.lwf_employee,0) else 0.0	 end	lwf_arear

	,coalesce(case when empsalaryregister.isgroupinsurance='Y' or t1.recordscreen='Increment Arear' then t1.insurance else 0 end,0,0)+coalesce(t5.insurance,0.0)
	Insurance,
															  
																										   
												 
																																											
					 
   
    0.00 Mobile,
	coalesce(t1.Advance,0.0) Advance,
	coalesce(case when t1.othervariables<0 and t1.recordscreen<>'Increment Arear' then t1.othervariables*-1 else 0.0 end,0.0)+
	coalesce(t1.Other,0.0)
	+coalesce(t1.otherledgerdeductions,0.0)
	+coalesce(t1.otherdeductions,0.0)
	+case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))>0 then (t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))  else 0 end+
	(coalesce(account1_7q_dues,0)
						+coalesce(account1_14b_dues,0)
						+coalesce(account10_7q_dues,0)
						+coalesce(account10_14b_dues,0)
						+coalesce(account2_7q_dues,0)
						+coalesce(account2_14b_dues,0)
						+coalesce(account21_7q_dues,0)
						+coalesce(account21_14b_dues,0)
						)
	other,
	case when t1.is_special_category='Y' and ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0))) >0 then ((t1.grossearning-coalesce(t1.grossdeduction,0.0))-(coalesce(t1.netpay,0.0)-coalesce(t1.totalarear,0.0)))  else 0 end+
	coalesce(t1.GrossDeduction,0)
	+coalesce(case when t1.othervariables<0 and t1.recordscreen<>'Increment Arear' then  t1.othervariables*-1 else 0.0 end,0.0)
    GrossDeduction,
	t1.NetPay-coalesce(t1.totalarear,0.0) NetPay,
 
 
	case when coalesce(o.epf_pension_opted,'Y')='Y' then round((ac_1+(greatest(ac_10-least(ac_10,1250),0)))::numeric(18,2),0) else round((coalesce(ac_1,0)+coalesce(ac_10,0))::numeric(18,2),0) end ac_1,
	case when coalesce(o.epf_pension_opted,'Y')='Y' then round(least(ac_10,1250)::numeric(18,2),0) else 0.0 end ac_10,
	round(coalesce(t1.ac_2,0.0)::numeric) ac_2,
	round(coalesce(t1.ac21,0.0)::numeric) ac21,
   
															
																																																												 
		  
														   
																											 
		   
														   
									  
		  
														  
									   
		  
 
												  
																																																												 
						 
												 
																											 
						  
												 
									  
						 
												 
									   
						 
   
 
 
	coalesce(t1.employeresirate,0.0)+coalesce(incrementarear_employeresi,0.0) Employer_ESI_Contr,
    salarystatus as salarystatus,
		t1.arearaddedmonths,
	t1.monthdays,
	t1.salaryid,
	case when banktransfers.emp_code is not null then 'Transferred' else 'Not Transferred' end banktransferstatus,
	coalesce(t1.aTDS,0) atds,
	coalesce(t1.voucher_amount,0.0) voucher_amount	
-----------Change for Additional fields---------------------------------	
	,coalesce(t1.ews,0.0)  ews,
	coalesce(t1.gratuity,0.0) gratuity ,
	coalesce(t1.bonus,0.0) bonus ,
	coalesce(t1.employeenps,0.0) employeenps ,
						(coalesce(account1_7q_dues,0)
						+coalesce(account1_14b_dues,0)
						+coalesce(account10_7q_dues,0)
						+coalesce(account10_14b_dues,0)
						+coalesce(account2_7q_dues,0)
						+coalesce(account2_14b_dues,0)
						+coalesce( account21_7q_dues,0)
						+coalesce(account21_14b_dues,0)
						) damagecharges ,
	coalesce(t1.otherledgerarears,0.0) otherledgerarears ,
	coalesce(t1.otherledgerdeductions,0.0) otherledgerdeductions ,
    coalesce(case when t1.othervariables>0 then t1.othervariables else 0.0 end,0.0) othervariables ,
    coalesce(t1.otherdeductions,0.0) otherdeductions ,
	coalesce(t1.otherledgerarearwithoutesi,0.0)  otherledgerarearwithoutesi , 
	coalesce(t1.otherbonuswithesi,0.0)  otherbonuswithesi 
	,coalesce(t1.totalarear,0.0) as totalarear
	,coalesce(t1.lwf_employer,0.0)+coalesce(t5.lwf_employer,0)  as lwf_employer
   
															
														   
				  
												 
														  
		  
					   
   
	,case when empsalaryregister.isgroupinsurance='E' then 'excluded' when empsalaryregister.isgroupinsurance='Y' then 'Yes' else 'No' end as insurancetype 
 	,1 as ordercol
-- 	,case when t1.recordscreen ='Current Wages' then 0.0 else coalesce(t1.govt_bonus_amt,0.0) end current_govt_bonus_amt
-- 	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.govt_bonus_amt,0.0) end  arear_govt_bonus_amt
	,t1.attendancemode||'-'||t1.recordscreen attendancemode
	,t1.recordscreen
	,t1.mprmonth
	,t1.mpryear
	,t1.salary_remarks
	,t1.downloadedflag
	,t1.id
	,t1.arearids
	,t1.batchid batchcode
	,coalesce(t1.otherledgerarears,0.0) +coalesce(t1.otherledgerarearwithoutesi,0.0) +coalesce(t1.otherbonuswithesi,0.0)  otherledgerarear
	,coalesce(t1.govt_bonus_amt,0.0) govt_bonus_amt	
	,t1.ctc+case when t1.recordscreen<>'Increment Arear' then (coalesce(empsalaryregister.employergratuity,0)*coalesce(t1.paiddays,0)/coalesce(nullif(t1.monthdays,0),1))::numeric(18,2) else 0.0+coalesce(t1.mealvoucher ,0) end ctc
	,t1.employeresirate
   
																												 
																																							
   
	,t1.pfnumber
	,t1.bankaccountno
	,t1.ifsccode
	,t1.bankname
	,t1.bankbranch
	,t1.salaryindaysopted
	,t1.mastersalarydays salarydays
	,t1.disbursementmode
	--,t1.professionaltax
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.professionaltax,0,0)	end professionaltax
	,case when t1.recordscreen <>'Current Wages' then coalesce(t1.professionaltax,0,0)	end professionaltax_arear
	,banktransfers.id as btid
	,t1.tptype
	,is_billable
	,banktransfers.createdon
	,tbldepartment.contractno,tbldepartment.contractstartdate,tbldepartment.contractenddate
	,coalesce(advancerecovery,0) advancerecovery
	,coalesce(loanrecovery,0) loanrecovery
/**********************************************************************************/
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.salarybonus ,0)	 end	salarybonus
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.commission ,0)	 end	commission
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.transport_allowance ,0)	 end	transport_allowance
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.travelling_allowance ,0)	 end	travelling_allowance
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.leave_encashment ,0)	 end	leave_encashment
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.overtime_allowance ,0)	 end	overtime_allowance
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.notice_pay ,0)	 end	notice_pay
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.hold_salary_non_taxable ,0)	 end	hold_salary_non_taxable
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.children_education_allowance ,0)	 end	children_education_allowance
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.gratuityinhand ,0)	 end	gratuityinhand
	,coalesce(t1.ratesalarybonus ,0) ratesalarybonus
	,coalesce(t1.ratecommission ,0) ratecommission
	,coalesce(t1.ratetransport_allowance ,0) ratetransport_allowance
	,coalesce(t1.ratetravelling_allowance ,0) ratetravelling_allowance
	,coalesce(t1.rateleave_encashment ,0) rateleave_encashment
	,coalesce(t1.rateovertime_allowance ,0) rateovertime_allowance
	,coalesce(t1.ratenotice_pay ,0) ratenotice_pay
	,coalesce(t1.ratehold_salary_non_taxable ,0) ratehold_salary_non_taxable
	,coalesce(t1.ratechildren_education_allowance ,0) ratechildren_education_allowance
	,coalesce(t1.rategratuityinhand ,0) rategratuityinhand
/**********************************************************************************/
	,o.biometricid
	,op.cjcode
	,op.orgempcode
-----------Change for Additional fields---------------------------------
   ,coalesce(t1.tea_allowance,0) tea_allowance
   ,t1.employerinsuranceamount
   ,t1.charity_contribution_amount
    -- START - CHANGES [1.17]
		,op.agencyname vendor_name,
		op.project_title project_name,
		op.salary_book_project,
		(
			SELECT STRING_AGG(tougf.org_unit_name::varchar, ',')
			FROM public.tbl_org_unit_geofencing tougf
			INNER JOIN (SELECT * FROM string_to_table(op.assigned_ou_ids,',') AS t) t1 ON t1.t::int = tougf.id
		) assigned_ou_names
    -- END - CHANGES [1.17]
/***********Change 1.18 starts**********************/
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(empsalaryregister.employerinsuranceamount,0) end as rate_employerinsuranceamount
	,case when t1.recordscreen <>'Current Wages' then 0.0 else case when (coalesce(t1.lwf_employer,0.0)+coalesce(t5.lwf_employer,0))>0 then coalesce(statewiselwfrate.employerlwfrate,0) else 0 end end as rate_employerlwf
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(empsalaryregister.employerepfrate,0) end as rate_employerepf
	,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(empsalaryregister.employeresirate,0) end as rate_employeresi
/***********Change 1.18 ends**********************/
,coalesce(empsalaryregister.employergratuity,0)::numeric(18,2) rate_employergratuity
,case when t1.recordscreen<>'Increment Arear' then (coalesce(empsalaryregister.employergratuity,0)*coalesce(t1.paiddays,0)/coalesce(nullif(t1.monthdays,0),1))::numeric(18,2) else 0.0 end employergratuity
,case when t1.recordscreen <>'Current Wages' then 0.0 else coalesce(t1.mealvoucher ,0)	 end	mealvoucher
,case when t1.recordscreen <>'Current Wages' then coalesce(t1.mealvoucher ,0) else 0.0	 end	mealvoucher_arear

/**********************************************************************************/
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.salarybonus else 0.0 end,0.0) as Arr_salarybonus
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.commission else 0.0 end,0.0) as Arr_commission
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.transport_allowance else 0.0 end,0.0) as Arr_transport_allowance
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.travelling_allowance else 0.0 end,0.0) as Arr_travelling_allowance
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.leave_encashment else 0.0 end,0.0) as Arr_leave_encashment
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.overtime_allowance else 0.0 end,0.0) as Arr_overtime_allowance
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.notice_pay else 0.0 end,0.0) as Arr_notice_pay
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.hold_salary_non_taxable else 0.0 end,0.0) as Arr_hold_salary_non_taxable
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.children_education_allowance else 0.0 end,0.0) as Arr_children_education_allowance
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.gratuityinhand else 0.0 end,0.0) as Arr_gratuityinhand

,coalesce(case when t1.recordscreen <>'Current Wages' then t1.ratesalarybonus else 0.0 end,0.0) as ratesalarybonus_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.ratecommission else 0.0 end,0.0) as ratecommission_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.ratetransport_allowance else 0.0 end,0.0) as ratetransport_allowance_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.ratetravelling_allowance else 0.0 end,0.0) as ratetravelling_allowance_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.rateleave_encashment else 0.0 end,0.0) as rateleave_encashment_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.rateovertime_allowance else 0.0 end,0.0) as rateovertime_allowance_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.ratenotice_pay else 0.0 end,0.0) as ratenotice_pay_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.ratehold_salary_non_taxable else 0.0 end,0.0) as ratehold_salary_non_taxable_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.ratechildren_education_allowance else 0.0 end,0.0) as ratechildren_education_allowance_arr
,coalesce(case when t1.recordscreen <>'Current Wages' then t1.rategratuityinhand else 0.0 end,0.0) as rategratuityinhand_arr
/**********************************************************************************/
		 
,salaryjson
,coalesce(mst_paymenttype.paymenttypename,mpt.paymenttypename,'') as payment_mode
,t1.createdon as liabilitycreatedon
,t1.paiddays
					  
from 
	(
		SELECT id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays,case when attendancemode='Ledger' then 0.0 else  monthdays end as monthdays, coalesce(nullif(ratebasic_arr,0),ratebasic)ratebasic, coalesce(nullif(ratehra_arr,0),ratehra) ratehra,coalesce(nullif(rateconv_arr,0),rateconv) rateconv,coalesce(nullif(ratemedical_arr,0),ratemedical) ratemedical,coalesce(nullif(ratespecialallowance_arr,0),ratespecialallowance) ratespecialallowance,coalesce(nullif(fixedallowancestotalrate_arr,0),fixedallowancestotalrate) fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, least(loan,0) loan,greatest(loan,0) loanrecovery, lwf, insurance, mobile, least(advance,0) advance,greatest(advance,0) advancerecovery, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks,case when mprmonth=p_rptmonth and mpryear=p_rptyear and recordscreen in ('Previous Wages','Arear Wages') then 'N' else 'Y' end isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by,case when mprmonth=p_rptmonth and mpryear=p_rptyear and recordscreen in ('Previous Wages','Arear Wages') then 'Current Wages' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid
		,TO_CHAR(TO_TIMESTAMP (t.mprmonth::text, 'MM'), 'Mon')||'-'||t.mpryear::text as Mon
		,1 as downloadedflag
		,'Processed' as salarystatus
		,disbursementmode
		,professionaltax
		,tptype
		,is_billable
		,ratesalarybonus,ratecommission,ratetransport_allowance,ratetravelling_allowance,rateleave_encashment,rateovertime_allowance,ratenotice_pay,ratehold_salary_non_taxable,ratechildren_education_allowance,rategratuityinhand,salarybonus,commission,transport_allowance,travelling_allowance,leave_encashment,overtime_allowance,notice_pay,hold_salary_non_taxable,children_education_allowance,gratuityinhand
		,tea_allowance
		,unitname,designationname,departmentname
		,coalesce(employerinsuranceamount::numeric(18,2),0) employerinsuranceamount
		,coalesce(charity_contribution_amount::numeric(18,2),0) charity_contribution_amount
		,coalesce(mealvoucher,0) mealvoucher
								
		,nullif(salaryjson,'') salaryjson
		,paymenttypeid
		,payment_record_id
					 
		FROM public.tbl_monthlysalary t
			where t.tptype=p_tptype and coalesce(t.is_rejected,'0')<>'1'
			and not (t.isarear='Y' and t.recordscreen='Current Wages')
			and is_advice='N'
			and (workflowappid = -9999 or is_workflow_approved='Y') --change 1.22
			and (p_action<>'ArrearDisbursementDetails' or (p_action='ArrearDisbursementDetails' and (recordscreen='Increment Arear' or attendancemode='Manual')))
	    	and(
				( (
						(
							to_date(left(t.hrgeneratedon,11),'dd Mon yyyy')
							between v_salstartdate  and v_salenddate
							and to_date((mpryear::text||'-'||lpad(mprmonth::text,2,'0')||'-01'),'yyyy-mm-dd')<v_salstartdate
						)
					or
						(	
						to_date(left(t.hrgeneratedon,11),'dd Mon yyyy')
						 between v_advancesalstartdate  and v_advancesalenddate	
							and mprmonth=p_rptmonth and mpryear=p_rptyear
						)
			)
				and (t.attendancemode<>'Ledger' or coalesce(t.loan,0)<>0 or coalesce(t.advance,0)<>0)
				)
				or(date_trunc('month',(to_date(left(t.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month'))::date=make_date(p_rptyear,p_rptmonth,1)  and (t.attendancemode='Ledger' and coalesce(t.loan,0)=0 and coalesce(t.advance,0)=0))
				)
		and not(netpay=0 and grossearning<0)
		and t.emp_code=coalesce(nullif(p_empcode,-9999),t.emp_code)
		and t.disbursementmode=case when p_disbursementmode='Both' then t.disbursementmode else p_disbursementmode end
	/* union all
		SELECT id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, least(loan,0) loan,greatest(loan,0) loanrecovery, lwf, insurance, mobile, least(advance,0) advance,greatest(advance,0) advancerecovery, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid
		,TO_CHAR(TO_TIMESTAMP (tl.mprmonth::text, 'MM'), 'Mon')||'-'||tl.mpryear::text||'[Not Downloaded]' as Mon	
		,2 as downloadedflag
		,'Partially Processed' as salarystatus
		,'Salary' as disbursementmode
		,professionaltax
		,tptype
		,'N' is_billable
		,ratesalarybonus,ratecommission,ratetransport_allowance,ratetravelling_allowance,rateleave_encashment,rateovertime_allowance,ratenotice_pay,ratehold_salary_non_taxable,ratechildren_education_allowance,rategratuityinhand,salarybonus,commission,transport_allowance,travelling_allowance,leave_encashment,overtime_allowance,notice_pay,hold_salary_non_taxable,children_education_allowance,gratuityinhand
		,tea_allowance
		,unitname,designationname,departmentname
		,coalesce(employerinsuranceamount::numeric(18,2),0) employerinsuranceamount
		,coalesce(charity_contribution_amount::numeric(18,2),0) charity_contribution_amount
		,coalesce(mealvoucher,0) mealvoucher
								
		,null salaryjson
		,0 paymenttypeid
		,0 payment_record_id
		FROM tbl_monthly_liability_salary tl
			where tl.tptype=p_tptype and 1=case when p_reporttype='Liability' then 1 else 2 end and
			  1=case when p_disbursementmode in ('Both','Salary') then 1 else 2 end and
				coalesce(tl.is_rejected,'0')<>'1'
				and is_advice='N'
			and (p_action<>'ArrearDisbursementDetails' or (p_action='ArrearDisbursementDetails' and (recordscreen='Increment Arear' or attendancemode='Manual')))
	    	and (
						(
							to_date(left(tl.hrgeneratedon,11),'dd Mon yyyy')
							between v_salstartdate  and v_salenddate
							and to_date((mpryear::text||'-'||lpad(mprmonth::text,2,'0')||'-01'),'yyyy-mm-dd')<v_salstartdate
						)
					or
						(	
						to_date(left(tl.hrgeneratedon,11),'dd Mon yyyy')
						 between v_advancesalstartdate  and v_advancesalenddate	
							and mprmonth=p_rptmonth and mpryear=p_rptyear
						)
			)	  
-- 			and (tl.emp_code,tl.mprmonth,tl.mpryear,tl.batchid) not in
-- 				 (select m.emp_code,m.mprmonth, m.mpryear,  trim(regexp_split_to_table(m.batchid,',')) from tbl_monthlysalary m where coalesce(m.is_rejected,'0')<>'1')
-- 		/*********Change Added for 1.3*********************/	
-- 		and (tl.emp_code,tl.mprmonth,tl.mpryear,tl.batchid||tl.transactionid::text) not in
-- 				 (select m.emp_code,m.mprmonth, m.mpryear,  trim(regexp_split_to_table(m.batchid,',')) from tbl_monthlysalary m where coalesce(m.is_rejected,'0')<>'1')
		
and (tl.batchid) not in
				 (select trim(regexp_split_to_table(m.batchid,',')) 
				  from tbl_monthlysalary m where coalesce(m.is_rejected,'0')<>'1'
				 and tl.emp_code=m.emp_code and tl.mprmonth=m.mprmonth and tl.mpryear=m.mpryear
				 )	
		and (tl.batchid||tl.transactionid::text) not in
				 (select trim(regexp_split_to_table(m.batchid,',')) 
				  from tbl_monthlysalary m where coalesce(m.is_rejected,'0')<>'1'
				 and tl.emp_code=m.emp_code and tl.mprmonth=m.mprmonth and tl.mpryear=m.mpryear)		
		/*********Change Added for 1.3 ends here*********************/		
	and not(netpay=0 and grossearning<0)
		and tl.emp_code=coalesce(nullif(p_empcode,-9999),tl.emp_code)
		*/
	) t1
	left join tbl_employer_payout_record on tbl_employer_payout_record.id=t1.payment_record_id
	left join mst_paymenttype mpt on mpt.id=tbl_employer_payout_record.payment_method_id
	left join mst_paymenttype on mst_paymenttype.id=t1.paymenttypeid
	inner join (select emp_code ecode,epf_pension_opted,biometricid from openappointments
				where appointment_status_id<>13 
				-- AND COALESCE(geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(geofencingid, 0) ELSE p_geofenceid END -- SIDDHARTH 22.04.2024
				--SIDDHARTH BANSAL 01/08/2024
				AND EXISTS
                    (
                        SELECT 1
                        FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(assigned_ou_ids, ''), COALESCE(NULLIF(geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
                        WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(assigned_ou_ids, ''), COALESCE(NULLIF(geofencingid::TEXT, ''), '0')), ','))
                    )
				--END
			
				and coalesce(openappointments.customeraccountid,-9999)<>1574) o on o.ecode=t1.emp_code
	left join (select emp_code,sum(case when empsalaryregister.isgroupinsurance='Y' then tbl_monthlysalary.insurance else 0 end) insurance
			   ,sum(lwf_employee) lwf_employee
			   ,sum(lwf_employer) lwf_employer
			   ,sum(paiddays) paiddays
			   from tbl_monthlysalary 
			   	left join empsalaryregister on tbl_monthlysalary.salaryid=empsalaryregister.id
			   where /*************Change 1.6******************************************/
					tbl_monthlysalary.emp_code= coalesce(nullif(p_empcode,-9999),tbl_monthlysalary.emp_code) and
				/**************Change 1.6 ends***********************************/
			   mprmonth=p_rptmonth and mpryear=p_rptyear
					and recordscreen ='Current Wages'
					and isarear='Y'
					and coalesce(is_rejected,'0')<>'1'
			  group by emp_code ) t5
	on 	t1.emp_code=t5.emp_code			
	left join empsalaryregister on t1.salaryid=empsalaryregister.id
	left join statewiselwfrate on coalesce(empsalaryregister.lwfstatecode,0)=statewiselwfrate.statecode and statewiselwfrate.isactive='1'
left join banktransfers 
	 on t1.emp_code=banktransfers.emp_code
	 and t1.mprmonth=banktransfers.salmonth
	 and t1.mpryear=banktransfers.salyear
	 and t1.batch_no=banktransfers.batchcode
	 and coalesce(banktransfers.isrejected,'0')<>'1'
	 inner join openappointments op
	 on t1.emp_code=op.emp_code
	 -- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END -- SIDDHARTH BANSAL 22/04/2024
		--SIDDHARTH BANSAL 01/08/2024
		AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
			)
		--END
-- 		-- SIDDHARTH BANSAL 17/10/2024
-- 		AND (lower(coalesce(nullif(p_post_offered,''),'all')) = 'all' OR 
-- 			(op.jobtype = 'Unit Parameter' 
-- 				AND lower(t1.designationname) = lower(p_post_offered)) OR 
-- 			(op.jobtype <> 'Unit Parameter' 
-- 				AND lower(op.post_offered) = lower(p_post_offered)))

-- 		AND (lower(coalesce(nullif(p_posting_department,''),'all')) = 'all' OR 
-- 			(op.jobtype = 'Unit Parameter' 
-- 				AND lower(t1.departmentname) = lower(p_posting_department)) OR 
-- 			(op.jobtype <> 'Unit Parameter' 
-- 				AND lower((string_to_array(op.posting_department,'#'))[1]::varchar) = lower(p_posting_department)))
-- 		AND (lower(coalesce(nullif(p_unitparametername,''),'all')) = 'all' OR lower(t1.unitname) = lower(p_unitparametername))
		--END
		--SIDDHARTH BANSAL 12/12/2024
		AND (
		COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
		OR EXISTS (
			SELECT 1
			FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(op.post_offered)), ',')) AS input_designation
			WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(op.post_offered), ''), ''), ','))
					)
		)

		AND (
	
   
		COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
		OR EXISTS (
			SELECT 1
			FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(op.posting_department)), ',')) AS input_department
			WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(op.posting_department), ''), ''), ','))
					)
		)
   
		AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
			)
		--end
	 and op.appointment_status_id<>13 
	 and op.customeraccountid=p_customeraccountid::bigint
left join(	 
select c.empcode,max(case when lower(c.bunitname) in ('onsite','tp') then c.contractno||', '||c.customeraccountname else c.bunitname end) departentname
	,string_agg(contractno,',') contractno,to_char(min(contractstartdate),'dd-Mon-yyyy') contractstartdate,to_char(max(contractenddate),'dd-Mon-yyyy') contractenddate
	from cmsdownloadedwages	 c
	where (
						(
							to_date(left(c.hrgeneratedon,11),'dd Mon yyyy')
							between v_salstartdate  and v_salenddate
							and to_date((mpryear::text||'-'||lpad(mprmonth::text,2,'0')||'-01'),'yyyy-mm-dd')<v_salstartdate
						)
					or
						(	
						to_date(left(c.hrgeneratedon,11),'dd Mon yyyy')
						 between v_advancesalstartdate  and v_advancesalenddate	
							and mprmonth=p_rptmonth and mpryear=p_rptyear
						)
			)	
and c.isactive='1'
and coalesce(nullif(trim(c.multi_performerwagesflag),''),'Y')<>'N'	
group by c.empcode
)	tbldepartment
on t1.emp_code=tbldepartment.empcode::bigint
-- added on 17.10.2025
LEFT JOIN mst_tp_designations mtd_designation ON mtd_designation.dsignationid = op.designation_id and mtd_designation.account_id= op.customeraccountid
;

/**************************Change 1.7 starts************************************/
Alter table tmpbilling add column monthctc numeric(10,2);
update tmpbilling set monthctc=coalesce(NetPay,0)+coalesce(epf,0)+coalesce(VPF,0)+
coalesce(ac_1,0)+coalesce(ac_10,0)+coalesce(ac_2,0.0)+coalesce(ac21,0)+
coalesce(damagecharges,0)+
coalesce(ESI,0)+coalesce(employeresirate,0)+
coalesce(professionaltax,0)+
coalesce(TDS,0)+
coalesce(lwf,0)+coalesce(lwf_employer,0)+
coalesce(Insurance,0)+
coalesce(employerinsuranceamount,0);

Alter table tmpbilling add column employerepf numeric(10,2);
update tmpbilling set employerepf=coalesce(ac_1,0)+coalesce(ac_10,0)+coalesce(ac_2,0.0)+coalesce(ac21,0);

-------------------------------------------------
/***** CHANGE 1.8 SIDDHARTH BANSAL STARTS********/ 

if p_action='DisbursementSummary'then
	open v_rfc_disbursment for
	SELECT
	mon,
    SUM(grossearning) AS Gross_Earning,
    SUM(GrossDeduction) AS Gross_Deduction,
	sum(advance) advance,
	sum(advancerecovery) advancerecovery,
    SUM(NetPay) AS NetPay,
	sum(monthctc) monthctc
	FROM tmpbilling
	group by mon;
	return next v_rfc_disbursment;

end if;
-------------------------------------------------------

if p_action='DisbursementDetails' then
	open v_rfc_disbursmentdetails for
	SELECT 
	string_agg(mon,',') mon,
	--string_agg(case when (string_to_array(attendancemode, '-'))[1] ='MPR' then mon else '' end,',') mon,
	Employee as EmployeeCode ,
	max(cjcode) tpcode,
	max(orgempcode) orgempcode,
	/**********************************************************************/
	max(Designation) Designation,
    max(posting_department) posting_department, max(jobtype) jobtype, max(unitparametername) unitparametername,
	max(DateofJoining) DateofJoining,
	max(dateofbirth) dateofbirth,
	max(esinumber) esinumber,
	max(email) email,
	max(mobilenumber) mobilenumber,
	max(dateofleaving) dateofleaving,
	sum(Arrear_Days) Arrear_Days,
	--sum(Loss_Off_Pay) Loss_Off_Pay,
	greatest(max(monthdays)-coalesce(sum(Total_Paid_Days),0),0) Loss_Off_Pay,
	sum(Total_Paid_Days) Total_Paid_Days,
	max(RateBasic) RateBasic,	
	max(RateHRA) RateHRA,
	max(RateCONV) RateCONV,
	max(RateMedical) RateMedical,
	max(RateSpecial_Allowance) RateSpecial_Allowance,
	max(FixedAllowancesTotalRate) FixedAllowancesTotalRate,
	sum(basic) basic,	
	sum(HRA) HRA,
	sum(CONV) CONV,
	sum(Medical) Medical,
	sum(SpecialAllowance) SpecialAllowance,
	sum(Arr_Basic) Arr_Basic,
	sum(Arr_HRA) Arr_HRA,
	sum(Arr_CONV) Arr_CONV,
	sum(Arr_Medical) ,
	sum(Arr_SpecialAllowance) Arr_SpecialAllowance,
	sum(Incentive) Incentive,
	sum(Monthly_Bonus) Monthly_Bonus,
	sum(other) other,
	sum(coalesce(epf,0)+coalesce(epf_arear,0)) epf,
	sum(Insurance) Insurance,
	max(salarystatus) salarystatus,
	string_agg(arearaddedmonths,',') arearaddedmonths,
	sum(totalarear) totalarear,
	sum(voucher_amount) voucher_amount,
	sum(ews)  ews,
	sum(gratuity) gratuity ,
	sum(bonus) bonus ,
	sum(employeenps) employeenps ,
    SUM(loan) AS loan,
    SUM(loanrecovery) AS loanrecovery,
	sum(refund) refund,
	max(insurancetype) insurancetype,
	sum(coalesce(professionaltax,0)+coalesce(professionaltax_arear,0)) professionaltax,
	sum(coalesce(esi,0)+coalesce(esi_arear,0)) esi, 
	sum(advance) advance,
	sum(advancerecovery) advancerecovery,
	SUM(grossearning) AS Gross_Earning,
	/**********************************************************************/	
	max(Employee_Name) as empname,
	max(pan_number) as pan_number,
	max(esinumber) as esinnumber,
	max(Father_Husband_Name) as fathername,
	max(uannumber) as uannumber,
    SUM(GrossDeduction) AS Gross_Deduction,
    SUM(NetPay) AS NetPay, 
    SUM(coalesce(epf,0)+coalesce(epf_arear,0)) AS employeeepf,
    SUM(coalesce(vpf,0)+coalesce(vpf_arear,0)) AS vpf,
    SUM(coalesce(ESI,0)+coalesce(esi_arear,0)) AS employeeESI,
    SUM(coalesce(tds,0)+coalesce(tds_arear,0)) AS tds,
    SUM(coalesce(lwf,0)+coalesce(lwf_arear,0)) AS lwf,
    SUM(ac_1) AS ac_1,
    SUM(ac_10) AS ac_10,
    SUM(ac_2) AS ac_2,
    SUM(ac21) AS ac21,
    SUM(Employer_ESI_Contr) AS Employer_ESI_Contr,
    SUM(lwf_employer) AS lwf_employer,
	sum(tea_allowance) as tea_allowance,
	sum(monthctc) monthctc,
		max(bankaccountno) AS bankaccountno,
		max(ifsccode) AS ifsccode,
		max(bankname) AS bankname,
		max(bankbranch) AS bankbranch,
	sum(charity_contribution_amount) charity_contribution_amount
    -- START - CHANGES [1.17]
	,MAX(vendor_name) vendor_name,
	MAX(project_name) project_name,
	MAX(salary_book_project) salary_book_project,
	MAX(assigned_ou_names) assigned_ou_names,
	sum(employerepf) employerepf
/***********Change 1.18 starts**********************/
	,MAX(rate_employerinsuranceamount) as rate_employerinsuranceamount
	,MAX(rate_employerlwf) as rate_employerlwf
	,MAX(rate_employerepf) as rate_employerepf
	,MAX(rate_employeresi) as rate_employeresirate
	,max(ctc) as masterctc
	,sum(mealvoucher) mealvoucher
	,sum(mealvoucher_arear) mealvoucher_arear
	
	,sum(arr_salarybonus) arr_salarybonus
	,sum(arr_commission) arr_commission
	,sum(arr_transport_allowance) arr_transport_allowance
	,sum(arr_travelling_allowance) arr_travelling_allowance
	,sum(arr_leave_encashment) arr_leave_encashment
	,sum(arr_overtime_allowance) arr_overtime_allowance
	,sum(arr_notice_pay) arr_notice_pay
	,sum(arr_hold_salary_non_taxable) arr_hold_salary_non_taxable
	,sum(arr_children_education_allowance) arr_children_education_allowance
	,sum(arr_gratuityinhand) arr_gratuityinhand

						  
						  
						  
						  
												  
   
	,json_agg(othervariables_json) othervariables_json
  
						  
						  
						  
						  
												  
   
	FROM tmpbilling

/************************************************/
LEFT JOIN LATERAL (
    SELECT json_agg(
               json_build_object(
                   'deduction_name', mt.deduction_name,
                   'amt', (tc.deduction_amount/(case when tc.deduction_frequency='Monthly' then 1 when  
tc.deduction_frequency='Quarterly' then 3 when tc.deduction_frequency='Half Yearly' 
then 6 when tc.deduction_frequency= 'Annually' then 12 end ) * tmpbilling.paiddays / (
                       CASE 
                           WHEN COALESCE(e.salaryindaysopted, 'N') = 'N' OR e.salarydays = 1 OR COALESCE(e.flexiblemonthdays, 'N') = 'Y' 
                           THEN v_fullmonthdays 
                           ELSE e.salarydays 
                       END
                   ))
               )
           ) as othervariables_json
   from empsalaryregister e 
		inner join trn_candidate_otherduction tc on tc.salaryid=e.id and tc.candidate_id=e.appointment_id and tmpbilling.othervariables>0
		inner join mst_otherduction mt on mt.id=tc.deduction_id
		and ( 
				(--tc.active='Y' and
				   coalesce(tc.includedinctc,'N')='Y' 
				  and coalesce(tc.isvariable,'N')='N'
				  and tc.deduction_id not in (7,10)
				  and tc.deduction_id<>134 --Meal Voucher ID, Must Change for Production
				  and tc.deduction_frequency in ('Quarterly','Half Yearly','Annually')
				  )
				or		
				(	
					--tc.active='Y' and
				    tc.deduction_amount>0
				  and tc.deduction_frequency in ('Monthly')
				  and tc.deduction_id not in (5,6,7,10)
				  --and coalesce(tc.is_taxable,'N')='N'
				  and mt.id<>134 --Meal Voucher ID, Must Change for Production)
				  )
			)
		where tmpbilling.salaryid=e.id and tmpbilling.recordscreen<>'Increment Arear' and tmpbilling.attendancemode='MPR'
			)
		deductions_lat ON true
/************************************************/	
	
	group by Employee/*,mon*/;
	return next v_rfc_disbursmentdetails;

end if;
--------------------------------------------------------
if p_action='ArrearDisbursementDetails'then
	open v_rfc_disbursmentdetails for
	SELECT 
	mon,
	Employee as EmployeeCode ,
	max(cjcode) tpcode,
	max(orgempcode) orgempcode,
	/**********************************************************************/
	max(Designation) Designation,
    max(posting_department) posting_department, max(jobtype) jobtype, max(unitparametername) unitparametername,
	max(DateofJoining) DateofJoining,
	max(dateofbirth) dateofbirth,
	max(esinumber) esinumber,
	max(email) email,
	max(dateofleaving) dateofleaving,
	sum(Arrear_Days) Arrear_Days,
	--sum(Loss_Off_Pay) Loss_Off_Pay,
	greatest(max(monthdays)-coalesce(sum(Total_Paid_Days),0),0) Loss_Off_Pay,
	sum(Total_Paid_Days) Total_Paid_Days,
	max(RateBasic) RateBasic,	
	max(RateHRA) RateHRA,
	max(RateCONV) RateCONV,
	max(RateMedical) RateMedical,
	max(RateSpecial_Allowance) RateSpecial_Allowance,
	max(FixedAllowancesTotalRate) FixedAllowancesTotalRate,
	sum(basic) basic,	
	sum(HRA) HRA,
	sum(CONV) CONV,
	sum(Medical) Medical,
	sum(SpecialAllowance) SpecialAllowance,
	sum(Arr_Basic) Arr_Basic,
	sum(Arr_HRA) Arr_HRA,
	sum(Arr_CONV) Arr_CONV,
	sum(Arr_Medical) ,
	sum(Arr_SpecialAllowance) Arr_SpecialAllowance,
	sum(Incentive) Incentive,
	sum(Monthly_Bonus) Monthly_Bonus,
	sum(other) other,
	SUM(coalesce(epf,0)+coalesce(epf_arear,0)) epf,
	sum(Insurance) Insurance,
	max(salarystatus) salarystatus,
	string_agg(arearaddedmonths,',') arearaddedmonths,
	sum(totalarear) totalarear,
	sum(voucher_amount) voucher_amount,
	sum(ews)  ews,
	sum(gratuity) gratuity ,
	sum(bonus) bonus ,
	sum(employeenps) employeenps ,
    SUM(loan) AS loan,
    SUM(loanrecovery) AS loanrecovery,
	sum(refund) refund,
	max(insurancetype) insurancetype,
	sum(coalesce(professionaltax,0)+coalesce(professionaltax_arear,0)) professionaltax,
    SUM(coalesce(ESI,0)+coalesce(esi_arear,0)) AS esi,
	sum(advance) advance,
	sum(advancerecovery) advancerecovery,
	SUM(grossearning) AS Gross_Earning,
	/**********************************************************************/	
	max(Employee_Name) as empname,
	max(pan_number) as pan_number,
	max(esinumber) as esinnumber,
	max(Father_Husband_Name) as fathername,
	max(uannumber) as uannumber,
    SUM(GrossDeduction) AS Gross_Deduction,
    SUM(NetPay) AS NetPay, 
    SUM(coalesce(epf,0)+coalesce(epf_arear,0)) AS employeeepf,
    SUM(coalesce(vpf,0)+coalesce(vpf_arear,0)) AS vpf,
    SUM(coalesce(ESI,0)+coalesce(esi_arear,0)) AS employeeESI,
    SUM(coalesce(tds,0)+coalesce(tds_arear,0)) AS tds,
    SUM(coalesce(lwf,0)+coalesce(lwf_arear,0)) AS lwf,
    SUM(ac_1) AS ac_1,
    SUM(ac_10) AS ac_10,
    SUM(ac_2) AS ac_2,
    SUM(ac21) AS ac21,
    SUM(Employer_ESI_Contr) AS Employer_ESI_Contr,
    SUM(lwf_employer) AS lwf_employer,
	sum(tea_allowance) as tea_allowance,
	sum(monthctc) monthctc,
		max(bankaccountno) AS bankaccountno,
		max(ifsccode) AS ifsccode,
		max(bankname) AS bankname,
		max(bankbranch) AS bankbranch,
	sum(charity_contribution_amount) charity_contribution_amount
    -- START - CHANGES [1.17]
	,MAX(vendor_name) vendor_name,
	MAX(project_name) project_name,
	MAX(salary_book_project) salary_book_project,
	MAX(assigned_ou_names) assigned_ou_names,
	sum(employerepf) employerepf
/***********Change 1.18 starts**********************/
	,MAX(rate_employerinsuranceamount) as rate_employerinsuranceamount
	,MAX(rate_employerlwf) as rate_employerlwf
	,MAX(rate_employerepf) as rate_employerepf
	,MAX(rate_employeresi) as rate_employeresirate
	,max(ctc) as masterctc
/***********Change 1.18 starts**********************/	
	,sum(mealvoucher) mealvoucher
	,sum(mealvoucher_arear) mealvoucher_arear	
    -- END - CHANGES [1.17]	
	,sum(arr_salarybonus) arr_salarybonus
	,sum(arr_commission) arr_commission
	,sum(arr_transport_allowance) arr_transport_allowance
	,sum(arr_travelling_allowance) arr_travelling_allowance
	,sum(arr_leave_encashment) arr_leave_encashment
	,sum(arr_overtime_allowance) arr_overtime_allowance
	,sum(arr_notice_pay) arr_notice_pay
	,sum(arr_hold_salary_non_taxable) arr_hold_salary_non_taxable
	,sum(arr_children_education_allowance) arr_children_education_allowance
	,sum(arr_gratuityinhand) arr_gratuityinhand
  
						  
						  
						  
						  
												  
   
	FROM tmpbilling
	group by Employee,mon;
	return next v_rfc_disbursmentdetails;

end if;
/***** CHANGE 1.8 SIDDHARTH BANSAL  ENDS********/ 

-----------------------------------------------------------------
if p_reporttype='Phase3Billing' then
	update tmpbilling
	set banktransferstatus='Transferred'
	where recordscreen='Increment Arear'
	and id in (select trim(regexp_split_to_table(m.arearids,','))::bigint from tmpbilling m where m.arearids is not null and m.banktransferstatus='Transferred');

	update tmpbilling
	set banktransferstatus='Not Transferred'
	where recordscreen<>'Increment Arear'
	and nullif(trim(arearids),'') is not null
	and coalesce(ESI,0)=0;
end if;
/**************************Change 1.7 ends************************************/	
Raise Notice 'Outside Liability Part1 at %',TIMEOFDAY();
if p_action='GetDetailedLiability' then
	if p_reporttype='Billing' then
		if p_contractno is null then
			create temporary table   tmpbilling2 on commit drop
			as
			select * from tmpbilling where (
			(recordscreen in('Current Wages','Previous Wages') and banktransferstatus='Transferred')
			or tmpbilling.id in (select  trim(regexp_split_to_table(t2.arearids,','))::bigint  from tmpbilling t2 where t2.recordscreen in('Current Wages','Previous Wages') and t2.banktransferstatus='Transferred' ))
			
			and (is_billable='Y' or disbursementmode='Salary');
		else
		    create temporary table   tmpbilling2 on commit drop
			as
			select * from tmpbilling where ((recordscreen in('Current Wages','Previous Wages') and banktransferstatus='Transferred'
												and(tmpbilling.employee,tmpbilling.mprmonth,tmpbilling.mpryear,tmpbilling.batchcode) in
												(select empcode::bigint,mprmonth,mpryear,batch_no from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1'  /*and bunit in(1,7)*/
												union
												select empcode::bigint,mprmonth,mpryear,batch_no||transactionid from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1'  /*and bunit in(1,7)*/
												)
										   )
								or tmpbilling.id in (select  trim(regexp_split_to_table(t2.arearids,','))::bigint  from tmpbilling t2 where t2.recordscreen in('Current Wages','Previous Wages') and t2.banktransferstatus='Transferred' 
								and(t2.employee,t2.mprmonth,t2.mpryear,t2.batchcode) in
												(select empcode::bigint,mprmonth,mpryear,batch_no from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1'
												union
												select empcode::bigint,mprmonth,mpryear,batch_no||transactionid from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1'
												))
											)
											and (is_billable='Y' or disbursementmode='Salary');
		end if;
	else
	Raise Notice 'Inside Liability Part2 at %',TIMEOFDAY();
		create temporary table   tmpbilling2 on commit drop
		as
		select * from tmpbilling;
		Raise Notice 'Outside Liability Part2 at %',TIMEOFDAY();
	end if;
if p_action='GetDetailedLiability' and p_reporttype='Liability'  then	
   	open v_rfc for
	select * from tmpbilling2
	order by ordercol;

	return next v_rfc;
end if;	
end if;	
if p_action='GetMonthLiability' then

if p_reporttype='Billing' then
	/**************Billing Code Goes Below ********************************/
		if p_contractno is null then
			create temporary table   tmpbilling2 on commit drop
			as
			select * from tmpbilling where (
										(recordscreen in('Current Wages','Previous Wages') and banktransferstatus='Transferred')
											or tmpbilling.id in (select  trim(regexp_split_to_table(t2.arearids,','))::bigint  from tmpbilling t2 where t2.recordscreen ='Current Wages' and t2.banktransferstatus='Transferred' )
											)
										and (is_billable='Y' or disbursementmode='Salary');
		else
		create temporary table   tmpbilling2 on commit drop
			as
			select * from tmpbilling where (
											(recordscreen in('Current Wages','Previous Wages') and banktransferstatus='Transferred'
												and(tmpbilling.employee,tmpbilling.mprmonth,tmpbilling.mpryear,tmpbilling.batchcode) in
												(select empcode::bigint,mprmonth,mpryear,batch_no from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1' /*and bunit in(1,7)*/
												union
												select empcode::bigint,mprmonth,mpryear,batch_no||transactionid from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1'  /*and bunit in(1,7)*/
												)
										   )
								or tmpbilling.id in (select  trim(regexp_split_to_table(t2.arearids,','))::bigint  from tmpbilling t2 where t2.recordscreen in('Current Wages','Previous Wages') and t2.banktransferstatus='Transferred' 
								and(t2.employee,t2.mprmonth,t2.mpryear,t2.batchcode) in
												(select empcode::bigint,mprmonth,mpryear,batch_no from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1'  /*and bunit in(1,7)*/
												union
												select empcode::bigint,mprmonth,mpryear,batch_no||transactionid from cmsdownloadedwages 
												 where contractno=p_contractno and isactive='1'  /*and bunit in(1,7)*/
												))
											)
											and (is_billable='Y' or disbursementmode='Salary');
		end if;
/************New code for Phase 3 Billing starts**********************/		
elsif p_reporttype='Phase3Billing' then		
		create temporary table   tmpbilling2 on commit drop
			as
			select * from tmpbilling where ((recordscreen in('Current Wages','Previous Wages') and banktransferstatus='Transferred')
								or tmpbilling.id in (select  trim(regexp_split_to_table(t2.arearids,','))::bigint  from tmpbilling t2 where t2.recordscreen ='Current Wages' and t2.banktransferstatus='Transferred' )
											)
									and tmpbilling.createdon::date>='2023-06-01'::date;
									
	   create temporary table tmpinvoices on commit drop
	   as
		select * from (
				select regexp_split_to_table(salarybillinginvoices.banktransferids,',')::bigint as btid2
					   from  salarybillinginvoices 
					   where salarybillinginvoices.isactive='1'
					  ) tmp2 order by btid2;
					  
INSERT INTO public.salarybillinginvoices(salaryperiod,billingmonth,billingyear,contractid,contractno,customeraccountname,associatecount,salarycount,billingamount,banktransferids,isactive,createdate, ac_1, ac_10, ac_2, ac21, employeresirate, lwf_employer, grossearning, voucherorsalary)

select mon salarydate,p_rptmonth,p_rptyear,
	c.cms_contractid::int contractid,
	c.contractno,
	c.customeraccountname
	,count(distinct t.employee) Associatecount 
	,count(*) salarycount
	,sum(coalesce(t.grossearning,0)+coalesce(ac_1,0)+coalesce(ac_10,0)+coalesce(ac_2,0)+coalesce(ac21,0)+coalesce(case when is_billable='N' or c.attendancemode='MPR' then employeresirate else 0 end,0)+coalesce(lwf_employer,0)) as disbamount
	,string_agg(t.btid::text,',') bids 
	,'1'::bit isactive
	,current_timestamp as createddate
	,sum(ac_1) ac_1
	,sum(ac_10) ac_10
	,sum(ac_2) ac_2
	,sum(ac21) ac21
	,sum(case when is_billable='N' or c.attendancemode in('MPR','Manual') then employeresirate else 0 end) employeresirate
	,sum(lwf_employer) lwf_employer
	,sum(grossearning) grossearning
	-- START - by Parveen on 22 May 2023 at 05:39 [Change 1.6]
	--,CASE WHEN c.attendancemode = 'Ledger' THEN 'Voucher' ELSE c.attendancemode END as attendancemode
	-- END - by Parveen on 22 May 2023 at 05:39 [Change 1.6]
	--,t.disbursementmode attendancemode
	,case when is_billable='N' or c.attendancemode in('MPR','Manual') then 'MPR' else 'Voucher' end attendancemode
	from tmpbilling2 t
	inner join cmsdownloadedwages c
	on c.empcode::bigint=t.Employee
	and c.mprmonth=t.mprmonth
	and c.mpryear=t.mpryear
	and c.batch_no=t.batchcode
	and c.isactive='1'
	and (c.attendancemode='MPR' OR c.attendancemode='Ledger' OR c.attendancemode='Manual')
	and t.tptype='NonTP'
	and to_date('01-'||mon,'dd-Mon-yyyy') >='2023-01-01'::date
	and nullif(c.cms_contractid,'') is not null
	-- and t.is_billable='Y'
	and (t.is_billable='Y' or t.disbursementmode='Salary')
	and not exists (select * from tmpinvoices where tmpinvoices.btid2=t.btid)
	group by mon,c.cms_contractid,c.contractno,c.customeraccountname,case when is_billable='N' or c.attendancemode in('MPR','Manual') then 'MPR' else 'Voucher' end;

open v_rfc for
select 1 as cnt;
return next v_rfc;
/************New code for Phase 3 Billing ends**********************/									
	/**************Billing Code ends here ********************************/		
	else
	/**************Liability Code Goes Here ********************************/	
		if nullif(p_contractno,'') is null then
		create temporary table   tmpbilling2 on commit drop
		as
		select * from tmpbilling;
	else
	create temporary table   tmpbilling2 on commit drop
			as
			select * from tmpbilling where ((recordscreen in('Current Wages','Previous Wages')
						and(tmpbilling.employee,tmpbilling.mprmonth,tmpbilling.mpryear,tmpbilling.batchcode) in
						(select empcode::bigint,mprmonth,mpryear,batch_no from cmsdownloadedwages 
						 where contractno=p_contractno and isactive='1' 
						union
						select empcode::bigint,mprmonth,mpryear,batch_no||transactionid from cmsdownloadedwages 
						 where contractno=p_contractno and isactive='1'
						)
				   )
		or tmpbilling.id in (select  trim(regexp_split_to_table(t2.arearids,','))::bigint  from tmpbilling t2 where t2.recordscreen in('Current Wages','Previous Wages') 
		and(t2.employee,t2.mprmonth,t2.mpryear,t2.batchcode) in
						(select empcode::bigint,mprmonth,mpryear,batch_no from cmsdownloadedwages 
						 where contractno=p_contractno and isactive='1'
						union
						select empcode::bigint,mprmonth,mpryear,batch_no||transactionid from cmsdownloadedwages 
						 where contractno=p_contractno and isactive='1'
						))
					);
	end if;
		/**************Liability Code ends here ********************************/	
	end if;
if p_reporttype='Liability' then
--Raise Notice 'Inside Liability Part3 at %',TIMEOFDAY();
alter table tmpbilling2 add column education_cess numeric(18,4);
alter table tmpbilling2 add column incometax numeric(18,4);
update tmpbilling2 set education_cess=(tds*4.0/104.0)::numeric(18,4); 
update tmpbilling2 set incometax=(tds-education_cess)::numeric(18,4); 

	/**************Liability Code Goes Here ********************************/
   	open v_rfc for
	with tmp as(
	select string_agg( distinct mon,',')	mon	,p_rptmonth mprmonth,p_rptyear mpryear,
	employee	employee	,
	max(cjcode) tpcode,
	max(orgempcode) orgempcode,
	max(employee_name)	employee_name	,
	max(father_husband_name)	father_husband_name	,
	max(tmpbilling2.designation) designation,
    max(posting_department) posting_department, max(jobtype) jobtype, max(unitparametername) unitparametername,
	max(department)	department	,
	max(subunit)	subunit	,
	max(dateofjoining)	dateofjoining	,
	max(dateofbirth)	dateofbirth	,
	string_agg( distinct esinumber,',')	esinumber	,
	string_agg( distinct pan_number,',')	pan_number	,
	string_agg( distinct uannumber,',')	uannumber	,
	string_agg( distinct email,',')	email	,
	max(dateofleaving)	dateofleaving	,
	SUM(arrear_days)	arrear_days	,
	greatest(max(case when mprmonth=p_rptmonth and mpryear=p_rptyear then monthdays else 0 end)-SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end),0)	loss_off_pay	,
	SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end)	total_paid_days	,
	max(tmprataes.ratebasic)	ratebasic	,
	max(tmprataes.ratehra)	ratehra	,
	max(tmprataes.rateconv)	rateconv	,
	max(tmprataes.ratemedical)	ratemedical	,
	max(tmprataes.ratespecial_allowance)	ratespecial_allowance	,
	max(tmprataes.fixedallowancestotalrate)	fixedallowancestotalrate	,
	SUM(tmpbilling2.basic)	basic	,
	SUM(tmpbilling2.hra)	hra	,
	SUM(tmpbilling2.conv)	conv	,
	SUM(tmpbilling2.medical)	medical	,
	SUM(tmpbilling2.specialallowance)	specialallowance	,
	SUM(tmpbilling2.arr_basic)	arr_basic	,
	SUM(tmpbilling2.arr_hra)	arr_hra	,
	SUM(tmpbilling2.arr_conv)	arr_conv	,
	SUM(tmpbilling2.arr_medical)	arr_medical	,
	SUM(tmpbilling2.arr_specialallowance)	arr_specialallowance	,
	SUM(tmpbilling2.incentive)	incentive	,
	SUM(tmpbilling2.refund)	refund	,
	SUM(tmpbilling2.monthly_bonus)	monthly_bonus	,
	SUM(tmpbilling2.grossearning)	grossearning	,
	SUM(tmpbilling2.epf)	epf	,
	SUM(tmpbilling2.vpf)	vpf	,
	SUM(tmpbilling2.esi)	esi	,
	SUM(tmpbilling2.tds)	tds	,
	SUM(tmpbilling2.loan)	loan	,
	SUM(tmpbilling2.lwf)	lwf	,
	SUM(tmpbilling2.insurance)	insurance	,
	SUM(tmpbilling2.mobile)	mobile	,
	SUM(tmpbilling2.advance)	advance	,
	SUM(tmpbilling2.other)	other	,
	SUM(tmpbilling2.grossdeduction)	grossdeduction	,
	SUM(tmpbilling2.netpay)	netpay	,
	SUM(tmpbilling2.ac_1)	ac_1	,
	SUM(tmpbilling2.ac_10)	ac_10	,
	SUM(tmpbilling2.ac_2)	ac_2	,
	max(tblac21.ac21temp)	ac21	,
	SUM(tmpbilling2.employer_esi_contr)	employer_esi_contr	,
	min(tmpbilling2.salarystatus)	salarystatus	,
	string_agg( distinct arearaddedmonths,',')	arearaddedmonths	,
	max(monthdays)	monthdays	,
	string_agg( distinct tmpbilling2.salaryid::text,',')	salaryid	,
	string_agg( distinct banktransferstatus,',')	banktransferstatus	,
	SUM(atds)	atds	,
	SUM(voucher_amount)	voucher_amount	,
	SUM(tmpbilling2.ews)	ews	,
	SUM(tmpbilling2.gratuity)	gratuity	,
	SUM(tmpbilling2.bonus)	bonus	,
	SUM(employeenps)	employeenps	,
	SUM(damagecharges)	damagecharges	,
	SUM(otherledgerarears)	otherledgerarears	,
	SUM(otherledgerdeductions)	otherledgerdeductions	,
	SUM(othervariables)	othervariables	,
	SUM(otherdeductions)	otherdeductions	,
	SUM(otherledgerarearwithoutesi)	otherledgerarearwithoutesi	,
	SUM(otherbonuswithesi)	otherbonuswithesi	,
	SUM(totalarear)	totalarear	,
	SUM(lwf_employer)	lwf_employer	,
	string_agg( distinct insurancetype,',')	insurancetype	,
	string_agg( distinct attendancemode,',')	attendancemode	
	,max(Employee_Name) Emp_Name
	,SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end) as paiddays
	,employee as emp_code
	,null::int emp_id
	,null rejectstatus
	,null reject_reason
	,max(father_husband_name) fathername
	,max(tmpbilling2.designation) post_offered,
    max(posting_department) posting_department, max(jobtype) jobtype, max(unitparametername) unitparametername
	,max(department)	posting_department
	,string_agg( distinct pan_number,',') pancard
	,greatest(max(case when mprmonth=p_rptmonth and mpryear=p_rptyear then monthdays else 0 end)-SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end),0)	lossofpay	
	,max(tmprataes.ratespecial_allowance)	ratespecialallowance
	,null::double precision ratebasic_arr
	,null::double precision ratehra_arr
	,null::double precision rateconv_arr
	,null::double precision ratemedical_arr
	,null::double precision ratespecialallowance_arr
	,SUM(esi) employeeesirate
	,sum(Employer_ESI_Contr) employeresirate
	,null::double precision incrementarear
	,null::double precision incrementarear_basic
	,null::double precision incrementarear_hra
	,null::double precision incrementarear_gross
	,null salaryindaysopted
	,null::int salarydays
	,null contractno
	,null pfnumber
	,null bankaccountno
	,null ifsccode
	,null bankname
	,null bankbranch
	,SUM(tmpbilling2.basic)+SUM(tmpbilling2.hra)+SUM(tmpbilling2.specialallowance)	fixedallowancestotal
	,coalesce(nullif(tmpbilling2.disbursementmode,'Voucher'),mo.deduction_name) disbursementmode
	,SUM(tmpbilling2.professionaltax) professionaltax
	,max(contractno) contractno
	,max(contractstartdate) contractstartdate
	,max(contractenddate) contractenddate
	,sum(advancerecovery) advancerecovery
	,sum(loanrecovery) loanrecovery
/*************************************************************/	
		,sum(tmpbilling2.salarybonus) salarybonus
		,sum(tmpbilling2.commission) commission
		,sum(tmpbilling2.transport_allowance) transport_allowance
		,sum(tmpbilling2.travelling_allowance) travelling_allowance
		,sum(tmpbilling2.leave_encashment) leave_encashment
		,sum(tmpbilling2.overtime_allowance) overtime_allowance
		,sum(tmpbilling2.notice_pay) notice_pay
		,sum(tmpbilling2.hold_salary_non_taxable) hold_salary_non_taxable
		,sum(tmpbilling2.children_education_allowance) children_education_allowance
		,sum(tmpbilling2.gratuityinhand) gratuityinhand
		,max(tmprataes.ratesalarybonus)  ratesalarybonus
		,max(tmprataes.ratecommission)  ratecommission
		,max(tmprataes.ratetransport_allowance)  ratetransport_allowance
		,max(tmprataes.ratetravelling_allowance)  ratetravelling_allowance
		,max(tmprataes.rateleave_encashment)  rateleave_encashment
		,max(tmprataes.rateovertime_allowance)  rateovertime_allowance
		,max(tmprataes.ratenotice_pay)  ratenotice_pay
		,max(tmprataes.ratehold_salary_non_taxable)  ratehold_salary_non_taxable
		,max(tmprataes.ratechildren_education_allowance)  ratechildren_education_allowance
		,max(tmprataes.rategratuityinhand)  rategratuityinhand
		,max(biometricid) biometricid
/*************************************************************/	
		,sum(tea_allowance) tea_allowance
		,string_agg(tmpbilling2.id::text,',')	salaryids
		,sum(tmpbilling2.employerinsuranceamount) employerinsuranceamount
		,sum(monthctc) monthctc
		,sum(charity_contribution_amount) charity_contribution_amount
		-- START - CHANGES [1.17]
		,MAX(vendor_name) vendor_name,
		MAX(project_name) project_name,
		MAX(salary_book_project) salary_book_project,
		MAX(assigned_ou_names) assigned_ou_names
		-- END - CHANGES [1.17]
		,sum(employerepf) employerepf
/***********Change 1.18 starts**********************/
	,MAX(rate_employerinsuranceamount) as rate_employerinsuranceamount
	,MAX(rate_employerlwf) as rate_employerlwf
	,MAX(rate_employerepf) as rate_employerepf
	,MAX(rate_employeresi) as rate_employeresirate
	,max(tmpbilling2.ctc) as masterctc
	,MAX(rate_employergratuity) as rate_employergratuity
	,sum(tmpbilling2.employergratuity) as employergratuity
/***********Change 1.18 starts**********************/
	,sum(mealvoucher) mealvoucher
	,sum(mealvoucher_arear) mealvoucher_arear	
	,sum(arr_salarybonus) arr_salarybonus
	,sum(arr_commission) arr_commission
	,sum(arr_transport_allowance) arr_transport_allowance
	,sum(arr_travelling_allowance) arr_travelling_allowance
	,sum(arr_leave_encashment) arr_leave_encashment
	,sum(arr_overtime_allowance) arr_overtime_allowance
	,sum(arr_notice_pay) arr_notice_pay
	,sum(arr_hold_salary_non_taxable) arr_hold_salary_non_taxable
	,sum(arr_children_education_allowance) arr_children_education_allowance
	,sum(arr_gratuityinhand) arr_gratuityinhand
	,sum(epf_arear) epf_arear
	
	,sum(vpf_arear) vpf_arear
	,sum(tds_arear) tds_arear
	,sum(lwf_arear) lwf_arear
	,sum(esi_arear) esi_arear
	,sum(professionaltax_arear) professionaltax_arear
						
	,jsonb_agg(salaryjson) salaryjson
	,string_agg(nullif(payment_mode,''),',') payment_mode
	,to_char(min(liabilitycreatedon),'dd-mm-yyyy') liabilitycreatedon
	,sum(education_cess)::numeric(18,0) education_cess
	,sum(incometax)::numeric(18,0) incometax
	,json_agg(othervariables_json) othervariables_json

	 ,json_agg(
        json_build_object(
            'headname', tl2.headname,
            'amount', tl2.amount
        )
    ) FILTER (WHERE tl2.emp_code IS NOT NULL and coalesce(tl2.is_taxable,'Y')='Y' AND tl2.masterhead = 'Additional income' ) AS taxable_ledgers
	,json_agg(
        json_build_object(
            'headname', tl2.headname,
            'amount', abs(tl2.amount)
        )
    ) FILTER (WHERE tl2.emp_code IS NOT NULL and coalesce(tl2.is_taxable,'Y')='Y' AND tl2.masterhead = 'Deduction' ) AS taxable_ledgers_d

	 ,json_agg(
        json_build_object(
            'headname', tl.headname,
            'amount', tl.amount
        )
    ) FILTER (WHERE tl.emp_code IS NOT NULL and coalesce(tl.is_taxable,'Y')='N' and coalesce(tmpbilling2.loan,0)=0 and coalesce(tmpbilling2.loanrecovery,0)=0 and coalesce(tmpbilling2.advance,0)=0 and coalesce(tmpbilling2.advancerecovery,0)=0  ) AS non_taxable_ledgers
from tmpbilling2 
  left join tbl_employeeledger tl on tmpbilling2.employee=tl.emp_code 
  and tmpbilling2.disbursementmode='Voucher'
  and tmpbilling2.batchcode=tl.ledgerbatchid 
  and tl.isactive='1'
   
  left join tbl_employeeledger tl2 on tmpbilling2.employee=tl2.emp_code 
  and tmpbilling2.disbursementmode='Salary'
  and tmpbilling2.batchcode=tl2.ledgerbatchid 
  and tl2.isactive='1'
  left join mst_otherduction mo on tl.headid=mo.id 
 left join (select ep,sum(least(ac21temp,75)) ac21temp from(select employee ep,sum(ac21) ac21temp from tmpbilling2 where coalesce(salary_remarks,'')<>'Invalid Paid Days' group by ep,mprmonth,mpryear) tn1 group by  ep) tblac21
			on tmpbilling2.employee=tblac21.ep
	and tmpbilling2.disbursementmode='Salary'			
 left join (select employee ep2,ratebasic,ratehra,rateconv,ratemedical,ratespecial_allowance,fixedallowancestotalrate
			,row_number()over(partition by employee order by salaryid desc) salrn
			,ratesalarybonus,ratecommission,ratetransport_allowance,ratetravelling_allowance,rateleave_encashment,rateovertime_allowance,ratenotice_pay,ratehold_salary_non_taxable,ratechildren_education_allowance,rategratuityinhand /*************************************************************/	
			from tmpbilling2 where coalesce(salary_remarks,'')<>'Invalid Paid Days' and tmpbilling2.recordscreen<>'Increment Arear' and (regexp_split_to_array(tmpbilling2.attendancemode,'-'))[1]='MPR') tmprataes
			on tmpbilling2.employee=tmprataes.ep2 and salrn=1

/************************************************/
LEFT JOIN LATERAL (
    SELECT json_agg(
               json_build_object(
                   'deduction_name', mt.deduction_name,
                   'amt', (tc.deduction_amount * tmpbilling2.paiddays / (
                       CASE 
                           WHEN COALESCE(e.salaryindaysopted, 'N') = 'N' OR e.salarydays = 1 OR COALESCE(e.flexiblemonthdays, 'N') = 'Y' 
                           THEN v_fullmonthdays 
                           ELSE e.salarydays 
                       END
                   ))
               )
           ) as othervariables_json
   from empsalaryregister e 
		inner join trn_candidate_otherduction tc on tc.salaryid=e.id and tc.candidate_id=e.appointment_id and tmpbilling2.othervariables>0
		inner join mst_otherduction mt on mt.id=tc.deduction_id
		and ( 
				(--tc.active='Y' and
				   coalesce(tc.includedinctc,'N')='Y' 
				  and coalesce(tc.isvariable,'N')='N'
				  and tc.deduction_id not in (7,10)
				  and tc.deduction_id<>134 --Meal Voucher ID, Must Change for Production
				  and tc.deduction_frequency in ('Quarterly','Half Yearly','Annually')
				  )
				or		
				(	
					--tc.active='Y' and
				    tc.deduction_amount>0
				  and tc.deduction_frequency in ('Monthly')
				  and tc.deduction_id not in (5,6,7,10)
				  and coalesce(tc.is_taxable,'N')='N'
				  and mt.id<>134 --Meal Voucher ID, Must Change for Production)
				  )
			)
		where tmpbilling2.salaryid=e.id and tmpbilling2.recordscreen<>'Increment Arear'
			)
		deductions_lat ON true
/************************************************/	
 where coalesce(salary_remarks,'')<>'Invalid Paid Days'
 group by employee,coalesce(nullif(tmpbilling2.disbursementmode,'Voucher'),mo.deduction_name)
		)
/*******Change 1.22**********/
,tmpmeal as
(
select emp_code as mealecode,sum(mealamount) mealvoucheramount from public.trnmealvoucher where isactive='1' and mealmonth=p_rptmonth and mealyear=p_rptyear group by emp_code
)
/*******Change 1.22**********/
		
select t1.*,case when mt.empid is null then 'Approved' else 'Hold' end as holdstatus
,t1.netpay-coalesce(tmpmeal.mealvoucheramount,0) as finalnetpay, coalesce(tmpmeal.mealvoucheramount,0) mealvoucheramount
from tmp t1 inner join openappointments op
on t1.employee=op.emp_code and op.customeraccountid=p_customeraccountid::bigint
left join managetemppausedsalary mt
on op.emp_id=mt.empid and mt.processmonth=p_rptmonth::int 
and mt.processyear=p_rptyear::int and mt.isactive='1' and mt.pausedstatus='Enable'
left join tmpmeal on tmpmeal.mealecode=t1.emp_code

 order by employee_name;
--Raise Notice 'Outside Liability Part3 at %',TIMEOFDAY();
	return next v_rfc;
	/**************Liability Code ends here ********************************/
end if;
end if;
/**************Billing Code Goes Below ********************************/
if p_action='GetMonthLiability' and p_reporttype='Billing'  then
   	open v_rfc for
select t1.* from (	
	select string_agg( distinct mon,',')	mon	,p_rptmonth mprmonth,p_rptyear mpryear,
	employee	employee	,
	max(cjcode) tpcode,
	max(orgempcode) orgempcode,
	max(employee_name)	employee_name	,
	max(father_husband_name)	father_husband_name	,
	max(tbljobrole.jobrole)	designation,
    max(posting_department) posting_department, max(jobtype) jobtype, max(unitparametername) unitparametername,
	max(department)	department	,
	max(subunit)	subunit	,
	max(dateofjoining)	dateofjoining	,
	max(dateofbirth)	dateofbirth	,
	string_agg( distinct esinumber,',')	esinumber	,
	string_agg( distinct pan_number,',')	pan_number	,
	string_agg( distinct uannumber,',')	uannumber	,
	string_agg( distinct email,',')	email	,
	max(dateofleaving)	dateofleaving	,
	SUM(arrear_days)	arrear_days	,
	greatest(max(case when mprmonth=p_rptmonth and mpryear=p_rptyear then monthdays else 0 end)-SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end),0)	loss_off_pay	,
	SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end)	total_paid_days	,
	max(tmprataes.ratebasic)	ratebasic	,
	max(tmprataes.ratehra)	ratehra	,
	max(tmprataes.rateconv)	rateconv	,
	max(tmprataes.ratemedical)	ratemedical	,
	max(tmprataes.ratespecial_allowance)	ratespecial_allowance	,
	max(tmprataes.fixedallowancestotalrate)	fixedallowancestotalrate	,
	SUM(basic)	basic	,
	SUM(hra)	hra	,
	SUM(conv)	conv	,
	SUM(medical)	medical	,
	SUM(specialallowance)	specialallowance	,
	SUM(arr_basic)	arr_basic	,
	SUM(arr_hra)	arr_hra	,
	SUM(arr_conv)	arr_conv	,
	SUM(arr_medical)	arr_medical	,
	SUM(arr_specialallowance)	arr_specialallowance	,
	SUM(incentive)	incentive	,
	SUM(refund)	refund	,
	SUM(monthly_bonus)	monthly_bonus,	
	SUM(grossearning)/*+coalesce(max(taxableledgerdeductions),0)*/	grossearning	,
    SUM(coalesce(epf,0)+coalesce(epf_arear,0)) AS epf,
    SUM(coalesce(vpf,0)+coalesce(vpf_arear,0)) AS vpf,
    SUM(coalesce(ESI,0)+coalesce(esi_arear,0)) AS esi,
    SUM(coalesce(tds,0)+coalesce(tds_arear,0)) AS tds,
	SUM(loan)	loan	,
	SUM(coalesce(lwf,0)+coalesce(lwf_arear,0))	lwf	,
	SUM(insurance)	insurance	,
	SUM(mobile)	mobile	,
	SUM(advance)	advance	,
	SUM(other)	other	,
	SUM(grossdeduction) /*+coalesce(max(taxableledgerdeductions),0)*/	grossdeduction	,
	SUM(netpay)	netpay	,
	SUM(ac_1)	ac_1	,
	SUM(ac_10)	ac_10	,
	SUM(ac_2)	ac_2	,
	max(tblac21.ac21temp)	ac21	,
	SUM(employer_esi_contr)	employer_esi_contr	,
	min(salarystatus)	salarystatus	,
	string_agg( distinct arearaddedmonths,',')	arearaddedmonths	,
	max(monthdays)	monthdays	,
	string_agg( distinct salaryid::text,',')	salaryid	,
	string_agg( distinct banktransferstatus,',')	banktransferstatus	,
	SUM(atds)	atds	,
	SUM(voucher_amount)	voucher_amount	,
	SUM(ews)	ews	,
	SUM(gratuity)	gratuity	,
	SUM(bonus)	bonus	,
	SUM(employeenps)	employeenps	,
	SUM(damagecharges)	damagecharges	,
	SUM(otherledgerarears)	otherledgerarears	,
	SUM(otherledgerdeductions)	otherledgerdeductions	,
	SUM(othervariables)	othervariables	,
	SUM(otherdeductions)	otherdeductions	,
	SUM(otherledgerarearwithoutesi)	otherledgerarearwithoutesi	,
	SUM(otherbonuswithesi)	otherbonuswithesi	,
	SUM(totalarear)	totalarear	,
	SUM(lwf_employer)	lwf_employer	,
	string_agg( distinct insurancetype,',')	insurancetype	,
	string_agg( distinct attendancemode,',')	attendancemode	
	,max(Employee_Name) Emp_Name
	,SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end) as paiddays
	,employee as emp_code
	,null::int emp_id
	,null rejectstatus
	,null reject_reason
	,max(father_husband_name) fathername
	,max(tbljobrole.jobrole) post_offered
	,max(department)	posting_department
	,string_agg( distinct pan_number,',') pancard
	,greatest(max(case when mprmonth=p_rptmonth and mpryear=p_rptyear then monthdays else 0 end)-SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end),0)	lossofpay	
	,max(tmprataes.ratespecial_allowance)	ratespecialallowance
	
	,coalesce(SUM(arr_basic),0)	ratebasic_arr
	,coalesce(SUM(arr_hra),0)	ratehra_arr
	,coalesce(SUM(arr_conv),0)	rateconv_arr
	,coalesce(SUM(arr_medical),0)	ratemedical_arr
	,coalesce(SUM(arr_specialallowance),0)	ratespecialallowance_arr
	,SUM(coalesce(ESI,0)+coalesce(esi_arear,0)) employeeesirate
	,sum(Employer_ESI_Contr) employeresirate
	,null::double precision incrementarear
	,null::double precision incrementarear_basic
	,null::double precision incrementarear_hra
	,null::double precision incrementarear_gross
	,max(salaryindaysopted) salaryindaysopted
	,max(salarydays) salarydays
	,null contractno
	,max(pfnumber) pfnumber
	,string_agg(distinct bankaccountno,',') bankaccountno
	,string_agg(distinct ifsccode,',') ifsccode
	,string_agg(distinct bankname,',') bankname
	,string_agg(distinct bankbranch,',') bankbranch
	,SUM(basic)+SUM(hra)+SUM(specialallowance)	fixedallowancestotal
	,max(ctc) ctc
	,coalesce(SUM(arr_basic),0)+coalesce(SUM(arr_hra),0)+coalesce(SUM(arr_conv),0)+coalesce(SUM(arr_medical),0)+coalesce(SUM(arr_specialallowance),0) netarear
	,coalesce(sum(otherledgerarear),0.0) as  otherledgerarear
	,sum(govt_bonus_amt) govt_bonus_amt
	,max(ctc) ctc
	,sum(coalesce(professionaltax,0)+coalesce(professionaltax_arear,0)) professionaltax
	,sum(loanrecovery) loanrecovery
	,sum(advancerecovery) advancerecovery
	
/*************************************************************/	
		,sum(salarybonus) salarybonus
		,sum(commission) commission
		,sum(transport_allowance) transport_allowance
		,sum(travelling_allowance) travelling_allowance
		,sum(leave_encashment) leave_encashment
		,sum(overtime_allowance) overtime_allowance
		,sum(notice_pay) notice_pay
		,sum(hold_salary_non_taxable) hold_salary_non_taxable
		,sum(children_education_allowance) children_education_allowance
		,sum(gratuityinhand) gratuityinhand
		,max(tmprataes.ratesalarybonus)  ratesalarybonus
		,max(tmprataes.ratecommission)  ratecommission
		,max(tmprataes.ratetransport_allowance)  ratetransport_allowance
		,max(tmprataes.ratetravelling_allowance)  ratetravelling_allowance
		,max(tmprataes.rateleave_encashment)  rateleave_encashment
		,max(tmprataes.rateovertime_allowance)  rateovertime_allowance
		,max(tmprataes.ratenotice_pay)  ratenotice_pay
		,max(tmprataes.ratehold_salary_non_taxable)  ratehold_salary_non_taxable
		,max(tmprataes.ratechildren_education_allowance)  ratechildren_education_allowance
		,max(tmprataes.rategratuityinhand)  rategratuityinhand
/*************************************************************/
		,sum(tea_allowance) tea_allowance
		,sum(charity_contribution_amount) charity_contribution_amount
 		-- START - CHANGES [1.17]
			,MAX(vendor_name) vendor_name,
			MAX(project_name) project_name,
			MAX(salary_book_project) salary_book_project,
			MAX(assigned_ou_names) assigned_ou_names
		-- END - CHANGES [1.17]
	,sum(employerepf) employerepf	
/***********Change 1.18 starts**********************/
	,MAX(rate_employerinsuranceamount) as rate_employerinsuranceamount
	,MAX(rate_employerlwf) as rate_employerlwf
	,MAX(rate_employerepf) as rate_employerepf
	,MAX(rate_employeresi) as rate_employeresirate
	,max(ctc) as masterctc
/***********Change 1.18 starts**********************/
	,sum(mealvoucher) mealvoucher
	,sum(mealvoucher_arear) mealvoucher_arear	
	,sum(arr_salarybonus) arr_salarybonus
	,sum(arr_commission) arr_commission
	,sum(arr_transport_allowance) arr_transport_allowance
	,sum(arr_travelling_allowance) arr_travelling_allowance
	,sum(arr_leave_encashment) arr_leave_encashment
	,sum(arr_overtime_allowance) arr_overtime_allowance
	,sum(arr_notice_pay) arr_notice_pay
	,sum(arr_hold_salary_non_taxable) arr_hold_salary_non_taxable
	,sum(arr_children_education_allowance) arr_children_education_allowance
	,sum(arr_gratuityinhand) arr_gratuityinhand
  
						  
						  
						  
						  
												  
   
 from tmpbilling2

	left join (select empcode,mpryear myear,mprmonth mmonth,max(jobrole) jobrole
			from cmsdownloadedwages
			where isactive='1' 
			group by empcode,mpryear,mprmonth) tbljobrole
				on tmpbilling2.employee=tbljobrole.empcode::bigint 
				and tmpbilling2.mpryear=tbljobrole.myear
				and tmpbilling2.mprmonth=tbljobrole.mmonth
	left join (select ep,sum(least(ac21temp,75)) ac21temp from(select employee ep,sum(ac21) ac21temp from tmpbilling2 where coalesce(salary_remarks,'')<>'Invalid Paid Days' group by ep,mprmonth,mpryear) tn1 group by  ep) tblac21
			on tmpbilling2.employee=tblac21.ep
 left join (select employee ep2,ratebasic,ratehra,rateconv,ratemedical,ratespecial_allowance,fixedallowancestotalrate
			,ratesalarybonus,ratecommission,ratetransport_allowance,ratetravelling_allowance,rateleave_encashment,rateovertime_allowance,ratenotice_pay,ratehold_salary_non_taxable,ratechildren_education_allowance,rategratuityinhand
			,row_number()over(partition by employee order by id desc) salrn
			from tmpbilling2 where coalesce(salary_remarks,'')<>'Invalid Paid Days' and tmpbilling2.recordscreen<>'Increment Arear') tmprataes
			on tmpbilling2.employee=tmprataes.ep2 and salrn=1		
	left join 
	(select emp_code ecode,sum(amount) taxableledgerdeductions
	from tbl_employeeledger
where tbl_employeeledger.isactive='1' 
	and processmonth=p_rptmonth 
	 and processyear=p_rptyear
	 and amount<0 
	 and headid<>12
	 and coalesce(is_taxable,'Y')='Y'
	 and coalesce(isledgerdisbursed,'0')='1'
group by emp_code) t2
on tmpbilling2.employee=t2.ecode 
 where coalesce(salary_remarks,'')<>'Invalid Paid Days'
 group by employee
	) t1 
	;
	return next v_rfc;
elsif p_action='GetDetailedLiability' and p_reporttype='Billing'  then
   	open v_rfc for
select t1.* from (	
	select string_agg( distinct mon,',')	mon	,p_rptmonth mprmonth,p_rptyear mpryear,
	employee	employee	,
	max(cjcode) tpcode,
	max(orgempcode) orgempcode,
	max(employee_name)	employee_name	,
	max(father_husband_name)	father_husband_name	,
	max(tbljobrole.jobrole)	designation,
    max(posting_department) posting_department, max(jobtype) jobtype, max(unitparametername) unitparametername,
	max(department)	department	,
	max(subunit)	subunit	,
	max(dateofjoining)	dateofjoining	,
	max(dateofbirth)	dateofbirth	,
	string_agg( distinct esinumber,',')	esinumber	,
	string_agg( distinct pan_number,',')	pan_number	,
	string_agg( distinct uannumber,',')	uannumber	,
	string_agg( distinct email,',')	email	,
	max(dateofleaving)	dateofleaving	,
	SUM(arrear_days)	arrear_days	,
	greatest(max(case when mprmonth=p_rptmonth and mpryear=p_rptyear then monthdays else 0 end)-SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end),0)	loss_off_pay	,
	SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end)	total_paid_days	,
	max(ratebasic)	ratebasic	,
	max(ratehra)	ratehra	,
	max(rateconv)	rateconv	,
	max(ratemedical)	ratemedical	,
	max(ratespecial_allowance)	ratespecial_allowance	,
	max(fixedallowancestotalrate)	fixedallowancestotalrate	,
	SUM(basic)	basic	,
	SUM(hra)	hra	,
	SUM(conv)	conv	,
	SUM(medical)	medical	,
	SUM(specialallowance)	specialallowance	,
	SUM(arr_basic)	arr_basic	,
	SUM(arr_hra)	arr_hra	,
	SUM(arr_conv)	arr_conv	,
	SUM(arr_medical)	arr_medical	,
	SUM(arr_specialallowance)	arr_specialallowance	,
	SUM(incentive)	incentive	,
	SUM(refund)	refund	,
	SUM(monthly_bonus)	monthly_bonus,	
	SUM(grossearning)/*+coalesce(max(taxableledgerdeductions),0)*/	grossearning	,
    SUM(coalesce(epf,0)+coalesce(epf_arear,0)) AS epf,
    SUM(coalesce(vpf,0)+coalesce(vpf_arear,0)) AS vpf,
    SUM(coalesce(ESI,0)+coalesce(esi_arear,0)) AS esi,
    SUM(coalesce(tds,0)+coalesce(tds_arear,0)) AS tds,
	SUM(loan)	loan	,
    SUM(coalesce(lwf,0)+coalesce(lwf_arear,0)) AS lwf,
	SUM(insurance)	insurance	,
	SUM(mobile)	mobile	,
	SUM(advance)	advance	,
	SUM(other)	other	,
	SUM(grossdeduction) /*+coalesce(max(taxableledgerdeductions),0)*/	grossdeduction	,
	SUM(netpay)	netpay	,
	SUM(ac_1)	ac_1	,
	SUM(ac_10)	ac_10	,
	SUM(ac_2)	ac_2	,
	max(tblac21.ac21temp)	ac21	,
	SUM(employer_esi_contr)	employer_esi_contr	,
	min(salarystatus)	salarystatus	,
	string_agg( distinct arearaddedmonths,',')	arearaddedmonths	,
	max(monthdays)	monthdays	,
	string_agg( distinct salaryid::text,',')	salaryid	,
	string_agg( distinct banktransferstatus,',')	banktransferstatus	,
	SUM(atds)	atds	,
	SUM(voucher_amount)	voucher_amount	,
	SUM(ews)	ews	,
	SUM(gratuity)	gratuity	,
	SUM(bonus)	bonus	,
	SUM(employeenps)	employeenps	,
	SUM(damagecharges)	damagecharges	,
	SUM(otherledgerarears)	otherledgerarears	,
	SUM(otherledgerdeductions)	otherledgerdeductions	,
	SUM(othervariables)	othervariables	,
	SUM(otherdeductions)	otherdeductions	,
	SUM(otherledgerarearwithoutesi)	otherledgerarearwithoutesi	,
	SUM(otherbonuswithesi)	otherbonuswithesi	,
	SUM(totalarear)	totalarear	,
	SUM(lwf_employer)	lwf_employer	,
	string_agg( distinct insurancetype,',')	insurancetype	,
	string_agg( distinct attendancemode,',')	attendancemode	
	,max(Employee_Name) Emp_Name
	,SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end) as paiddays
	,employee as emp_code
	,null::int emp_id
	,null rejectstatus
	,null reject_reason
	,max(father_husband_name) fathername
	,max(tbljobrole.jobrole) post_offered
	,max(department)	posting_department
	,string_agg( distinct pan_number,',') pancard
	,greatest(max(case when mprmonth=p_rptmonth and mpryear=p_rptyear then monthdays else 0 end)-SUM(case when mprmonth=p_rptmonth and mpryear=p_rptyear then total_paid_days else 0 end),0)	lossofpay	
	,max(ratespecial_allowance)	ratespecialallowance
	
	,coalesce(SUM(arr_basic),0)	ratebasic_arr
	,coalesce(SUM(arr_hra),0)	ratehra_arr
	,coalesce(SUM(arr_conv),0)	rateconv_arr
	,coalesce(SUM(arr_medical),0)	ratemedical_arr
	,coalesce(SUM(arr_specialallowance),0)	ratespecialallowance_arr
	,SUM(coalesce(ESI,0)+coalesce(esi_arear,0)) employeeesirate
	,sum(Employer_ESI_Contr) employeresirate
	,null::double precision incrementarear
	,null::double precision incrementarear_basic
	,null::double precision incrementarear_hra
	,null::double precision incrementarear_gross
	,max(salaryindaysopted) salaryindaysopted
	,max(salarydays) salarydays
	,null contractno
	,max(pfnumber) pfnumber
	,string_agg(distinct bankaccountno,',') bankaccountno
	,string_agg(distinct ifsccode,',') ifsccode
	,string_agg(distinct bankname,',') bankname
	,string_agg(distinct bankbranch,',') bankbranch
	,SUM(basic)+SUM(hra)+SUM(specialallowance)	fixedallowancestotal
	,max(ctc) ctc
	,coalesce(SUM(arr_basic),0)+coalesce(SUM(arr_hra),0)+coalesce(SUM(arr_conv),0)+coalesce(SUM(arr_medical),0)+coalesce(SUM(arr_specialallowance),0) netarear
	,coalesce(sum(otherledgerarear),0.0) as  otherledgerarear
	,sum(govt_bonus_amt) govt_bonus_amt
	,max(ctc) ctc
	,sum(coalesce(professionaltax,0)+coalesce(professionaltax_arear,0)) professionaltax
	,sum(loanrecovery) loanrecovery
	,sum(advancerecovery) advancerecovery
	/****************************************************************/
	,sum(tea_allowance) tea_allowance
,sum(salarybonus) salarybonus
,sum(commission) commission
,sum(transport_allowance) transport_allowance
,sum(travelling_allowance) travelling_allowance
,sum(leave_encashment) leave_encashment
,sum(overtime_allowance) overtime_allowance
,sum(notice_pay) notice_pay
,sum(hold_salary_non_taxable) hold_salary_non_taxable
,sum(children_education_allowance) children_education_allowance
,sum(gratuityinhand) gratuityinhand
,max(ratesalarybonus)  ratesalarybonus
,max(ratecommission)  ratecommission
,max(ratetransport_allowance)  ratetransport_allowance
,max(ratetravelling_allowance)  ratetravelling_allowance
,max(rateleave_encashment)  rateleave_encashment
,max(rateovertime_allowance)  rateovertime_allowance
,max(ratenotice_pay)  ratenotice_pay
,max(ratehold_salary_non_taxable)  ratehold_salary_non_taxable
,max(ratechildren_education_allowance)  ratechildren_education_allowance
,max(rategratuityinhand)  rategratuityinhand
,sum(charity_contribution_amount) charity_contribution_amount
-- START - CHANGES [1.17]
,MAX(vendor_name) vendor_name,
MAX(project_name) project_name,
MAX(salary_book_project) salary_book_project,
MAX(assigned_ou_names) assigned_ou_names
    -- END - CHANGES [1.17]
	,sum(employerepf) employerepf
/***********Change 1.18 starts**********************/
	,MAX(rate_employerinsuranceamount) as rate_employerinsuranceamount
	,MAX(rate_employerlwf) as rate_employerlwf
	,MAX(rate_employerepf) as rate_employerepf
	,MAX(rate_employeresi) as rate_employeresirate
	,max(ctc) as masterctc
/***********Change 1.18 starts**********************/	
	,sum(mealvoucher) mealvoucher
	,sum(mealvoucher_arear) mealvoucher_arear	
/****************************************************************/  	
	,sum(arr_salarybonus) arr_salarybonus
	,sum(arr_commission) arr_commission
	,sum(arr_transport_allowance) arr_transport_allowance
	,sum(arr_travelling_allowance) arr_travelling_allowance
	,sum(arr_leave_encashment) arr_leave_encashment
	,sum(arr_overtime_allowance) arr_overtime_allowance
	,sum(arr_notice_pay) arr_notice_pay
	,sum(arr_hold_salary_non_taxable) arr_hold_salary_non_taxable
	,sum(arr_children_education_allowance) arr_children_education_allowance
	,sum(arr_gratuityinhand) arr_gratuityinhand
  
						 
						 
						 
						 
												 
   
 from tmpbilling2
	left join (select empcode,mpryear myear,mprmonth mmonth,max(jobrole) jobrole
			from cmsdownloadedwages
			where isactive='1' 
			group by empcode,mpryear,mprmonth) tbljobrole
				on tmpbilling2.employee=tbljobrole.empcode::bigint 
				and tmpbilling2.mpryear=tbljobrole.myear
				and tmpbilling2.mprmonth=tbljobrole.mmonth
	--left join (select ep,sum(least(ac21temp,75)) ac21temp from(select employee ep,sum(ac21) ac21temp from tmpbilling2 where coalesce(salary_remarks,'')<>'Invalid Paid Days' group by ep,mprmonth,mpryear) tn1 group by  ep) tblac21
	--		on tmpbilling2.employee=tblac21.ep
	left join (select ep,tn1.id,sum(least(ac21temp,75)) ac21temp from(select employee ep,sum(ac21) ac21temp,tmpbilling2.id from tmpbilling2 where coalesce(salary_remarks,'')<>'Invalid Paid Days' group by ep,mprmonth,mpryear,tmpbilling2.id) tn1 group by  ep,tn1.id) tblac21
            on tmpbilling2.employee=tblac21.ep and tmpbilling2.id=tblac21.id
	left join 
	(select emp_code ecode,sum(amount) taxableledgerdeductions
	from tbl_employeeledger
where tbl_employeeledger.isactive='1' 
	and processmonth=p_rptmonth 
	 and processyear=p_rptyear
	 and amount<0 
	 and headid<>12
	 and coalesce(is_taxable,'Y')='Y'
	 and coalesce(isledgerdisbursed,'0')='1'
group by emp_code) t2
on tmpbilling2.employee=t2.ecode 
 where coalesce(salary_remarks,'')<>'Invalid Paid Days'
 group by employee,tmpbilling2.id
	) t1 
	;
	return next v_rfc;
end if;
	/**************Billing Code ends here ********************************/
---------------------------------------------------------------------------
IF p_reporttype <> 'Phase3Billing' THEN		
   	open v_rfctotalattendance for
	select 0 totalattendancecount,
	       0 as multiperformercount,
		   0 nonmultiperformercount,
		   
		   0 processedasarear,
		   0 processedascurrent,
		   0 processedasprevious,
		   0 uniquemultipermerbatch,0 uniquenonmultipermerbatch
		   ,v_message as compilereportmessage;
	return next v_rfctotalattendance;
END IF;	

end if;

end;
$BODY$;

ALTER FUNCTION public.uspmonthwiseiablityreport(integer, integer, text, bigint, text, character varying, character varying, character varying, character varying, character varying, integer, text, text, text, character varying)
    OWNER TO payrollingdb;

