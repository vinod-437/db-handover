-- FUNCTION: public.uspepfecrreport(integer, integer, character varying, bigint, character varying, character varying, integer, text, text, character varying)

-- DROP FUNCTION IF EXISTS public.uspepfecrreport(integer, integer, character varying, bigint, character varying, character varying, integer, text, text, character varying);

CREATE OR REPLACE FUNCTION public.uspepfecrreport(
	p_rpt_month integer,
	p_rpt_year integer,
	p_action character varying DEFAULT NULL::character varying,
	p_downloadedby bigint DEFAULT NULL::bigint,
	p_downloadedbyip character varying DEFAULT NULL::character varying,
	p_reporttype character varying DEFAULT 'EPF'::character varying,
	p_lwfstatecode integer DEFAULT 7,
	p_tptype text DEFAULT 'NonTP'::text,
	p_customeraccountid text DEFAULT '-9999'::text,
	p_ou_ids character varying DEFAULT NULL::character varying)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
	declare 
	  rfcreport refcursor;
	  v_reporttimestamp timestamp;
	  v_reportquery text;
	  v_challanfrom text;
	  v_challanto text;
	  v_currentmonth int;
	  v_currentyear int;
	  v_totalmonthdays numeric(18,2);
		begin

/*************************************************************************
Version 	Date			Change								Done_by
1.1			03-Sep-2022		Non ESIC Voucher Exclusion			Shiv Kumar
1.2         23-Oct-2023     Adding filter for 
							customeraccountid 					Siddharth Bansal
1.3         13-03-2024		Adding customeraccount id
							condition 							Siddharth Bansal
							in action
1.4         18-Apr-2024     Handling Variable Amount			Shiv Kumar
							(as per mail dated 13-Apr-2024)
1.5 		06-Aug-2024		OuId Changes						Siddharth Bansal
1.6 		23-Aug-2024		tpcode and orgempcode changes		Siddharth Bansal
1.7 		14-Aug-2025		Reduce Joining Days from NCP days	Shiv Kumar
							in EPF Report
**************************************************************************/
select extract ('day' from make_date(p_rpt_year,p_rpt_month,1)+interval '1 month -1 day') into v_totalmonthdays;
		if p_reporttype='LWF'then	
			 select challanfrom,challanto
			 into v_challanfrom,v_challanto
			 from mst_lwfchallanperiod
			 where statecode=p_lwfstatecode
			 and challanmonth=p_rpt_month;
			
		v_challanfrom:=replace(replace(v_challanfrom,'currentyear',p_rpt_year::text),'lastyear',(p_rpt_year-1)::text);
		v_challanto:=replace(replace(v_challanto,'currentyear',p_rpt_year::text),'lastyear',(p_rpt_year-1)::text);
		end if;
		if p_action='DisplayReport' then
		v_reportquery:='select o.emp_id appointment_id,'||p_rpt_month||' rpt_month,'||p_rpt_year||' rpt_year,	
			o.uannumber uan,o.emp_name member_name,o.emp_code,e.batchid,o.cjcode tpcode,o.orgempcode,';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'
			round(e.gross::numeric(18,2),2) gross_wages,
			round(e.basic::numeric(18,2),2) epf_wages,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(e.basic,15000)::numeric(18,2),2) else 0.0 end eps_wages,
			round(least(e.basic,15000)::numeric(18,2),2) edli_wages,
			round((epf_contri_remitted+coalesce(e.vpf,0))::numeric(18,2),2) epf_contri_remitted,
--			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(eps_contri_remitted,1250)::numeric(18,2),2) else 0.0 end  eps_contri_remitted,
--			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round((epf_eps_diff_remitted+(greatest(eps_contri_remitted-least(eps_contri_remitted,1250),0)))::numeric(18,2),2) else round((coalesce(epf_eps_diff_remitted,0)+coalesce(eps_contri_remitted,0))::numeric(18,2),2) end epf_eps_diff_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(eps_contri_remitted::numeric(18,2),0) else 0.0 end  eps_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round((epf_eps_diff_remitted+(eps_contri_remitted-round(eps_contri_remitted::numeric(18,2),0)))::numeric(18,2),0) else round((coalesce(epf_eps_diff_remitted,0)+coalesce(eps_contri_remitted,0))::numeric(18,2),0) end epf_eps_diff_remitted,
			case when '''||p_reporttype||'''<>''EPF'' or o.dateofjoining<=make_date('||p_rpt_year||','||p_rpt_month||',1)  then monthdays-paiddays
			else 
			least(monthdays,'||v_totalmonthdays||'-(extract(''day'' from o.dateofjoining)::int-1)) -(paiddays) end as ncp_days,
			0 refund_of_advances
			,e.wagestatus
			,o.esinumber
			,ceil(e.esic_amt) esic_amt
			,e.lastworkingday, ';
		end if;		
		v_reportquery:=v_reportquery||'
			o.fathername
            ,o.posting_location emplocation
			,to_char(o.dateofjoining,''dd-mm-yyyy'') doj
			,e.employeelwf
			,e.employerlwf
			,e.totallwf';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'
			,e.address
			,'''||p_reporttype||''' reporttype
			,e.vpf
			,monthdays 
			,round(grossearning::numeric(18,2),0) grossearning
			 , govt_bonus_amt
			 , otherbonuswithesi
			 , totalarear
			 , otherledgerarears
			 , ROUND(gross_esi_income::numeric(18,2),0) gross_esi_income';
		end if;		
		v_reportquery:=v_reportquery||'
			from public.openappointments o inner join 
--------------------------------------------------------------------------			
			(select emp_code,string_agg(batchid,'','') batchid,';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'
			case when sum(epf_contri_remitted)=1800 then 15000 else sum(basic) end basic,
			 sum(gross) gross
			 ,''Processed'' wagestatus
			 ,sum(epf_contri_remitted) epf_contri_remitted
			 ,sum(eps_contri_remitted) eps_contri_remitted
			 ,sum(epf_eps_diff_remitted) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(esic_amt) esic_amt
			 ,max(lastworkingday) lastworkingday,';
		end if;
		v_reportquery:=v_reportquery||'
			 sum(employeelwf) employeelwf
			 ,sum(employerlwf) employerlwf
			 ,sum(totallwf) totallwf ';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'
			 ,max(address) address
			 ,sum(vpf) vpf
			  ,max(monthdays) monthdays 
			 ,sum(grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(gross_esi_income) gross_esi_income';
		end if;	
		v_reportquery:=v_reportquery||'
			 from 
---------------------------------------------------------------------------			 
			(select t.emp_code,string_agg(t.batchid,'','') batchid,';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'sum(t.basic) basic,
			 sum(t.fixedallowancestotal) gross
			 ,''Processed'' wagestatus
			 ,sum(epf) epf_contri_remitted
			 ,sum(Ac_10) eps_contri_remitted
			 ,sum(Ac_1) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(t.employeeesirate+coalesce(incrementarear_employeeesi,0)) esic_amt
			 ,max(dateofleaving) lastworkingday,';
		end if;		
		v_reportquery:=v_reportquery||'
			 sum(lwf_employee) employeelwf
			 ,sum(lwf_employer) employerlwf
			 ,sum(coalesce(lwf_employee,0)+coalesce(lwf_employer,0)) totallwf';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'
			 ,max(residential_address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(t.grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(coalesce(nullif(t.esiapplicablecomponents,0.0)+coalesce(otherledgerarears,0),t.grossearning-othernonesicparts,0)+coalesce(t2.GrossEarning,0)-(coalesce(t.otherdeductions,0)+coalesce(t2.otherdeductions,0))) gross_esi_income';
		end if;		
		v_reportquery:=v_reportquery||'
			 	from  (
				select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate,coalesce(nullif(tbl_monthlysalary.pfapplicablecomponents,0),tbl_monthlysalary.basic,0) basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, 																					  recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid ,esiapplicablecomponents 
				,coalesce(conv,0)+coalesce(travelling_allowance,0)+coalesce(leave_encashment,0)+coalesce(notice_pay,0)+coalesce(hold_salary_non_taxable,0)+coalesce(gratuityinhand,0)+coalesce(salarybonus,0) othernonesicparts
				from tbl_monthlysalary
				where coalesce(is_rejected,''0'')<>''1'' and tbl_monthlysalary.recordscreen in(''Current Wages'' ,''Previous Wages'',''Increment Arear'')
				and coalesce(tbl_monthlysalary.istaxapplicable,''1'')=''1'' 
				and (tbl_monthlysalary.emp_code,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mprmonth else tbl_monthlysalary.arearprocessmonth end,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mpryear else tbl_monthlysalary.arearprocessyear end,tbl_monthlysalary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	

				union all
				select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate,coalesce(nullif(tbl_monthly_liability_salary.pfapplicablecomponents,0),tbl_monthly_liability_salary.basic,0) basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, case when recordscreen=''Arear Wages'' then ''Previous Wages'' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid ,esiapplicablecomponents 
				,0 othernonesicparts
				from tbl_monthly_liability_salary
				where coalesce(tbl_monthly_liability_salary.is_rejected,''0'')<>''1'' and coalesce(salary_remarks,'''')<>''Invalid Paid Days''
				and (tbl_monthly_liability_salary.emp_code,tbl_monthly_liability_salary.mprmonth,tbl_monthly_liability_salary.mpryear,tbl_monthly_liability_salary.batchid)
				 not in (select tbl_monthlysalary_3.emp_code,tbl_monthlysalary_3.mprmonth,tbl_monthlysalary_3.mpryear,tbl_monthlysalary_3.batchid from tbl_monthlysalary tbl_monthlysalary_3 where tbl_monthlysalary_3.is_rejected = ''0''::"bit")
				and (tbl_monthly_liability_salary.emp_code,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mprmonth else tbl_monthly_liability_salary.arearprocessmonth end,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mpryear else tbl_monthly_liability_salary.arearprocessyear end,tbl_monthly_liability_salary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
	
				)
				t ';
				v_reportquery:=v_reportquery||'	left join 
						(select emp_code,sum(
							case when recordscreen=''Increment Arear'' and employee_esi_incentive>0 and fixedallowancestotal<0 then
								(coalesce(er.esiapplicablecomponents,fixedallowancestotalrate)*paiddays/monthdays)
							else coalesce(nullif(tbl_monthlysalary.esiapplicablecomponents,0.0),tbl_monthlysalary.grossearning) end) grossearning
											,sum(otherdeductions) otherdeductions
											,sum(othervariables) othervariables
						from public.tbl_monthlysalary
						 inner join empsalaryregister er on tbl_monthlysalary.salaryid=er.id
						 where recordscreen in (''Arear Wages'',''Increment Arear'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						and coalesce(is_rejected,''0'')<>''1''
						group by emp_code) t2
						on t.emp_code=t2.emp_code
						and t.arearaddedmonths is not null';
				
			v_reportquery:=v_reportquery||'	where ';
			if p_reporttype<>'LWF' then		
-- 				v_reportquery:=v_reportquery||' t.mprmonth='||p_rpt_month||'
-- 					and t.mpryear='||p_rpt_year||' and ';

					if p_reporttype='ESIC'then	
						v_reportquery:=v_reportquery||' 
						(
						(t.mprmonth='||p_rpt_month||' and t.mpryear='||p_rpt_year||' and t.recordscreen=''Current Wages'')
						or
						(t.arearprocessmonth='||p_rpt_month||' and t.arearprocessyear='||p_rpt_year||' and t.recordscreen=''Previous Wages'')
						)
						and ';
					else
									v_reportquery:=v_reportquery||' t.mprmonth='||p_rpt_month||'
										and t.mpryear='||p_rpt_year||' and ';
					end if;					
			end if;	
			v_reportquery:=v_reportquery||' coalesce(t.is_rejected,''0'')<>''1''
			        and (recordscreen,coalesce(isarear,''N'')) not in (select ''Current Wages'',''Y'')
			';
			 	if p_reporttype='EPF'then	
			 		v_reportquery:=v_reportquery||' and epf<>0 ';
				end if;
				if p_reporttype='ESIC'then	
			 		v_reportquery:=v_reportquery||' and t.employeeesirate<>0 ';
				end if;
				if p_reporttype='LWF'then	
						v_reportquery:=v_reportquery||' and lwf_employee>0 ';
						v_reportquery:=v_reportquery||' and to_date(''01''||lpad(t.mprmonth::text,2,''0'')||t.mpryear::text,''ddmmyyyy'')  between to_date('''||v_challanfrom ||''',''dd-mon-yyyy'') and to_date('''||v_challanto ||''',''dd-mon-yyyy'')';
						v_reportquery:=v_reportquery||' and coalesce(t.lwfstatecode,7)='||p_lwfstatecode||' ';
				end if;
		    v_reportquery:=v_reportquery||' and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||'  and r.isactive=''1'')	
			group by t.emp_code,t.batchid
union all
		select t.emp_code,'''' batchid,';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'0 basic,
			  0 gross
			 ,''Processed'' wagestatus
			 ,0 epf_contri_remitted
			 ,0 eps_contri_remitted
			 ,0 epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,0 esic_amt
			 ,null lastworkingday,';
		end if;	
		v_reportquery:=v_reportquery||'
			 sum(lwf_employee) employeelwf
			 ,sum(lwf_employer) employerlwf
			 ,sum(coalesce(lwf_employee,0)+coalesce(lwf_employer,0)) totallwf';
		if p_reporttype<>'LWF' then		
		v_reportquery:=v_reportquery||'
			 ,'''' address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,0 grossearning 
			 ,0 govt_bonus_amt
			 ,0 otherbonuswithesi
			 ,0 totalarear
			 ,0 otherledgerarears
			 ,0 gross_esi_income';
		end if;	
		v_reportquery:=v_reportquery||'
			 	from  (
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, 																					  recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid 
					from tbl_monthlysalary
					where coalesce(is_rejected,''0'')<>''1'' and tbl_monthlysalary.recordscreen in(''Current Wages'' ,''Previous Wages'')
				and coalesce(tbl_monthlysalary.istaxapplicable,''1'')=''1'' 
				and (tbl_monthlysalary.emp_code,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mprmonth else tbl_monthlysalary.arearprocessmonth end,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mpryear else tbl_monthlysalary.arearprocessyear end,tbl_monthlysalary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	

					union all
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, case when recordscreen=''Arear Wages'' then ''Previous Wages'' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid
					from tbl_monthly_liability_salary
					where coalesce(tbl_monthly_liability_salary.is_rejected,''0'')<>''1'' and coalesce(salary_remarks,'''')<>''Invalid Paid Days''
					and (tbl_monthly_liability_salary.emp_code,tbl_monthly_liability_salary.mprmonth,tbl_monthly_liability_salary.mpryear,tbl_monthly_liability_salary.batchid)
					 not in (select tbl_monthlysalary_3.emp_code,tbl_monthlysalary_3.mprmonth,tbl_monthlysalary_3.mpryear,tbl_monthlysalary_3.batchid from tbl_monthlysalary tbl_monthlysalary_3 where tbl_monthlysalary_3.is_rejected = ''0''::"bit")
				and (tbl_monthly_liability_salary.emp_code,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mprmonth else tbl_monthly_liability_salary.arearprocessmonth end,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mpryear else tbl_monthly_liability_salary.arearprocessyear end,tbl_monthly_liability_salary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
	
				)
				t
						where ';		
			if p_reporttype<>'LWF' then		
				v_reportquery:=v_reportquery||' t.mprmonth='||p_rpt_month||'
					and t.mpryear='||p_rpt_year||' and ';
			end if;	
			v_reportquery:=v_reportquery||' coalesce(t.is_rejected,''0'')<>''1''
					and (recordscreen,coalesce(isarear,''N'')) in (select ''Current Wages'',''Y'')
					';
			 	if p_reporttype='EPF'then	
			 		v_reportquery:=v_reportquery||' and epf>0 ';
				end if;
				if p_reporttype='ESIC'then	
			 		v_reportquery:=v_reportquery||' and t.employeeesirate<>0 ';
				end if;
				if p_reporttype='LWF'then	
						v_reportquery:=v_reportquery||' and lwf_employee>0 ';
						v_reportquery:=v_reportquery||' and to_date(''01''||lpad(t.mprmonth::text,2,''0'')||t.mpryear::text,''ddmmyyyy'')  between to_date('''||v_challanfrom ||''',''dd-mon-yyyy'') and to_date('''||v_challanto ||''',''dd-mon-yyyy'')';
						v_reportquery:=v_reportquery||' and coalesce(lwfstatecode,7)='||p_lwfstatecode||' ';
				end if;
		    v_reportquery:=v_reportquery||' and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select m.emp_code,m.rpt_month,m.rpt_year,m.batchid from unprocessed_epfecrreport m where m.rpt_month='||p_rpt_month||' and m.rpt_year='||p_rpt_year||')	
			and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||'  and r.isactive=''1'')	
			group by t.emp_code,t.batchid
			) e1
	---------------------------------------------
	group by emp_code
	)e
	------------------------------------------------
			on o.emp_code=e.emp_code
			and o.appointment_status_id<>13
			and o.customeraccountid=coalesce(nullif('||p_customeraccountid||',''-9999'')::bigint,o.customeraccountid)
			AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF('''||p_ou_ids||''', ''''), COALESCE(NULLIF(o.assigned_ou_ids, ''''), COALESCE(NULLIF(o.geofencingid::TEXT, ''''), ''0''))), '','')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(o.assigned_ou_ids, ''''), COALESCE(NULLIF(o.geofencingid::TEXT, ''''), ''0'')), '',''))
			) 
			and o.recordsource= case when '''||p_tptype||'''=''TP'' then ''HUBTPCRM'' else nullif(o.recordsource,''HUBTPCRM'') end
			and (o.emp_code,'||p_rpt_month||','||p_rpt_year||',e.batchid,'''||p_reporttype||''')
			not in (select m.emp_code,m.rpt_month,m.rpt_year,m.batchid,m.reporttype from epfecrreport m where m.rpt_month='||p_rpt_month||' and m.rpt_year='||p_rpt_year||'  and m.isactive=''1'')';

			
			open rfcreport for execute v_reportquery;
			return rfcreport;
		end if;
		if p_action='DownloadReport' then
			
			v_reporttimestamp:=current_timestamp;
			v_reportquery:='INSERT INTO public.epfecrreport(
				appointment_id, rpt_month, rpt_year, uan, member_name,';		
			if p_reporttype<>'LWF' then		
				v_reportquery:=v_reportquery||' 
				gross_wages, epf_wages,
				eps_wages, edli_wages, epf_contri_remitted, eps_contri_remitted,
				epf_eps_diff_remitted, ncp_days, refund_of_advances, ';		
			end if;	
				v_reportquery:=v_reportquery||' 
				created_by, createdon, createdbyip,emp_code,batchid,';		
			if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 
				wagestatus,esicnumber,esic_amt,lastworkingday,	';	
			end if;		
				v_reportquery:=v_reportquery||' 
				fathername,emplocation,doj,employeelwf,employerlwf,totallwf';		
			if p_reporttype<>'LWF' then		
				v_reportquery:=v_reportquery||' 
				,address';
			end if;	
			v_reportquery:=v_reportquery||' ,reporttype';
			if p_reporttype<>'LWF' then	
				v_reportquery:=v_reportquery||' 
				,vpf,monthdays,gross_earning,
					govt_bonus_amt,otherbonuswithesi,totalarear,otherledgerarears,gross_esi_income';
			end if;	
		v_reportquery:=v_reportquery||' 	)
			select o.emp_id appointment_id,'||p_rpt_month||' rpt_month,'||p_rpt_year||' rpt_year,	
			o.uannumber uan,o.emp_name member_name,';		
			if p_reporttype<>'LWF' then	
				v_reportquery:=v_reportquery||' 
				round(e.gross::numeric(18,2),2) gross_wages,
				round(e.basic::numeric(18,2),2) epf_wages,
				case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then least(e.basic,15000) else 0.0 end eps_wages,
				round(least(e.basic,15000)::numeric(18,2),2) edli_wages,
				round((epf_contri_remitted+coalesce(e.vpf,0))::numeric(18,2),2) epf_contri_remitted,
--				case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(eps_contri_remitted,1250)::numeric(18,2),2) else 0.0 end  eps_contri_remitted,
--				case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then (epf_eps_diff_remitted+(greatest(eps_contri_remitted-least(eps_contri_remitted,1250),0)))::numeric(18,2) else round((coalesce(epf_eps_diff_remitted,0)+coalesce(eps_contri_remitted,0))::numeric(18,2),2) end  epf_eps_diff_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(eps_contri_remitted::numeric(18,2),0) else 0.0 end  eps_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round((epf_eps_diff_remitted+(eps_contri_remitted-round(eps_contri_remitted::numeric(18,2),0)))::numeric(18,2),0) else round((coalesce(epf_eps_diff_remitted,0)+coalesce(eps_contri_remitted,0))::numeric(18,2),0) end epf_eps_diff_remitted,
				case when '''||p_reporttype||'''=''EPF'' then monthdays-paiddays else paiddays end ncp_days,
				0 refund_of_advances,';		
			end if;
			v_reportquery:=v_reportquery
			||p_downloadedby||','''
			||v_reporttimestamp||''','''
			||p_downloadedbyip||''',
			o.emp_code,e.batchid,';		
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 
			e.wagestatus
			,o.esinumber
			,e.esic_amt esic_amt
			,e.lastworkingday,';		
		end if;
			v_reportquery:=v_reportquery||' 
			 o.fathername
            ,o.posting_location emplocation
			,o.dateofjoining doj
			,e.employeelwf
			,e.employerlwf
			,e.totallwf';		
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 
			,e.address ';
		end if;	
		v_reportquery:=v_reportquery||' 
			,'''||p_reporttype||''' reporttype ';	
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 	
			,e.vpf
			,monthdays 
			,grossearning
			 , govt_bonus_amt
			 , otherbonuswithesi
			 , totalarear
			 , otherledgerarears
			 ,ROUND(gross_esi_income::numeric(18,2),0) gross_esi_income ';
		end if;	 
		v_reportquery:=v_reportquery||' 
			from public.openappointments o inner join 
			--------------------------------------------------------------------------			
			(select emp_code,string_agg(batchid,'','') batchid,';		
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 
			case when sum(epf_contri_remitted)=1800 then 15000 else sum(basic) end basic,
			 sum(gross) gross
			 ,''Processed'' wagestatus
			 ,sum(epf_contri_remitted) epf_contri_remitted
			 ,sum(eps_contri_remitted) eps_contri_remitted
			 ,sum(epf_eps_diff_remitted) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(esic_amt) esic_amt
			 ,max(lastworkingday) lastworkingday,';		
		end if;
			v_reportquery:=v_reportquery||' 
			 sum(employeelwf) employeelwf
			 ,sum(employerlwf) employerlwf
			 ,sum(totallwf) totallwf';		
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 
			 ,max(address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(gross_esi_income) gross_esi_income';		
		end if;
			v_reportquery:=v_reportquery||' 
			 from
---------------------------------------------------------------------------		
			(select t.emp_code,string_agg(t.batchid,'','') batchid,';		
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' sum(t.basic) basic,
			 sum(t.fixedallowancestotal) gross
			 ,''Processed'' wagestatus
			 ,sum(epf) epf_contri_remitted
			 ,sum(Ac_10) eps_contri_remitted
			 ,sum(Ac_1) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(t.employeeesirate+coalesce(t.incrementarear_employeeesi,0) ) esic_amt
			 ,max(dateofleaving) lastworkingday,';		
		end if;
			v_reportquery:=v_reportquery||' 
			 sum(lwf_employee) employeelwf
			 ,sum(lwf_employer) employerlwf
			 ,sum(coalesce(lwf_employee,0)+coalesce(lwf_employer,0)) totallwf';		
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 
			 ,max(residential_address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(t.grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(coalesce(nullif(t.esiapplicablecomponents,0.0)+coalesce(otherledgerarears,0),t.grossearning-othernonesicparts,0)+coalesce(t2.GrossEarning,0)-(coalesce(t.otherdeductions,0)+coalesce(t2.otherdeductions,0))) gross_esi_income';
		end if;
			v_reportquery:=v_reportquery||' 
			 				 	from  (
				select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate,coalesce(nullif(tbl_monthlysalary.pfapplicablecomponents,0),tbl_monthlysalary.basic,0) basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, 																					  recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid ,esiapplicablecomponents 
				,coalesce(conv,0)+coalesce(travelling_allowance,0)+coalesce(leave_encashment,0)+coalesce(notice_pay,0)+coalesce(hold_salary_non_taxable,0)+coalesce(gratuityinhand,0)+coalesce(salarybonus,0) othernonesicparts
				from tbl_monthlysalary
				where coalesce(is_rejected,''0'')<>''1'' and tbl_monthlysalary.recordscreen in(''Current Wages'' ,''Previous Wages'',''Increment Arear'')
				and coalesce(tbl_monthlysalary.istaxapplicable,''1'')=''1'' 
				and (tbl_monthlysalary.emp_code,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mprmonth else tbl_monthlysalary.arearprocessmonth end,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mpryear else tbl_monthlysalary.arearprocessyear end,tbl_monthlysalary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
				union all
				select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate,coalesce(nullif(tbl_monthly_liability_salary.pfapplicablecomponents,0),tbl_monthly_liability_salary.basic,0) basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, case when recordscreen=''Arear Wages'' then ''Previous Wages'' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid ,esiapplicablecomponents 
				,0 othernonesicparts
				from tbl_monthly_liability_salary
				where coalesce(tbl_monthly_liability_salary.is_rejected,''0'')<>''1'' and coalesce(salary_remarks,'''')<>''Invalid Paid Days''
				and (tbl_monthly_liability_salary.emp_code,tbl_monthly_liability_salary.mprmonth,tbl_monthly_liability_salary.mpryear,tbl_monthly_liability_salary.batchid)
				 not in (select tbl_monthlysalary_3.emp_code,tbl_monthlysalary_3.mprmonth,tbl_monthlysalary_3.mpryear,tbl_monthlysalary_3.batchid from tbl_monthlysalary tbl_monthlysalary_3 where tbl_monthlysalary_3.is_rejected = ''0''::"bit")
				and (tbl_monthly_liability_salary.emp_code,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mprmonth else tbl_monthly_liability_salary.arearprocessmonth end,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mpryear else tbl_monthly_liability_salary.arearprocessyear end,tbl_monthly_liability_salary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
				) t ';
				v_reportquery:=v_reportquery||'	left join 
						(select emp_code,sum(
							case when recordscreen=''Increment Arear'' and employee_esi_incentive>0 and fixedallowancestotal<0 then
								(coalesce(er.esiapplicablecomponents,fixedallowancestotalrate)*paiddays/monthdays)
							else coalesce(nullif(tbl_monthlysalary.esiapplicablecomponents,0.0),tbl_monthlysalary.grossearning) end) grossearning
											,sum(otherdeductions) otherdeductions
											,sum(othervariables) othervariables
						from public.tbl_monthlysalary
						 inner join empsalaryregister er on tbl_monthlysalary.salaryid=er.id
						 where recordscreen in (''Arear Wages'',''Increment Arear'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						and coalesce(is_rejected,''0'')<>''1''
						group by emp_code) t2
						on t.emp_code=t2.emp_code
						and t.arearaddedmonths is not null ';
				
			v_reportquery:=v_reportquery||'	where ';		
			if p_reporttype<>'LWF' then		
						if p_reporttype='ESIC'then	
							v_reportquery:=v_reportquery||' 
							(
							(t.mprmonth='||p_rpt_month||' and t.mpryear='||p_rpt_year||' and t.recordscreen=''Current Wages'')
							or
							(t.arearprocessmonth='||p_rpt_month||' and t.arearprocessyear='||p_rpt_year||' and t.recordscreen=''Previous Wages'')
							)
							and ';
						else
										v_reportquery:=v_reportquery||' t.mprmonth='||p_rpt_month||'
											and t.mpryear='||p_rpt_year||' and ';
						end if;	
			end if;	
			v_reportquery:=v_reportquery||' coalesce(t.is_rejected,''0'')<>''1''
			        and (recordscreen,coalesce(isarear,''N'')) not in (select ''Current Wages'',''Y'')
			';
			 	if p_reporttype='EPF'then	
			 		v_reportquery:=v_reportquery||' and epf<>0 ';
				end if;
				if p_reporttype='ESIC'then	
			 		v_reportquery:=v_reportquery||' and t.employeeesirate<>0 ';
				end if;
				if p_reporttype='LWF'then	
						v_reportquery:=v_reportquery||' and lwf_employee>0 ';
						v_reportquery:=v_reportquery||' and to_date(''01''||lpad(t.mprmonth::text,2,''0'')||t.mpryear::text,''ddmmyyyy'')  between to_date('''||v_challanfrom ||''',''dd-mon-yyyy'') and to_date('''||v_challanto ||''',''dd-mon-yyyy'')';
						v_reportquery:=v_reportquery||' and coalesce(lwfstatecode,7)='||p_lwfstatecode||' ';
				end if;
		    v_reportquery:=v_reportquery||' and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.reporttype='''||p_reporttype||'''  and r.isactive=''1'')	
			 group by t.emp_code,t.batchid
			 union all
		select t.emp_code,'''' batchid,';		
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||
			' 0 basic
			 , 0 gross
			 ,''Processed'' wagestatus
			 ,0 epf_contri_remitted
			 ,0 eps_contri_remitted
			 ,0 epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,0 esic_amt
			 ,null lastworkingday,';		
		end if;
			v_reportquery:=v_reportquery||' 
			 sum(lwf_employee) employeelwf
			 ,sum(lwf_employer) employerlwf
			 ,sum(coalesce(lwf_employee,0)+coalesce(lwf_employer,0)) totallwf';	
			 
		if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||' 
			 ,'''' address
			 ,sum(vpf) vpf		 
			 ,max(monthdays) monthdays 
			 ,0 grossearning
			 ,0 govt_bonus_amt
			 ,0 otherbonuswithesi
			 ,0 totalarear
			 ,0 otherledgerarears
			 ,0 gross_esi_income';		
		end if;	
			v_reportquery:=v_reportquery||' 
			 	from  (
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, 																					  recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid 
					from tbl_monthlysalary
					where coalesce(is_rejected,''0'')<>''1'' and tbl_monthlysalary.recordscreen in(''Current Wages'' ,''Previous Wages'')
					and coalesce(tbl_monthlysalary.istaxapplicable,''1'')=''1'' 
					and (tbl_monthlysalary.emp_code,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mprmonth else tbl_monthlysalary.arearprocessmonth end,case when tbl_monthlysalary.recordscreen=''Current Wages'' then  tbl_monthlysalary.mpryear else tbl_monthlysalary.arearprocessyear end,tbl_monthlysalary.batchid)
					not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	

					union all
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, case when recordscreen=''Arear Wages'' then ''Previous Wages'' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid
					from tbl_monthly_liability_salary
					where coalesce(tbl_monthly_liability_salary.is_rejected,''0'')<>''1'' and coalesce(salary_remarks,'''')<>''Invalid Paid Days''
					and (tbl_monthly_liability_salary.emp_code,tbl_monthly_liability_salary.mprmonth,tbl_monthly_liability_salary.mpryear,tbl_monthly_liability_salary.batchid)
					 not in (select tbl_monthlysalary_3.emp_code,tbl_monthlysalary_3.mprmonth,tbl_monthlysalary_3.mpryear,tbl_monthlysalary_3.batchid from tbl_monthlysalary tbl_monthlysalary_3 where tbl_monthlysalary_3.is_rejected = ''0''::"bit")
				and (tbl_monthly_liability_salary.emp_code,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mprmonth else tbl_monthly_liability_salary.arearprocessmonth end,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mpryear else tbl_monthly_liability_salary.arearprocessyear end,tbl_monthly_liability_salary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
	
				) t
				where ';						
			if p_reporttype<>'LWF' then		
				v_reportquery:=v_reportquery||' t.mprmonth='||p_rpt_month||'
					and t.mpryear='||p_rpt_year||' and ';
			end if;	
			v_reportquery:=v_reportquery||' coalesce(t.is_rejected,''0'')<>''1''
					and (recordscreen,coalesce(isarear,''N'')) in (select ''Current Wages'',''Y'')
					';
			 	if p_reporttype='EPF'then	
			 		v_reportquery:=v_reportquery||' and epf>0 ';
				end if;
				if p_reporttype='ESIC'then	
			 		v_reportquery:=v_reportquery||' and t.employeeesirate<>0 ';
				end if;
				if p_reporttype='LWF'then	
						v_reportquery:=v_reportquery||' and lwf_employee>0 ';
						v_reportquery:=v_reportquery||' and to_date(''01''||lpad(t.mprmonth::text,2,''0'')||t.mpryear::text,''ddmmyyyy'')  between to_date('''||v_challanfrom ||''',''dd-mon-yyyy'') and to_date('''||v_challanto ||''',''dd-mon-yyyy'')';
						v_reportquery:=v_reportquery||' and coalesce(lwfstatecode,7)='||p_lwfstatecode||' ';
				end if;
		    v_reportquery:=v_reportquery||' and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and reporttype='''||p_reporttype||'''  and r.isactive=''1'')	
			group by t.emp_code,t.batchid) e1
	---------------------------------------------
	group by emp_code
	)e
	------------------------------------------------
			on o.emp_code=e.emp_code
			and o.appointment_status_id<>13
			and o.customeraccountid=coalesce(nullif('||p_customeraccountid||',''-9999'')::bigint,o.customeraccountid)
			AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF('''||p_ou_ids||''', ''''), COALESCE(NULLIF(o.assigned_ou_ids, ''''), COALESCE(NULLIF(o.geofencingid::TEXT, ''''), ''0''))), '','')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(o.assigned_ou_ids, ''''), COALESCE(NULLIF(o.geofencingid::TEXT, ''''), ''0'')), '',''))
			) 
			and o.recordsource= case when '''||p_tptype||'''=''TP'' then ''HUBTPCRM'' else nullif(o.recordsource,''HUBTPCRM'') end
			and (o.emp_id,'||p_rpt_month||','||p_rpt_year||',e.batchid,'''||p_reporttype||''')
			not in (select m.appointment_id,m.rpt_month,m.rpt_year,m.batchid,m.reporttype from epfecrreport m where  m.isactive=''1'')
			limit 1000';
			
			raise notice 'Query: % ', v_reportquery;	
			
			 execute v_reportquery;
			/*
			update 	unprocessed_epfecrreport
			set isreportdownloaded='1',
			     downloadedby=p_downloadedby,
				 downloadedon=v_reporttimestamp,
				 downloadedbyip=p_downloadedbyip
			where rpt_month=p_rpt_month
				and rpt_year=p_rpt_year
				and coalesce(isreportdownloaded,'0')<>'1'
				and reporttype=p_reporttype;
			*/
			
			open rfcreport for
			select appointment_id appointment_id,rpt_month rpt_month,rpt_year rpt_year,	
			coalesce(op.uannumber,epfecrreport.uan) uan,coalesce(op.emp_name,epfecrreport.member_name) member_name,
			round(gross_wages::numeric(18,2),0) gross_wages,
			round(epf_wages::numeric(18,2),0) epf_wages,
			round(eps_wages::numeric(18,2),0) eps_wages,
			round(edli_wages::numeric(18,2),0) edli_wages,
			round(epf_contri_remitted::numeric(18,2),0) epf_contri_remitted,
			round(eps_contri_remitted::numeric(18,2),0) eps_contri_remitted,
			round(epf_eps_diff_remitted::numeric(18,2),0) epf_eps_diff_remitted,
			ncp_days,
			refund_of_advances
			,op.emp_code,batchid
			,wagestatus
			,coalesce(op.esinumber,epfecrreport.esicnumber) esinumber
			,ceil(esic_amt::numeric(18,2)) esic_amt
			,to_char(lastworkingday,'dd-mm-yyyy') lastworkingday
			,op.fathername
			,emplocation
			,to_char(doj,'dd-mm-yyyy') doj
			,round(employeelwf::numeric(18,2),2) employeelwf
			,round(employerlwf::numeric(18,2),2) employerlwf
			,round(totallwf::numeric(18,2),2) totallwf
			,address
			,reporttype
			,vpf
			,to_char(epfecrreport.createdon at time zone 'utc' at time zone 'Asia/Calcutta', 'DD/MM/YYYY, HH:mi:SS AM')   downloadedon
			, (select name from users where userid =created_by) downloadedby
			,monthdays
			,round(gross_earning::numeric(18,2),0) grossearning
			,ROUND(gross_esi_income::numeric(18,2),0) gross_esi_income
			from epfecrreport
			inner join openappointments op on op.emp_code=epfecrreport.emp_code and op.appointment_status_id<>13
			where rpt_month=p_rpt_month
			and rpt_year=p_rpt_year
			and op.customeraccountid=coalesce(nullif(p_customeraccountid,'-9999')::bigint,op.customeraccountid) -- SIDDHARTH BANSAL 13/03/2024
			--SIDDHARTH BANSAL 06/08/2024
			AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
			)
			--END 
			and reporttype=p_reporttype
			and epfecrreport.isactive='1'
			and op.recordsource= case when p_tptype='TP' then 'HUBTPCRM' else nullif(op.recordsource,'HUBTPCRM') end
			and 0<> case when p_reporttype='EPF' then epf_contri_remitted 
					when p_reporttype='ESIC'then esic_amt
					when p_reporttype='LWF' then employeelwf end
		    and epfecrreport.createdon=current_timestamp;
			return rfcreport;
		end if;
		
		if p_action='RetrieveProcessedReport' then
			open rfcreport for
			select appointment_id appointment_id,rpt_month rpt_month,rpt_year rpt_year,	
			coalesce(op.uannumber,epfecrreport.uan) uan,coalesce(op.emp_name,epfecrreport.member_name) member_name,
			round(gross_wages::numeric(18,2),0) gross_wages,
			round(epf_wages::numeric(18,2),0) epf_wages,
			round(eps_wages::numeric(18,2),0) eps_wages,
			round(edli_wages::numeric(18,2),0) edli_wages,
			round(epf_contri_remitted::numeric(18,2),0) epf_contri_remitted,
			round(eps_contri_remitted::numeric(18,2),0) eps_contri_remitted,
			greatest(round((epf_eps_diff_remitted::numeric(18,2)+eps_contri_remitted-round(eps_contri_remitted::numeric(18,2),0))::numeric(18,2),0),0) epf_eps_diff_remitted,
			case when p_reporttype<>'EPF' or dateofjoining<=make_date(p_rpt_year,p_rpt_month,1)  then ncp_days
			else 
			least(monthdays,v_totalmonthdays-(extract('day' from dateofjoining)::int-1)) -(monthdays-ncp_days) end as ncp_days,
			refund_of_advances
			,op.emp_code,batchid
			,wagestatus
			,coalesce(op.esinumber,epfecrreport.esicnumber) esinumber
			,ceil(esic_amt::numeric(18,2)) esic_amt
			,to_char(lastworkingday,'dd-mm-yyyy') lastworkingday
			,op.fathername
			,emplocation
			,to_char(doj,'dd-mm-yyyy') doj
			,round(employeelwf::numeric(18,2),2) employeelwf
			,round(employerlwf::numeric(18,2),2) employerlwf
			,round(totallwf::numeric(18,2),2) totallwf
			,address
			,reporttype
			,vpf
			,to_char(epfecrreport.createdon at time zone 'utc' at time zone 'Asia/Calcutta', 'DD/MM/YYYY, HH:mi:SS AM')   downloadedon
			, (select name from users where userid =created_by) downloadedby
			,monthdays
			,round(gross_earning::numeric(18,2),0) grossearning
			,ROUND(gross_esi_income::numeric(18,2),0) gross_esi_income,op.cjcode tpcode,op.orgempcode
			from epfecrreport
			inner join openappointments op on op.emp_code=epfecrreport.emp_code and op.appointment_status_id<>13
			where rpt_month=p_rpt_month
			and rpt_year=p_rpt_year
			and reporttype=p_reporttype
			and epfecrreport.isactive='1'
			and op.customeraccountid=coalesce(nullif(p_customeraccountid,'-9999')::bigint,op.customeraccountid)
			--SIDDHARTH BANSAL 06/08/2024
			AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
			)
			--END
			and op.recordsource= case when p_tptype='TP' then 'HUBTPCRM' else nullif(op.recordsource,'HUBTPCRM') end
			and 0<> case when p_reporttype='EPF' then epf_contri_remitted 
					when p_reporttype='ESIC'then esic_amt
					when p_reporttype='LWF' then employeelwf end;
			return rfcreport;
		end if;
		if p_action='Demark' then
			INSERT INTO public.tblpfchalandates(
				pfyear, pfmonth, chalandownloaddate, createdby, createdon, createdbyip, active)
			VALUES (p_rpt_year, p_rpt_month, current_timestamp, p_downloadedby, current_timestamp, p_downloadedbyip, '1');	

			open rfcreport for
			select null as a;
			return rfcreport;
		end if;
		if p_action='DisplayArrearChallan' then
		v_reportquery:='select o.emp_id appointment_id,mprmonth rpt_month,mpryear rpt_year,	
			o.uannumber uan,o.emp_name member_name,
			round(e.gross::numeric(18,2),2) gross_wages,
			round(e.basic::numeric(18,2),2) epf_wages,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(e.basic,15000)::numeric(18,2),2) else 0.0 end eps_wages,
			round(least(e.basic,15000)::numeric(18,2),2) edli_wages,
			round((epf_contri_remitted+coalesce(e.vpf,0))::numeric(18,2),2) epf_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(eps_contri_remitted,1250)::numeric(18,2),2) else 0.0 end  eps_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round((epf_eps_diff_remitted+(greatest(eps_contri_remitted-least(eps_contri_remitted,1250),0)))::numeric(18,2),2) else round((coalesce(epf_eps_diff_remitted,0)+coalesce(eps_contri_remitted,0))::numeric(18,2),2) end epf_eps_diff_remitted,
			case when '''||p_reporttype||'''=''EPF'' then monthdays-paiddays else paiddays end ncp_days,
			0 refund_of_advances
			,o.emp_code,e.batchid
			,e.wagestatus
			,o.esinumber
			,ceil(e.esic_amt) esic_amt
			,e.lastworkingday
			,o.fathername
            ,o.posting_location emplocation
			,to_char(o.dateofjoining,''dd-mm-yyyy'') doj
			,e.employeelwf
			,e.employerlwf
			,e.totallwf
			,e.address
			,'''||p_reporttype||''' reporttype
			,e.vpf
			,monthdays 
			,round(grossearning::numeric(18,2),0) grossearning
			 , govt_bonus_amt
			 , otherbonuswithesi
			 , totalarear
			 , otherledgerarears
			 , ROUND(gross_esi_income::numeric(18,2),2) gross_esi_income
			 ,'||p_rpt_month||' challanmonth,'||p_rpt_year||' challanyear
			 ,''Previous'' as challantype
			from public.openappointments o inner join 
--------------------------------------------------------------------------			
			(select emp_code,string_agg(batchid,'','') batchid,
			case when sum(epf_contri_remitted)=1800 then 15000 else sum(basic) end basic,
			 sum(gross) gross
			 ,''Processed'' wagestatus
			 ,sum(epf_contri_remitted) epf_contri_remitted
			 ,sum(eps_contri_remitted) eps_contri_remitted
			 ,sum(epf_eps_diff_remitted) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(esic_amt) esic_amt
			 ,max(lastworkingday) lastworkingday
			 ,sum(employeelwf) employeelwf
			 ,sum(employerlwf) employerlwf
			 ,sum(totallwf) totallwf
			 ,max(address) address
			 ,sum(vpf) vpf
			  ,max(monthdays) monthdays 
			 ,sum(grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(gross_esi_income) gross_esi_income
			 ,mprmonth,mpryear
			 
			 from 
---------------------------------------------------------------------------			 
			(select t.emp_code,string_agg(t.batchid,'','') batchid,sum(t.basic) basic,
			 sum(t.fixedallowancestotal) gross
			 ,''Processed'' wagestatus
			 ,sum(epf) epf_contri_remitted
			 ,sum(Ac_10) eps_contri_remitted
			 ,sum(Ac_1) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(t.employeeesirate+coalesce(incrementarear_employeeesi,0)) esic_amt
			 ,max(dateofleaving) lastworkingday
			 ,sum(lwf_employee) employeelwf
			 ,sum(lwf_employer) employerlwf
			 ,sum(coalesce(lwf_employee,0)+coalesce(lwf_employer,0)) totallwf
			 ,max(residential_address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(t.grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,t.mprmonth,t.mpryear	
			,sum(coalesce(t.GrossEarning,0)+coalesce(t2.GrossEarning,0)+coalesce(t3.GrossEarning,0)-(coalesce(t.otherdeductions,0)+coalesce(t2.otherdeductions,0)+coalesce(t3.otherdeductions,0))) gross_esi_income
			 from  (
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate,coalesce(nullif(tbl_monthlysalary.pfapplicablecomponents,0),tbl_monthlysalary.basic,0) basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, 																					  recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid 
					from tbl_monthlysalary
					where coalesce(is_rejected,''0'')<>''1''
					and coalesce(tbl_monthlysalary.istaxapplicable,''1'')=''1'' 
					and (tbl_monthlysalary.emp_code,tbl_monthlysalary.mprmonth,tbl_monthlysalary.mpryear,tbl_monthlysalary.batchid)
					not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
	
					union all
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate,coalesce(nullif(tbl_monthly_liability_salary.pfapplicablecomponents,0),tbl_monthly_liability_salary.basic,0) basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, case when recordscreen=''Arear Wages'' then ''Previous Wages'' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid
					from tbl_monthly_liability_salary
					where coalesce(tbl_monthly_liability_salary.is_rejected,''0'')<>''1'' and coalesce(salary_remarks,'''')<>''Invalid Paid Days''
					and (tbl_monthly_liability_salary.emp_code,tbl_monthly_liability_salary.mprmonth,tbl_monthly_liability_salary.mpryear,tbl_monthly_liability_salary.batchid)
					 not in (select tbl_monthlysalary_3.emp_code,tbl_monthlysalary_3.mprmonth,tbl_monthlysalary_3.mpryear,tbl_monthlysalary_3.batchid from tbl_monthlysalary tbl_monthlysalary_3 where tbl_monthlysalary_3.is_rejected = ''0''::"bit")
				--where coalesce(is_rejected,''0'')<>''1'' and tbl_monthlysalary.recordscreen in(''Current Wages'' ,''Previous Wages'')
				and (tbl_monthly_liability_salary.emp_code,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mprmonth else tbl_monthly_liability_salary.arearprocessmonth end,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mpryear else tbl_monthly_liability_salary.arearprocessyear end,tbl_monthly_liability_salary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
		
				) t ';
				v_reportquery:=v_reportquery||'	left join 
						(select emp_code,sum(grossearning) grossearning
											,sum(otherdeductions) otherdeductions
						from public.tbl_monthlysalary
						 where recordscreen in (''Arear Wages'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						and coalesce(is_rejected,''0'')<>''1''
						group by emp_code) t2
						on t.emp_code=t2.emp_code
						and t.arearaddedmonths is not null
						left join 
						(select emp_code,sum(coalesce(nullif(tbl_monthlysalary.esiapplicablecomponents,0.0),tbl_monthlysalary.grossearning)) grossearning
											,sum(otherdeductions) otherdeductions
						from public.tbl_monthlysalary
						 inner join empsalaryregister er on tbl_monthlysalary.salaryid=er.id
						 where recordscreen in (''Increment Arear'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						and coalesce(is_rejected,''0'')<>''1''
						group by emp_code) t3
						on t.emp_code=t3.emp_code
						and t.arearaddedmonths is not null ';
				
			v_reportquery:=v_reportquery||'	where ';
			if p_reporttype<>'LWF' then	
			v_reportquery:=v_reportquery||'(t.createdon::date between (DATE_TRUNC(''month'',to_date(''01'||lpad(p_rpt_month::text,2,'0')||p_rpt_year::text||''',''ddmmyyyy'') )) ::date 
							 and
							 ((DATE_TRUNC(''month'',to_date(''01'||lpad(p_rpt_month::text,2,'0')||p_rpt_year::text||''',''ddmmyyyy'') )+interval ''2 month'')-interval ''1 day'') ::date
							and recordscreen=''Previous Wages''
							)  and';
			end if;	
			v_reportquery:=v_reportquery||' coalesce(t.is_rejected,''0'')<>''1''
			        and (recordscreen,coalesce(isarear,''N'')) not in (select ''Current Wages'',''Y'')
			';
			 	if p_reporttype='EPF'then	
			 		v_reportquery:=v_reportquery||' and epf>0 ';
				end if;
				if p_reporttype='ESIC'then	
			 		v_reportquery:=v_reportquery||' and t.employeeesirate<>0 ';
				end if;
				if p_reporttype='LWF'then	
						v_reportquery:=v_reportquery||' and lwf_employee>0 ';
						v_reportquery:=v_reportquery||' and to_date(''01''||lpad(t.mprmonth::text,2,''0'')||t.mpryear::text,''ddmmyyyy'')  between to_date('''||v_challanfrom ||''',''dd-mon-yyyy'') and to_date('''||v_challanto ||''',''dd-mon-yyyy'')';
						v_reportquery:=v_reportquery||' and coalesce(t.lwfstatecode,7)='||p_lwfstatecode||' ';
				end if;
		    v_reportquery:=v_reportquery||' and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select m.emp_code,m.rpt_month,m.rpt_year,m.batchid from unprocessed_epfecrreport m)	
			and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where reporttype='''||p_reporttype||'''  and r.isactive=''1'')	
			group by t.emp_code,t.batchid,t.mprmonth,t.mpryear
			) e1
	---------------------------------------------
	group by emp_code,mprmonth,mpryear
	)e
	------------------------------------------------
			on o.emp_code=e.emp_code
			and o.appointment_status_id<>13
			and o.recordsource= case when '''||p_tptype||'''=''TP'' then ''HUBTPCRM'' else nullif(o.recordsource,''HUBTPCRM'') end
			and (o.emp_id,mprmonth,mpryear,e.batchid,'''||p_reporttype||''')
			not in (select m.appointment_id,m.rpt_month,m.rpt_year,m.batchid,m.reporttype from epfecrreport m)';
			
			raise notice 'Query: % ', v_reportquery;	
			
			open rfcreport for execute v_reportquery;
			return rfcreport;
		end if;
		if p_action='DownloadArrearChallan' then
		v_reportquery:='select o.emp_id appointment_id,mprmonth rpt_month,mpryear rpt_year,	
			o.uannumber uan,o.emp_name member_name,
			round(e.gross::numeric(18,2),2) gross_wages,
			round(e.basic::numeric(18,2),2) epf_wages,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(e.basic,15000)::numeric(18,2),2) else 0.0 end eps_wages,
			round(least(e.basic,15000)::numeric(18,2),2) edli_wages,
			round((epf_contri_remitted+coalesce(e.vpf,0))::numeric(18,2),2) epf_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(eps_contri_remitted,1250)::numeric(18,2),2) else 0.0 end  eps_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round((epf_eps_diff_remitted+(greatest(eps_contri_remitted-least(eps_contri_remitted,1250),0)))::numeric(18,2),2) else round((coalesce(epf_eps_diff_remitted,0)+coalesce(eps_contri_remitted,0))::numeric(18,2),2) end epf_eps_diff_remitted,
			case when '''||p_reporttype||'''=''EPF'' then monthdays-paiddays else paiddays end ncp_days,
			0 refund_of_advances
			,o.emp_code,e.batchid
			,e.wagestatus
			,o.esinumber
			,ceil(e.esic_amt) esic_amt
			,e.lastworkingday
			,o.fathername
            ,o.posting_location emplocation
			,to_char(o.dateofjoining,''dd-mm-yyyy'') doj
			,e.employeelwf
			,e.employerlwf
			,e.totallwf
			,e.address
			,'''||p_reporttype||''' reporttype
			,e.vpf
			,monthdays 
			,round(grossearning::numeric(18,2),0) grossearning
			, govt_bonus_amt
			 , otherbonuswithesi
			 , totalarear
			 , otherledgerarears
			 , ROUND(gross_esi_income::numeric(18,2),2) gross_esi_income
			 ,'||p_rpt_month||' challanmonth,'||p_rpt_year||' challanyear
			 ,''Previous'' as challantype
			from public.openappointments o inner join 
			--------------------------------------------------------------------------			
			(select emp_code,string_agg(batchid,'','') batchid,
			case when sum(epf_contri_remitted)=1800 then 15000 else sum(basic) end basic,
			 sum(gross) gross
			 ,''Processed'' wagestatus
			 ,sum(epf_contri_remitted) epf_contri_remitted
			 ,sum(eps_contri_remitted) eps_contri_remitted
			 ,sum(epf_eps_diff_remitted) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(esic_amt) esic_amt
			 ,max(lastworkingday) lastworkingday
			 ,sum(employeelwf) employeelwf
			 ,sum(employerlwf) employerlwf
			 ,sum(totallwf) totallwf
			 ,max(address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(gross_esi_income) gross_esi_income
			 ,mprmonth,mpryear
			 from 
---------------------------------------------------------------------------		
			(select t.emp_code,string_agg(t.batchid,'','') batchid,sum(t.basic) basic,
			 sum(t.fixedallowancestotal) gross
			 ,''Processed'' wagestatus
			 ,sum(epf) epf_contri_remitted
			 ,sum(Ac_10) eps_contri_remitted
			 ,sum(Ac_1) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,round(sum(t.employeeesirate+coalesce(incrementarear_employeeesi,0))) esic_amt
			 ,max(dateofleaving) lastworkingday
			 ,sum(lwf_employee) employeelwf
			 ,sum(lwf_employer) employerlwf
			 ,sum(coalesce(lwf_employee,0)+coalesce(lwf_employer,0)) totallwf
			 ,max(residential_address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(t.grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,t.mprmonth,t.mpryear
			 ,sum(coalesce(t.GrossEarning,0)+coalesce(t2.GrossEarning,0)+coalesce(t3.GrossEarning,0)-(coalesce(t.otherdeductions,0)+coalesce(t2.otherdeductions,0)+coalesce(t3.otherdeductions,0))) gross_esi_income
			 	from  (
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, 																					  recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid 
					from tbl_monthlysalary
					where coalesce(is_rejected,''0'')<>''1''
					and coalesce(tbl_monthlysalary.istaxapplicable,''1'')=''1'' 
					and (tbl_monthlysalary.emp_code,tbl_monthlysalary.mprmonth,tbl_monthlysalary.mpryear,tbl_monthlysalary.batchid)
					not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
	
					union all
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, case when recordscreen=''Arear Wages'' then ''Previous Wages'' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid
					from tbl_monthly_liability_salary
					where coalesce(tbl_monthly_liability_salary.is_rejected,''0'')<>''1'' and coalesce(salary_remarks,'''')<>''Invalid Paid Days''
					and (tbl_monthly_liability_salary.emp_code,tbl_monthly_liability_salary.mprmonth,tbl_monthly_liability_salary.mpryear,tbl_monthly_liability_salary.batchid)
					 not in (select tbl_monthlysalary_3.emp_code,tbl_monthlysalary_3.mprmonth,tbl_monthlysalary_3.mpryear,tbl_monthlysalary_3.batchid from tbl_monthlysalary tbl_monthlysalary_3 where tbl_monthlysalary_3.is_rejected = ''0''::"bit")
				--where coalesce(is_rejected,''0'')<>''1'' and tbl_monthlysalary.recordscreen in(''Current Wages'' ,''Previous Wages'')
				and (tbl_monthly_liability_salary.emp_code,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mprmonth else tbl_monthly_liability_salary.arearprocessmonth end,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mpryear else tbl_monthly_liability_salary.arearprocessyear end,tbl_monthly_liability_salary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
		
				) t ';
				v_reportquery:=v_reportquery||'	left join 
						(select emp_code,sum(grossearning) grossearning
											,sum(otherdeductions) otherdeductions
						from public.tbl_monthlysalary
						 where recordscreen in (''Arear Wages'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						and coalesce(is_rejected,''0'')<>''1''
						group by emp_code) t2
						on t.emp_code=t2.emp_code
						and t.arearaddedmonths is not null
						left join 
						(select emp_code,sum(grossearning) grossearning
											,sum(otherdeductions) otherdeductions
						from public.tbl_monthlysalary
						 where recordscreen in (''Increment Arear'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						group by emp_code) t3
						on t.emp_code=t3.emp_code
						and t.arearaddedmonths is not null ';
				
			v_reportquery:=v_reportquery||'	where ';		
			if p_reporttype<>'LWF' then		
				v_reportquery:=v_reportquery||'(t.createdon::date between (DATE_TRUNC(''month'',to_date(''01'||lpad(p_rpt_month::text,2,'0')||p_rpt_year::text||''',''ddmmyyyy'') )) ::date 
				 and
				 ((DATE_TRUNC(''month'',to_date(''01'||lpad(p_rpt_month::text,2,'0')||p_rpt_year::text||''',''ddmmyyyy'') )+interval ''2 month'')-interval ''1 day'') ::date
				and recordscreen=''Previous Wages''
				)  and';
			end if;	
			v_reportquery:=v_reportquery||' coalesce(t.is_rejected,''0'')<>''1''
			        and (recordscreen,coalesce(isarear,''N'')) not in (select ''Current Wages'',''Y'')
			';
			 	if p_reporttype='EPF'then	
			 		v_reportquery:=v_reportquery||' and epf>0 ';
				end if;
				if p_reporttype='ESIC'then	
			 		v_reportquery:=v_reportquery||' and t.employeeesirate<>0 ';
				end if;
				if p_reporttype='LWF'then	
						v_reportquery:=v_reportquery||' and lwf_employee>0 ';
						v_reportquery:=v_reportquery||' and to_date(''01''||lpad(t.mprmonth::text,2,''0'')||t.mpryear::text,''ddmmyyyy'')  between to_date('''||v_challanfrom ||''',''dd-mon-yyyy'') and to_date('''||v_challanto ||''',''dd-mon-yyyy'')';
						v_reportquery:=v_reportquery||' and coalesce(lwfstatecode,7)='||p_lwfstatecode||' ';
				end if;
		    v_reportquery:=v_reportquery||' and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select m.emp_code,m.rpt_month,m.rpt_year,m.batchid from unprocessed_epfecrreport m)
			and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where reporttype='''||p_reporttype||'''  and r.isactive=''1'')	
			group by t.emp_code,t.batchid,t.mprmonth,t.mpryear
			) e1
	---------------------------------------------
	group by emp_code,mprmonth,mpryear
	)e
	------------------------------------------------
			on o.emp_code=e.emp_code
			and o.appointment_status_id<>13
			and o.recordsource= case when '''||p_tptype||'''=''TP'' then ''HUBTPCRM'' else nullif(o.recordsource,''HUBTPCRM'') end
			and (o.emp_id,mprmonth,mpryear,e.batchid,'''||p_reporttype||''')
			not in (select m.appointment_id,m.rpt_month,m.rpt_year,m.batchid,m.reporttype from epfecrreport m where  m.isactive=''1'')';
			
			raise notice 'Query: % ', v_reportquery;	
			
			open rfcreport for execute v_reportquery;
			return rfcreport;
		end if;
		if p_action='SaveArrearChallan' then
			
			v_reporttimestamp:=current_timestamp;
			v_reportquery:='INSERT INTO public.epfecrreport(
				appointment_id, rpt_month, rpt_year, uan, member_name, gross_wages, epf_wages,
				eps_wages, edli_wages, epf_contri_remitted, eps_contri_remitted,
				epf_eps_diff_remitted, ncp_days, refund_of_advances, 
				created_by, createdon, createdbyip,emp_code,batchid,wagestatus
				,esicnumber,esic_amt,lastworkingday,fathername,emplocation,doj
				,employeelwf,employerlwf,totallwf,address,reporttype,vpf,monthdays,gross_earning,
				govt_bonus_amt,otherbonuswithesi,totalarear,otherledgerarears,gross_esi_income
				,challanmonth,challanyear,challantype
				)
			select o.emp_id appointment_id,mprmonth rpt_month,mpryear rpt_year,		
			o.uannumber uan,o.emp_name member_name,
			round(e.gross::numeric(18,2),2) gross_wages,
			round(e.basic::numeric(18,2),2) epf_wages,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then least(e.basic,15000) else 0.0 end eps_wages,
			round(least(e.basic,15000)::numeric(18,2),2) edli_wages,
			round((epf_contri_remitted+coalesce(e.vpf,0))::numeric(18,2),2) epf_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then round(least(eps_contri_remitted,1250)::numeric(18,2),2) else 0.0 end  eps_contri_remitted,
			case when coalesce(o.epf_pension_opted,''Y'')=''Y'' then (epf_eps_diff_remitted+(greatest(eps_contri_remitted-least(eps_contri_remitted,1250),0)))::numeric(18,2) else round((coalesce(epf_eps_diff_remitted,0)+coalesce(eps_contri_remitted,0))::numeric(18,2),2) end  epf_eps_diff_remitted,
			case when '''||p_reporttype||'''=''EPF'' then monthdays-paiddays else paiddays end ncp_days,
			0 refund_of_advances,'
			||p_downloadedby||','''
			||v_reporttimestamp||''','''
			||p_downloadedbyip||''',
			o.emp_code,e.batchid
			,e.wagestatus
			,o.esinumber
			,e.esic_amt esic_amt
			,e.lastworkingday
			,o.fathername
            ,o.posting_location emplocation
			,o.dateofjoining doj
			,e.employeelwf
			,e.employerlwf
			,e.totallwf
			,e.address
			,'''||p_reporttype||''' reporttype
			,e.vpf
			,monthdays 
			,grossearning
			 , govt_bonus_amt
			 , otherbonuswithesi
			 , totalarear
			 , otherledgerarears
			 , gross_esi_income
			 ,'||p_rpt_month||' challanmonth,'||p_rpt_year||' challanyear
			 ,''Previous'' as challantype
			from public.openappointments o inner join 
			--------------------------------------------------------------------------			
			(select emp_code,string_agg(batchid,'','') batchid,
			case when sum(epf_contri_remitted)=1800 then 15000 else sum(basic) end basic,
			 sum(gross) gross
			 ,''Processed'' wagestatus
			 ,sum(epf_contri_remitted) epf_contri_remitted
			 ,sum(eps_contri_remitted) eps_contri_remitted
			 ,sum(epf_eps_diff_remitted) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(esic_amt) esic_amt
			 ,max(lastworkingday) lastworkingday
			 ,sum(employeelwf) employeelwf
			 ,sum(employerlwf) employerlwf
			 ,sum(totallwf) totallwf
			 ,max(address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(gross_esi_income) gross_esi_income
			 ,mprmonth,mpryear
			 from
---------------------------------------------------------------------------		
			(select t.emp_code,string_agg(t.batchid,'','') batchid,sum(t.basic) basic,
			 sum(t.fixedallowancestotal) gross
			 ,''Processed'' wagestatus
			 ,sum(epf) epf_contri_remitted
			 ,sum(Ac_10) eps_contri_remitted
			 ,sum(Ac_1) epf_eps_diff_remitted
			 ,sum(paiddays) paiddays
			 ,sum(t.employeeesirate+coalesce(t.incrementarear_employeeesi,0) ) esic_amt
			 ,max(dateofleaving) lastworkingday
			 ,sum(lwf_employee) employeelwf
			 ,sum(lwf_employer) employerlwf
			 ,sum(coalesce(lwf_employee,0)+coalesce(lwf_employer,0)) totallwf
			 ,max(residential_address) address
			 ,sum(vpf) vpf
			 ,max(monthdays) monthdays 
			 ,sum(t.grossearning) grossearning
			 ,sum(govt_bonus_amt) govt_bonus_amt
			 ,sum(otherbonuswithesi) otherbonuswithesi
			 ,sum(totalarear) totalarear
			 ,sum(otherledgerarears) otherledgerarears
			 ,sum(coalesce(t.GrossEarning,0)+coalesce(t2.GrossEarning,0)+coalesce(t3.GrossEarning,0)-(coalesce(t.otherdeductions,0)+coalesce(t2.otherdeductions,0)+coalesce(t3.otherdeductions,0))) gross_esi_income
			 ,t.mprmonth,t.mpryear
			 	from  (
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, 																					  recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid 
					from tbl_monthlysalary
					where coalesce(is_rejected,''0'')<>''1''
					and coalesce(tbl_monthlysalary.istaxapplicable,''1'')=''1'' 
					and (tbl_monthlysalary.emp_code,tbl_monthlysalary.mprmonth,tbl_monthlysalary.mpryear,tbl_monthlysalary.batchid)
					not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
	
					union all
					select id, mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, modifiedby, modifiedon, modifiedbyip, is_special_category, ctc2, batch_no, actual_paid_ctc2, ctc, ctc_paid_days, ctc_actual_paid, mobile_deduction, salaryid, bankaccountno, ifsccode, bankname, bankbranch, employeenps, employernps, insuranceamount, familyinsurance, issalarydownloaded, remarks, isarear, isarearprocessed, arearprocessmonth, arearprocessyear, arearprocessedby, arearprocessedon, arearprocessedbyip, employee_esi_incentive, employer_esi_incentive, total_esi_incentive, account1_7q_dues, account1_14b_dues, account10_7q_dues, account10_14b_dues, account2_7q_dues, account2_14b_dues, account21_7q_dues, account21_14b_dues, pf_due_date, pf_paid_date, totalarear, arearaddedmonths, employee_esi_incentive_deduction, employer_esi_incentive_deduction, total_esi_incentive_deduction, salaryindaysopted, mastersalarydays, otherledgerarears, otherledgerdeductions, is_rejected, reject_reason, rejected_on, rejected_by, case when recordscreen=''Arear Wages'' then ''Previous Wages'' else recordscreen end recordscreen, esi_incentive_processed, esi_incentive_processedon, esi_incentive_processedby, esi_incentive_processedbyip, esi_incentive_processmonth, esi_incentive_processyear, attendancemode, incrementarear, incrementarear_basic, incrementarear_hra, incrementarear_allowance, incrementarear_gross, incrementarear_employeeesi, incrementarear_employeresi, lwf_employee, lwf_employer, othervariables, otherdeductions, bonus, otherledgerarearwithoutesi, otherbonuswithesi, salarydownloadedby, salarydownloadedon, salarydownloadedbyip, lwfstatecode, tdsadjustment, is_disbersible, atds, manual_tds_adjustment, manual_remarks, voucher_amount, voucher_remarks, salary_remarks, voucher_date, arearids, hrgeneratedon, transactionid
					from tbl_monthly_liability_salary
					where coalesce(tbl_monthly_liability_salary.is_rejected,''0'')<>''1'' and coalesce(salary_remarks,'''')<>''Invalid Paid Days''
					and (tbl_monthly_liability_salary.emp_code,tbl_monthly_liability_salary.mprmonth,tbl_monthly_liability_salary.mpryear,tbl_monthly_liability_salary.batchid)
					 not in (select tbl_monthlysalary_3.emp_code,tbl_monthlysalary_3.mprmonth,tbl_monthlysalary_3.mpryear,tbl_monthlysalary_3.batchid from tbl_monthlysalary tbl_monthlysalary_3 where tbl_monthlysalary_3.is_rejected = ''0''::"bit")
				--where coalesce(is_rejected,''0'')<>''1'' and tbl_monthlysalary.recordscreen in(''Current Wages'' ,''Previous Wages'')
				and (tbl_monthly_liability_salary.emp_code,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mprmonth else tbl_monthly_liability_salary.arearprocessmonth end,case when tbl_monthly_liability_salary.recordscreen=''Current Wages'' then  tbl_monthly_liability_salary.mpryear else tbl_monthly_liability_salary.arearprocessyear end,tbl_monthly_liability_salary.batchid)
				not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where r.reporttype='''||p_reporttype||''' and r.rpt_month='||p_rpt_month||' and r.rpt_year='||p_rpt_year||' and r.isactive=''1'')	
		
				) t ';
				v_reportquery:=v_reportquery||'	left join 
						(select emp_code,sum(grossearning) grossearning
											,sum(otherdeductions) otherdeductions
						from public.tbl_monthlysalary
						 where recordscreen in (''Arear Wages'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						and coalesce(is_rejected,''0'')<>''1''
						group by emp_code) t2
						on t.emp_code=t2.emp_code
						and t.arearaddedmonths is not null
						left join 
						(select emp_code,sum(grossearning) grossearning
											,sum(otherdeductions) otherdeductions
						from public.tbl_monthlysalary
						 where recordscreen in (''Increment Arear'')
						 and isarearprocessed=''Y''
						 and arearprocessmonth='||p_rpt_month||' 
						and arearprocessyear='||p_rpt_year||'
						and coalesce(is_rejected,''0'')<>''1''
						group by emp_code) t3
						on t.emp_code=t3.emp_code
						and t.arearaddedmonths is not null ';
				
			v_reportquery:=v_reportquery||'	where ';			
			if p_reporttype<>'LWF' then		
				v_reportquery:=v_reportquery||'(t.createdon::date between (DATE_TRUNC(''month'',to_date(''01'||lpad(p_rpt_month::text,2,'0')||p_rpt_year::text||''',''ddmmyyyy'') )) ::date 
				 and
				 ((DATE_TRUNC(''month'',to_date(''01'||lpad(p_rpt_month::text,2,'0')||p_rpt_year::text||''',''ddmmyyyy'') )+interval ''2 month'')-interval ''1 day'') ::date
				and recordscreen=''Previous Wages''
				)  and';
			end if;	
			v_reportquery:=v_reportquery||' coalesce(t.is_rejected,''0'')<>''1''
			        and (recordscreen,coalesce(isarear,''N'')) not in (select ''Current Wages'',''Y'')
			';
			 	if p_reporttype='EPF'then	
			 		v_reportquery:=v_reportquery||' and epf>0 ';
				end if;
				if p_reporttype='ESIC'then	
			 		v_reportquery:=v_reportquery||' and t.employeeesirate<>0 ';
				end if;
				if p_reporttype='LWF'then	
						v_reportquery:=v_reportquery||' and lwf_employee>0 ';
						v_reportquery:=v_reportquery||' and to_date(''01''||lpad(t.mprmonth::text,2,''0'')||t.mpryear::text,''ddmmyyyy'')  between to_date('''||v_challanfrom ||''',''dd-mon-yyyy'') and to_date('''||v_challanto ||''',''dd-mon-yyyy'')';
						v_reportquery:=v_reportquery||' and coalesce(lwfstatecode,7)='||p_lwfstatecode||' ';
				end if;
		    v_reportquery:=v_reportquery||' and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select m.emp_code,m.rpt_month,m.rpt_year,m.batchid from unprocessed_epfecrreport m)	
			and (t.emp_code,t.mprmonth,t.mpryear,t.batchid)
			not in (select r.emp_code,r.rpt_month,r.rpt_year,regexp_split_to_table(r.batchid,'','') from epfecrreport r where reporttype='''||p_reporttype||''' and  r.isactive=''1'')	
			 group by t.emp_code,t.batchid,t.mprmonth,t.mpryear
			) e1
	---------------------------------------------
	group by emp_code,mprmonth,mpryear
	)e
	------------------------------------------------
			on o.emp_code=e.emp_code
			and o.appointment_status_id<>13
			and o.recordsource= case when '''||p_tptype||'''=''TP'' then ''HUBTPCRM'' else nullif(o.recordsource,''HUBTPCRM'') end
			and (o.emp_id,mprmonth,mpryear,e.batchid,'''||p_reporttype||''')
			not in (select m.appointment_id,m.rpt_month,m.rpt_year,m.batchid,m.reporttype from epfecrreport m where  m.isactive=''1'')';
			
			raise notice 'Query: % ', v_reportquery;	
			
			 execute v_reportquery;
			
			update 	unprocessed_epfecrreport
			set isreportdownloaded='1',
			     downloadedby=p_downloadedby,
				 downloadedon=v_reporttimestamp,
				 downloadedbyip=p_downloadedbyip
			where rpt_month=p_rpt_month
				and rpt_year=p_rpt_year
				and coalesce(isreportdownloaded,'0')<>'1'
				and reporttype=p_reporttype;
			
			
			open rfcreport for
			select null as a;
			return rfcreport;
		end if;
		
		if p_action='RetrieveProcessedArrearChallan' then
			open rfcreport for
			select appointment_id appointment_id,rpt_month rpt_month,rpt_year rpt_year,	
			uan,member_name,
			round(gross_wages::numeric(18,2),0) gross_wages,
			round(epf_wages::numeric(18,2),0) epf_wages,
			round(eps_wages::numeric(18,2),0) eps_wages,
			round(edli_wages::numeric(18,2),0) edli_wages,
			round(epf_contri_remitted::numeric(18,2),0) epf_contri_remitted,
			round(eps_contri_remitted::numeric(18,2),0) eps_contri_remitted,
			round(epf_eps_diff_remitted::numeric(18,2),0) epf_eps_diff_remitted,
			ncp_days,
			refund_of_advances
			,epfecrreport.emp_code,batchid
			,wagestatus
			,esicnumber esinumber
			,ceil(esic_amt::numeric(18,2)) esic_amt
			,to_char(lastworkingday,'dd-mm-yyyy') lastworkingday
			,epfecrreport.fathername
			,emplocation
			,to_char(doj,'dd-mm-yyyy') doj
			,round(employeelwf::numeric(18,2),2) employeelwf
			,round(employerlwf::numeric(18,2),2) employerlwf
			,round(totallwf::numeric(18,2),2) totallwf
			,address
			,reporttype
			,vpf
			,to_char(epfecrreport.createdon at time zone 'utc' at time zone 'Asia/Calcutta', 'DD/MM/YYYY, HH:mi:SS AM')   downloadedon
			, (select name from users where userid =created_by) downloadedby
			,monthdays
			,round(gross_earning::numeric(18,2),0) grossearning
			,ROUND(gross_esi_income::numeric(18,2),2) gross_esi_income
			from epfecrreport
			inner join openappointments o on epfecrreport.emp_code=o.emp_code
			where challanmonth=p_rpt_month
			and challanyear=p_rpt_year
			and reporttype=p_reporttype
			and epfecrreport.isactive='1'
			and o.recordsource= case when p_tptype='TP' then 'HUBTPCRM' else nullif(o.recordsource,'HUBTPCRM') end
			and challantype='Previous'
			and o.customeraccountid=coalesce(nullif(p_customeraccountid,'-9999')::bigint,o.customeraccountid)
			--SIDDHARTH BANSAL 03/08/2024
			AND EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(o.assigned_ou_ids, ''), COALESCE(NULLIF(o.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(o.assigned_ou_ids, ''), COALESCE(NULLIF(o.geofencingid::TEXT, ''), '0')), ','))
			)
			--END
			and 0<> case when p_reporttype='EPF' then epf_contri_remitted 
					when p_reporttype='ESIC'then esic_amt
					when p_reporttype='LWF' then employeelwf end;
			return rfcreport;
		end if;
		end;
	
$BODY$;

ALTER FUNCTION public.uspepfecrreport(integer, integer, character varying, bigint, character varying, character varying, integer, text, text, character varying)
    OWNER TO payrollingdb;

