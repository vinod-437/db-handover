-- FUNCTION: public.uspmonthwisesalarycoponents(text, bigint, double precision, character varying, text, integer, character varying, text, text, text, text)

-- DROP FUNCTION IF EXISTS public.uspmonthwisesalarycoponents(text, bigint, double precision, character varying, text, integer, character varying, text, text, text, text);

CREATE OR REPLACE FUNCTION public.uspmonthwisesalarycoponents(
	p_financialyear text,
	p_empcode bigint,
	p_balancetax double precision,
	p_tptype character varying DEFAULT 'NonTP'::character varying,
	p_customeraccountid text DEFAULT '-9999'::text,
	p_geofenceid integer DEFAULT 0,
	p_ou_ids character varying DEFAULT NULL::character varying,
	p_post_offered text DEFAULT ''::text,
	p_posting_department text DEFAULT ''::text,
	p_unitparametername text DEFAULT ''::text,
	p_search_keyword text DEFAULT ''::text)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
/*************************************************************************
Version   Date			Change							Done_by
1.1						Initial version
1.2 	01/08/2024		Added OuId changes				Siddharth bansal
1.3     22/08/2024      Added tpcode and orgempcode 	Siddharth Bansal
						in response
1.3     19/02/2025      Added mobile and dob 			Siddharth Bansal
						in response
1.4     31/03/2025      Added Filter for Search Keyword Siddharth Bansal
1.5     21/04/2025	    Added regime and ou details     Siddharth Bansal
1.6     08/07/2025	    hrgeneratedon change for Vouchers     Shiv Kumar
													   
*************************************************************************/
declare
v_rfc refcursor;
v_remainingtdspermonth numeric(18,2);
v_mon1 int;
v_mon2 int;
v_leftflag varchar(1):='N';
v_dateofrelieveing date;
v_year1 int;
v_year2 int;

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
v_currentmonthpayoutdone varchar(1):='N';
begin

if exists(select * from tbl_monthlysalary 
		  where emp_code=p_empcode 
		  		and mprmonth=extract('month' from current_date)::int 
		  		and mpryear=extract('year' from current_date)::int
		 		and is_rejected='0'
		 		and recordscreen in ('Current Wages','Previous Wages')
		 		and paiddays>0) then
v_currentmonthpayoutdone:='Y';				
end if;				
v_year1:=left(p_financialyear,4)::int;
v_year2:=right(p_financialyear,4)::int;

v_startdate:=to_date(v_year1::text||'-05-01','yyyy-mm-dd');
v_enddate:=to_date(v_year2::text||'-04-30','yyyy-mm-dd');

v_advancestartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_advanceenddate:=to_date(v_year1::text||'-04-30','yyyy-mm-dd');

v_finyearstartdate:=to_date(v_year1::text||'-04-01','yyyy-mm-dd');
v_finyearenddate:=to_date(v_year2::text||'-03-31','yyyy-mm-dd');

if p_empcode<>-9999 then
select coalesce(left_flag,'N'),dateofrelieveing,nullif(trim(pancard),'') into v_leftflag,v_dateofrelieveing,v_pancard from openappointments where emp_code=p_empcode;
end if;
v_mon1:=extract (month from current_date);

if v_mon1 between 4 and 12 then
	if v_currentmonthpayoutdone='N' then
		v_remainingtdspermonth:=p_balancetax/((12-v_mon1)+4);
	else
		v_remainingtdspermonth:=p_balancetax/((12-v_mon1-1)+4);
	end if;
else
	if v_currentmonthpayoutdone='N' then
		v_remainingtdspermonth:=p_balancetax/((3-v_mon1)+1);
	else
		v_remainingtdspermonth:=p_balancetax/greatest(((3-v_mon1)+1),1);
		
end if;	
end if;
	if v_mon1 =4  and v_year2=extract (year from current_date) then
		v_remainingtdspermonth:=p_balancetax;
	end if;
create temporary table tmp_tblproj on commit drop
as
select max(op.emp_code)over(partition by coalesce(nullif(trim(op.pancard),''),op.emp_code::text) order by op.emp_id desc) lastempcode,
tbl_monthlysalary.emp_code, 
op.emp_name,op.dateofbirth,op.mobile,nullif(trim(op.pancard),'') pancard,op.cjcode tpcode,op.orgempcode,(select string_agg(ton.org_unit_name,', ') 
                              from public.tbl_org_unit_geofencing ton 
                              inner join (select * from string_to_table(op.assigned_ou_ids,',')   as t) t1
                              on t1.t::int=ton.id
                             ) as assignedous,
---------------------------------
case when (substring(hrgeneratedon,4,3)='Apr' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
     and ((mprmonth=4 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 
	 or (substring(hrgeneratedon,4,3)='May' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,5,1))

	or (substring(hrgeneratedon,4,3)='Apr' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=4 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='May' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,5,1))
		
		
	or 	(substring(hrgeneratedon,4,3)='May' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')
		then 4

when (substring(hrgeneratedon,4,3)='May' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
     and ((mprmonth=5 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Jun' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,6,1))
	or (substring(hrgeneratedon,4,3)='May' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=5 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Jun' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,6,1))
	or 	(substring(hrgeneratedon,4,3)='Jun' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')
		then 5

when (substring(hrgeneratedon,4,3)='Jun' and substring(hrgeneratedon,8,4)::int=v_year1
 		and recordscreen<>'Increment Arear'
    and ((mprmonth=6 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Jul' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,7,1))	
	or (substring(hrgeneratedon,4,3)='Jun' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=6 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Jul' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,7,1))
	or 	(substring(hrgeneratedon,4,3)='Jul' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')
		then 6

when (substring(hrgeneratedon,4,3)='Jul' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
     and ((mprmonth=7 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Aug' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,8,1)) 
	or (substring(hrgeneratedon,4,3)='Jul' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=7 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Aug' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,8,1))

	or 	(substring(hrgeneratedon,4,3)='Aug' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')
		then 7
		
when (substring(hrgeneratedon,4,3)='Aug' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
     and ((mprmonth=8 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Sep' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,9,1))
	or (substring(hrgeneratedon,4,3)='Aug' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=8 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Sep' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,9,1))

	or 	(substring(hrgeneratedon,4,3)='Sep' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')	
		then 8
		
when (substring(hrgeneratedon,4,3)='Sep' and substring(hrgeneratedon,8,4)::int=v_year1
 		and recordscreen<>'Increment Arear'
    and ((mprmonth=9 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Oct' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,10,1))
	or (substring(hrgeneratedon,4,3)='Sep' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=9 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Oct' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,9,1))

	or 	(substring(hrgeneratedon,4,3)='Oct' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')		
		then 9		
------
when (substring(hrgeneratedon,4,3)='Oct' and substring(hrgeneratedon,8,4)::int=v_year1
 		and recordscreen<>'Increment Arear'
    and ((mprmonth=10 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Nov' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,11,1))
	or (substring(hrgeneratedon,4,3)='Oct' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=10 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Nov' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,11,1))

	or 	(substring(hrgeneratedon,4,3)='Nov' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')		
		then 10

when (substring(hrgeneratedon,4,3)='Nov' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
     and ((mprmonth=11 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Dec' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year1,12,1))
	or (substring(hrgeneratedon,4,3)='Nov' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=11 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Dec' and substring(hrgeneratedon,8,4)::int=v_year1 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year1,12,1))

	or 	(substring(hrgeneratedon,4,3)='Dec' and substring(hrgeneratedon,8,4)::int=v_year1 and attendancemode='Ledger')		
		then 11

when (substring(hrgeneratedon,4,3)='Dec' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen<>'Increment Arear'
     and ((mprmonth=12 and mpryear=v_year1) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Jan' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year2,1,1))

	or (substring(hrgeneratedon,4,3)='Dec' and substring(hrgeneratedon,8,4)::int=v_year1
		and recordscreen='Increment Arear'
     and (arearprocessmonth=12 and arearprocessyear=v_year1))
	 
	 or (substring(hrgeneratedon,4,3)='Jan' and substring(hrgeneratedon,8,4)::int=v_year2 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year2,1,1))

	or 	(substring(hrgeneratedon,4,3)='Jan' and substring(hrgeneratedon,8,4)::int=v_year2 and attendancemode='Ledger')		
		then 12

when (substring(hrgeneratedon,4,3)='Jan' and substring(hrgeneratedon,8,4)::int=v_year2
 		and recordscreen<>'Increment Arear'
    and ((mprmonth=1 and mpryear=v_year2) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Feb' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year2,2,1)) 
	or (substring(hrgeneratedon,4,3)='Jan' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen='Increment Arear'
     and (arearprocessmonth=1 and arearprocessyear=v_year2))
	 
	 or (substring(hrgeneratedon,4,3)='Feb' and substring(hrgeneratedon,8,4)::int=v_year2 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year2,2,1))

	or 	(substring(hrgeneratedon,4,3)='Feb' and substring(hrgeneratedon,8,4)::int=v_year2 and attendancemode='Ledger')		
		then 1
		
when (substring(hrgeneratedon,4,3)='Feb' and substring(hrgeneratedon,8,4)::int=v_year2
 		and recordscreen<>'Increment Arear'
     and ((mprmonth=2 and mpryear=v_year2) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Mar' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year2,3,1))	

	or (substring(hrgeneratedon,4,3)='Feb' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen='Increment Arear'
     and (arearprocessmonth=2 and arearprocessyear=v_year2))
	 
	 or (substring(hrgeneratedon,4,3)='Mar' and substring(hrgeneratedon,8,4)::int=v_year2 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year2,3,1))

	or 	(substring(hrgeneratedon,4,3)='Mar' and substring(hrgeneratedon,8,4)::int=v_year2 and attendancemode='Ledger')		
		then 2

when (substring(hrgeneratedon,4,3)='Mar' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen<>'Increment Arear'
      and ((mprmonth=3 and mpryear=v_year2) and attendancemode<>'Ledger'))
	 or (substring(hrgeneratedon,4,3)='Apr' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen<>'Increment Arear'
		and attendancemode<>'Ledger' and make_date(mpryear,mprmonth,1)<make_date(v_year2,4,1))
	or (substring(hrgeneratedon,4,3)='Mar' and substring(hrgeneratedon,8,4)::int=v_year2
		and recordscreen='Increment Arear'
     and (arearprocessmonth=3 and arearprocessyear=v_year2))
	 
	 or (substring(hrgeneratedon,4,3)='Apr' and substring(hrgeneratedon,8,4)::int=v_year2 
		and recordscreen='Increment Arear'
		and make_date(arearprocessyear,arearprocessmonth,1)<make_date(v_year2,4,1))

	or 	(substring(hrgeneratedon,4,3)='Apr' and substring(hrgeneratedon,8,4)::int=v_year2 and attendancemode='Ledger')		
		then 3	
end		
as mprmonth,
grossearning grossearning,otherdeductions,grossdeduction,otherledgerarears,otherledgerdeductions,fixedallowancestotal,netpay,tds,atds	
,case when recordscreen in('Current Wages','Previous Wages','Arear Wages') then paiddays else 0 end as paiddays
,voucher_amount
,paystatus
,op.jobtype
from (select tbl_monthlysalary.emp_code,tds,grossearning,voucher_amount,otherdeductions,hrgeneratedon,is_rejected,is_rejected,mprmonth,mpryear,grossdeduction,otherledgerarears,otherledgerdeductions,fixedallowancestotal,netpay-coalesce(totalarear,0) netpay,atds,recordscreen,paiddays
	  ,'Paid' as paystatus,attendancemode,arearprocessmonth,arearprocessyear
			   
	  ,mealvoucher
	  from tbl_monthlysalary inner join openappointments op2 on tbl_monthlysalary.emp_code=op2.emp_code and op2.appointment_status_id<>13		
	and op2.customeraccountid=coalesce(nullif(nullif(p_customeraccountid,''),'-9999')::bigint,op2.customeraccountid)::bigint
	--SIDDHARTH BANSAL 31/03/2025
	AND
	(	nullif(p_search_keyword,'') is null or
		op2.emp_name ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op2.emp_name)||'%' OR
		op2.mobile ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op2.mobile)||'%' OR
		op2.orgempcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op2.orgempcode)||'%' OR
		op2.cjcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op2.cjcode)||'%'
	)
	--END
	  --SIDDHARTH BANSAL 01/08/2024
		AND (NULLIF(p_ou_ids, '') is null or 
			EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op2.assigned_ou_ids, ''), COALESCE(NULLIF(op2.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op2.assigned_ou_ids, ''), COALESCE(NULLIF(op2.geofencingid::TEXT, ''), '0')), ','))
			)
			 )
		--END
	  --SIDDHARTH BANSAL 10/02/2025
		AND (
		COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
		OR EXISTS (
			SELECT 1
			FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(op2.post_offered)), ',')) AS input_designation
			WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(op2.post_offered), ''), ''), ','))
					)
		)

		AND (
		COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
		OR EXISTS (
			SELECT 1
			FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(op2.posting_department)), ',')) AS input_department
			WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(op2.posting_department), ''), ''), ','))
					)
		)
		AND (NULLIF(p_unitparametername, '') is null or
			 EXISTS
			(
				SELECT 1
				FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(op2.assigned_ou_ids, ''), COALESCE(NULLIF(op2.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
				WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op2.assigned_ou_ids, ''), COALESCE(NULLIF(op2.geofencingid::TEXT, ''), '0')), ','))
			)
			 )
		--end
	  -- AND COALESCE(op2.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op2.geofencingid, 0) ELSE p_geofenceid END -- SIDDHARTH BANSAL 23.04.2024
	  where (op2.emp_code=case when p_empcode=-9999 then op2.emp_code else p_empcode end 
			or
			nullif(trim(op2.pancard),'')=case when p_empcode=-9999 then nullif(trim(op2.pancard),'')  else v_pancard end 
			)
	    and coalesce(tbl_monthlysalary.istaxapplicable,'1')='1' and
	  (
	  (
		  (
			to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_startdate  and v_enddate	 
			or
				(
				to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy')
				between v_advancestartdate  and v_advanceenddate		 
				and mprmonth=4 and mpryear=v_year1
				 )
			)
		  and tbl_monthlysalary.attendancemode<>'Ledger'
	   )
		or(to_date(left(tbl_monthlysalary.hrgeneratedon,11),'dd Mon yyyy') between v_advancestartdate  and v_finyearenddate  and tbl_monthlysalary.attendancemode='Ledger')
 
	   )
	  	  	and not(mprmonth=4 and mpryear=v_year2)
		and coalesce(is_rejected,'0')<>'1'
	  

			)tbl_monthlysalary
inner join openappointments op on tbl_monthlysalary.emp_code=op.emp_code and op.appointment_status_id<>13
and op.customeraccountid=coalesce(nullif(nullif(p_customeraccountid,''),'-9999')::bigint,op.customeraccountid)::bigint
 --SIDDHARTH BANSAL 31/03/2025
	AND
	(
		op.emp_name ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op.emp_name)||'%' OR
		op.mobile ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op.mobile)||'%' OR
		op.orgempcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op.orgempcode)||'%' OR
		op.cjcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), op.cjcode)||'%'
	)
	--END
-- AND COALESCE(op.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(op.geofencingid, 0) ELSE p_geofenceid END -- SIDDHARTH BANSAL 23.04.2024
 --SIDDHARTH BANSAL 01/08/2024
	AND EXISTS
		(
			SELECT 1
			FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
			WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
		)
	--END
	 --SIDDHARTH BANSAL 11/02/2025
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
 where (op.emp_code=case when p_empcode=-9999 then op.emp_code else p_empcode end 
			or
			nullif(trim(op.pancard),'')=case when p_empcode=-9999 then nullif(trim(op.pancard),'')  else v_pancard end 
			)
	and op.recordsource= case when p_tptype='TP' then 'HUBTPCRM' else nullif(op.recordsource,'HUBTPCRM') end			
and op.dateofjoining<=v_finyearenddate and (op.dateofrelieveing is null or op.dateofrelieveing>=v_finyearstartdate);

Raise Notice 'v_currentmonthpayoutdone=%',v_currentmonthpayoutdone;
if v_mon1>=4 and v_year1=extract (year from current_date) then
 for i in v_mon1+(case when v_currentmonthpayoutdone='Y' then 1 else 0 end)..12
 loop
 
 insert into tmp_tblproj
 select lastempcode,emp_code, emp_name,dateofbirth,mobile,nullif(trim(pancard),''),cjcode tpcode,orgempcode, assignedous,mprmonth, grossearning+coalesce(mealvoucher,0) grossearning,otherdeductions,grossdeduction,otherledgerarears,otherledgerdeductions,fixedallowancestotal,gross,tds,atds,paiddays,voucher_amount,paystatus,jobtype
from (
select openappointments.emp_code lastempcode,openappointments.emp_code, openappointments.emp_name,openappointments.dateofbirth,openappointments.mobile,nullif(trim(openappointments.pancard),'') pancard,i mprmonth,case when openappointments.left_flag='Y' then 0 else gross end grossearning,case when openappointments.left_flag='Y' then 0 else deduction_amount end otherdeductions,0 grossdeduction,0 otherledgerarears,0 otherledgerdeductions,case when openappointments.left_flag='Y' then 0 else gross end fixedallowancestotal,case when openappointments.left_flag='Y' then 0 else gross end gross,case when openappointments.left_flag='Y' then 0 else v_remainingtdspermonth end tds,case when openappointments.left_flag='Y' then 0 else v_remainingtdspermonth end atds	
,0 paiddays
,0 voucher_amount
,'Projection' paystatus
,row_number()over(partition by coalesce(nullif(trim(openappointments.pancard),''),openappointments.emp_code::text) order by openappointments.emp_id desc) rn
,openappointments.cjcode
,openappointments.jobtype
,openappointments.orgempcode,(select string_agg(ton.org_unit_name,', ') 
                              from public.tbl_org_unit_geofencing ton 
                              inner join (select * from string_to_table(openappointments.assigned_ou_ids,',')   as t) t1
                              on t1.t::int=ton.id
                             ) as assignedous
,mealvoucher	
from openappointments inner join empsalaryregister
on openappointments.emp_id=empsalaryregister.appointment_id
and openappointments.converted='Y' 
and openappointments.appointment_status_id<>13
and openappointments.customeraccountid=coalesce(nullif(nullif(p_customeraccountid,''),'-9999')::bigint,openappointments.customeraccountid)::bigint
--SIDDHARTH BANSAL 31/03/2025
AND
(
	openappointments.emp_name ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.emp_name)||'%' OR
	openappointments.mobile ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.mobile)||'%' OR
	openappointments.orgempcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.orgempcode)||'%' OR
	openappointments.cjcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.cjcode)||'%'
)
--END
-- AND COALESCE(openappointments.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(openappointments.geofencingid, 0) ELSE p_geofenceid END -- SIDDHARTH BANSAL 23.04.2024
--SIDDHARTH BANSAL 01/08/2024
AND EXISTS
(
	SELECT 1
	FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
	WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0')), ','))
)
--END
--SIDDHARTH BANSAL 11/02/2025
AND (
COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
OR EXISTS (
	SELECT 1
	FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(openappointments.post_offered)), ',')) AS input_designation
	WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(openappointments.post_offered), ''), ''), ','))
			)
)

AND (
COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
OR EXISTS (
	SELECT 1
	FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(openappointments.posting_department)), ',')) AS input_department
	WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(openappointments.posting_department), ''), ''), ','))
			)
)
AND EXISTS
	(
		SELECT 1
		FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
		WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0')), ','))
	)
--end
and empsalaryregister.isactive='1'
and openappointments.recordsource= case when p_tptype='TP' then 'HUBTPCRM' else nullif(openappointments.recordsource,'HUBTPCRM') end	
and openappointments.dateofjoining<=v_finyearenddate and (openappointments.dateofrelieveing is null or openappointments.dateofrelieveing>=v_finyearstartdate)
left join (
select candidate_id,salaryid,sum(deduction_amount) deduction_amount
	from public.trn_candidate_otherduction
	where deduction_frequency<>'Monthly'
	and includedinctc='Y'
	and isvariable='N'
	and active='Y'
	and deduction_id<>10
	group by candidate_id,salaryid
) tmdeductions
on empsalaryregister.id=tmdeductions.salaryid
		
left join (
select candidate_id,salaryid,sum(deduction_amount) mealvoucher
	from public.trn_candidate_otherduction
	where active='Y'
	and deduction_id=134
	group by candidate_id,salaryid
) tmpvouchers
on empsalaryregister.id=tmpvouchers.salaryid	
--inner join (select distinct lastempcode from tmp_tblproj) t2 on openappointments.emp_code=t2.lastempcode
where  (emp_code=case when p_empcode=-9999 then emp_code else p_empcode end 
			or
			nullif(trim(pancard),'')=case when p_empcode=-9999 then nullif(trim(pancard),'')  else v_pancard end 
)
)tmp where rn=1
;
 end loop;
end if;
if v_mon1 between 4 and 12 then
	v_mon2:=1;
else
	if v_currentmonthpayoutdone='N' then
		v_mon2:=v_mon1;
	else
		v_mon2:=greatest(v_mon1+1,0);
	end if;
end if;

if v_year2=extract (year from current_date) and extract (month from current_date) in (1,2,3)
	or v_year1=extract (year from current_date) and extract (month from current_date) between 4 and 12 then

  for i in v_mon2..3
 loop
 insert into tmp_tblproj
  select lastempcode,emp_code, emp_name,dateofbirth,mobile,nullif(trim(pancard),'') pancard,cjcode tpcode,orgempcode, assignedous,mprmonth, grossearning+coalesce(mealvoucher,0) grossearning,otherdeductions,grossdeduction,otherledgerarears,otherledgerdeductions,fixedallowancestotal,gross,tds,atds,paiddays,voucher_amount,paystatus,jobtype
from (
select openappointments.emp_code lastempcode,openappointments.emp_code, openappointments.emp_name,openappointments.dateofbirth,openappointments.mobile,nullif(trim(openappointments.pancard),'') pancard,i mprmonth,case when openappointments.left_flag='Y' then 0 else gross end grossearning,case when openappointments.left_flag='Y' then 0 else deduction_amount end otherdeductions,0 grossdeduction,0 otherledgerarears,0 otherledgerdeductions,case when openappointments.left_flag='Y' then 0 else gross end fixedallowancestotal,case when openappointments.left_flag='Y' then 0 else gross end gross,case when openappointments.left_flag='Y' then 0 else v_remainingtdspermonth end tds,case when openappointments.left_flag='Y' then 0 else v_remainingtdspermonth end atds	
,0 paiddays
,0 voucher_amount
,'Projection' paystatus
,row_number()over(partition by coalesce(nullif(trim(openappointments.pancard),''),openappointments.emp_code::text) order by openappointments.emp_id desc) rn
,openappointments.cjcode
,openappointments.jobtype
,openappointments.orgempcode,
(select string_agg(ton.org_unit_name,', ') 
from public.tbl_org_unit_geofencing ton 
inner join (select * from string_to_table(openappointments.assigned_ou_ids,',')   as t) t1
on t1.t::int=ton.id
) as assignedous
,mealvoucher
from openappointments inner join empsalaryregister
on openappointments.emp_id=empsalaryregister.appointment_id
and openappointments.converted='Y' 
and openappointments.appointment_status_id<>13
and openappointments.customeraccountid=coalesce(nullif(nullif(p_customeraccountid,''),'-9999')::bigint,openappointments.customeraccountid)::bigint
--SIDDHARTH BANSAL 31/03/2025
AND
(nullif(p_search_keyword,'') is null or
	openappointments.emp_name ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.emp_name)||'%' OR
	openappointments.mobile ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.mobile)||'%' OR
	openappointments.orgempcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.orgempcode)||'%' OR
	openappointments.cjcode ILIKE '%'||COALESCE(nullif(p_search_keyword,''), openappointments.cjcode)||'%'
)
-- AND COALESCE(openappointments.geofencingid, 0) = CASE WHEN p_geofenceid=0 THEN COALESCE(openappointments.geofencingid, 0) ELSE p_geofenceid END -- SIDDHARTH BANSAL 23.04.2024
	--SIDDHARTH BANSAL 01/08/2024
AND (NULLIF(p_ou_ids, '') is null
	 or 
	 EXISTS
	(
		SELECT 1
		FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
		WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0')), ','))
	)
	 )
--END
--SIDDHARTH BANSAL 11/02/2025
AND (
COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
OR EXISTS (
	SELECT 1
	FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(openappointments.post_offered)), ',')) AS input_designation
	WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(openappointments.post_offered), ''), ''), ','))
			)
)

AND (
COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
OR EXISTS (
	SELECT 1
	FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(openappointments.posting_department)), ',')) AS input_department
	WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(openappointments.posting_department), ''), ''), ','))
			)
)
AND EXISTS
	(
		SELECT 1
		FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
		WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(openappointments.assigned_ou_ids, ''), COALESCE(NULLIF(openappointments.geofencingid::TEXT, ''), '0')), ','))
	)
--end
and empsalaryregister.isactive='1'
and openappointments.recordsource= case when p_tptype='TP' then 'HUBTPCRM' else nullif(openappointments.recordsource,'HUBTPCRM') end
and openappointments.dateofjoining<=v_finyearenddate and (openappointments.dateofrelieveing is null or openappointments.dateofrelieveing>=v_finyearstartdate)
left join (
select candidate_id,salaryid,sum(deduction_amount) deduction_amount
	from public.trn_candidate_otherduction
	where deduction_frequency<>'Monthly'
	and includedinctc='Y'
	and isvariable='N'
	and active='Y'
	and deduction_id<>10
	group by candidate_id,salaryid
) tmdeductions
on empsalaryregister.id=tmdeductions.salaryid
	
left join (
select candidate_id,salaryid,sum(deduction_amount) mealvoucher
	from public.trn_candidate_otherduction
	where active='Y'
	and deduction_id=134
	group by candidate_id,salaryid
) tmpvouchers
on empsalaryregister.id=tmpvouchers.salaryid	
--inner join (select distinct lastempcode from tmp_tblproj) t2 on openappointments.emp_code=t2.lastempcode
where  (emp_code=case when p_empcode=-9999 then emp_code else p_empcode end 
			or
			nullif(trim(pancard),'')=case when p_empcode=-9999 then nullif(trim(pancard),'')  else v_pancard end 
		)
)tmp where rn=1;
 end loop;
 end if;
 /****************************************************************
 open v_rfc for
select * from tmp_tblproj;
return v_rfc;
 ****************************************************************/
open v_rfc for
select 
(string_agg(paystatus,',' order by paystatus)) paystatus,
max(pancard) pancard,
max(tmp_tblproj.emp_code) as emp_code,max(emp_name)||case when v_leftflag='Y' then '(Relieved on :'||v_dateofrelieveing::text||')' else '' end as emp_name, 'Gross Earning'|| '<br>Gross Deductions'|| '<br>Other Deductions'|| '<br>Other Ledger Arrears'|| '<br>Other Ledger Deductions'|| '<br>Gross'|| '<br>Net Pay'|| '<br>TDS'|| '<br>Paid Days'|| '<br>Voucher' as fields,
'<span style="color: '||case when (string_agg(case when mprmonth=4 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=4 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=4 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=4 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=4 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=4 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=4 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=4 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=4 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=4 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=4 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=4 then round(voucher_amount) else 0 end)::text as apr,
'<span style="color: '||case when (string_agg(case when mprmonth=5 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=5 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=5 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=5 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=5 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=5 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=5 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=5 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=5 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=5 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=5 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=5 then round(voucher_amount) else 0 end)::text as may,
'<span style="color: '||case when (string_agg(case when mprmonth=6 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=6 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=6 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=6 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=6 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=6 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=6 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=6 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=6 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=6 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=6 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=6 then round(voucher_amount) else 0 end)::text as jun,
'<span style="color: '||case when (string_agg(case when mprmonth=7 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=7 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=7 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=7 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=7 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=7 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=7 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=7 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=7 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=7 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=7 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=7 then round(voucher_amount) else 0 end)::text as jul,
'<span style="color: '||case when (string_agg(case when mprmonth=8 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=8 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=8 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=8 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=8 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=8 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=8 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=8 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=8 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=8 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=8 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=8 then round(voucher_amount) else 0 end)::text as aug,
'<span style="color: '||case when (string_agg(case when mprmonth=9 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=9 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=9 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=9 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=9 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=9 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=9 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=9 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=9 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=9 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=9 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=9 then round(voucher_amount) else 0 end)::text as sep,
'<span style="color: '||case when (string_agg(case when mprmonth=10 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=10 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=10 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=10 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=10 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=10 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=10 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=10 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=10 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=10 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=10 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=10 then round(voucher_amount) else 0 end)::text as oct,
'<span style="color: '||case when (string_agg(case when mprmonth=11 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=11 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=11 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=11 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=11 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=11 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=11 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=11 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=11 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=11 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=11 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=11 then round(voucher_amount) else 0 end)::text as nov,
'<span style="color: '||case when (string_agg(case when mprmonth=12 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=12 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=12 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=12 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=12 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=12 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=12 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=12 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=12 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=12 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=12 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=12 then round(voucher_amount) else 0 end)::text as dec,
'<span style="color: '||case when (string_agg(case when mprmonth=1 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=1 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=1 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=1 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=1 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=1 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=1 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=1 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=1 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=1 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=1 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=1 then round(voucher_amount) else 0 end)::text as jan,
'<span style="color: '||case when (string_agg(case when mprmonth=2 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=2 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=2 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=2 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=2 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=2 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=2 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=2 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=2 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=2 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=2 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=2 then round(voucher_amount) else 0 end)::text as feb,
'<span style="color: '||case when (string_agg(case when mprmonth=3 then paystatus else null end,',' order by paystatus)) ilike '%Hold%' then '#ff4000' when (string_agg(case when mprmonth=3 then paystatus else null end,',' order by paystatus)) ilike '%Projection%' then '#d938ce' else '#38d938' end||';">'||round(sum(case when mprmonth=3 then (grossearning) else 0 end))::text || '</span>'|| '<br>'||round(sum(case when mprmonth=3 then (grossdeduction) else 0 end))::text || '<br>'||round(sum(case when mprmonth=3 then (otherdeductions) else 0 end))::text || '<br>'||round(sum(case when mprmonth=3 then (otherledgerarears) else 0 end))::text || '<br>'||sum(case when mprmonth=3 then round(otherledgerdeductions) else 0 end)::text || '<br>'||sum(case when mprmonth=3 then round(fixedallowancestotal) else 0 end)::text || '<br>'||sum(case when mprmonth=3 then round(netpay) else 0 end)::text || '<br>'||sum(case when mprmonth=3 then round(tds) else 0 end)::text|| '<br>'||sum(case when mprmonth=3 then round(paiddays) else 0 end)::text|| '<br>'||sum(case when mprmonth=3 then round(voucher_amount) else 0 end)::text as mar,
round(coalesce(sum(grossearning),0)-coalesce(sum(otherdeductions),0))::text || '<br>'||round(coalesce(sum(grossdeduction),0))::text || '<br>'||round(coalesce(sum( otherdeductions),0))::text || '<br>'||round(coalesce(sum(otherledgerarears),0))::text || '<br>'||round(coalesce(sum(otherledgerdeductions),0))::text || '<br>'||round(coalesce(sum(fixedallowancestotal),0))::text || '<br>'||round(coalesce(sum(netpay),0))::text || '<br>'||round(coalesce(sum(tds),0))::text|| '<br>'||round(coalesce(sum(voucher_amount),0))::text as TotalGrossEarning
,sum(grossearning) grossearning,sum(tds) tds
,max(jobtype) jobtype,
max(tpcode) tpcode
,max(orgempcode) orgempcode,
max(assignedous) assignedous,
max(mobile) mobile,max(to_char(dateofbirth, 'DD/MM/YYYY')) dateofbirth,
--SIDDHARTH BANSAL 23/12/2024
round(sum(case when mprmonth = 1 then grossearning else 0 end))::text as jan_grossearning,
round(sum(case when mprmonth = 2 then grossearning else 0 end))::text as feb_grossearning,
round(sum(case when mprmonth = 3 then grossearning else 0 end))::text as mar_grossearning,
round(sum(case when mprmonth = 4 then grossearning else 0 end))::text as apr_grossearning,
round(sum(case when mprmonth = 5 then grossearning else 0 end))::text as may_grossearning,
round(sum(case when mprmonth = 6 then grossearning else 0 end))::text as jun_grossearning,
round(sum(case when mprmonth = 7 then grossearning else 0 end))::text as jul_grossearning,
round(sum(case when mprmonth = 8 then grossearning else 0 end))::text as aug_grossearning,
round(sum(case when mprmonth = 9 then grossearning else 0 end))::text as sep_grossearning,
round(sum(case when mprmonth = 10 then grossearning else 0 end))::text as oct_grossearning,
round(sum(case when mprmonth = 11 then grossearning else 0 end))::text as nov_grossearning,
round(sum(case when mprmonth = 12 then grossearning else 0 end))::text as dec_grossearning,
round(sum(case when mprmonth in (4, 5, 6) then grossearning else 0 end))::text as Q1_grossearning, -- April, May, June
round(sum(case when mprmonth in (7, 8, 9) then grossearning else 0 end))::text as Q2_grossearning, -- July, August, September
round(sum(case when mprmonth in (10, 11, 12) then grossearning else 0 end))::text as Q3_grossearning, -- October, November, December
round(sum(case when mprmonth in (1, 2, 3) then grossearning else 0 end))::text as Q4_grossearning -- January, February, March
,--SIDDHARTH BANSAL 21/04/2025 1.5
max (CASE 
WHEN er.emp_code IS NULL THEN 'Pending'
ELSE 'Submitted'
END )AS regime_status,max(er.regime_tye) regime_tye,
max(TO_CHAR(COALESCE(er.modifiedon, er.createdon) + INTERVAL '5 HOURS 30 MINUTE', 'DD/MM/YYYY')) AS createdon
--END

																  
																  
																   
																  
																  
																   
																   
																	
																  
																  
																 
from tmp_tblproj	
left join employee_regime er ON er.emp_code = tmp_tblproj.emp_code and er.financial_year = p_financialyear and er.isactive = '1' -- CHANGE 1.5
and er.emp_code=(select max (tt.emp_code) from tmp_tblproj tt)
 group by coalesce(pancard,tmp_tblproj.emp_code::text)--,er.emp_code,er.regime_tye,er.modifiedon, er.createdon
 ; -- 1.5
 
 return v_rfc;
 end;
 
$BODY$;

ALTER FUNCTION public.uspmonthwisesalarycoponents(text, bigint, double precision, character varying, text, integer, character varying, text, text, text, text)
    OWNER TO payrollingdb;

