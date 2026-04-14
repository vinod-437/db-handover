-- FUNCTION: public.uspsavevoucher(bigint, bigint, text, integer, integer, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, bigint, character varying, character varying, character varying, text, integer, bigint, bigint, bigint)

-- DROP FUNCTION IF EXISTS public.uspsavevoucher(bigint, bigint, text, integer, integer, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, bigint, character varying, character varying, character varying, text, integer, bigint, bigint, bigint);

CREATE OR REPLACE FUNCTION public.uspsavevoucher(
	p_emp_id bigint,
	p_emp_code bigint,
	p_ledgerdata text,
	p_mprmonth integer,
	p_mpryear integer,
	p_createdby bigint,
	p_createdbyip character varying,
	p_action character varying,
	p_loanmasterid bigint DEFAULT NULL::bigint,
	p_remarks character varying DEFAULT ''::character varying,
	p_createdbyusertype character varying DEFAULT ''::character varying,
	p_voucherorigin character varying DEFAULT 'Web'::character varying,
	p_is_reimbursement_claim character varying DEFAULT 'N'::character varying,
	p_reimbursement_claim_id bigint DEFAULT NULL::bigint,
	p_voucher_source character varying DEFAULT ''::character varying,
	p_unique_bulk_voucher_batch_id character varying DEFAULT ''::character varying,
	p_isadvice character varying DEFAULT 'N'::character varying,
	p_tdsdeductionmonth text DEFAULT 'current'::text,
	p_assetid integer DEFAULT '-9999'::integer,
	p_fnfid bigint DEFAULT NULL::bigint,
	p_encashment_id bigint DEFAULT NULL::bigint,
	p_bonus_id bigint DEFAULT NULL::bigint)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
v_status int:=0;
v_attendancecount int:=0;
v_manualattendancecount int:=0;
v_autounprocessedcount int:=0;
v_autopaiddays int:=0;
v_monthdays int;
v_customeraccountname text;
v_contractno text;
v_mprmonth int;
v_mpryear int;

v_generatedattendanceid bigint;
v_generatedledgerid bigint;
v_emp_id bigint;
v_recmst_otherduction record;
v_headid int;
v_amount numeric(18,2);
v_batchid varchar(255);
v_tds numeric(18,2);

v_employeresirate numeric(18,2);
v_employeeesirate numeric(18,2);
v_grossearning numeric(18,2);
v_grossdeduction numeric(18,2);
v_netpay numeric(18,2);
v_otherledgerarears numeric(18,2);
v_otherledgerdeductions numeric(18,2);
v_otherledgerarearwithoutesi numeric(18,2);
v_refund numeric(18,2);

v_alreadytds  numeric(18,2);

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
	v_salrecord record;
	v_disbursementmode text;
	v_istaxable varchar(1);
	v_left_flag varchar(1);
	v_dateofrelieveing date;
	v_pancard varchar(10);
	v_is_billable varchar(1);
	v_recordsource varchar(30);
	v_tptype varchar(30):='NonTP';
	v_loan numeric(18,2):=0.00;
	v_advance numeric(18,2):=0.00;
	v_empsalaryregister empsalaryregister%rowtype;
	v_rec record;
	v_walletamount numeric(18,2):=0.00;
	v_customeraccountid int;
	v_currentmonthadvancepaid  numeric(18,2):=0.00;
	v_investmentresult int;
	v_grossesicincome numeric(18,2):=0;
	v_tbl_monthlysalary tbl_monthlysalary%rowtype;
	v_appcount int;
begin
/*************************************************************************
Version 	Date			Change									Done_by
1.0			25-Aug-2022		Initial Version							Shiv Kumar
1.1			18-Oct-2022		Separate Loans and Advances				Shiv Kumar
1.2			09-Nov-2022		Vouchers not allowed after				Shiv Kumar
							 date of relieving
1.3			15-Nov-2022		Add cms_contractid, cms_trackingid		Shiv Kumar
1.4			10-Nov-2022		Existing Tax on Pancard				  	Shiv Kumar
1.5			12-May-2023		Existing Tax on Pancard				  	Shiv Kumar
1.5			12-May-2023		Existing Tax on Pancard				  	Shiv Kumar
1.6			22-Jun-2023		TP Voucher							  	Shiv Kumar
1.7			31-Aug-2023		Loan/Advance value as negative amount  	Shiv Kumar
							in respective column in place of
							gross earning
1.8			01-Sep-2023		Add Limits as per monthly salary and  	Shiv Kumar
							Wallet Amount
1.8			01-Sep-2023		Add p_is_reimbursement_claim,  			Parveen Kumar
							and p_reimbursement_claim_id
1.9			19-Feb-2025		Populate Monthwise Investment		Shiv Kumar
2.0			19-JUN-2025		TDS Exemption						Shiv Kumar
2.1			13-Sep-2025		Work flow integration				Shiv Kumar
*************************************************************************/
--select emp_id from openappointments where emp_code=p_emp_code into v_emp_id;

/*********change 1.2 starts*************************/
select emp_id,case when recordsource='HUBTPCRM' then 'TP' else 'NonTP' end,coalesce(left_flag,'N'),dateofrelieveing,nullif(trim(pancard),''),customeraccountid from openappointments where emp_code=p_emp_code
into v_emp_id,v_tptype,v_left_flag,v_dateofrelieveing,v_pancard,v_customeraccountid;
-- if v_left_flag='Y' and current_date>v_dateofrelieveing then
--		return 0;
-- end if;
/*********change 1.2 ends*************************/
if EXISTS (SELECT * FROM pg_catalog.pg_class c   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    		WHERE  c.relname = 'tmp_tbl_monthlysalary' AND c.relkind = 'r' and n.oid=pg_my_temp_schema()
					  ) then
delete from  tmp_tbl_monthlysalary;
else
create temporary table tmp_tbl_monthlysalary as select * from tbl_monthlysalary where 1=2;
end if;		
/*********change 1.8 starts*************************/
		DROP  TABLE  IF EXISTS tmp_ledgers;
	    create temp table tmp_ledgers(headid int,
									headname varchar(100),
									amount numeric(18,2),
								   	masterheadname varchar(100),
									is_taxable  varchar(1),
									is_billable character varying(1) 
									);
			   
	   insert into tmp_ledgers(headid,headname,amount,masterheadname,is_taxable,is_billable)
	   SELECT headid::bigint,headname::text,amount::numeric(18,2),masterheadname,is_taxable,is_billable
	   		FROM 
			json_populate_recordset(null::empledger_type,p_ledgerdata::json);
		
	select * from tmp_ledgers into v_rec; 
	
	select * from empsalaryregister where appointment_id=v_emp_id and isactive='1' order by id desc limit 1
	into v_empsalaryregister;	
if v_tptype='TP' and v_rec.headid=53 then
	
	select sum(ts.netpay) netamountpaid
		from openappointments op inner join tbl_monthlysalary ts
		on op.emp_code=ts.emp_code
		and ts.is_rejected='0'
		and op.recordsource='HUBTPCRM'
		and op.emp_code=p_emp_code
		inner join public.tbl_employeeledger tl on ts.emp_code=tl.emp_code and ts.disbursedledgerids=tl.id::text
		and tl.headid=53
		where mprmonth=p_mprmonth and mpryear=p_mpryear
		into v_currentmonthadvancepaid;

		v_currentmonthadvancepaid:=coalesce(v_currentmonthadvancepaid,0);
-- 	if v_rec.amount> v_empsalaryregister.salaryinhand then
-- 		return 2;
-- 	end if;

Raise notice 'Step 1';
	select (coalesce(tblrec.netamountreceived,0)-coalesce(tblpay.netamountpaid,0))::numeric(18,2) barebalance
		from (
			select customeraccountid,
			sum(netamount) netamountreceived,
			sum(case when tr.status='Paid' then netamount else 0.0 end) barenetamountreceived,
			max(payoutday) payoutday
			from tbl_account ta inner join tbl_receivables tr
			on ta.id=tr.customeraccountid
			and ta.status='1' and ta.pause_inactive_status='Active'
			and  tr.isactive='1' 
			and (tr.status='Paid' /*or (tr.status='Outstanding' and coalesce(tr.credit_applicable,'N')='Y')*/)
			and ta.id=coalesce(nullif(v_customeraccountid,-9999),ta.id)
			group by customeraccountid
		) tblrec
		left join (
			select op.customeraccountid,
			sum((coalesce(ts.netpay,0)+coalesce(ceil(ts.employeeesirate),0)+coalesce(round(ts.employeresirate::numeric),0)+coalesce(ts.epf,0)+coalesce(ts.vpf,0)+coalesce(ts.ac_1,0)+coalesce(ts.ac_10,0)+coalesce(ts.ac_2,0)+coalesce(ts.ac21,0)+coalesce(ts.lwf_employer,0)+coalesce(ts.lwf_employee,0)+coalesce(ts.professionaltax,0)+coalesce(ts.tds,0))*(case when coalesce(tl.headid,0)<>67 then 1 when mprmonth=p_mprmonth and mpryear=p_mpryear then  100.0/75.0 else 0.0 end)) netamountpaid
			from openappointments op inner join tbl_monthlysalary ts
			on op.emp_code=ts.emp_code
			and ts.is_rejected='0'
			and op.recordsource='HUBTPCRM'
			and op.customeraccountid=coalesce(nullif(v_customeraccountid,-9999),op.customeraccountid)
			and op.customeraccountid is not null
			left join public.tbl_employeeledger tl on ts.emp_code=tl.emp_code and ts.disbursedledgerids=tl.id::text
			group by op.customeraccountid
		) tblpay
		on tblrec.customeraccountid=tblpay.customeraccountid::bigint
		into v_walletamount;
	v_walletamount:=coalesce(v_walletamount,0);
-- 	if v_rec.amount>v_walletamount*.75 then
-- 		return 3;
-- 		--return v_walletamount::int;
-- 	end if;

Raise notice 'Step 2';
	if p_action='GetTPAdvanceStatus' then
		return -1;
		if v_rec.amount> greatest(v_empsalaryregister.salaryinhand-v_currentmonthadvancepaid,0) or v_rec.amount>v_walletamount*.75 then
			return least(floor(greatest(v_empsalaryregister.salaryinhand-v_currentmonthadvancepaid,0))::bigint,(floor(greatest(v_walletamount,0)*.75))::bigint);
		else
			return -1;
		end if;	
	end if;
end if;
/*********change 1.8 ends*************************/

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

 select DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE ) - INTERVAL '1 month 1 DAY')::date,
	DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE  - INTERVAL '1 DAY')::date,
	(DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE ) - INTERVAL '1 DAY')::date
	into v_salstartdate,v_salenddate,v_prevsaldate,v_advancesalstartdate,v_advancesalenddate;
/**************************************************************************/
v_monthdays:=date_part('day',DATE_TRUNC('MONTH', (p_mpryear||'-'||p_mprmonth||'-01')::DATE ) - INTERVAL '1 DAY');
if  coalesce(p_action,'')<>'GetVoucherTDS' then
INSERT INTO public.cmsdownloadedwages(
	 mprmonth, mpryear, empcode, employeename, 
	 pancardno,lossofpay, totalpaiddays,  remark,isactive, createdby,
	 createdon, createdbyip,  batch_no,  totalsalarydays, 
	 transactionid, attendancemode, manualmodereason,totalleavetaken,
	 customeraccountname, contractno 
	,dateofjoining, deputeddate, 
	projectname, agencyname,
	contractcategory, contracttype,
	dateofleaving,  companycode, bunit,  bunitname, agencyid,
	minexperience, maxexperience, jobrole,
	educationqualification, eduqualspecialization, 
	skillstoolstech, contractstartdate, contractenddate, 
	relieveddate, multi_performerwagesflag,
	cms_jobid, cms_posting_department, cms_posting_location,hrgeneratedon
	,cms_contractid,cms_trackingid /*Change 1.3*/)
select p_mprmonth, p_mpryear, p_emp_code, openappointments.emp_name,
	openappointments.pancard,0,0, 'Voucher Disbursement','1', p_createdby, 
	current_timestamp, p_createdbyip,  (clock_timestamp()::text)||p_mprmonth::text||p_mpryear::text||coalesce(p_assetid,0)::text, 0,--------------
	nextval('transactionid_seq'), 'Ledger', 'Voucher',0,--------------
	tmpcontract.customeraccountname,tmpcontract.contractno,
	coalesce(tmpcontract.dateofjoining,openappointments.dateofjoining),tmpcontract.deputeddate,
	coalesce(tmpcontract.projectname,contract_name), coalesce(tmpcontract.agencyname,openappointments.agencyname),
	coalesce(tmpcontract.contractcategory,contract_category), coalesce(tmpcontract.contracttype,type_of_contract), 
	coalesce(tmpcontract.dateofleaving,openappointments.dateofrelieveing),  tmpcontract.companycode, 
	coalesce(tmpcontract.bunit), coalesce(tmpcontract.bunitname), coalesce(tmpcontract.agencyid), 
	coalesce(tmpcontract.minexperience), coalesce(tmpcontract.maxexperience),
	coalesce(tmpcontract.jobrole,openappointments.post_offered), 
	coalesce(tmpcontract.educationqualification), coalesce(tmpcontract.eduqualspecialization), 
	coalesce(tmpcontract.skillstoolstech), coalesce(tmpcontract.contractstartdate), coalesce(tmpcontract.contractenddate), 
	coalesce(tmpcontract.relieveddate), coalesce(tmpcontract.multi_performerwagesflag), 
	coalesce(tmpcontract.cms_jobid), coalesce(tmpcontract.cms_posting_department), coalesce(tmpcontract.cms_posting_location)
	,case when p_loanmasterid is null then 
	to_char(make_date(p_mpryear,p_mprmonth,1)+interval '1 month','dd Mon yyyy hh:mi') 
	else  to_char(v_salstartdate,'dd Mon yyyy hh:mi') end
	,tmpcontract.cms_contractid,tmpcontract.cms_trackingid /*Change 1.3*/
	from openappointments
	left join (	
				select empcode,customeraccountname, contractno,dateofjoining,deputeddate  ,projectname
		        ,agencyname,contractcategory,contracttype,dateofleaving
				,minexperience, maxexperience, jobrole, educationqualification, eduqualspecialization, skillstoolstech, contractstartdate, contractenddate, relieveddate, multi_performerwagesflag, cms_jobid, cms_posting_department, cms_posting_location
				,companycode,bunit,bunitname,agencyid
				,cms_contractid,cms_trackingid /*Change 1.3*/
		       ,row_number() over (partition by empcode order by "tblAutoId" desc) rn
				from cmsdownloadedwages
				where isactive='1'
				and coalesce(nullif(trim(cmsdownloadedwages.multi_performerwagesflag),''),'Y')<>'N'
			) tmpcontract
			on openappointments.emp_code=tmpcontract.empcode::bigint and rn=1
			-- and openappointments.isactive='1'
		where openappointments.emp_code=p_emp_code
		limit 1
		returning "tblAutoId",batch_no into v_generatedattendanceid,v_batchid; 
/*******************************************/
	insert into tbl_employeeledger
	(
		emp_id,emp_code,headid,headname,amount,processmonth,processyear,
		isactive,createdby,createdon,createdbyip,masterhead,is_taxable,loan_master_id,is_billable,remarks,createdbyusertype,
		is_reimbursement_claim, reimbursement_id,tdsdeductionmonth,assetid,fnfid,encashment_id,bonus_id
	)
	select coalesce(p_emp_id,v_emp_id),p_emp_code,headid,headname,amount,p_mprmonth,p_mpryear,
		'1',p_createdby,current_timestamp,p_createdbyip ,masterheadname,is_taxable,nullif(p_loanmasterid,-9999),is_billable,p_remarks,nullif(p_createdbyusertype,''),
		p_is_reimbursement_claim, p_reimbursement_claim_id,p_tdsdeductionmonth,nullif(p_assetid,-9999),p_fnfid,p_encashment_id,p_bonus_id
	from tmp_ledgers
	returning id,headid,amount,is_taxable,is_billable into v_generatedledgerid,v_headid,v_amount,v_istaxable,v_is_billable;			
/*****************************************************/
else
select is_taxable into v_istaxable from tmp_ledgers;
v_amount:=v_rec.amount;
end if;
		select * into v_recmst_otherduction
		from mst_otherduction
		where id=v_headid;
		v_tds:=0;
	
	select * into v_salrecord
	from openappointments op 
		inner join empsalaryregister e
			on op.emp_id=e.appointment_id and e.isactive='1'
			and  op.emp_code=p_emp_code;
	if v_recmst_otherduction.masterledgername='Additional income' or v_recmst_otherduction.masterledgername='Deduction' then
		v_disbursementmode:='Salary';
	else
		v_disbursementmode:='Voucher';
	end if;

	if v_istaxable='Y' and coalesce(v_empsalaryregister.is_exemptedfromtds,'N')='N' then

	if coalesce(p_tdsdeductionmonth,'current')<>'next' then
			perform public.uspupdatetaxforsalary(
				p_empcode =>p_emp_code,
				p_createdby =>p_createdby,
				p_createdbyip =>p_createdbyip,
				p_month =>(case when p_mprmonth in (1,2,3) then 12 else p_mprmonth-1 end),
				p_year =>(case when p_mprmonth in (1,2,3) then p_mpryear-1 else p_mpryear end),
				p_currentgrossearning =>v_amount,
				p_currentotherdeductions =>0,
				p_currentbasic =>0,
				p_currenthra =>0,
				p_batchid =>v_batchid);

				select e.taxes into v_tds
				from openappointments op inner join empsalaryregister e
				on op.emp_id=e.appointment_id 
				and op.emp_code=p_emp_code 
				and e.isactive='1';		
				
				v_tds:=coalesce(v_tds,0);
				
				
				
/**************************change 1.9 starts**************************************/
if  coalesce(p_action,'')='GetVoucherTDS' then
	select public.uspmonthwiseinvestmentreport(p_financialyear =>v_financial_year,
								p_action =>'GetAllInvestmentReport',
								p_empcode =>p_emp_code::bigint,
								p_mprmonth =>(case when p_mprmonth in (1,2,3) then 12 else p_mprmonth-1 end),
								p_mpryear=>(case when p_mprmonth in (1,2,3) then p_mpryear-1 else p_mpryear end))
	into v_investmentresult;
end if;	
/**************************change 1.9 ends**************************************/					
/****************Already Deducted TDS*********************************************/
select sum(case when 
	 (
						(
							to_date(left(hrgeneratedon,11),'dd Mon yyyy')
							between v_salstartdate::date  and v_salenddate::date
							and to_date((mpryear::text||'-'||lpad(mprmonth::text,2,'0')||'-01'),'yyyy-mm-dd')<v_salstartdate::date
						)
					or
						(	
						to_date(left(hrgeneratedon,11),'dd Mon yyyy')
						 between v_advancesalstartdate::date  and v_advancesalenddate::date	
							and mprmonth=p_mprmonth and mpryear=p_mpryear
						)
			)
	 then tds else 0 end) into v_alreadytds
from (select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear
	  from tbl_monthlysalary
	 where (tbl_monthlysalary.emp_code= p_emp_code or tbl_monthlysalary.emp_code in (select emp_code from openappointments where pancard=v_pancard))
	  and (((
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate::date  and v_enddate::date	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate::date   and  v_advanceenddate::date		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	   		and attendancemode<>'Ledger'
		   )
		or(to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')	between v_advancestartdate  and v_advanceenddate and attendancemode='Ledger')	  

		   )
	  	  	and not(mprmonth=4 and mpryear=v_year2)
		   and coalesce(is_rejected,'0')<>'1'

	 union all
	  select emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,mprmonth,mpryear
	from tbl_monthly_liability_salary
	where (tbl_monthly_liability_salary.emp_code= p_emp_code or tbl_monthly_liability_salary.emp_code in (select emp_code from openappointments where pancard=v_pancard))
	  and coalesce(salary_remarks,'')<>'Invalid Paid Days'
	and coalesce(is_rejected,'0')='0'	
	and (emp_code,mprmonth, mpryear, batchid) not in
		(select p_emp_code,p_mprmonth, p_mpryear, v_batchid) 	
	and (emp_code,mprmonth, mpryear, batchid||transactionid) not in
		(select p_emp_code,p_mprmonth, p_mpryear, v_batchid) 		  
	----------------------------------------------------------------------------------------	  
	  	 and not(mprmonth=4 and mpryear=v_year2)
	  	 and (
			to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate::date  and v_enddate::date	 
			or
				(
				to_date(left(tbl_monthly_liability_salary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate::date  and v_advanceenddate::date		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
-----------------------------------------------------------------------	  
	and (emp_code,mprmonth, mpryear, batchid) not in
	  (
	(select emp_code,mprmonth, mpryear, batchid 
		 from tbl_monthlysalary 
	 	where (tbl_monthlysalary.emp_code= p_emp_code or tbl_monthlysalary.emp_code in (select emp_code from openappointments where pancard=v_pancard))
		and (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate::date  and v_enddate::date 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate::date  and v_advanceenddate::date		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
	 and coalesce(is_rejected,'0')='0'
	)
union all
	(select emp_code,mprmonth, mpryear, batchid ||coalesce(transactionid::text,'')
		 from tbl_monthlysalary 
	 where  (tbl_monthlysalary.emp_code= p_emp_code or tbl_monthlysalary.emp_code in (select emp_code from openappointments where pancard=v_pancard))
	 	and(
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate::date  and v_enddate 
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
		  union all
	(select m.mprmonth, m.mpryear,  m.emp_code,trim(regexp_split_to_table(m.batchid,',')) 
	 from tbl_monthlysalary m where 
	 (m.emp_code= p_emp_code or m.emp_code in (select emp_code from openappointments where pancard=v_pancard))
	 and coalesce(m.is_rejected,'0')='0'
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
group by emp_code;

v_tds:=case when v_salrecord.jobtype='Independent Contractors' then v_amount*coalesce(v_empsalaryregister.customtaxpercent/100.0,.01) when coalesce(v_tds,0)>=0 then (v_tds-coalesce(v_alreadytds,0)) else 0 end;
end if;
if  coalesce(p_action,'')='GetVoucherTDS' then
		return v_tds::bigint;
end if;
/************************************************************/
			if coalesce(v_salrecord.employeeesirate,0) >0 then
				v_employeresirate:=v_amount*0.03250;
				v_employeeesirate:=v_amount*0.00750;
				v_grossesicincome:=v_amount;
			else
				v_employeresirate:=0;
				v_employeeesirate:=0;
			
			end if;
		
			if v_amount>0 then
				v_grossearning:=v_amount;
				v_refund:=0;
				v_otherledgerarears:=v_amount;
				v_grossdeduction:=coalesce(v_employeeesirate,0)+coalesce(v_tds,0);
				v_otherledgerdeductions:=0;
				v_otherledgerarearwithoutesi:=0;
			else
				v_grossearning:=v_amount;
				v_refund:=v_amount;
				v_otherledgerarears:=0;
				v_grossdeduction:=coalesce(v_employeeesirate,0)+coalesce(v_tds,0);
				v_otherledgerdeductions:=0;
				v_otherledgerarearwithoutesi:=0;
			end if;
		
		v_netpay:=v_grossearning-v_grossdeduction;		
	else
		v_tds:=0;
		v_employeresirate:=0;
		v_employeeesirate:=0;
		v_otherledgerarears:=0;
		v_grossearning:=0.00;
		v_otherledgerarearwithoutesi:=0.00;
		if v_amount>0 then
			if v_headid=9 or v_headid=53 then
				v_advance:=v_amount*-1;
				v_grossdeduction:=v_amount*-1;
			elsif v_headid=38 then
				v_loan:=v_amount*-1;
				v_grossdeduction:=v_amount*-1;
			else	
				v_grossearning:=v_amount;
				v_otherledgerarearwithoutesi:=v_amount;
				v_grossdeduction:=0;
			end if;
			v_otherledgerdeductions:=0;
		else
			v_grossearning:=0;
			v_grossdeduction:=v_amount*-1;
			v_otherledgerdeductions:=v_amount*-1;
			v_otherledgerarearwithoutesi:=0;
		end if;
		v_netpay:=v_grossearning-v_grossdeduction;
	end if;
	with v_tbl_monthlysalary as (
		insert into tbl_monthlysalary ( mprmonth, mpryear, batchid, createdby, createdon, createdbyip, emp_code, subunit, dateofleaving, totalleavetaken, emp_name, post_offered, emp_address, email, mobilenum, pancard, gender, dateofbirth, fathername, residential_address, pfnumber, uannumber, lossofpay, paiddays, monthdays, ratebasic, ratehra, rateconv, ratemedical, ratespecialallowance, fixedallowancestotalrate, basic, hra, conv, medical, specialallowance, fixedallowancestotal, ratebasic_arr, ratehra_arr, rateconv_arr, ratemedical_arr, ratespecialallowance_arr, fixedallowancestotalrate_arr, incentive, refund, grossearning, epf, vpf, employeeesirate, tds, loan, lwf, insurance, mobile, advance, other, grossdeduction, netpay, ac_1, ac_10, ac_2, ac21, employeresirate, lwfcontr, ews, gratuity, recordtype, govt_bonus_opted, govt_bonus_amt, is_special_category, ctc2,batch_no,actual_paid_ctc2,ctc,ctc_paid_days,ctc_actual_paid,mobile_deduction,salaryid,employeenps,employernps,insuranceamount,familyinsurance,bankaccountno, ifsccode, bankname, bankbranch,totalarear,arearaddedmonths,employee_esi_incentive_deduction,employer_esi_incentive_deduction,total_esi_incentive_deduction,salaryindaysopted,mastersalarydays,otherledgerarears,otherledgerdeductions,attendancemode,incrementarear,incrementarear_basic,incrementarear_hra,incrementarear_allowance,incrementarear_gross,incrementarear_employeeesi,incrementarear_employeresi,lwf_employee,lwf_employer,bonus,otherledgerarearwithoutesi,otherdeductions,othervariables,otherbonuswithesi,lwfstatecode,tdsadjustment,atds,hrgeneratedon,disbursedledgerids,security_amt,issalaryorliability,disbursementmode,istaxapplicable,is_billable,tptype,is_advice,gross_esic_income,tdsdeductionmonth)
		select p_mprmonth, p_mpryear, v_batchid, p_createdby,current_timestamp,p_createdbyip,
		p_emp_code, cmd.bunit, cmd.dateofleaving, cmd.totalleavetaken, 
		op.emp_name, op.post_offered, op.emp_address, op.email, op.mobile, op.pancard, 
		op.gender, op.dateofbirth, op.fathername, op.residential_address, op.pfnumber, op.uannumber, 
		0 lossofpay, 0 paiddays,
		v_monthdays monthdays, 
		e.basic, e.hra, e.conveyance_allowance rateconv, e.medical_allowance ratemedical,
		e.allowances ratespecialallowance,
		e.gross fixedallowancestotalrate,0 basic,
		0 hra,0 conv,0 medical,0 specialallowance,0 fixedallowancestotal,0 ratebasic_arr,0 ratehra_arr,0 rateconv_arr,0 ratemedical_arr,0 ratespecialallowance_arr,0 fixedallowancestotalrate_arr,
		0 incentive,v_refund refund,
		v_grossearning grossearning,-----------------------------------------------------
		0 epf,case when v_headid=10 then v_otherledgerdeductions else 0 end vpf,
		v_employeeesirate employeeesirate,--------------------
		v_tds tds, 
		case when v_headid=39 then v_otherledgerdeductions  when v_headid=38 then v_loan else 0 end loan, 
		0 lwf, 
		0 insurance, 
		0 mobile, 
		case when v_headid in(19,60) then v_otherledgerdeductions  when v_headid in(9,53) then v_advance else 0 end advance, 
		0 other, 
		v_grossdeduction grossdeduction, v_netpay netpay,
		0 ac_1, 0 ac_10, 0 ac_2, 0 ac21, 
		v_employeresirate employeresirate,
		0 lwfcontr, 0 ews, 0 gratuity, '' recordtype,'N' govt_bonus_opted,0 govt_bonus_amt,
		e.is_special_category, e.ct2,v_batchid batch_no,0 actual_paid_ctc2,
		e.ctc,0 ctc_paid_days,0 ctc_actual_paid,0 mobile_deduction,
		e.id salaryid,0 employeenps,0 employernps,0 insuranceamount,0 familyinsurance,op. bankaccountno,op.ifsccode,op.bankname,op.bankbranch,
		0 totalarear,null arearaddedmonths,0 employee_esi_incentive_deduction,0 employer_esi_incentive_deduction,0 total_esi_incentive_deduction,
		e.salaryindaysopted,e.salarydays mastersalarydays,
		v_otherledgerarears otherledgerarears,case when v_headid in(19,39,10,60) then  0 else v_otherledgerdeductions end otherledgerdeductions,
		cmd.attendancemode,0 incrementarear,0 incrementarear_basic,0 incrementarear_hra,0 incrementarear_allowance,0 incrementarear_gross,0 incrementarear_employeeesi,0 incrementarear_employeresi,0 lwf_employee,0 lwf_employer,0 bonus,
		v_otherledgerarearwithoutesi otherledgerarearwithoutesi,
		0 otherdeductions,0 othervariables,0 otherbonuswithesi,
		null lwfstatecode,0 tdsadjustment,v_tds atds,cmd.hrgeneratedon,
		v_generatedledgerid::text disbursedledgerids,
		0 security_amt,case when p_voucherorigin='Mobile' then 'S' else 'L' end issalaryorliability,
		v_disbursementmode as disbursementmode,
		case when v_istaxable='Y' then '1'::bit else '0'::bit end,
		v_is_billable
		,v_tptype
		,p_isadvice
		,v_grossesicincome
		,p_tdsdeductionmonth
		from openappointments op inner join cmsdownloadedwages cmd
			on op.emp_code=cmd.empcode::bigint 
			and op.emp_code=p_emp_code 
			and cmd."tblAutoId"=v_generatedattendanceid
		inner join empsalaryregister e
			on op.emp_id=e.appointment_id and e.isactive='1'
			limit 1
			returning *
			)
			insert into tmp_tbl_monthlysalary
			select * from v_tbl_monthlysalary;

		update tbl_employeeledger 
		set isledgerdisbursed='1',
			ledgerbatchid=v_batchid,
			ledgerdisbursedby=p_createdby,
			ledgerdisbursedon=current_timestamp,
			ledgerdisbursedbyip=p_createdbyip
		where emp_code=p_emp_code
			and processmonth=p_mprmonth
			and processyear=p_mpryear
			and coalesce(isledgerdisbursed,'0')<>'1'
			and isactive='1'
			and id=v_generatedledgerid;
/*********change 2.1 starts*************************/

select public.uspintegrateworkflow(
	p_customeraccountid =>v_customeraccountid,
	p_emp_code =>p_emp_code,
	p_moduleid =>25,
	p_createdby =>p_createdby,
	p_createdbyip =>p_createdbyip,
	p_masterid =>(select id from tmp_tbl_monthlysalary)
	)
	into v_appcount;
/*********change 2.1 ends*************************/
	
/****************************************************************************/
return 1;
end;
$BODY$;

ALTER FUNCTION public.uspsavevoucher(bigint, bigint, text, integer, integer, bigint, character varying, character varying, bigint, character varying, character varying, character varying, character varying, bigint, character varying, character varying, character varying, text, integer, bigint, bigint, bigint)
    OWNER TO stagingpayrolling_app;

