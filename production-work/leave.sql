-- FUNCTION: public.get_leave_balance_by_account(character varying, character varying, character varying, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.get_leave_balance_by_account(character varying, character varying, character varying, character varying, character varying);

CREATE OR REPLACE FUNCTION public.get_leave_balance_by_account(
	p_account_id character varying DEFAULT ''::character varying,
	p_att_month character varying DEFAULT ''::character varying,
	p_att_year character varying DEFAULT ''::character varying,
	p_emp_id character varying DEFAULT ''::character varying,
	p_att_processdt character varying DEFAULT ''::character varying)
    RETURNS TABLE(leave_bank_id bigint, emp_id bigint, template_id character varying, account_id character varying, template_name character varying, template_txt character varying, prev_bal character varying, leave_taken character varying, leave_taken_tot character varying, balance_txt character varying, balance_tot character varying, comp_off_txt character varying, leave_mst character varying) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
declare 
/*
 This function created by vinod dated. 27.12.2023
 
 select * from get_leave_balance_by_account(
 	p_account_id =>'653',
	p_att_month =>'12',
	p_att_year =>'2023',
	p_att_processdt=>'18/10/2023'::text
 );
 
 for account wise calculate employee leave balance
 
  Dated. 02.1.2025
 
 Dated. 02.1.2025
 Include HL in attendance_type for manage Half Days Leave
 
  Dated. 06.02.2024
 
 Add Maternity Leave and Other Direct Leave Type
 
 Dated. 08.07.2027 Vinod
 
 Add Maternity Leave and Other Direct Leave Type
 
*/

v_mst_leaves text;

v_typecode_arr_fullday TEXT[];
v_typecode_arr_halfday TEXT[];

v_eomonth_month_year date;
v_eomonth_current_date date;
v_p_att_processdt date:=NULL;
begin

			v_eomonth_month_year:= (date_trunc('month', make_date(p_att_year::int, p_att_month::int, 1))+ interval '1 month - 1 day')::date;
			
			-- added for fullday and helf day type dated. 13.05.2025
			SELECT array_agg(leavetypecode)
			INTO v_typecode_arr_fullday
			FROM mst_tp_leavetype
			WHERE status = '1' AND (type_account_id = p_account_id::bigint OR type_account_id = 0) AND is_halfday_leave='N';
	
	
			SELECT array_agg(leavetypecode)
			INTO v_typecode_arr_halfday
			FROM mst_tp_leavetype
			WHERE status = '1' AND 
			(type_account_id = p_account_id::bigint OR type_account_id = 0) AND is_halfday_leave='Y';
			
			-- end
		v_p_att_processdt:= (CASE WHEN COALESCE(trim(p_att_processdt),'')='' THEN NULL ELSE to_date(p_att_processdt,'dd-mm-yyyy') END );
		
 
	 select array_to_json(array_agg(row_to_json(t))) into v_mst_leaves from (
		select leavetypecode,leavetypename, leave_unit,leave_ctg 
		from public.mst_tp_leavetype where status='1'
		and is_enable='Y' and type_account_id in (p_account_id::bigint  , 0)
		--and leave_ctg='Unpaid'
		) t ;
	 
      return query 					
		select  rowid leave_bank_id  ,a.emp_id  , a.template_id::varchar, a.account_id::varchar,
		a.template_name,a.template_txt::varchar, tot_credited::varchar prev_bal, b.leave_taken_txt::varchar , 
		leave_taken2::varchar leave_taken_tot, 	
		
				((select array_to_json(array_agg(row_to_json(t)))::varchar from
				(
					select t1.typecode,t1.typename,t1.effective_min_paid_days ,
										(t1.prev_bal::numeric(18,2)- COALESCE(t2.leave_taken::numeric(18,2),0.0))::varchar prev_bal,'N' is_spacial
					from (	select * from jsonb_populate_recordset(null::record,tot_credited::jsonb) 
					as ( typecode varchar,typename varchar,	prev_bal  varchar,effective_min_paid_days varchar) ) as t1
					left join
					( select * from jsonb_populate_recordset(null::record,b.leave_taken_txt::jsonb) 
					as ( typecode varchar,	leave_taken  varchar) 
					) as t2 on t1.typecode=t2.typecode ) as t)::jsonb 
					|| (
					
					CASE WHEN tbl_special_leave.special_leave_txt IS NOT NULL THEN 
					tbl_special_leave.special_leave_txt ELSE '[]' END 
					
					)::jsonb
		
		)::varchar balance_txt, 
		(select sum(t.prev_bal)::varchar from
				(
					select t1.typecode,t1.typename,
					-- CASE WHEN p_account_id='2719' THEN 0.0 else -- now need to show the leave
										(t1.prev_bal::numeric(18,2)- COALESCE(t2.leave_taken::numeric(18,2),0.0)) /* END */  prev_bal
										
										-- (t1.prev_bal::numeric(18,2)- COALESCE(t2.leave_taken::numeric(18,2),0.0)) prev_bal
					from (	select * from jsonb_populate_recordset(null::record,tot_credited::jsonb) 
					as ( typecode varchar,typename varchar,	prev_bal  varchar,effective_min_paid_days varchar) ) as t1
					left join
					( select * from jsonb_populate_recordset(null::record,b.leave_taken_txt::jsonb) 
					as ( typecode varchar,	leave_taken  varchar) 
					) as t2 on t1.typecode=t2.typecode ) as t) ::varchar balance_tot, 
					tbl_comp_off.compoff_text::varchar comp_off_txt,v_mst_leaves::varchar leave_mst
					
					
	 
	 
		from tbl_employee_leavebank a 
		
		
		-- current_month Taken
		left join		
		(	
			select  t.emp_id,customeraccountid,leavebankid , 
			('['||STRING_AGG(json_build_object('typecode',leavetype,'leave_taken',leave_taken1)::varchar,',')||']')::varchar leave_taken_txt 
			,sum(leave_taken1::numeric(18,2))::varchar leave_taken2 from 
			(select tbl_open.emp_id,a1.customeraccountid,a1.leavebankid,a1.leavetype,
			sum(

				CASE WHEN leavetype = any (v_typecode_arr_fullday)
				AND attendance_type='LL' THEN 1.0	
				WHEN leavetype = any (v_typecode_arr_halfday)
				AND attendance_type='LL' THEN 2.0 
				WHEN leavetype = any (v_typecode_arr_fullday)
				AND attendance_type IN ('HD','HL') THEN 0.5  
				WHEN leavetype = any (v_typecode_arr_halfday)
				AND attendance_type IN ('HD','HL')  THEN 1.0
				ELSE 0.0 END
				
				
			   )::varchar leave_taken1
			from tbl_monthly_attendance a1
			inner join openappointments tbl_open on a1.emp_code= tbl_open.emp_code AND a1.customeraccountid=tbl_open.customeraccountid
			where  a1.customeraccountid=p_account_id::bigint and a1.isactive='1' 
			 and att_date between make_date(p_att_year::int,p_att_month::int,1)					
			-- and eomonth(make_date(p_att_year::int,p_att_month::int,1) )  -- commnt on 08.09.2025 by vinod
			 AND (
						CASE
							WHEN (p_att_year::int = EXTRACT(YEAR FROM CURRENT_DATE)::int
								  AND p_att_month::int = EXTRACT(MONTH FROM CURRENT_DATE)::int)
							THEN (make_date(p_att_year::int, p_att_month::int, 1) + INTERVAL '6 months')::date
							ELSE v_eomonth_month_year
						END
					)
			
			and leavetype is not null AND (v_p_att_processdt IS NULL OR a1.att_date <> v_p_att_processdt)
			group by tbl_open.emp_id,a1.customeraccountid,leavebankid,
			leavetype ) t group by t.emp_id,customeraccountid,leavebankid
					

		) b on a.rowid= b.leavebankid and a.emp_id=b.emp_id  and a.status='1'
		-- Previous Month Taken
		
		/*
			SELECT date_trunc('month', '2024-05-06'::date)::date,eomonth('2024-05-06'::date)+1,
			EXTRACT(day FROM DATE '2024-05-06') ;
		*/
		
		left join 
		(
				select a.emp_id,a.customeraccountid,
				a.dateofjoining,((trim(trim(b.template_txt,']'),
				'[')::jsonb->>'leave_details')::jsonb->>'leave_type') mst_leavetype, 
				c.intial_leave_bal_txt,
				(
				select array_to_json(array_agg(row_to_json(t))) from
				(
				
					select  a0.typecode, a0.typename, a0.effective_min_paid_days,	(
															CASE WHEN a0.accumulate='Monthly' AND is_carry_forward='Y' 
															then COALESCE(nullif(b.opening_bal,''),'0')::numeric(10,2)+(a0.days::numeric(18,2) * 				   
															round(
															abs(make_date(p_att_year::int,p_att_month::int,1)::Date - 
															/* OLD CODE BACKUP:
															(CASE WHEN b.periodfrom::date >=date_trunc('month', dateofjoining ::date) ::date
															THEN b.periodfrom::date ELSE 
															date_trunc('month', dateofjoining ::date) ::date
															END )
															*/
															(CASE WHEN b.periodfrom::date >=
																/* START: NEW LOGIC FOR DOJ CUTOFF */
																(CASE 
																	WHEN COALESCE(tb.is_joining_cutoff_days_applied_yn, 'N') = 'Y' THEN
																		(CASE 
																			WHEN EXTRACT(DAY FROM a.dateofjoining::date) >= COALESCE(NULLIF(tb.is_joining_cutoff_days_applied_days, '')::integer, 1)
																			THEN (date_trunc('month', a.dateofjoining::date) + INTERVAL '1 month')::date
																			ELSE date_trunc('month', a.dateofjoining::date)::date
																		END)
																	ELSE 
																		/* PREVIOUS LOGIC - KEPT FOR BACKWARD COMPATIBILITY */
																		date_trunc('month', a.dateofjoining::date)::date
																END)
																/* END: NEW LOGIC FOR DOJ CUTOFF */
															THEN b.periodfrom::date ELSE 
																/* START: NEW LOGIC FOR DOJ CUTOFF */
																(CASE 
																	WHEN COALESCE(tb.is_joining_cutoff_days_applied_yn, 'N') = 'Y' THEN
																		(CASE 
																			WHEN EXTRACT(DAY FROM a.dateofjoining::date) >= COALESCE(NULLIF(tb.is_joining_cutoff_days_applied_days, '')::integer, 1)
																			THEN (date_trunc('month', a.dateofjoining::date) + INTERVAL '1 month')::date
																			ELSE date_trunc('month', a.dateofjoining::date)::date
																		END)
																	ELSE 
																		/* PREVIOUS LOGIC - KEPT FOR BACKWARD COMPATIBILITY */
																		date_trunc('month', a.dateofjoining::date)::date
																END)
																/* END: NEW LOGIC FOR DOJ CUTOFF */
															END ) :: date)/(365.25/12),0) 						   

															)
															WHEN a0.accumulate='Quarterly' AND is_carry_forward='Y' 
															then COALESCE(nullif(b.opening_bal,''),'0')::numeric(10,2)+(a0.days::numeric(18,2) * 				   
															round(
															abs(make_date(p_att_year::int,p_att_month::int,1)::Date - 
															/* OLD CODE BACKUP:
															(CASE WHEN b.periodfrom::date >=date_trunc('month', dateofjoining ::date) ::date
															THEN b.periodfrom::date ELSE 
															date_trunc('month', dateofjoining ::date) ::date
															END )
															*/
															(CASE WHEN b.periodfrom::date >=
																/* START: NEW LOGIC FOR DOJ CUTOFF */
																(CASE 
																	WHEN COALESCE(tb.is_joining_cutoff_days_applied_yn, 'N') = 'Y' THEN
																		(CASE 
																			WHEN EXTRACT(DAY FROM a.dateofjoining::date) >= COALESCE(NULLIF(tb.is_joining_cutoff_days_applied_days, '')::integer, 1)
																			THEN (date_trunc('month', a.dateofjoining::date) + INTERVAL '1 month')::date
																			ELSE date_trunc('month', a.dateofjoining::date)::date
																		END)
																	ELSE 
																		/* PREVIOUS LOGIC - KEPT FOR BACKWARD COMPATIBILITY */
																		date_trunc('month', a.dateofjoining::date)::date
																END)
																/* END: NEW LOGIC FOR DOJ CUTOFF */
															THEN b.periodfrom::date ELSE 
																/* START: NEW LOGIC FOR DOJ CUTOFF */
																(CASE 
																	WHEN COALESCE(tb.is_joining_cutoff_days_applied_yn, 'N') = 'Y' THEN
																		(CASE 
																			WHEN EXTRACT(DAY FROM a.dateofjoining::date) >= COALESCE(NULLIF(tb.is_joining_cutoff_days_applied_days, '')::integer, 1)
																			THEN (date_trunc('month', a.dateofjoining::date) + INTERVAL '1 month')::date
																			ELSE date_trunc('month', a.dateofjoining::date)::date
																		END)
																	ELSE 
																		/* PREVIOUS LOGIC - KEPT FOR BACKWARD COMPATIBILITY */
																		date_trunc('month', a.dateofjoining::date)::date
																END)
																/* END: NEW LOGIC FOR DOJ CUTOFF */
															END ) :: date)/(365.25/4),0) 						   

															)
				   
															WHEN a0.accumulate='Monthly' AND is_carry_forward='N' then nullif(days,'')::numeric(18,2) 
															WHEN a0.accumulate='Quarterly' AND is_carry_forward='N' THEN COALESCE(nullif(b.opening_bal,''),'0')::numeric(10,1)
															WHEN a0.accumulate='Yearly' THEN COALESCE(nullif(b.opening_bal,''),'0')::numeric(10,1)
															WHEN a0.accumulate='OneTime' THEN COALESCE(nullif(b.opening_bal,''),'0')::numeric(10,1)
															END
						
			
 						- COALESCE( CASE WHEN  a0.accumulate='Monthly' AND is_carry_forward='N' then 0.0
						 ELSE tbl_prev_taken.leave_taken END ,0.0)
						 -- COALESCE(tbl_prev_taken.leave_taken,0)

													)::varchar prev_bal
					from
					(
							select * from jsonb_populate_recordset(null::record,((trim(trim(b.template_txt,']'),
							'[')::jsonb->>'leave_details')::jsonb->>'leave_type')::jsonb) 
							as ( days varchar,	typecode  varchar,	typename  varchar,	
							accumulate varchar,	maximum_limit varchar,	is_carry_forward varchar,effective_min_paid_days varchar)
					) a0 inner join  
					(
							select * from jsonb_populate_recordset(null::record,c.intial_leave_bal_txt::jsonb) 
							as ( opening_bal varchar,	typecode  varchar,	typename  varchar,	
							periodfrom varchar,		periodto varchar)
					) b on b.typecode= a0.typecode
					left join
						(
							select tbl_open.emp_id,a1.customeraccountid,a1.leavebankid,a1.leavetype typecode,
							sum(

								CASE WHEN leavetype = any (v_typecode_arr_fullday)
								AND attendance_type='LL' THEN 1.0	
								WHEN leavetype = any (v_typecode_arr_halfday)
								AND attendance_type='LL' THEN 2.0 
								WHEN leavetype = any (v_typecode_arr_fullday)
								AND attendance_type IN ('HD','HL') THEN 0.5  
								WHEN leavetype = any (v_typecode_arr_halfday)
								AND attendance_type IN ('HD','HL')  THEN 1.0
								ELSE 0.0 END
							   
							   )::numeric(18,2) leave_taken
							from tbl_monthly_attendance a1
							inner join openappointments tbl_open on a1.emp_code= tbl_open.emp_code AND tbl_open.customeraccountid=p_account_id::bigint
							where  a1.customeraccountid=p_account_id::bigint and a1.isactive='1' and att_date >= 
							
								(select CASE WHEN ((trim(trim(l.template_txt,']'),'[')::jsonb->>'leave_details')::jsonb->>'leaves_calender')='Financial Year'
								THEN (p_att_year::int - 1)::varchar||'-04-01' ELSE p_att_year||'-01-01' end
								from tbl_employee_leavebank l where rowid=a1.leavebankid and status='1'
								)::date

							and att_date < make_date(p_att_year::int,p_att_month::int,1)  and leavetype is not null
							AND (v_p_att_processdt IS NULL OR a1.att_date <> v_p_att_processdt)
							group by tbl_open.emp_id,a1.customeraccountid,leavebankid,leavetype 
						) tbl_prev_taken on  tbl_prev_taken.typecode= b.typecode 
							and a.emp_id=tbl_prev_taken.emp_id 
					 
					) t 
				
				) tot_credited
				from openappointments a
				inner join tbl_employee_leavebank b on a.emp_id= b.emp_id
				and a.customeraccountid= b.account_id  and b.status='1'
				LEFT JOIN tbl_tpleavebank tb ON tb.template_id = b.template_id::bigint AND tb.status = '1'
				inner join (
				
							SELECT t.rowid, array_to_json(array_agg(j)) intial_leave_bal_txt 
							FROM tbl_employee_leavebank t, jsonb_array_elements(t.intial_leave_bal_txt::jsonb) j
							WHERE make_date(p_att_year::int,p_att_month::int,1)::Date between (j->>'periodfrom')::Date  and (j->>'periodto' )::Date
							and j->>'status'='1' and status='1'  and t.account_id=p_account_id::bigint
							GROUP BY rowid
						) c on c.rowid= b.rowid 
				where a.customeraccountid=p_account_id::bigint AND b.status='1'

		) k on a.emp_id= k.	emp_id
		and k.customeraccountid=a.account_id
		left join (
			
					select a1.emp_id, a1.customeraccountid,
						jsonb_build_object('tot_co_taken',tot_compoff_taken::varchar,
						'leavetypecode',leavetypecode,'leavetypename',leavetypename,
						'is_comp_off_applicable',is_comp_off_applicable ,'per_month_max_comp_off',
						
						-- per_month_max_comp_off 
						
						(CASE WHEN comp_request_mode_entry='application' then coalesce(btl_appl_comp_off.comp_off_bal_in_month,0.0)::varchar else per_month_max_comp_off end )
						
						,'comp_off_applicable_type',comp_off_applicable_type ,'comp_off_applicable_dayname',comp_off_applicable_dayname ,
						'tot_co_bal',
						
						coalesce(
						
						 (CASE WHEN (CASE WHEN comp_request_mode_entry='application' then coalesce(btl_appl_comp_off.comp_off_bal_in_month,0.0) else 	
						coalesce(nullif(per_month_max_comp_off,'')::numeric(18,1),0.0) end ) - tot_compoff_taken < 0.0 					
						
						THEN 0.0 ELSE

						coalesce( (CASE WHEN comp_request_mode_entry='application' then coalesce(btl_appl_comp_off.comp_off_bal_in_month,0.0) else 	
						coalesce(nullif(per_month_max_comp_off,'')::numeric(18,1),0.0) end ),0.0)- tot_compoff_taken 	END ),	0.0 ) ::varchar
						
						/* coalesce(CASE WHEN coalesce(nullif(per_month_max_comp_off,'')::numeric(18,1),0.0)- tot_compoff_taken <0.0 
						THEN 0.0 ELSE coalesce(nullif(per_month_max_comp_off,'')::numeric(18,1),0.0)- tot_compoff_taken END,0.0 ) ::varchar*/
						
						
						) compoff_text
					from
					(
					select tbl_open.emp_id,tbl_open.customeraccountid,
					sum( CASE WHEN attendance_type='LL' AND leavetype ='CO' THEN 1 
					WHEN attendance_type='AA' AND leavetype ='CO'  THEN 0.5
					WHEN attendance_type IN ('HD','HL') AND leavetype ='CO' THEN 0.5 ELSE  0.0 END
					)::numeric(18,2) tot_compoff_taken
					from openappointments tbl_open 
					left join tbl_monthly_attendance a1 on a1.emp_code= tbl_open.emp_code 
					AND a1.customeraccountid= tbl_open.customeraccountid and a1.isactive='1'	
					AND tbl_open.customeraccountid=p_account_id::bigint
			   
					and att_date BETWEEN date_trunc('year',make_date(p_att_year::int,p_att_month::int,1))	and v_eomonth_month_year
					-- and att_date BETWEEN make_date(p_att_year::int,p_att_month::int,1) and eomonth(make_date(p_att_year::int,p_att_month::int,1))
					 AND (v_p_att_processdt IS NULL OR a1.att_date <> v_p_att_processdt)
					where  tbl_open.customeraccountid=p_account_id::bigint 						
					group  by tbl_open.emp_id,tbl_open.customeraccountid
					) a1
					
					/*,
					(
					
					select leavetypecode,leavetypename from 
						mst_tp_leavetype where status='1' 
						and leavetypecode='CO' and type_account_id='0'
						
						) a , 	
						(
						
						select tp_account_id ,is_comp_off_applicable,per_month_max_comp_off,comp_off_applicable_type,comp_off_applicable_dayname,
						leave_credit_count_for_wk, leave_credit_count_for_ho from public.mst_leave_general_settings 
						where tp_account_id= p_account_id::bigint and status='1'
						
						) b */
						
						
						LEFT JOIN  mst_tp_leavetype a ON a.leavetypecode = 'CO'
						AND a.type_account_id = '0'
						AND a.status = '1' 
						LEFT JOIN mst_leave_general_settings b ON b.tp_account_id = p_account_id::BIGINT
						AND b.status = '1'
						
						left join (				
										SELECT	SUM(comp_off_credit_value) AS comp_off_bal_in_month, tbl_compoff_request_application.accountid,	
										tbl_compoff_request_application.emp_id
										FROM tbl_compoff_request_application
										WHERE tbl_compoff_request_application.status = '1'  -- Approved status
										AND accountid = p_account_id::bigint
										-- AND comp_expiry_date::date >= make_date(p_att_year::int,p_att_month::int,1) 
										AND approvedon::date >= date_trunc('year', make_date(p_att_year::int,p_att_month::int,1)) 
										AND coalesce(approvedon,current_date) <= v_eomonth_month_year 
										AND approval_status='Approved'
										GROUP BY tbl_compoff_request_application.accountid,tbl_compoff_request_application. emp_id 
										
							) btl_appl_comp_off 
						on btl_appl_comp_off.emp_id= a1.emp_id
						and btl_appl_comp_off.accountid= a1.customeraccountid

				)tbl_comp_off on  a.emp_id=tbl_comp_off.emp_id	and tbl_comp_off.customeraccountid=a.account_id
		
		left join 	(
						select t .emp_id emp_id_1,t .customeraccountid , 
						('['||STRING_AGG(json_build_object('typecode',leavetypecode,'typename',t.leavetypename, 
						'effective_min_paid_days',null,'init_bal',init_bal::varchar ,'leave_taken', 
						t.leave_taken::varchar ,	'prev_bal',cur_bal ::varchar,'is_spacial','Y'
						)::varchar,',')||']')::varchar  special_leave_txt
						from
						(
						select  tbl_open.emp_id, tbl_open.customeraccountid ,t_gender,	
						tl.leavetypecode ,tl.leavetypename, coalesce(tbl_global.opening_balance, leave_days) init_bal, count(a1.att_date) leave_taken,
						(coalesce(tbl_global.opening_balance, leave_days) - count(a1.att_date) ) cur_bal		
						from openappointments tbl_open  	
						inner join mst_tp_leavetype tl on  tl.type_account_id= tbl_open.customeraccountid
						and  is_enable='Y' 	and leave_days>0 AND  upper(tl.t_gender) in ('B',UPPER(
						left(tbl_open.gender,1)))
						left join ( SELECT tbl_employee_global_leave_opening.emp_id ::bigint g_emp_id,   elem->>'leave_type' AS leave_type,     
								nullif( elem->>'opening_bal' ,'')::numeric(18,2)
								AS opening_balance
								FROM tbl_employee_global_leave_opening,
								jsonb_array_elements(leave_bal_txt::jsonb) AS elem
								WHERE tbl_employee_global_leave_opening.account_id = p_account_id::bigint
								AND tbl_employee_global_leave_opening.status = '1' 
						 ) tbl_global on 	tbl_global.g_emp_id= tbl_open.emp_id
						 AND tbl_global.leave_type= tl.leavetypecode
														
						left join tbl_monthly_attendance a1					
						on a1.leavetype= tl.leavetypecode
						AND a1.emp_code= tbl_open.emp_code and	
						a1.customeraccountid=tbl_open.customeraccountid	and a1.isactive='1'	AND	a1.leavetype is not null AND (v_p_att_processdt IS NULL OR a1.att_date <> v_p_att_processdt)
						AND	a1.leavetype is not null
						WHERE  	tbl_open.customeraccountid=p_account_id::bigint   and 
						tbl_open.emp_id= (CASE WHEN  (p_emp_id='' OR p_emp_id IS NULL) THEN tbl_open.emp_id ELSE p_emp_id::bigint END) 
						 and tl.status='1'
						  -- added for DIC dated and local dummy account
						 AND  (  CASE   WHEN tbl_open.jobtype = 'Third Party'  
						 AND tbl_open.customeraccountid in (3088,6927)  THEN tl.leavetypecode <> 'PT'    
						 ELSE TRUE    END )
						 -- end 
						 group by tbl_open.emp_id,leavetypecode ,tbl_open.customeraccountid,t_gender,leave_days,tbl_global.opening_balance,tl.leavetypename
						
						) t 
						group by t.emp_id,t.customeraccountid		
					) tbl_special_leave on  a.emp_id=tbl_special_leave.emp_id_1	
					and tbl_special_leave.customeraccountid=a.account_id
		
		where a.account_id=p_account_id::bigint AND a.status='1'    
		AND a.emp_id= (CASE WHEN  (p_emp_id='' OR p_emp_id IS NULL) THEN a.emp_id ELSE p_emp_id::bigint END)
		--and b.status='1' 
		;
				  
   
END;
$BODY$;

ALTER FUNCTION public.get_leave_balance_by_account(character varying, character varying, character varying, character varying, character varying)
    OWNER TO payrollingdb;

