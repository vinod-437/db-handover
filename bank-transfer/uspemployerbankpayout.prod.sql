-- FUNCTION: public.uspemployerbankpayout(text, bigint, integer, integer, bigint, character varying, character varying, character varying, integer, character varying)

-- DROP FUNCTION IF EXISTS public.uspemployerbankpayout(text, bigint, integer, integer, bigint, character varying, character varying, character varying, integer, character varying);

CREATE OR REPLACE FUNCTION public.uspemployerbankpayout(
	p_action text,
	p_customeraccountid bigint,
	p_month integer DEFAULT 0,
	p_year integer DEFAULT 0,
	p_createdby bigint DEFAULT NULL::bigint,
	p_createdbyip character varying DEFAULT NULL::character varying,
	p_clientcode character varying DEFAULT NULL::character varying,
	p_paymentmode character varying DEFAULT 'Auto'::character varying,
	p_role_id integer DEFAULT 70,
	p_bank_format_type character varying DEFAULT 'HDFC'::character varying)
    RETURNS SETOF refcursor 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
declare 
	v_rfc1 refcursor;
	v_rfc2 refcursor;
	v_rfc3 refcursor;
	v_rfc4 refcursor;
	v_id int:=1;
	v_startdate date;
	v_numberofmonths int;
	v_fileid bigint;
	
	v_filesequence int;
	v_filesuffix varchar(3);
	v_clientcode varchar(20);
	v_filename varchar(50);
	v_month integer;
	v_year integer;
	v_domainname varchar(100);
	v_rec record;
	
	v_initialsalarypayable numeric(18,2);
	v_remainingsalarypayable numeric(18,2);
	v_remaingcredit numeric(18,2);
	v_remainingcredit numeric(18,2);
	v_payout_mode_type varchar(10);

	-- Change - START [2.0]
	v_hsbc_bank_name  refcursor;
	v_hsbc_bank_details refcursor;
	v_filename_hsbc_bank varchar(100);
	v_employer_name varchar(500);
	v_employer_bank_ac_no varchar(100);
	v_ach_transaction_type varchar(100);
	-- Change - END [2.0]

begin
/********************************************************************************
Version 	Date				Change								Done_by
1.0								Initial Version						Shiv Kumar
1.1			21-Mar-2023			Stop KYC Pending Salary				Shiv Kumar
1.2			04-Sep-2023			Disburse advance/voucher			Shiv Kumar
								before payment date
1.3			13-Sep-2023			Change file name		 			Parveen Kumar
1.4			22-Nov-2023			Add payout_mode_type condition		Shiv Kumar
1.5			22-Aug-2024			Advance Payout						Shiv Kumar
1.6			03-Mar-2025			ESIC/PF Revert Case					Shiv Kumar
2.0			21-Feb-2025			Changes 							Parveen Kumar
								1. 
2.1			05-Jul-2025			Negative Salaries					Shiv Kumar
********************************************************************************/
if(	p_month between 1 and 12 and p_year>0) then
	v_month:=p_month;
	v_year:=p_year;
else
	v_month:=extract('month' from current_date-interval '1 month')::int;
	v_year:=extract('year' from current_date-interval '1 month')::int;
end if;

	-- Change - START [2.0]
		SELECT employername, bank_ac_no, ach_transaction_type FROM employer WHERE employerid = 1
		INTO v_employer_name, v_employer_bank_ac_no, v_ach_transaction_type;
	-- Change - END [2.0]
	/********************************************/
	drop table if exists tmpexclusion;
	create temporary table tmpexclusion as
				 	select op.emp_code,
						sum(case when bt.emp_code is null and mts.empid is null then coalesce(ts.netpay,0) else 0 end) netpayabledue
			 		from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
						and ts.is_rejected='0'
				 		and op.recordsource='HUBTPCRM'
				 		and ts.issalaryorliability='S'
						and op.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),op.customeraccountid)
				 		and op.customeraccountid is not null
						and ts.recordscreen in ('Current Wages','Previous Wages')
					inner join tbl_account ta on op.customeraccountid=ta.id	
					left join (select tep.customeracountid,tep.payoutday,row_number()over(partition by tep.customeracountid order by tep.id desc) rn
								from tbl_employerpayoutdate tep	where date_trunc('month',effectivefrom)<=date_trunc('month',current_date)::date
							   and tep.customeracountid=coalesce(nullif(p_customeraccountid,-9999),tep.customeracountid)
							  ) tep on ta.id=tep.customeracountid and tep.rn=1
					left join banktransfers bt on ts.emp_code=bt.emp_code and ts.batchid=bt.batchcode and ts.mprmonth=bt.salmonth and ts.mpryear=bt.salyear and bt.isrejected='0'
				 	left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id and mts.IsActive='1' and  coalesce(mts.PausedStatus,'Enable')='Enable'
						and mts.ProcessYear =ts.mpryear	and mts.ProcessMonth =ts.mprmonth
					where 	(
							(make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date)::date)
								 or
							(ta.payout_period='Advance' and extract('day' from current_date)::int>=coalesce(tep.payoutday,ta.payoutday) and make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date+interval '1 month')::date)
							)	
				 group by op.emp_code 
				 having sum(case when bt.emp_code is null and mts.empid is null then coalesce(ts.netpay,0) else 0 end)<0;
/***********************************************************/
	drop table if exists tmpqualifiedcustomers;
	create temporary table tmpqualifiedcustomers as
			select tblrec.customeraccountid as customeraccountid,
					coalesce(tblpayday.payday,tblrec.payoutday) payoutday,
					tblrec.accountname,
					trunc(coalesce(tblrec.netamountreceived,0))::numeric(18,2) credit,
					trunc(coalesce(tblpay.netamountpaid,0))::numeric(18,2)+coalesce(adjustment_amount_invoice,0) debit,
					(coalesce(tblrec.netamountreceived,0)-coalesce(tblpay.netamountpaid,0)-coalesce(tblpayboth.netpayabledue,0)-coalesce(adjustment_amount_invoice,0)-coalesce(negativepayout,0))::numeric(18,2) balance,
					case when (coalesce(tblrec.netamountreceived,0)-coalesce(tblpay.netamountpaid,0)-round(coalesce(tblpayboth.netpayabledue,0)::numeric(18,2),2)-coalesce(adjustment_amount_invoice,0)-coalesce(negativepayout,0))<-50 then 'Insufficient' else 'Sufficient' end as balancestatus,
					trunc(coalesce(tblpayboth.netpayabledue,0))::numeric(18,2) netpayabledue,
					trunc(coalesce(tblpayboth.netpauseddue,0))::numeric(18,2) netpauseddue,
					remaingcredit,
					case when /*coalesce(remaingcredit,0)<=0 and*/ mec.customer_account_id is not null then'Y' else 'N' end iscreditavailable
					--,salarymode
					,tblrec.payout_mode_type
					,tblrec.payout_period
		from (
				select ta.id customeraccountid,ta.accountname,
			  		ceil(sum(netamount)+sum(coalesce(tr.excess_amount,0))) netamountreceived,
					max(payoutday) payoutday,
					sum(case when coalesce(tr.credit_applicable,'N')='Y' and lower(coalesce(tr.status,'Pending')) in ('pending','outstanding') and coalesce(credit_used,'N') ='N' then coalesce(netamount,0)/*-coalesce(credit_amount_used,0.00)*/ else 0.00 end) as remaingcredit
					,ta.payout_mode_type
					,coalesce(ta.payout_period,'Current') payout_period
			 	from tbl_account ta inner join tbl_receivables tr
			  		on ta.id=tr.customeraccountid
 			  		and ta.status='1' and ta.pause_inactive_status='Active'
 			  		and  tr.isactive='1'
					and (entrytype='Receipt' or packagename='Starting Payment') 
 			  		and (tr.status='Paid' or (coalesce(tr.credit_applicable,'N')='Y' and lower(coalesce(tr.status,'Pending')) in ('pending','outstanding') and coalesce(credit_used,'N') ='N'))
					and ta.id=coalesce(nullif(p_customeraccountid,-9999),ta.id)
			 		group by ta.id,ta.accountname,ta.payout_mode_type,coalesce(ta.payout_period,'Current')
			 ) tblrec
			 left join (select tep.customeracountid,tep.payoutday payday,
						row_number()over(partition by tep.customeracountid order by tep.id desc) rn
						from tbl_employerpayoutdate tep
						where date_trunc('month',tep.effectivefrom)<=date_trunc('month',current_date)::date
					   and tep.customeracountid=coalesce(nullif(p_customeraccountid,-9999),tep.customeracountid)
					   ) tblpayday
			on 	tblrec.customeraccountid=tblpayday.customeracountid
			and tblpayday.rn=1	   
			 left join (
				 	select op.customeraccountid,
				 		sum(coalesce(ts.netpay,0)+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or ts.esichallannumber is not null) then ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric) else 0 end+case when make_date(ts.mpryear,ts.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(ts.professionaltax,0)+coalesce(ts.tds,0)) netamountpaid
				 	from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
						and ts.is_rejected='0'
				 		and op.recordsource='HUBTPCRM'
				 		and ts.issalaryorliability='S'
						and op.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),op.customeraccountid)
				 		and op.customeraccountid is not null
						and ts.recordscreen in ('Current Wages','Previous Wages')
					 /********************Change 1.6 starts*******************************/
					left join (SELECT tcd.customeraccountid, tcd.challan_month, tcd.challan_year,
								sum(case when tcd.challantype='PF' then tcd.totalchallanamount::numeric else 0 end) as pfchallanamount,
								sum(case when tcd.challantype='ESIC' then tcd.totalchallanamount::numeric else 0 end) as esichallanamount
									FROM public.tbl_employer_challan_deposit tcd
									where tcd.isactive='1'
									and nullif(trim(tcd.challannumber),'') is not null
									--and tcd.customeraccountid=p_customeraccountid 
								group by tcd.customeraccountid, tcd.challan_month, tcd.challan_year
							  )	 tmpchallans
						 on op.customeraccountid= tmpchallans.customeraccountid
						 and make_date(tmpchallans.challan_year,tmpchallans.challan_month,1)=date_trunc('month',to_date(left(ts.hrgeneratedon,11),'dd Mon yyyy'))::date
		/********************Change 1.6 ends*******************************/
					
					inner join banktransfers bt on ts.emp_code=bt.emp_code and ts.batchid=bt.batchcode and ts.mprmonth=bt.salmonth and ts.mpryear=bt.salyear and bt.isrejected='0'
				 group by op.customeraccountid
			 ) tblpay
			 on tblrec.customeraccountid=tblpay.customeraccountid::bigint	   
			 left join (
				 	select op.customeraccountid,
				 		sum(coalesce(ts.netpay,0)+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or ts.esichallannumber is not null) then ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric) else 0 end+case when make_date(ts.mpryear,ts.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(ts.professionaltax,0)+coalesce(ts.tds,0)) netpeparedsalamount,
						sum(case when bt.emp_code is null and mts.empid is null then (coalesce(ts.netpay,0)+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or ts.esichallannumber is not null) then ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric) else 0 end+case when make_date(ts.mpryear,ts.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(ts.professionaltax,0)+coalesce(ts.tds,0)) else 0 end) netpayabledue,
						sum(case when bt.emp_code is null and mts.empid is not null then (coalesce(ts.netpay,0)+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or ts.esichallannumber is not null) then ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric) else 0 end+case when make_date(ts.mpryear,ts.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(ts.professionaltax,0)+coalesce(ts.tds,0)) else 0 end) netpauseddue
				 		--,case when ts.attendancemode='MPR' or netpay<0 then 'MPR' else 'Ledger' end  salarymode
			 		from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
						and ts.is_rejected='0'
				 		and op.recordsource='HUBTPCRM'
				 		and ts.issalaryorliability='S'
						and op.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),op.customeraccountid)
				 		and op.customeraccountid is not null
						and ts.recordscreen in ('Current Wages','Previous Wages')
				 		and ts.emp_code not in (select te.emp_code from tmpexclusion te)

						inner join tbl_account ta on op.customeraccountid=ta.id	
						left join (select tep.customeracountid,tep.payoutday,row_number()over(partition by tep.customeracountid order by tep.id desc) rn
									from tbl_employerpayoutdate tep	where date_trunc('month',effectivefrom)<=date_trunc('month',current_date)::date
								   and tep.customeracountid=coalesce(nullif(p_customeraccountid,-9999),tep.customeracountid)
								  ) tep on ta.id=tep.customeracountid and tep.rn=1
					left join banktransfers bt on ts.emp_code=bt.emp_code and ts.batchid=bt.batchcode and ts.mprmonth=bt.salmonth and ts.mpryear=bt.salyear and bt.isrejected='0'
				 	left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id and mts.IsActive='1' and  coalesce(mts.PausedStatus,'Enable')='Enable'
						and mts.ProcessYear =ts.mpryear	and mts.ProcessMonth =ts.mprmonth
				 	left join (SELECT tcd.customeraccountid, tcd.challan_month, tcd.challan_year,
								sum(case when tcd.challantype='PF' then tcd.totalchallanamount::numeric else 0 end) as pfchallanamount,
								sum(case when tcd.challantype='ESIC' then tcd.totalchallanamount::numeric else 0 end) as esichallanamount
									FROM public.tbl_employer_challan_deposit tcd
									where tcd.isactive='1'
									and nullif(trim(tcd.challannumber),'') is not null
									--and tcd.customeraccountid=p_customeraccountid 
								group by tcd.customeraccountid, tcd.challan_month, tcd.challan_year
							  )	 tmpchallans
						 on op.customeraccountid= tmpchallans.customeraccountid
						 and make_date(tmpchallans.challan_year,tmpchallans.challan_month,1)=date_trunc('month',to_date(left(ts.hrgeneratedon,11),'dd Mon yyyy'))::date 			   
				 
				 where 	(
						(make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date)::date)
							 or
						(ta.payout_period='Advance' and extract('day' from current_date)::int>=coalesce(tep.payoutday,ta.payoutday) and make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date+interval '1 month')::date)
						)
				 group by op.customeraccountid
			 ) tblpayboth
			 on tblrec.customeraccountid=tblpayboth.customeraccountid::bigint
			 left join mst_employer_credit mec on tblrec.customeraccountid=mec.customer_account_id and mec.is_active='1' and mec.monthly_credit_amount_limit>0 and mec.monthly_credit_percent_limit>0
			 left join (select customeraccountid,sum(coalesce(adjustment_amount,0)) adjustment_amount_invoice
					   from tbl_receivables where entrytype='Invoice' and isactive='1' and status='Paid'
					  and customeraccountid = coalesce(nullif(p_customeraccountid, -9999), customeraccountid)
					   group by customeraccountid
					) tblinvoice
					on tblrec.customeraccountid=tblinvoice.customeraccountid::bigint
					
			left join (select ta.id as customerid,sum(ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0)) 
				  +sum(round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric)) 
					as negativepayout
			 		from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
						and ts.is_rejected='0'
				 		and op.recordsource='HUBTPCRM'
				 		and ts.issalaryorliability='S'
						and op.customeraccountid=p_customeraccountid
				 		and op.customeraccountid is not null
						and ts.recordscreen in ('Current Wages','Previous Wages')
					inner join tbl_account ta on op.customeraccountid=ta.id	and ta.payout_mode_type='standard'
					left join (select tep.customeracountid,tep.payoutday,row_number()over(partition by tep.customeracountid order by tep.id desc) rn
								from tbl_employerpayoutdate tep	where date_trunc('month',effectivefrom)<=date_trunc('month',current_date)::date
							   and tep.customeracountid=p_customeraccountid
							  ) tep on ta.id=tep.customeracountid and tep.rn=1
					left join banktransfers bt on ts.emp_code=bt.emp_code and ts.batchid=bt.batchcode and ts.mprmonth=bt.salmonth and ts.mpryear=bt.salyear and bt.isrejected='0'
				 		/************************************************************/
			left join (SELECT tcd.customeraccountid, tcd.challan_month, tcd.challan_year,
						sum(case when tcd.challantype='PF' then tcd.totalchallanamount::numeric else 0 end) as pfachallanamount,
						sum(case when tcd.challantype='ESIC' then tcd.totalchallanamount::numeric else 0 end) as esichallanamount
							FROM public.tbl_employer_challan_deposit tcd
							where tcd.isactive='1'
							and nullif(trim(tcd.challannumber),'') is not null
							and tcd.customeraccountid=p_customeraccountid 
						group by tcd.customeraccountid, tcd.challan_month, tcd.challan_year
					  )	 tmpchallans
				 on op.customeraccountid= tmpchallans.customeraccountid
				 and make_date(tmpchallans.challan_year,tmpchallans.challan_month,1)=date_trunc('month',to_date(left(ts.hrgeneratedon,11),'dd Mon yyyy'))::date
				left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id and mts.IsActive='1' and  coalesce(mts.PausedStatus,'Enable')='Enable'
						and mts.ProcessYear =ts.mpryear	and mts.ProcessMonth =ts.mprmonth
					where 	(
							(make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date)::date)
								 or
							(ta.payout_period='Advance' and extract('day' from current_date)::int>=coalesce(tep.payoutday,ta.payoutday) and make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date+interval '1 month')::date)
							)
					and bt.emp_code is null and mts.empid is null
					   group by ta.id
				 having sum(coalesce(ts.netpay,0))<=0) tmpnegativesalaries
				 on tmpnegativesalaries.customerid=tblrec.customeraccountid;
	
		drop table if exists tmppayout;
		create temporary table tmppayout as
				select oa.emp_id,oa.emp_code,tm.batchid,
				CASE WHEN p_bank_format_type = 'HSBC' THEN 'BATCHREF'||trim(LEFT(TO_CHAR(TO_TIMESTAMP (v_month::text, 'MM'), 'Month'),5))||v_year ELSE 'SALAKAL'||trim(LEFT(TO_CHAR(TO_TIMESTAMP (v_month::text, 'MM'), 'MONTH'),5))||v_year END bankbatchcode,
				-- 'SALAKAL'||trim(LEFT(TO_CHAR(TO_TIMESTAMP (v_month::text, 'MM'), 'MONTH'),5))||v_year bankbatchcode,  
				oa.emp_name,trim(oa.bankaccountno) bankaccountno
				,trim(oa.ifsccode) ifsccode,oa.bankname
				,oa.bankbranch,11 static_col,round(tm.netpay) salary,
				to_char(current_date,'yyyymmdd') salary_yearmonday,
				tm.mpryear salyear,tm.mprmonth salmonth
				,'TP' tptype
				,oa.posting_department
				,ta.id
				,tm.attendancemode
				from tbl_account ta
					inner join openappointments oa on oa.customeraccountid = ta.id 
					and ta.status = '1' 
					and oa.converted = 'Y' 
					and oa.appointment_status_id = '11'
					and oa.recordsource='HUBTPCRM'
					and (ta.id=p_customeraccountid or p_customeraccountid=-9999)
					-- and ta.id=coalesce(nullif(p_customeraccountid,-9999),ta.id)
					
					left join (select tep.customeracountid,tep.payoutday,row_number()over(partition by tep.customeracountid order by tep.id desc) rn
								from tbl_employerpayoutdate tep	where date_trunc('month',effectivefrom)<=date_trunc('month',current_date)::date
							   and tep.customeracountid=coalesce(nullif(p_customeraccountid,-9999),tep.customeracountid)
							  ) tep on ta.id=tep.customeracountid and tep.rn=1
					inner join tbl_monthlysalary tm on oa.emp_code=tm.emp_code 
					and tm.is_rejected='0'
					and tm.issalaryorliability='S'
					and tm.recordscreen in ('Current Wages','Previous Wages')
					and coalesce(is_account_verified,'0'::bit)='1'::bit
					--and make_date(tm.mpryear,tm.mprmonth,1)<date_trunc('month',current_date+case when extract('day' from current_date)::int>=25 then interval '1 month' else interval '0 month' end)::date
					and tm.emp_code not in (select te.emp_code from tmpexclusion te)
				left join ManageTempPausedSalary mts on mts.EmpId=oa.emp_id 
				and mts.IsActive='1'
				and  coalesce(mts.PausedStatus,'Enable')='Enable'
				and mts.ProcessYear =tm.mpryear
				and mts.ProcessMonth =tm.mprmonth
				where ta.status = '1' and mts.EmpId is null
				--and make_date(tm.mpryear,tm.mprmonth,1)<date_trunc('month',current_date+case when extract('day' from current_date)::int>=25 then interval '1 month' else interval '0 month' end)::date
				and (
					(make_date(tm.mpryear,tm.mprmonth,1)<date_trunc('month',current_date)::date)
						 or
					(ta.payout_period='Advance' and extract('day' from current_date)::int>=coalesce(tep.payoutday,ta.payoutday) and make_date(tm.mpryear,tm.mprmonth,1)<date_trunc('month',current_date+interval '1 month')::date)
					)
				and (oa.emp_code,tm.batchid,tm.mprmonth,tm.mpryear)
				not in (select emp_code,batchcode,salmonth,salyear from banktransfers where isrejected='0')
				;

if p_action='GetTPDuePayoutSummary'  then
	open v_rfc2 for
	select  emp_id,emp_code,string_agg(batchid,',') batchid,string_agg(distinct bankbatchcode,',') bankbatchcode,
	max(emp_name) emp_name,max(bankaccountno) bankaccountno,max(ifsccode) ifsccode,max(bankname) bankname,
	max(static_col) static_col,sum(salary) salary,max(salary_yearmonday) salary_yearmonday,
	current_timestamp createdon,string_agg(salyear::text||'-'||salmonth::text,',') salmonth  ,
	string_agg(posting_department,',') as posting_department 
	,tq.customeraccountid,tq.payoutday||'th of every month'||coalesce(' - '||nullif(tq.payout_period,'Current'),'') payoutday ,tq.accountname
	,max(tq.balance) balance
	,max(balancestatus) balancestatus
	,max(netpayabledue) netpayabledue
	,max(netpauseddue) netpauseddue
	,max(iscreditavailable) iscreditavailable
	,case when (extract('day' from current_date)>=tq.payoutday) or tq.payout_period='Advance' then 'PayoutReached' else 'Waiting for Payout Date ('||tq.payoutday||')' end as payoutreachstatus
	,'Salary' attendancemode
	from (select emp_id,emp_code,batchid,bankbatchcode,emp_name,bankaccountno,ifsccode,bankname,
		  		bankbranch,static_col,salary,salary_yearmonday,			
				salyear,salmonth,tptype,posting_department,id
		 		from tmppayout
		 )tmppayout inner join tmpqualifiedcustomers tq
			on tmppayout.id=tq.customeraccountid
			and tq.payout_mode_type='standard'
	group by emp_id,emp_code,tq.customeraccountid,tq.payoutday,tq.accountname,tq.payout_period
	;

	return next v_rfc2;

end if;

if p_action='SaveTPPayout'  then 

	select payout_mode_type from tbl_account 
	where id=p_customeraccountid 
	into v_payout_mode_type;

if v_payout_mode_type='standard' then 
	select remaingcredit,netpayabledue 
	from tmpqualifiedcustomers 
	into v_remaingcredit,v_initialsalarypayable;

	v_remainingsalarypayable:=v_initialsalarypayable;
	v_remainingcredit:=v_remaingcredit;
	
	
				drop table IF EXISTS tmpupdatedpayouts;
				create temporary table tmpupdatedpayouts
				as
				select * from banktransfers where 1=2;
				
		with tmpinsertedpayouts as (
		insert into banktransfers (emp_id,emp_code,batchcode,bankbatchcode,emp_name,bankaccountno,ifsccode,bankname,
								bankbranch,static_col,salary,salary_yearmonday,createdby,createdon,ipaddcreatedby,salyear,salmonth,tptype
								, referencenumber, remitterbankname)
						select emp_id,emp_code,batchid,bankbatchcode,emp_name,bankaccountno,ifsccode,bankname,
							bankbranch,static_col,salary,salary_yearmonday,p_createdby createdby,current_timestamp createdon,p_createdbyip createdbyip,salyear,salmonth,'TP'
							, 'TRN'||TO_CHAR(nextval('hsbc_transaction_id_seq'), 'FM00000000'), p_bank_format_type
							from (select emp_id,emp_code,batchid,bankbatchcode,emp_name,bankaccountno,ifsccode,bankname,
											bankbranch,static_col,salary,salary_yearmonday,			
											salyear,salmonth,tptype,posting_department,id
										   ,attendancemode actualattendancemode
											from tmppayout
									 )tmppayout inner join tmpqualifiedcustomers tq
						on tmppayout.id=tq.customeraccountid
						and ((extract('day' from current_date)>=case when p_paymentmode='Manual' then extract('day' from current_date) else tq.payoutday end ) or tq.payout_period='Advance')
						and tq.balancestatus='Sufficient' 
						and (emp_code) in (select emp_code 
									 from /*(select emp_id,emp_code,batchid,bankbatchcode,emp_name,bankaccountno,ifsccode,bankname,
											bankbranch,static_col,salary,salary_yearmonday,			
											salyear,salmonth,tptype,posting_department,id
										   ,attendancemode actualattendancemode
											from tmppayout
									 )*/tmppayout inner join tmpqualifiedcustomers tq
									on tmppayout.id=tq.customeraccountid
									--and ((extract('day' from current_date)>=case when p_paymentmode='Manual' then extract('day' from current_date) else tq.payoutday end) or tq.payout_period='Advance')
									and tq.balancestatus='Sufficient' 
									 group by emp_code
									 having sum(salary)>=0
									)
				returning *
			)
	insert into tmpupdatedpayouts
	select * from tmpinsertedpayouts;
						
		update tbl_monthlysalary
			set issalarydownloaded='P'
			,salarydownloadedby=p_createdby,
			salarydownloadedon=current_timestamp,
			salarydownloadedbyip=p_createdbyip
		where (emp_code,mpryear,mprmonth,batchid)
         in (select emp_code,salyear,salmonth,batchcode
			 			from tmpupdatedpayouts);
		
 open v_rfc1 for select bankbatchcode,emp_name,bankaccountno,ifsccode,11 account_type,sum(salary)::numeric(18,2),salary_yearmonday 
 from tmpupdatedpayouts
 group by bankbatchcode,emp_name,bankaccountno,ifsccode,salary_yearmonday 
 having sum(salary)::numeric(18,2)>0;
 	return next v_rfc1;	
	
v_domainname:='AKALINS';
v_clientcode:=coalesce(p_clientcode,'KAL30NES');

select max(filesequence) into v_filesequence
	from public.tblhdfcfiledetails
where clientcode=v_clientcode
and filedownloadday=extract('day' from current_date)::int
and filedownloadmonth=extract('month' from current_date)::int
and filedownloadyear=extract('year' from current_date)::int;

v_filesequence:=coalesce(v_filesequence,0);
v_filesequence:=v_filesequence+1;
-- START [1.3] - Change File name as per the mail of Sujesh Sir
-- v_filename:=v_domainname||'_'||v_clientcode||'_'||v_clientcode||to_char(current_date,'ddmm')||'.'||lpad(v_filesequence::text,3,'0');
v_filename:=v_clientcode||to_char(current_date,'ddmm')||'.'||lpad(v_filesequence::text,3,'0');
-- END [1.3]

	INSERT INTO public.tblhdfcfiledetails
	(
		filesequence, 
		clientcode,
		filedownloadday,
		filedownloadmonth,
		filedownloadyear,
		filedownload_ddmm,
		filesuffix, 
		payoutfile_name,
		createdon, 
		isactive, 
		filemovedtosource, 
		filesent_to_hdfc, 
		bankprocess_status
	)
	VALUES
	(
		v_filesequence,
		v_clientcode,
		extract('day' from current_date),
		extract('month' from current_date),
		extract('year' from current_date),
		to_char(current_date,'ddmm'),
		lpad(v_filesequence::text,3,'0'),
		v_filename,
		current_timestamp,
		'1',
		'0',
		'0',
		'Pending'
   );
		   
	open v_rfc2 for
		select v_filename as filename;
 	return next v_rfc2;

	open v_rfc3 for
		select * from tmpupdatedpayouts;					
 	return next v_rfc3;
end if;

	v_filename_hsbc_bank := ('AKALSalary_'||TO_CHAR(CURRENT_DATE, 'Mon_YYYY'));
	OPEN v_hsbc_bank_name FOR
		SELECT v_filename_hsbc_bank AS file_name_hsbc_bank;
	RETURN NEXT v_hsbc_bank_name;

	OPEN v_hsbc_bank_details FOR
		SELECT
			v_ach_transaction_type ach_transaction_type,
			referencenumber reference_number,
			bankbatchcode batch_ref_no,
			emp_name bene_name,
			v_employer_bank_ac_no remitter_ac_no,
			v_employer_name remitter_name,
			'Salary '||TO_CHAR(TO_DATE(salary_yearmonday, 'YYYYMMDD'), 'Mon')||' '||TO_CHAR(TO_DATE(salary_yearmonday, 'YYYYMMDD'), 'YY') narration,
			TO_CHAR(CURRENT_DATE, 'dd/mm/yyyy') value_date,
			SUM(salary)::numeric(18,2) amount,
			'' email_address_1,
			'' email_address_2,
			'' email_address_3,
			'' advise_col1,
			'' advise_col2,
			'' advise_col3,
			'' advise_col4,
			'' advise_col5,
			bankaccountno bene_bank_account_number,
			ifsccode bene_rtgs_codes,
			bankname bene_bank_name
		FROM tmpupdatedpayouts
		GROUP BY referencenumber, salary_yearmonday, bankname, bankbatchcode, emp_name, bankaccountno, ifsccode;
		-- having sum(salary)::numeric(18,2)>0;
	return next v_hsbc_bank_details;
end if;
-- exception when others then
--  open v_rfc4 for select -1 as cnt;
--  	return next v_rfc4;
end;
$BODY$;

ALTER FUNCTION public.uspemployerbankpayout(text, bigint, integer, integer, bigint, character varying, character varying, character varying, integer, character varying)
    OWNER TO stagingpayrolling_app;

