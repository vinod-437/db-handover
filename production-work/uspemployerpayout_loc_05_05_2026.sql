-- FUNCTION: public.uspemployerpayout(text, bigint, integer, integer, integer, character varying, text, text, text, text)

-- DROP FUNCTION IF EXISTS public.uspemployerpayout(text, bigint, integer, integer, integer, character varying, text, text, text, text);

CREATE OR REPLACE FUNCTION public.uspemployerpayout(
	p_action text,
	p_customeraccountid bigint,
	p_month integer DEFAULT 0,
	p_year integer DEFAULT 0,
	p_geofenceid integer DEFAULT 0,
	p_ou_ids character varying DEFAULT NULL::character varying,
	p_empname text DEFAULT ''::text,
	p_post_offered text DEFAULT ''::text,
	p_posting_department text DEFAULT ''::text,
	p_unitparametername text DEFAULT ''::text)
    RETURNS SETOF refcursor 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
/*
 * Modified on: 04-May-2026
 * Description: Clubbed 'dfm' and 'eor' payout mode types with 'standard', updating their calculations to track undisbursed and status identically to 'standard'. Reverted previous grouping with 'hybrid' and 'self'.
 */
declare 
	v_rfc1 refcursor;
	v_rfc2 refcursor;
	v_rfc3 refcursor;
	v_id int:=1;
	v_startdate date;
	v_numberofmonths int;
	v_generatedsalarycount int:=0;
	v_netpayableamount numeric(18,2):=0.0;
	v_emp_code bigint;
	v_netpay_pregenerated numeric(18,2):=0;
	v_netpay_pausedpregenerated numeric(18,2):=0;
	v_rfc refcursor;
	v_rec record;
	v_isattendancerequiredemployee varchar(30);
	v_isattendancerequiredemployer varchar(30);
	v_rfc0 refcursor;
	v_currentmonthstartdate varchar(12);
	v_currentmonthenddate varchar(12);
	v_year int;
	v_month int;
	i int:=0;
	v_tmfa tbl_monthwise_flexi_attendance%rowtype;
	v_netpay_pregenerated_ctc numeric(18,2):=0;
	v_bonus double precision:=0.0;
	v_deduction double precision:=0.0;
	v_rfccheck refcursor;
	v_payout_mode_type text;
	v_workreportexists varchar(1):='N';
	v_invoice_adjustment_amount numeric(18,2):=0;
	v_accountcreationdate date;
	v_paidadmincharges numeric(18,2):=0;
	v_freetrialenddate date;
	v_cnt int;
	v_tbl_account tbl_account%rowtype;
	v_currentmonthdays int;
	v_tbl_receivables record;
	v_subscriptionfrom date;
	v_subscriptionto date;
	v_invoicefrequency varchar(20);
	v_terms int;
	counter int;
	v_rfcadvice refcursor;
	v_rfcarearadvice refcursor;
	v_cmsdownloadedwages cmsdownloadedwages%rowtype;
	v_negativepayout numeric(18,2);
	v_inhand_pregenerated numeric(18,2):=0;
begin
/***********************************************************************************************************
1.0 	Date			Initial 											Done By						
1.1		28-Feb-2024		ESI Roundup/roundoff (MIS Mail Dated 27-Feb-202)	Shiv Kumar						
1.2		28-Feb-2024		Current Month Invoice								Shiv Kumar	
1.3		08-Jun-2024		AC21 Min 500 check(As per mail dated 08-Jun-2024)	Shiv Kumar
1.4		27-Jun-2024		Get Advice from prestored Data						Shiv Kumar
1.5		02-Aug-2024		Display orgempcode in payout details				Shiv Kumar	
1.6		05-Aug-2024		Payout Day current v/s Advance						Shiv Kumar	
1.7		07-Aug-2024		ouid changes										Siddharth Bansal	
1.8		14-Aug-2024		Fetch PF Admin Charges from 						Shiv Kumar
						tbl_employer_challan_deposit table
1.9		27-Aug-2024		Implement Subscription Plan							Shiv Kumar
2.0		03-Sep-2024		Manage No of employees from Advance Subscription	Shiv Kumar	
2.2		22-Nov-2024		Apply challan submitted condition 
						from tbl_employer_challan_deposit
3.3		25-Nov-2024		Remove LWF,PT and TDS for Compserve					Shiv Kumar							
3.4		06-Jan-2025		Add Increment arrear in Payout						Shiv Kumar							
3.5		17-May-2025		Add Net Pay COLUMNS									Shiv Kumar							
3.6		02-Jul-2025		Negative or zero salaries							Shiv Kumar
3.7		30-Jul-2025		Avoid temp tables for self payout mode				Shiv Kumar
3.8		01-Aug-2025		Comp Serve Payout									Shiv Kumar
3.9		07-Aug-2025		No display zero Amount or No Advice Employee		Shiv Kumar
4.0		13-Sep-2025		Workflow Integration								Shiv Kumar
*************************************************************************************************************/
/********************Part 1.9 starts*******************************/	
	create temporary table tblinvoices
	(
	invoiceid int,
	--customeraccountid bigint,
	invoicemonth int,
	invoiceyear int,
	netamountreceived numeric
	) ON COMMIT DROP;

   for v_tbl_receivables in (select *  from tbl_receivables 
							 where customeraccountid=p_customeraccountid 
							 and status='Paid' and isactive='1' and entrytype='Invoice'
							 and subscriptionfrom is not null and subscriptionto is not null
							)
   loop
    v_invoicefrequency:=v_tbl_receivables.invoicefrequency;
	-- [4.0']
	if coalesce(v_invoicefrequency,'')='Custom' then
		v_terms:=(extract(year from age(date_trunc('month',v_tbl_receivables.subscriptionto),date_trunc('month',v_tbl_receivables.subscriptionfrom))) * 12) + extract(month from age(date_trunc('month',v_tbl_receivables.subscriptionto),date_trunc('month',v_tbl_receivables.subscriptionfrom)));
	else
		v_terms:=case when v_invoicefrequency='Triennially' then 36 when v_invoicefrequency='Monthly' then 1 when v_invoicefrequency='Bi-Monthly' then 2 when v_invoicefrequency='Quarterly' then 3 when v_invoicefrequency='Half Yearly' then 6 when v_invoicefrequency='Annually' then 12 else 1 end;
   	
	end if;
	v_terms := greatest(coalesce(v_terms, 1), 1);
	-- [4.0'] old
	/*	if v_invoicefrequency='Custom' then
		v_terms:=extract(month from age(date_trunc('month',v_tbl_receivables.subscriptionto),date_trunc('month',v_tbl_receivables.subscriptionfrom)));
	else
		v_terms:=case when v_invoicefrequency='Triennially' then 36 when v_invoicefrequency='Monthly' then 1 when v_invoicefrequency='Bi-Monthly' then 2 when v_invoicefrequency='Quarterly' then 3 when v_invoicefrequency='Half Yearly' then 6 when  v_invoicefrequency='Annually' then 12 end;
   	
	end if;
	*/
	v_subscriptionfrom:=v_tbl_receivables.subscriptionfrom;
	for counter in 1 .. v_terms
		loop
		   insert into tblinvoices
			select v_tbl_receivables.id,extract('month' from v_subscriptionfrom-interval '1 month'),extract('year' from v_subscriptionfrom-interval '1 month'),v_tbl_receivables.netamountreceived/v_terms;
			v_subscriptionfrom:=(v_subscriptionfrom+interval '1 month')::date;
		 end loop;
   end loop;
   
 insert into tblinvoices
select id,invoicemonth,invoiceyear,netamountreceived
   from tbl_receivables 
		where customeraccountid=p_customeraccountid 
		and status='Paid'
		and isactive='1' 
		and entrytype='Invoice'
		and invoicemonth is not null and invoiceyear is not null
		/*and id not in (select id from tblinvoices)*/;
/********************Part 1.9 ends*******************************/		
/*********Added invoice_adjustment_amount on 12-Feb-2024*************************************/
select * from tbl_account into v_tbl_account where id=p_customeraccountid;
--select extract('day' from date_trunc('month',make_date(p_year,p_month,1))+interval '1 month -1 day')::int into v_currentmonthdays;
select sum(adjustment_amount) from tbl_receivables where customeraccountid=p_customeraccountid and isactive='1' and status='Paid' and entrytype='Invoice' into v_invoice_adjustment_amount;
v_invoice_adjustment_amount:=coalesce(v_invoice_adjustment_amount,0);

select sum(pfadmincharges) from tbl_receivables 
where customeraccountid=p_customeraccountid and isactive='1' and status='Paid'
and invoicemonth=p_month and invoiceyear=p_year
and payout_mode_type in ('standard','hybrid')
into v_paidadmincharges;

--select sum(totalchallanamount::numeric) 
--from tbl_employer_challan_deposit 
--where customeraccountid=p_customeraccountid and 
--pfadminchargestatus='Paid' and ispfdmincharge='Y'
--into v_paidadmincharges;

v_paidadmincharges:=coalesce(v_paidadmincharges,0);

if p_month>0 and p_year>0 then
	v_currentmonthstartdate:=make_date(p_year,p_month,1)::varchar(12);
	v_currentmonthenddate:=((v_currentmonthstartdate::date+interval '1 month -1 day')::date)::varchar(12);
else
	v_currentmonthstartdate:=to_char(date_trunc('month',current_date),'yyyy-mm-dd');
	v_currentmonthenddate:=((v_currentmonthstartdate::date+interval '1 month -1 day')::date)::varchar(12);
end if;

select case when ta.leavetemplateapplicableon='Employer' then ta.payout_settings else null end,trim(payout_mode_type)
,date_trunc('month',createddate)::date,freetrialenddate
from tbl_account ta where ta.id=p_customeraccountid
into v_isattendancerequiredemployer,v_payout_mode_type,v_accountcreationdate,v_freetrialenddate;
	/*******Change 3.6 Negative Salaries******************/		
if trim(v_payout_mode_type) in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then
select sum(ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0)) 
	  +sum(round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric)) 
	into v_negativepayout
			 		from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
						and ts.is_rejected='0'
				 		and op.recordsource='HUBTPCRM'
				 		and ts.issalaryorliability='S'
						and op.customeraccountid=p_customeraccountid
				 		and op.customeraccountid is not null
						and ts.recordscreen in ('Current Wages','Previous Wages')
						and (workflowappid = -9999 or is_workflow_approved='Y') --change 4.0
					inner join tbl_account ta on op.customeraccountid=ta.id	
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
				 having sum(coalesce(ts.netpay,0))<=0;
--v_negativepayout:=0;
end if;
v_negativepayout:=coalesce(v_negativepayout,0);
--raise notice 'v_negativepayout=%',v_negativepayout;
			/*******Change 3.6 Negative Salaries end******************/
	begin
		select max(coalesce(isattendancerequired,'Y'))
		FROM empsalaryregister e
		inner join openappointments op
		on e.appointment_id=op.emp_id 
		-- 		AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
		--SIDDHARTH BANSAL 05/08/2024
		AND (NULLIF(p_ou_ids, '') is null or
		EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
		WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
		)
		)
		--END
		where op.customeraccountid=p_customeraccountid and op.converted='Y' and op.appointment_status_id=11	
		and date_trunc('month',op.dateofjoining)::date <=v_currentmonthstartdate
		and (op.dateofrelieveing is null or dateofrelieveing>=v_currentmonthstartdate::date)
		and  v_currentmonthstartdate::date between date_trunc('month',effectivefrom) and coalesce(effectiveto,v_currentmonthstartdate::date)
		into v_isattendancerequiredemployee;
	exception when others then
		null;
	end;
--end if;
/***************Added for Unapproved Attendance********************/
		if (p_month=0 or make_date(p_year,p_month,1)>=date_trunc('month',current_date)) then
			i:=0;
		else
			i:=1;
		end if;
drop table if exists pregeneratedpay ;
create temporary table pregeneratedpay(ecode bigint,salary numeric(18,2),pausedsalary numeric(18,2),paiddays numeric(18,2),salmon int,salyear int,unpaidac21 numeric,unpaidepf numeric,netpay numeric(18,2),pausednetpay numeric(18,2),issalapprovalapproved varchar(1));

create temporary table tmpyearmaster
		(
			id int,
			attmon int,
			attyear int,
			attmonthname varchar(30),
			attmonthdate date
		) on commit drop;
		
		
		if p_month=0 then
			v_numberofmonths:=3;
			v_startdate:=(date_trunc('month',current_date)/*-interval '1 month'*/)::date;
		else
			v_numberofmonths:=1;
			v_startdate:=to_date('01'||lpad(p_month::text,2,'0')||p_year::text,'ddmmyyyy');		
		end if;
/*****************call Unit Employee Advice**********************************/
-- begin
 	if p_month<>0 and p_year<>0 then
	select public.uspgenerateunitwiseadvice(
		p_action =>'MoveAttendanceToWages',
		p_customeraccountid =>p_customeraccountid,
		p_createdby =>-9999,
		p_createdbyip =>'::1',
		p_month =>p_month,
		p_year =>p_year)
		into v_rfcadvice;
	end if;
-- 	exception when others then
-- 	null;
-- end;
--RAISE NOTICE 'Exit FROm uspgenerateunitwiseadvice';
--RAISE NOTICE 'v_numberofmonths [%]', v_numberofmonths;

/***************************************************/	
		for v_cnt in 1..v_numberofmonths loop
		
			v_year:=extract('year' from v_startdate)::int;
			v_month:=extract('mon' from v_startdate)::int;
			
			insert into tmpyearmaster
			(id,attmon,attyear,attmonthname,attmonthdate)
			select v_id,v_month,v_year,to_char(v_startdate,'Mon-yyyy'),v_startdate
			-- where v_startdate>=(select date_trunc('month',createddate)::date from tbl_account where id=p_customeraccountid)
				; --Condition changed on 06-Nov-2023 as per issue of Goodwill customer suggested by Yatin Sir;		
/******************************************************************/
insert into pregeneratedpay select pa.emp_code,(case when v_payout_mode_type='hybrid' then 0 else coalesce(pa.netpay,0) end+coalesce(insurance::numeric(18,2),0)+coalesce(employerinsuranceamount,0)+coalesce(ceil(pa.employeeesirate::numeric),0)+coalesce(pa.employeresirate::numeric)+round(coalesce(pa.epf,0)::numeric)+coalesce(pa.vpf,0)+round(coalesce(pa.ac_1,0)::numeric)+round(coalesce(pa.ac_10,0)::numeric)+round(coalesce(pa.ac_2,0)::numeric)+round(coalesce(pa.ac21,0)::numeric)+coalesce(pa.professionaltax,0)+case when v_tbl_account.payout_mode_type in('standard','self','dfm','eor') /* Added dfm and eor with standard payout mode type */ then coalesce(pa.lwf_employer,0)+coalesce(pa.lwf_employee,0)+coalesce(pa.tds,0) else 0 end+case when v_workreportexists='N' then 0 else ((coalesce(v_bonus,0))*(case when coalesce(ceil(pa.employeeesirate::numeric),0)>0 then .04 else 0 end)) end)+coalesce(pa.mealvoucher,0),0,pa.paiddays,pa.mprmonth,pa.mpryear,round(coalesce(pa.ac21,0)::numeric),round(coalesce(pa.epf,0)::numeric),coalesce(pa.netpay,0),0,pa.issalapprovalapproved
from paymentadvice pa inner join openappointments op 
on pa.emp_code=op.emp_code and op.customeraccountid=p_customeraccountid 
and pa.paiddaysstatus<>'Invalid'
--and pa.issalapprovalapproved='Y'
-- and COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
--SIDDHARTH BANSAL 05/08/2024
AND EXISTS
(
SELECT 1
FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
)
--END
and op.converted = 'Y' and op.appointment_status_id  in(11,14)
and date_trunc('month',op.dateofjoining)::date <=v_startdate
and (op.dateofrelieveing is null or op.dateofrelieveing>=v_startdate) 
and ((pa.mprmonth=v_month and pa.mpryear=v_year and attendancemode<>'Manual')
	 or 
	 (date_trunc('month',to_date(left(hrgeneratedon,11),'dd Mon yyyy')-interval '1 month')::date=make_date(v_year,v_month,1)  and attendancemode='Manual')
	 
	 )
	/***************************/
	left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id 
	and mts.IsActive='1'
	and coalesce(mts.PausedStatus,'Enable')='Enable'
	and mts.ProcessYear =pa.mpryear
	and mts.ProcessMonth =pa.mprmonth
	/***************************/
where mts.EmpId is null;
--and v_payout_mode_type<>'self'

								 
insert into pregeneratedpay select pa.emp_code,0,(case when v_payout_mode_type='hybrid' then 0 else coalesce(pa.netpay,0) end+coalesce(insurance::numeric(18,2),0)+coalesce(employerinsuranceamount,0)+coalesce(ceil(pa.employeeesirate::numeric),0)+coalesce(pa.employeresirate::numeric)+round(coalesce(pa.epf,0)::numeric)+coalesce(pa.vpf,0)+round(coalesce(pa.ac_1,0)::numeric)+round(coalesce(pa.ac_10,0)::numeric)+round(coalesce(pa.ac_2,0)::numeric)+round(coalesce(pa.ac21,0)::numeric)+coalesce(pa.professionaltax,0)+case when v_tbl_account.payout_mode_type in('standard','self','dfm','eor') /* Added dfm and eor with standard payout mode type */ then coalesce(pa.lwf_employer,0)+coalesce(pa.lwf_employee,0)+coalesce(pa.tds,0) else 0 end+case when v_workreportexists='N' then 0 else ((coalesce(v_bonus,0))*(case when coalesce(ceil(pa.employeeesirate::numeric),0)>0 then .04 else 0 end)) end)+coalesce(pa.mealvoucher,0),pa.paiddays,pa.mprmonth,pa.mpryear,round(coalesce(pa.ac21,0)::numeric),round(coalesce(pa.epf,0)::numeric),0,coalesce(pa.netpay,0),pa.issalapprovalapproved
from paymentadvice pa inner join openappointments op 
on pa.emp_code=op.emp_code and op.customeraccountid=p_customeraccountid 
and pa.paiddaysstatus<>'Invalid'
--and pa.issalapprovalapproved='Y'
-- and COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
--SIDDHARTH BANSAL 05/08/2024
AND (NULLIF(p_ou_ids, '') is null or EXISTS
(
SELECT 1
FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
))
--END
and op.converted = 'Y' and op.appointment_status_id  in(11,14)
and date_trunc('month',op.dateofjoining)::date <=v_startdate
and (op.dateofrelieveing is null or op.dateofrelieveing>=v_startdate) 
and pa.mprmonth=v_month and pa.mpryear=v_year --and coalesce(pa.is_paused,'Disable')='Enable'
	/***************************/
	left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id 
	and mts.IsActive='1'
	and  coalesce(mts.PausedStatus,'Enable')='Enable'
	and mts.ProcessYear =pa.mpryear
	and mts.ProcessMonth =pa.mprmonth
	/***************************/
where mts.EmpId is not null;
select sum(case when v_payout_mode_type='hybrid' then 0 else coalesce(pa.netpay,0) end+coalesce(insurance::numeric(18,2),0)+coalesce(employerinsuranceamount,0)+coalesce(ceil(pa.employeeesirate::numeric),0)+coalesce(pa.employeresirate::numeric)+round(coalesce(pa.epf,0)::numeric)+coalesce(pa.vpf,0)+round(coalesce(pa.ac_1,0)::numeric)+round(coalesce(pa.ac_10,0)::numeric)+round(coalesce(pa.ac_2,0)::numeric)+round(coalesce(pa.ac21,0)::numeric)+coalesce(pa.professionaltax,0)+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then coalesce(pa.lwf_employer,0)+coalesce(pa.lwf_employee,0)+coalesce(pa.tds,0) else 0 end+case when v_workreportexists='N' then 0 else ((coalesce(v_bonus,0))*(case when coalesce(ceil(pa.employeeesirate::numeric),0)>0 then .04 else 0 end)) end)
,sum(case when v_payout_mode_type='hybrid' then coalesce(pa.netpay,0) else 0 end)
from paymentadvice pa inner join openappointments op 
on pa.emp_code=op.emp_code and op.customeraccountid=p_customeraccountid
and pa.paiddaysstatus<>'Invalid'
--and pa.issalapprovalapproved='Y'
 
-- and COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
--SIDDHARTH BANSAL 05/08/2024
AND (NULLIF(p_ou_ids, '') is null or EXISTS
(
SELECT 1
FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
))
--END 
and op.converted = 'Y' and op.appointment_status_id  in(11,14)
and date_trunc('month',op.dateofjoining)::date <=v_startdate
and (op.dateofrelieveing is null or op.dateofrelieveing>=v_startdate)

and pa.mprmonth=v_month and pa.mpryear=v_year
	/***************************/
	left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id 
	and mts.IsActive='1'
	and  coalesce(mts.PausedStatus,'Enable')='Enable'
	and mts.ProcessYear =pa.mpryear
	and mts.ProcessMonth =pa.mprmonth
	/***************************/
where mts.EmpId is null
into v_netpay_pregenerated,v_inhand_pregenerated;
--RAISE NOTICE 'v_netpay_pregenerated [%]', v_netpay_pregenerated;
/******************************************************************/
							i:=i+1;

			v_id:=v_id+1;
			v_startdate:=(v_startdate-interval '1 month')::date;	
		end loop;
drop table if exists tmpselfsalacount ;
create temporary table tmpselfsalacount
as
	select ts.mprmonth as salmonth,ts.mpryear as salyear,count(ts.*) as salempcount
			,count(distinct case when ts.emp_code is not null and ts.attendancemode in ('MPR','Manual') then ts.emp_code else null end) as salpaidcount
	from tbl_monthlysalary ts inner join openappointments op 
	on ts.emp_code=op.emp_code and op.customeraccountid=p_customeraccountid 
	and ts.is_rejected='0'
	inner join tmpyearmaster ta
	on ts.mprmonth=ta.attmon and ts.mpryear=ta.attyear
	/***************************/
	left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id 
	and mts.IsActive='1'
	and  coalesce(mts.PausedStatus,'Enable')='Enable'
	and mts.ProcessYear =ts.mpryear
	and mts.ProcessMonth =ts.mprmonth
	/***************************/
	where /*mts.EmpId is null
	and*/ v_payout_mode_type='self'
	group by ts.mprmonth,ts.mpryear;

/******************************************************************/	
  --raise notice 'v_netpay_pregenerated=%',v_netpay_pregenerated;
/******************************************************************/
/***************Added for Unapproved Attendance ends here********************/
	drop table if exists tmpqualifiedcustomers ;
if trim(v_payout_mode_type)='self' then
	create temporary table tmpqualifiedcustomers as
			select tblrec.customeraccountid as customeraccountid,
					tblrec.payoutday,
					(coalesce(tblrec.barenetamountreceived,0)-0.0-v_invoice_adjustment_amount-coalesce(v_negativepayout,0))::numeric(18,2) barebalance
		from (
				select customeraccountid,
			  		sum(coalesce(netamount,0)+coalesce(excess_amount,0)) netamountreceived,
					sum(coalesce(netamount,0)+coalesce(excess_amount,0)) barenetamountreceived,
					max(payoutday) payoutday
			 	from tbl_account ta inner join tbl_receivables tr
			  		on ta.id=tr.customeraccountid
 			  		and ta.status='1' and ta.pause_inactive_status='Active'
 			  		and  tr.isactive='1' 
 			  		and tr.status='Paid'
					and (entrytype='Receipt' or packagename='Starting Payment')
					 and (ta.id=p_customeraccountid or ta.parentaccountid=p_customeraccountid
						or ta.id=(select ta2.parentaccountid from tbl_account ta2 where ta2.id=p_customeraccountid)
						or ta.parentaccountid=(select ta3.parentaccountid from tbl_account ta3 where ta3.id=p_customeraccountid)
						)
					--and ta.id=coalesce(nullif(p_customeraccountid,-9999),ta.id)
			 		group by customeraccountid
			 ) tblrec;	
else	
	create temporary table tmpqualifiedcustomers as
			select tblrec.customeraccountid as customeraccountid,
					tblrec.payoutday,
					(coalesce(tblrec.barenetamountreceived,0)-coalesce(tblpay.netamountpaid,0)-v_invoice_adjustment_amount-coalesce(v_negativepayout,0))::numeric(18,2) barebalance
		from (
				select customeraccountid,
			  		sum(coalesce(netamount,0)+coalesce(excess_amount,0)) netamountreceived,
					sum(coalesce(netamount,0)+coalesce(excess_amount,0)) barenetamountreceived,
					max(payoutday) payoutday
			 	from tbl_account ta inner join tbl_receivables tr
			  		on ta.id=tr.customeraccountid
 			  		and ta.status='1' and ta.pause_inactive_status='Active'
 			  		and  tr.isactive='1' 
 			  		and tr.status='Paid'
					and (entrytype='Receipt' or packagename='Starting Payment')
					 and (ta.id=p_customeraccountid or ta.parentaccountid=p_customeraccountid
						or ta.id=(select ta2.parentaccountid from tbl_account ta2 where ta2.id=p_customeraccountid)
						or ta.parentaccountid=(select ta3.parentaccountid from tbl_account ta3 where ta3.id=p_customeraccountid)
						)
					--and ta.id=coalesce(nullif(p_customeraccountid,-9999),ta.id)
			 		group by customeraccountid
			 ) tblrec
			 left join (
				 	select op.customeraccountid,
						sum(case when coalesce(ts.issalarydownloaded,'')='P' then coalesce(netpay,0) +case when (coalesce(tmpchallans.esichallanamount,0)<=0 or ts.esichallannumber is not null) then ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then  round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric)+coalesce(professionaltax,0) else 0 end+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(ts.mpryear,ts.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(tds,0) else 0 end
							when v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and ts.attendancemode='Ledger' and issalaryorliability='L' then 0
							when v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and op.appointment_status_id=15 then 0 
							when v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and coalesce(ts.issalarydownloaded,'')<>'P' then 0 
							else case when v_payout_mode_type='hybrid' then 0 else coalesce(netpay,0) end+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or ts.esichallannumber is not null) then ceil(coalesce(employeeesirate,0))+coalesce(employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(epf,0)::numeric)+round(coalesce(vpf,0)::numeric)+round(coalesce(ac_1,0)::numeric)+round(coalesce(ac_10,0)::numeric)+round(coalesce(ac_2,0)::numeric)+round(coalesce(ac21,0)::numeric) else 0 end+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(ts.mpryear,ts.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(professionaltax,0)+coalesce(tds,0) else 0 end end) netamountpaid
			 		from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
						and (1= case when v_payout_mode_type='self' then 2 else 1 end)
						and ts.is_rejected='0'
						and (workflowappid = -9999 or is_workflow_approved='Y') --change 4.0
				 		and op.recordsource='HUBTPCRM'
						and op.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),op.customeraccountid)
						and ts.payment_record_id is null --Added on 16-Aug-2024		
						and v_payout_mode_type<>'self'
						and op.customeraccountid is not null
						-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
				 --SIDDHARTH BANSAL 05/08/2024
				AND (NULLIF(p_ou_ids, '') is null or EXISTS
				(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
				))
				--END
			and make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date)::date
/********************Change 2.2 starts*******************************/				 
			left join (SELECT tcd.customeraccountid, tcd.challan_month, tcd.challan_year,
						sum(case when tcd.challantype='PF' then tcd.totalchallanamount::numeric else 0 end) as pfchallanamount,
						sum(case when tcd.challantype='ESIC' then tcd.totalchallanamount::numeric else 0 end) as esichallanamount
							FROM public.tbl_employer_challan_deposit tcd
							where (1= case when v_payout_mode_type='self' then 2 else 1 end)
							and tcd.isactive='1'
							and nullif(trim(tcd.challannumber),'') is not null
							and tcd.customeraccountid=p_customeraccountid 
						group by tcd.customeraccountid, tcd.challan_month, tcd.challan_year
					  )	 tmpchallans
				 on op.customeraccountid= tmpchallans.customeraccountid
				 and make_date(tmpchallans.challan_year,tmpchallans.challan_month,1)=date_trunc('month',to_date(left(ts.hrgeneratedon,11),'dd Mon yyyy'))::date 			   
/********************Change 2.2 ends*******************************/	
				/***************************/
				left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id 
				and mts.IsActive='1'
				and  coalesce(mts.PausedStatus,'Enable')='Enable'
				and mts.ProcessYear =ts.mpryear
				and mts.ProcessMonth =ts.mprmonth
			    where mts.EmpId is null 
				/***************************/
			 		group by op.customeraccountid
			 ) tblpay
			 on tblrec.customeraccountid=tblpay.customeraccountid::bigint
			 --where trunc(coalesce(tblrec.netamountreceived,0)-coalesce(tblpay.netamountpaid,0))>0
			 ;			 
	--RAISE NOTICE 'srfdgfdgfdgfg';
end if;		 
/***************change 1.3 starts**************************/			 
	drop table if exists tmpac21 ;
if trim(v_payout_mode_type) in ('standard','hybrid') then	
	create temporary table tmpac21 as
				 	select op.customeraccountid,ts.mprmonth ac21month,ts.mpryear ac21year
				 			,sum(case when coalesce(ts.issalarydownloaded,'')='P' and (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(ac21,0)::numeric)
							when v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and coalesce(ts.issalarydownloaded,'')<>'P' then 0 
							else /*case when v_payout_mode_type='hybrid' then 0 else*/ case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(ac21,0)::numeric) else 0 end /*end*/ end) bareac21
				 			,sum(case when coalesce(ts.issalarydownloaded,'')='P' and (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(epf,0)::numeric)
							when v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and coalesce(ts.issalarydownloaded,'')<>'P' then 0 
							else case when v_payout_mode_type='hybrid' then 0 else case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or ts.pfchallannumber is not null) then round(coalesce(epf,0)::numeric) else 0 end end end) bareepf
			 		from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
						and ts.is_rejected='0'
				 		and op.recordsource='HUBTPCRM'
						and (workflowappid = -9999 or is_workflow_approved='Y') --change 4.0
						and op.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),op.customeraccountid)
						and v_payout_mode_type<>'self'
						and op.customeraccountid is not null
						--AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END
					 --SIDDHARTH BANSAL 05/08/2024
					AND (NULLIF(p_ou_ids, '') is null or EXISTS
					(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
					))
					--END
			and make_date(ts.mpryear,ts.mprmonth,1)<date_trunc('month',current_date)::date
/********************Change 2.2 starts*******************************/				 
			left join (SELECT tcd.customeraccountid, tcd.challan_month, tcd.challan_year,
						sum(case when tcd.challantype='PF' then tcd.totalchallanamount::numeric else 0 end) as pfchallanamount,
						sum(case when tcd.challantype='ESIC' then tcd.totalchallanamount::numeric else 0 end) as esichallanamount
							FROM public.tbl_employer_challan_deposit tcd
							where tcd.isactive='1'
							and nullif(trim(tcd.challannumber),'') is not null
							and tcd.customeraccountid=p_customeraccountid 
						group by tcd.customeraccountid, tcd.challan_month, tcd.challan_year
					  )	 tmpchallans
				 on op.customeraccountid= tmpchallans.customeraccountid
				 and make_date(tmpchallans.challan_year,tmpchallans.challan_month,1)=date_trunc('month',to_date(left(ts.hrgeneratedon,11),'dd Mon yyyy'))::date 			   
/********************Change 2.2 ends*******************************/	
				/***************************/
				left join ManageTempPausedSalary mts on mts.EmpId=op.emp_id 
				and mts.IsActive='1'
				and  coalesce(mts.PausedStatus,'Enable')='Enable'
				and mts.ProcessYear =ts.mpryear
				and mts.ProcessMonth =ts.mprmonth
			    where mts.EmpId is null 
				/***************************/
			 		group by op.customeraccountid,ts.mprmonth,ts.mpryear;
else
create temporary table tmpac21 as
				 	select null::bigint customeraccountid,
					 		null::int ac21month,
					 		null::int ac21year
				 			,0 bareac21
				 			,0 bareepf;
			 		
end if;
/***************change 1.3 ends**************************/				 
/******************/
-- 	open v_rfccheck for select * from tmpqualifiedcustomers;
-- 	return next v_rfccheck;
/******************/	
if p_action='PayoutSummary' or p_action='PayoutDetails'  or p_action='VoucherDetails' then
	drop table if exists tmppayout;
			create temporary table  tmppayout
			as
				select t.id,ta.payoutday,t.attmon,t.attyear,t.attmonthname
				, count(distinct case when date_trunc('month',oa.dateofjoining)::date <=make_date(t.attyear,t.attmon,1) and (oa.dateofrelieveing is null or oa.dateofrelieveing>=t.attmonthdate)  then oa.emp_code else null end) totalemployees
				,count(distinct case when date_trunc('month',oa.dateofjoining)::date <=make_date(t.attyear,t.attmon,1) and (oa.dateofrelieveing is null or oa.dateofrelieveing>=t.attmonthdate) and mts.EmpId is not null  then oa.emp_code else null end) pausedemployees
				,count(distinct case when date_trunc('month',oa.dateofjoining)::date <=make_date(t.attyear,t.attmon,1) and (oa.dateofrelieveing is null or oa.dateofrelieveing>=t.attmonthdate) and tm.emp_code  is not null  then oa.emp_code else null end) salarydueemployees
				,count(distinct case when date_trunc('month',oa.dateofjoining)::date <=make_date(t.attyear,t.attmon,1) and (oa.dateofrelieveing is null or oa.dateofrelieveing>=t.attmonthdate) and tm.emp_code  is not null  then tm.emp_code  else null end) salarypaidemployees
				,0::numeric(18,2) totaldue
				,coalesce(sum(/*case when mts.EmpId is null then */(case when v_payout_mode_type='hybrid' then 0 else coalesce(tm.netpay,0) end+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or tm.esichallannumber is not null) then coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or tm.pfchallannumber is not null) then round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric) else 0 end+coalesce(tm.professionaltax,0)+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(tm.tds,0) else 0 end) /*else 0 end*/+coalesce(tm.mealvoucher,0)),0) totalpaid
				,coalesce(sum(case when coalesce(tm.issalarydownloaded,'')='P' or (v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and mts.EmpId is not null) or v_payout_mode_type='hybrid'  then 0 else (case when v_payout_mode_type='hybrid' then 0 else coalesce(tm.netpay,0) end+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or tm.esichallannumber is not null) then coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or tm.pfchallannumber is not null) then round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric) else 0 end+coalesce(tm.professionaltax,0)+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(lwf_employee,0) else 0 end+coalesce(tm.tds,0)+coalesce(tm.mealvoucher,0) else 0 end) end),0) totalundisbursed
				,coalesce(sum(case when coalesce(tm.issalarydownloaded,'')='P' or (v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and mts.EmpId is not null) or v_payout_mode_type='hybrid'  then 0 else case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or tm.pfchallannumber is not null) then (round(coalesce(tm.ac21,0)::numeric)) else 0 end end),0) totalundisbursed_ac21
				,coalesce(sum(case when coalesce(tm.issalarydownloaded,'')='P' or (v_payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ and mts.EmpId is not null) or v_payout_mode_type='hybrid'  then 0 else case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or tm.pfchallannumber is not null) then (round(coalesce(tm.epf,0)::numeric)) else 0 end end),0) totalundisbursed_epf
				,coalesce(sum(case when tm.attendancemode<>'Ledger' then (case when v_payout_mode_type='hybrid' then 0 else coalesce(tm.netpay,0) end+case when (coalesce(tmpchallans.esichallanamount,0)<=0 or tm.esichallannumber is not null) then coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0) else 0 end+case when (coalesce(tmpchallans.pfchallanamount,0)<=0 or tm.pfchallannumber is not null) then round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric) else 0 end+coalesce(tm.professionaltax,0)+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(tm.lwf_employee,0) else 0 end+coalesce(tm.tds,0)+coalesce(tm.mealvoucher,0) else 0 end) else 0 end),0) totalamtpaid
				,coalesce(max(approvedattendance),0)+coalesce(max(flexiapprovedattendance),0) approvedattendance
				,trim(TO_CHAR(make_date(t.attyear,t.attmon,
												least(coalesce((select tep.payoutday from tbl_employerpayoutdate tep where tep.customeracountid=p_customeraccountid 
													and tep.effectivefrom<=make_date(t.attyear,t.attmon,1)
													and tep.isactive='1' 
													order by effectivefrom desc limit 1),1)
													,extract('day' from date_trunc('month',make_date(t.attyear,t.attmon,1))+interval '1 month -1 day')::int
													)
		  		)+case when v_tbl_account.payout_period='Current' then interval '1 month' else interval '0 month' end, 'ddth Mon''yy'),'0') payoutdate
				,ta.id as customerid
				,ta.payout_settings
				,coalesce(sum(case when mts.EmpId is not null then (case when v_payout_mode_type='hybrid' then 0 else coalesce(tm.netpay,0) end+coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0)+round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric)+coalesce(tm.professionaltax,0)+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then coalesce(lwf_employer,0)+coalesce(tm.lwf_employee,0) else 0 end+coalesce(tm.tds,0) else 0 end) else 0 end),0) totalhold
				,0 unpaidac21
				,0 unpaidepf
				,null::int days_left
				,0::numeric(18,2) netpay
				,0::numeric(18,2) pausednetpay
				from tbl_account ta
				/*inner*/left join openappointments oa on oa.customeraccountid = ta.id 
				and ta.status = '1' and oa.converted = 'Y' and oa.appointment_status_id = '11'
				and ta.id=p_customeraccountid
				-- AND COALESCE(oa.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(oa.geofencingid, 0) ELSE p_geofenceid END
				--SIDDHARTH BANSAL 05/08/2024
				AND EXISTS
				(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0')), ','))
				)
				--END
				left join tmpyearmaster t on 1=1
				left join ManageTempPausedSalary mts on mts.EmpId=oa.emp_id 
				and mts.IsActive='1'
				and  coalesce(mts.PausedStatus,'Enable')='Enable'
				and mts.ProcessYear =t.attyear
				and mts.ProcessMonth =t.attmon	
				left join tbl_monthlysalary tm on oa.emp_code=tm.emp_code 
				and t.attmon=tm.mprmonth and t.attyear=tm.mpryear and tm.is_rejected='0'
				and tm.payment_record_id is null --Added on 16-Aug-2024
				and (workflowappid = -9999 or is_workflow_approved='Y') --change 4.0
				and v_payout_mode_type<>'self'
				
/********************Change 2.2 starts*******************************/				 
			left join (SELECT tcd.customeraccountid, tcd.challan_month, tcd.challan_year,
						sum(case when tcd.challantype='PF' then tcd.totalchallanamount::numeric else 0 end) as pfchallanamount,
						sum(case when tcd.challantype='ESIC' then tcd.totalchallanamount::numeric else 0 end) as esichallanamount
							FROM public.tbl_employer_challan_deposit tcd
							where tcd.isactive='1'
							and nullif(trim(tcd.challannumber),'') is not null
							and tcd.customeraccountid=p_customeraccountid 
						group by tcd.customeraccountid, tcd.challan_month, tcd.challan_year
					  )	 tmpchallans
				 on oa.customeraccountid= tmpchallans.customeraccountid
				 and make_date(tmpchallans.challan_year,tmpchallans.challan_month,1)=date_trunc('month',to_date(left(tm.hrgeneratedon,11),'dd Mon yyyy'))::date 			   
/********************Change 2.2 ends*******************************/
				left join (
				select oa.customeraccountid accountid,extract('month' from att_date) attmonth,
						extract('year' from att_date) attyear,
					count(distinct oa.emp_code) as approvedattendance
						 from tbl_monthly_attendance ta
					inner join openappointments oa on ta.emp_code=oa.emp_code 
					-- AND COALESCE(oa.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(oa.geofencingid, 0) ELSE p_geofenceid END
							--SIDDHARTH BANSAL 05/08/2024
							AND EXISTS
							(
							SELECT 1
							FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
							WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0')), ','))
							)
							--END
								where ta.isactive='1'
								and ta.approval_status='A'
								and oa.customeraccountid=p_customeraccountid
								and oa.appointment_status_id in(11,15)
								and ta.att_date>=oa.dateofjoining 
								and ((oa.dateofrelieveing is null and oa.appointment_status_id=11) or (ta.att_date<=case when oa.appointment_status_id=15 then oa.modifiedon::date else oa.dateofrelieveing end))
					
						group by oa.customeraccountid,extract('month' from att_date),
						extract('year' from att_date)	
				) app_attendance
				on ta.id=app_attendance.accountid
				and t.attmon=app_attendance.attmonth and t.attyear=app_attendance.attyear 
				and v_payout_mode_type<>'self' 
				left join (
				select oa.customeraccountid accountid,attendancemonth attmonth,attendanceyear attyear,
					count(distinct oa.emp_code) as flexiapprovedattendance
						 from public.tbl_monthwise_flexi_attendance ta
					inner join openappointments oa on ta.emp_code=oa.emp_code 
						-- AND COALESCE(oa.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(oa.geofencingid, 0) ELSE p_geofenceid END
						--SIDDHARTH BANSAL 05/08/2024
						AND (NULLIF(p_ou_ids, '') is null or EXISTS
						(
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
						WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0')), ','))
						))
						--END
								where ta.isactive='1'
								and oa.customeraccountid=p_customeraccountid
								and oa.appointment_status_id in (11,15)
 								and make_date(attendanceyear,attendancemonth,1)>=date_trunc('month',oa.dateofjoining) 
								and ((oa.dateofrelieveing is null and oa.appointment_status_id=11) or (make_date(attendanceyear,attendancemonth,1)<=case when oa.appointment_status_id=15 then oa.modifiedon::date else oa.dateofrelieveing end))
						group by oa.customeraccountid,attendancemonth,attendanceyear	
				) app_attendance_flexi
				on ta.id=app_attendance_flexi.accountid
				and t.attmon=app_attendance_flexi.attmonth and t.attyear=app_attendance_flexi.attyear
				
				where ta.status = '1'
				and ta.id=p_customeraccountid
				group by t.id,ta.payoutday,t.attmon,t.attyear,t.attmonthname,ta.id,ta.payout_settings;
				
			update tmppayout set totaldue=coalesce((select sum(salary) from pregeneratedpay where  attmon=salmon and attyear=salyear),0::numeric(18,2));
			update tmppayout set totalhold=totalhold+coalesce((select sum(pausedsalary) from pregeneratedpay where  salmon=attmon and salyear=attyear),0);
			update tmppayout set unpaidac21=coalesce((select sum(unpaidac21) from pregeneratedpay where  attmon=salmon and attyear=salyear),0::numeric(18,2));
			update tmppayout set unpaidepf= coalesce((select sum(unpaidepf)  from pregeneratedpay where  attmon=salmon and attyear=salyear),0::numeric(18,2));
			update tmppayout set netpay=coalesce((select sum(netpay) from pregeneratedpay where  attmon=salmon and attyear=salyear),0::numeric(18,2));
			update tmppayout set pausednetpay=coalesce((select sum(pausednetpay) from pregeneratedpay where  attmon=salmon and attyear=salyear),0::numeric(18,2));

		/********Test************/
update tmppayout t set days_left=greatest((make_date(t.attyear,t.attmon,least(coalesce((select tep.payoutday from tbl_employerpayoutdate tep where tep.customeracountid=p_customeraccountid 
													and tep.effectivefrom<=make_date(t.attyear,t.attmon,1)
													and tep.isactive='1' 
													order by effectivefrom desc limit 1),1)
													,extract('day' from date_trunc('month',make_date(t.attyear,t.attmon,1))+interval '1 month -1 day')::int
													)
		  		)+(case when v_tbl_account.payout_period='Current' then interval '1 month' else interval '0 month' end))::date-current_date,0);
	/********Test************/	
-- 		open v_rfccheck for select * from tmppayout;
-- 		return next v_rfccheck;
	/**********/

	open v_rfc1 for
			select
	(coalesce(tf.barebalance,0.00::numeric(18,2))-coalesce(totalundisbursed,0)-coalesce(t.totaldue,0.00::numeric(18,2))+ coalesce(creditamount,0.00::numeric(18,2))
					-
			 (case  when v_payout_mode_type in ('self','attendance') then 0 else
			 coalesce(case when (coalesce(unpaidepf,0)+coalesce(totalundisbursed_epf,0)+coalesce(bareepf,0))>0 then greatest(500-v_paidadmincharges-(coalesce(unpaidac21,0)+coalesce(totalundisbursed_ac21,0)+coalesce(bareac21,0)),0) else 0 end,0)      
			 end)
			 ) balance,
			t.id,
			least(coalesce((select tep.payoutday from tbl_employerpayoutdate tep where tep.customeracountid=t.customerid and tep.effectivefrom<=make_date(t.attyear,t.attmon,1)+case when v_tbl_account.payout_period='Current' then interval '1 month' else interval '0 month' end and tep.isactive='1' order by effectivefrom desc limit 1),t.payoutday),extract('day' from date_trunc('month',make_date(t.attyear,t.attmon,1))+interval '1 month -1 day')::int) ::text payoutdate,
			t.attmon mprmonth,t.attyear as mpryear,t.attyear p_year,
			t.attmonthname month_name,t.totalemployees,t.pausedemployees,
			case when (coalesce(tblunpaidsal.salary,0)+coalesce(totalpaid,0))=0 then 0 
				else ceil(greatest(case  when v_payout_mode_type in ('self','attendance') then 0 else coalesce(tblunpaidsal.salary,0) end+case when v_payout_mode_type='hybrid'  then 0 else coalesce(totalundisbursed,0) end,0)::numeric(18,4))
				end 
				+(case  when v_payout_mode_type in ('self','attendance') then 0 else coalesce(case when (coalesce(unpaidepf,0)+coalesce(totalundisbursed_epf,0)+coalesce(bareepf,0))>0 then greatest(500-v_paidadmincharges-(coalesce(unpaidac21,0)+coalesce(totalundisbursed_ac21,0)+coalesce(bareac21,0)),0) else 0 end,0) end )
				as amount,
			greatest(coalesce(t.salarydueemployees,0)-coalesce(t.pausedemployees,0),0) as workers,
		   	case    when v_payout_mode_type ='self' and payout_settings='Manual' then					
					case	when coalesce(salpaidcount,0)=coalesce(totalemployees,0) then 'Completed'
						when coalesce(totalhold,0)=0 and coalesce(v_netpay_pregenerated,0)=0 then 'Pending'
							when coalesce(v_netpay_pregenerated,0)>0 then 'Pending'
							when coalesce(totalhold,0)>0 then 'PartiallyPending'
							when coalesce(tss.salempcount,0)>0 and coalesce(v_netpay_pregenerated,0)>0 then 'PartiallyPending'
							when coalesce(tss.salempcount,0)=0 and coalesce(v_netpay_pregenerated,0)=0 then 'Pending'
							when coalesce(tss.salempcount,0)>0 and coalesce(v_netpay_pregenerated,0)=0 then 'Completed'
							when (coalesce(tss.salempcount,0)>0 or coalesce(totalhold,0)>0) and coalesce(v_netpay_pregenerated,0)>0 then 'PartiallyPending'
							when coalesce(tss.salempcount,0)=0 and coalesce(v_netpay_pregenerated,0)=0 then 'NotGenerated'
					end
		   	  when current_date<=coalesce(v_freetrialenddate,current_date-interval '1 day') then 'Pending'
					when v_payout_mode_type in ('attendance') then
					case	
							when ceil(coalesce(tf.barebalance,0.00::numeric(18,2)))<0  then 'Low Balance'
							when coalesce(v_invoicevalue,0)<=0 then 'Low Balance'
																																												
							else 'Completed'
					end
					when v_payout_mode_type in ('self') then
					case	when trunc(coalesce(tf.barebalance,0.00::numeric(18,2)))<0  then 'Low Balance'
							when coalesce(v_invoicevalue,0)<=0 then 'Low Balance'
		                   when coalesce(tss.salempcount,0)>0 and coalesce(totalhold,0)>0 then 'PartiallyPending' 
							when coalesce(tss.salempcount,0)>0 and coalesce(v_netpay_pregenerated,0)=0 then 'Completed'
							when coalesce(tss.salempcount,0)>0 and coalesce(v_netpay_pregenerated,0)>0 then 'PartiallyPending'
							when coalesce(tss.salempcount,0)=0 and coalesce(v_netpay_pregenerated,0)=0 then 'NotGenerated'
							when coalesce(tss.salempcount,0)=0 and coalesce(v_netpay_pregenerated,0)>0 then 'Pending'
							when coalesce(totaldue,0)=0 then 'Completed'
							else 'Pending'
					end	
			else 
				case		
		       --Change date 18 May 2024 due same month account creation with balance showing low balance
		--when coalesce(v_invoicevalue,0)<=0 then 'Low Balance' -- comment opened on 15-Jun-2024 for comp serve with 0 amount compliance case
		when coalesce(v_invoicevalue,0)<=0 and (coalesce(t.totaldue,0.00::numeric(18,2))>0 or coalesce(t.totalamtpaid,0)>0) then 'Low Balance'  --Added on 13-Jun-2024
		when coalesce(v_invoicevalue,0)<=0 and coalesce(tf.barebalance,0.00::numeric(18,2))<0 and (coalesce(t.totaldue,0.00::numeric(18,2))>0 or coalesce(t.totalamtpaid,0)>0) then 'Low Balance'
			--End Changes	
		when (trunc(coalesce(tf.barebalance,0.00::numeric(18,2))-coalesce(t.totaldue,0.00::numeric(18,2))-coalesce(totalundisbursed,0)+ coalesce(creditamount,0.00::numeric(18,2)))
				-coalesce(case when (coalesce(unpaidepf,0)+coalesce(totalundisbursed_epf,0)+coalesce(bareepf,0))>0 then greatest(500-v_paidadmincharges-(coalesce(unpaidac21,0)+coalesce(totalundisbursed_ac21,0)+coalesce(bareac21,0)),0) else 0 end
	 			,0))<-100 then 'Low Balance'
				--when t.totalamtpaid>0 and totalhold=0 then 'Pending'
				when v_payout_mode_type ='hybrid' and coalesce(t.netpay,0)>0 then  'Pending'		 
				when coalesce(t.totalamtpaid,0)>0 and coalesce(totalhold,0)>0 then 'PartiallyPending'
				when coalesce(t.totalamtpaid,0)>0 and coalesce(t.totaldue,0.00::numeric(18,2))>0 then 'PartiallyPending'
				when coalesce(t.totalamtpaid,0)>0 and coalesce(totalhold,0)=0 then 'Completed'
				when coalesce(t.totalamtpaid,0)>0 and coalesce(totalhold,0)>0  then 'PartiallyCompleted'
				when coalesce(totalhold,0)>0 then 'PartiallyPending'
				when coalesce(totalhold,0)=0 then 'Pending'
				when (payout_settings='Auto' and t.days_left<=0) then 'Completed'
				when (payout_settings='Auto' and t.days_left>0) then 'Pending'
			end 
		end as status
	,case when p_action='PayoutSummary' then trim(TO_CHAR(TO_DATE (t.attmon::text, 'MM'), 'Month'))  
	else trim(TO_CHAR(TO_DATE (t.attmon::text, 'MM')+interval '1 month', 'Month'))  end AS month_full_name
	,days_left
	 ,case when v_payout_mode_type ='self' and coalesce(salpaidcount,0)=coalesce(totalemployees,0) then 'Generated'
	when (payout_settings='Manual' and coalesce(t.totalamtpaid,0)<=0) then 'Not Generated'
	 			 when (coalesce(tf.barebalance,0.00::numeric(18,2))-coalesce(t.totaldue,0.00::numeric(18,2))+ coalesce(creditamount,0.00::numeric(18,2)))<-100 then 'Low Balance' 
	 	   		when floor(coalesce(t.totalamtpaid,0))>0 then 'Generated'
				when (coalesce(tf.barebalance,0.00::numeric(18,2))-coalesce(t.totaldue,0.00::numeric(18,2))+ coalesce(creditamount,0.00::numeric(18,2)))>=0 and pausedemployees=0 then 'Auto'
		  else 'Not Generated' end as Payment_status
	 ,t.approvedattendance
	 ,coalesce(v_isattendancerequiredemployer,v_isattendancerequiredemployee) as payout_settings
	 ,t.payoutdate payoutdate
	 ,tf.barebalance
	 ,'Salary' as payouttype
	 ,case when v_payout_mode_type ='self' and payout_settings='Manual' then 0.1 else coalesce(v_invoicevalue,0)+case when current_date<=coalesce(v_freetrialenddate,current_date-interval '1 day') and coalesce(v_invoicevalue,0)=0 then 1 else 0 end end invoicevalue
	 
	 ,coalesce(
		 coalesce(case when (coalesce(unpaidepf,0)+coalesce(totalundisbursed_epf,0)+coalesce(bareepf,0))>0 then greatest(500-v_paidadmincharges-(coalesce(unpaidac21,0)+coalesce(totalundisbursed_ac21,0)+coalesce(bareac21,0)),0) else 0 end,0)
		 ,0) as pfadmincharges
		 ,v_tbl_account.payment_plan
		 ,coalesce(tss.salempcount,0) salempcount
		 ,coalesce(totalhold,0) totalhold
		 ,coalesce(v_netpay_pregenerated,0) v_netpay_pregenerated
		 ,salpaidcount
		,(trunc(coalesce(tf.barebalance,0.00::numeric(18,2))-coalesce(t.totaldue,0.00::numeric(18,2))-coalesce(totalundisbursed,0)+ coalesce(creditamount,0.00::numeric(18,2)))
				-coalesce(case when (coalesce(unpaidepf,0)+coalesce(totalundisbursed_epf,0)+coalesce(bareepf,0))>0 then greatest(500-v_paidadmincharges-(coalesce(unpaidac21,0)+coalesce(totalundisbursed_ac21,0)+coalesce(bareac21,0)),0) else 0 end
	 			,0)) balancecheckamount
				 ,coalesce(v_inhand_pregenerated,0) inhand_pregenerated
				 ,v_tbl_account.pause_inactive_status
	from tmppayout t
	left join tmpqualifiedcustomers tf on t.customerid=tf.customeraccountid
	left join LATERAL
	(
		select salmon,salyear,sum(salary) as salary,sum(pausedsalary) pausedsalary
		from pregeneratedpay
		WHERE pregeneratedpay.salmon=t.attmon and pregeneratedpay.salyear=t.attyear
		group by salmon,salyear
	) tblunpaidsal on v_payout_mode_type<>'self'	
	left join LATERAL
	(
		select invoicemonth,invoiceyear,sum(netamountreceived) v_invoicevalue
		from tblinvoices
		WHERE tblinvoices.invoicemonth=t.attmon and tblinvoices.invoiceyear=t.attyear
		group by invoicemonth,invoiceyear
	) tblinvoices on TRUE
	left join LATERAL
	(
		select	ta.id as creditcustomerid,credityear,creditmonth,sum(netamount) creditamount
		from tbl_account ta
		inner join tbl_receivables tr
			on ta.id=tr.customeraccountid and v_payout_mode_type<>'self'
			and ta.status='1' and ta.pause_inactive_status='Active'
			and  tr.isactive='1' 
			and (tr.status='Outstanding' AND coalesce(tr.credit_applicable,'N')='Y')
			and ta.id=coalesce(nullif(p_customeraccountid,-9999),ta.id)
			AND creditmonth=t.attmon and credityear=t.attyear	
		group by ta.id,credityear,creditmonth
	) tmpcredit ON TRUE
	left join tmpac21 on tmpac21.ac21year=t.attyear and tmpac21.ac21month=t.attmon
	left join tmpselfsalacount tss on tss.salmonth=t.attmon and tss.salyear=t.attyear 

	union all
	select
		0.00 balance,0 as id,null::text payoutdate,
		t.mprmonth,t.mpryear,t.mpryear p_year,
		to_char(make_date(mpryear,mprmonth,1),'Mon-yyyy') month_name,count(t.emp_code) totalemployees,0 pausedemployees,
		round(sum(t.netpay))  as amount,
		count(t.emp_code) as workers,
		'' status
		, trim(TO_CHAR(TO_DATE (t.mprmonth::text, 'MM'), 'Month'))   AS month_full_name
		,0 days_left
		,'' Payment_status
		,0 approvedattendance
		,'' as payout_settings
		,'' payoutdate
		,0 barebalance
		,'Voucher' as payouttype
		,coalesce(max(v_invoicevalue),0)+case when current_date<=coalesce(v_freetrialenddate,current_date-interval '1 day') and coalesce(max(v_invoicevalue),0)=0 then 1 else 0 end invoicevalue
		,0 pfadmincharges
		,v_tbl_account.payment_plan
		,0 salempcount
		,0 totalhold
		, v_netpay_pregenerated
		,0 salpaidcount
		,0 balancecheckamount
		,0 inhand_pregenerated
		,v_tbl_account.pause_inactive_status
	from openappointments op
	inner join tbl_monthlysalary t
		on op.emp_code=t.emp_code and t.is_rejected='0' and op.recordsource='HUBTPCRM'
		and op.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),op.customeraccountid)
		and op.customeraccountid is not null and t.attendancemode='Ledger' and t.netpay>0
		and (workflowappid = -9999 or is_workflow_approved='Y') --change 1.0
	left join LATERAL
	(
		select invoicemonth,invoiceyear,sum(netamountreceived) v_invoicevalue
		from tbl_receivables 
		WHERE invoicemonth=t.mprmonth and invoiceyear=t.mpryear
		group by invoicemonth,invoiceyear
	) tblinvoices ON TRUE
	inner join tbl_employeeledger tl on t.emp_code=tl.emp_code and t.disbursedledgerids::int=tl.id and tl.headid in (9,67)
			and mprmonth=extract('month' from (current_date-interval '1 month'))::int 
			and mpryear=extract('year' from (current_date-interval '1 month'))::int
			and (p_action='PayoutSummary' or p_action='VoucherDetails')
			-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END 
			--SIDDHARTH BANSAL 05/08/2024
			AND
			(
				NULLIF(p_ou_ids, '') is null or EXISTS
				(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
				)
			)
			--END
	group by t.mprmonth,t.mpryear,op.customeraccountid
	order by id;
	return next v_rfc1;
end if;

if p_action='VoucherDetails'  then
	open v_rfc2 for
		select oa.emp_code,oa.emp_name,0 paiddays,
			max(t.mprmonth) mprmonth,max(t.mpryear) mpryear,
			coalesce(round(sum(t.netpay))) amount,
			'' as approvalstatus
			,'' as photopath
			,max(oa.mobile) mobile,max(to_char(oa.dateofbirth,'dd/mm/yyyy')) dateofbirth
			,''::text payoutday
		from openappointments oa
		inner join tbl_monthlysalary t
			on oa.emp_code=t.emp_code
			and t.is_rejected='0'
			and oa.recordsource='HUBTPCRM'
			and (workflowappid = -9999 or is_workflow_approved='Y') --change 4.0
			and oa.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),oa.customeraccountid)
			and oa.customeraccountid is not null
			and t.attendancemode='Ledger' and t.netpay<>0
			inner join tbl_employeeledger tl on t.emp_code=tl.emp_code and t.disbursedledgerids::int=tl.id and tl.headid in(9,67)
			and mprmonth=extract('month' from (current_date-interval '1 month'))::int 
			and mpryear=extract('year' from (current_date-interval '1 month'))::int
			-- AND COALESCE(oa.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(oa.geofencingid, 0) ELSE p_geofenceid END 
			--SIDDHARTH BANSAL 05/08/2024
				AND (NULLIF(p_ou_ids, '') is null or EXISTS
				(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0')), ','))
				))
				--END
		group by oa.emp_code,oa.emp_name,t.mprmonth,t.mpryear,oa.customeraccountid;
	return next v_rfc2;
end if;

if p_action='PayoutDetails'  then
	open v_rfc2 for
				select oa.emp_code,oa.emp_name||' ('||coalesce(nullif(oa.orgempcode,''),nullif(oa.cjcode,''),'')||')' emp_name,coalesce(nullif(sum(tm.paiddays),0),sum(pregeneratedpay.paiddays)) paiddays,
				max(t.attmon) mprmonth,max(t.attyear) mpryear,oa.post_offered,--case when oa.jobtype='Unit Parameter' then tm.departmentname else (string_to_array(oa.posting_department,'#'))[1]::varchar end as posting_department,coalesce(unitname,'') unitparametername, -- SIDDHARTH BANSAL 21/10/2024
				round(greatest(coalesce(sum(tm.paidsal),0)+coalesce(sum(case when mts.EmpId is not null then 0 else pregeneratedpay.salary end),0),0)::numeric,0) amount,
				max(case when mts.EmpId is not null then 'Hold' else 'Approved' end) as approvalstatus
				,nullif(max(tcd.document_path),'https://api.contract-jobs.com/crm_api/') as photopath
				,max(oa.mobile) mobile,max(to_char(oa.dateofbirth,'dd/mm/yyyy')) dateofbirth
				,max(ta.payoutday)::text payoutday
				,case when (coalesce(sum(tm.mprpaidsal_status),0)>0 or sum(coalesce(mprpaiddays,0))>0) /*and coalesce(sum(pregeneratedpay.salary),0)::numeric=0*/ then 'Paid' else '' end as paystatus
				,round(greatest(coalesce(sum(tm.paidnetpay),0)+coalesce(sum(case when mts.EmpId is not null then 0 else pregeneratedpay.netpay end),0),0)::numeric,0) nepay
				,case when max(pregeneratedpay.ecode) is null then 'N' else 'Y' end adviceexists
				,coalesce(min(issalapprovalapproved),'Y') issalapprovalapproved
				from tbl_account ta
				inner join openappointments oa on oa.customeraccountid = ta.id 
				and ta.status = '1' and oa.converted = 'Y' and oa.appointment_status_id = '11'
				-- SIDDHARTH BANSAL 21/10/2024
					 AND (
					COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
					OR EXISTS (
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(oa.post_offered)), ',')) AS input_designation
						WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(oa.post_offered), ''), ''), ','))
								)
					)

					AND (
					COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
					OR EXISTS (
						SELECT 1
						FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(oa.posting_department)), ',')) AS input_department
						WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(oa.posting_department), ''), ''), ','))
								)
					)
					AND (NULLIF(p_unitparametername, '') is null or
					EXISTS
						(
							SELECT 1
							FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
							WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0')), ','))
						))
				--END				
															   
				and ta.id=p_customeraccountid
				and date_trunc('month',oa.dateofjoining) <=to_date('01'||lpad(p_month::text,2,'0')||p_year::text,'ddmmyyyy')
				and (oa.dateofrelieveing is null or oa.dateofrelieveing>=to_date('01'||lpad(p_month::text,2,'0')||p_year::text,'ddmmyyyy'))
				and oa.jobtype<>'Consultant'
				-- AND COALESCE(oa.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(oa.geofencingid, 0) ELSE p_geofenceid END
				--SIDDHARTH BANSAL 05/08/2024
				AND
				(nullif(p_empname,'')is null or 
					oa.emp_name ILIKE '%'||COALESCE(nullif(p_empname,''), oa.emp_name)||'%' OR
					oa.mobile ILIKE '%'||COALESCE(nullif(p_empname,''), oa.mobile)||'%' OR
					oa.orgempcode ILIKE '%'||COALESCE(nullif(p_empname,''), oa.orgempcode)||'%' OR
					oa.cjcode ILIKE '%'||COALESCE(nullif(p_empname,''), oa.cjcode)||'%'
				)
				--SIDDHARTH BANSAL 05/08/2024
					AND (NULLIF(p_ou_ids, '') is null OR EXISTS
					(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0')), ','))
					))
					--END
				left join tbl_candidate_documentlist tcd on oa.emp_id = tcd.candidate_id and tcd.document_id = 17 and tcd.active = 'Y'	
				left join tmpyearmaster t on 1=1
				left join (select ecode,sum(salary) salary,sum(pausedsalary) pausedsalary,sum(paiddays) paiddays, salmon, salyear,sum(unpaidac21) unpaidac21,sum(unpaidepf) unpaidac21,sum(netpay) netpay,min(issalapprovalapproved) issalapprovalapproved  from pregeneratedpay group by ecode, salmon, salyear)pregeneratedpay on pregeneratedpay.ecode=oa.emp_code
				left join ManageTempPausedSalary mts on mts.EmpId=oa.emp_id 
				and mts.IsActive='1'
				and  coalesce(mts.PausedStatus,'Enable')='Enable'
				and mts.ProcessYear =t.attyear
				and mts.ProcessMonth =t.attmon		
				left join
				(select tm.emp_code,tm.is_advice,
				 case when tm.recordscreen in('Previous Wages','Increment Arear') then tm.arearprocessmonth  when tm.attendancemode='Manual' then extract('month' from to_date(left(tm.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month') else tm.mprmonth end as mprmonth, 
				 case when tm.recordscreen in('Previous Wages','Increment Arear') then tm.arearprocessyear when tm.attendancemode='Manual' then extract('year' from to_date(left(tm.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month') else tm.mpryear end as mpryear, 
				 sum(case when tm.recordscreen in('Previous Wages','Increment Arear') then 0 else  tm.paiddays end) paiddays,
				 sum(case when v_payout_mode_type='hybrid'  then 0 else case when v_payout_mode_type='hybrid' and coalesce(tm.issalarydownloaded,'')<>'P'then 0 else coalesce(tm.netpay,0)-coalesce(totalarear,0) end+coalesce(employerinsuranceamount,0)+coalesce(tm.insuranceamount,0)+coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0)+coalesce(tm.employee_esi_incentive,0)+coalesce(tm.employer_esi_incentive,0)+round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric)+coalesce(tm.professionaltax,0)+case when v_tbl_account.payout_mode_type in('standard','self','dfm','eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then +coalesce(tm.lwf_employee,0)+coalesce(lwf_employer,0) else 0 end+coalesce(tm.tds,0)+coalesce(tm.mealvoucher,0) else 0 end end) paidsal,
				 sum(case when v_payout_mode_type='hybrid'  or tm.attendancemode not in ('MPR','Manual') then 0 else case when v_payout_mode_type='hybrid' and coalesce(tm.issalarydownloaded,'')<>'P'then 0 else coalesce(tm.netpay,0)-coalesce(totalarear,0) end+coalesce(employerinsuranceamount,0)+coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0)+coalesce(tm.employee_esi_incentive,0)+coalesce(tm.employer_esi_incentive,0)+round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric)+coalesce(tm.professionaltax,0)+case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then +coalesce(tm.lwf_employee,0)+coalesce(lwf_employer,0) else 0 end+coalesce(tm.tds,0)+coalesce(tm.mealvoucher,0) end) mprpaidsal,
				 sum(case when v_payout_mode_type='hybrid'  or coalesce(tm.issalarydownloaded,'')<>'P' then 0 else  coalesce(tm.netpay,0)-coalesce(totalarear,0)+coalesce(employerinsuranceamount,0)+coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0)+coalesce(tm.employee_esi_incentive,0)+coalesce(tm.employer_esi_incentive,0)+round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric)+coalesce(tm.professionaltax,0)+case when v_tbl_account.payout_mode_type in ('standard', 'dfm', 'eor') /* Added dfm and eor with standard payout mode type */ then case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then +coalesce(tm.lwf_employee,0)+coalesce(lwf_employer,0) else 0 end+coalesce(tm.tds,0)+coalesce(tm.mealvoucher,0) else 0 end end) disbursedsal,
				 sum(case when (tm.mprmonth=p_month and tm.mpryear=p_year and tm.recordscreen='Current Wages' and tm.attendancemode='MPR') then paiddays else 0 end) as mprpaiddays,
				 sum(case when tm.is_advice='Y' then 0 when v_payout_mode_type='hybrid'  or tm.attendancemode not in ('MPR','Manual') then 0 else case when v_payout_mode_type='hybrid' and coalesce(tm.issalarydownloaded,'')<>'P'then 0 else coalesce(tm.netpay,0)-coalesce(totalarear,0) end+coalesce(employerinsuranceamount,0)+coalesce(ceil(tm.employeeesirate),0)+coalesce(tm.employeresirate,0)+coalesce(tm.employee_esi_incentive,0)+coalesce(tm.employer_esi_incentive,0)+round(coalesce(tm.epf,0)::numeric)+coalesce(tm.vpf,0)+round(coalesce(tm.ac_1,0)::numeric)+round(coalesce(tm.ac_10,0)::numeric)+round(coalesce(tm.ac_2,0)::numeric)+round(coalesce(tm.ac21,0)::numeric)+coalesce(tm.professionaltax,0)+case when make_date(tm.mpryear,tm.mprmonth,1)>='2024-03-01'::date then +coalesce(tm.lwf_employee,0)+coalesce(lwf_employer,0) else 0 end+coalesce(tm.tds,0)+coalesce(tm.mealvoucher,0) end) mprpaidsal_status,
				 sum(netpay-coalesce(totalarear,0)) as paidnetpay
				 ,count(case when tm.attendancemode in ('MPR','Manual')  and recordscreen <>'Increment Arear' then tm.emp_code else null end) as salpaidcount
				 from tbl_monthlysalary tm
				inner join openappointments oa on tm.emp_code=oa.emp_code 
				and (workflowappid = -9999 or is_workflow_approved='Y') --change 4.0
				 and oa.customeraccountid=p_customeraccountid and tm.is_rejected='0' 
				and (
					(tm.mprmonth=p_month and tm.mpryear=p_year and tm.recordscreen='Current Wages' and is_advice='N')
					or
					(tm.arearprocessmonth=p_month and tm.arearprocessyear=p_year and tm.recordscreen in('Previous Wages','Increment Arear'))
					or
					(date_trunc('month',to_date(left(tm.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month')::date=make_date(v_year,v_month,1)  and tm.attendancemode='Manual')	 
				)
				 --  AND COALESCE(oa.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(oa.geofencingid, 0) ELSE p_geofenceid END
				 --SIDDHARTH BANSAL 05/08/2024
				AND (NULLIF(p_ou_ids, '') is null or EXISTS
				(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(oa.assigned_ou_ids, ''), COALESCE(NULLIF(oa.geofencingid::TEXT, ''), '0')), ','))
				))
				--END
				left join banktransfers bt on tm.emp_code=bt.emp_code 
				and tm.mprmonth=bt.salmonth and tm.mpryear=bt.salyear  and tm.batchid=bt.batchcode and bt.isrejected='0'
				 group by tm.emp_code,tm.is_advice,
				 case when tm.recordscreen in('Previous Wages','Increment Arear') then tm.arearprocessmonth when tm.attendancemode='Manual' then extract('month' from to_date(left(tm.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month') else tm.mprmonth end, 
				 case when tm.recordscreen in('Previous Wages','Increment Arear') then tm.arearprocessyear when tm.attendancemode='Manual' then extract('year' from to_date(left(tm.hrgeneratedon,11),'dd Mon yyyy')-interval '1 month') else tm.mpryear end 
				 
				 --,tm.mprmonth, tm.mpryear
				)tm
				on oa.emp_code=tm.emp_code 
				and t.attmon=tm.mprmonth and t.attyear=tm.mpryear

				where ta.status = '1'
				group by oa.emp_name,oa.emp_code,oa.orgempcode,oa.cjcode,oa.post_offered,oa.posting_department 
/*change 3.9*/	having (round(greatest(coalesce(sum(tm.paidsal),0)+coalesce(sum(case when mts.EmpId is not null then pregeneratedpay.pausedsalary else pregeneratedpay.salary end),0),0)::numeric,0)>0 or max(pregeneratedpay.ecode) is not null or coalesce(sum(salpaidcount),0) >0)
				order by  oa.emp_name;																						   

	return next v_rfc2 ;

end if;

end;
$BODY$;

ALTER FUNCTION public.uspemployerpayout(text, bigint, integer, integer, integer, character varying, text, text, text, text)
    OWNER TO stagingpayrolling_app;

