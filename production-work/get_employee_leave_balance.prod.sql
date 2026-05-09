-- FUNCTION: public.get_employee_leave_balance(character varying, character varying, character varying, character varying, text, text, text)

-- DROP FUNCTION IF EXISTS public.get_employee_leave_balance(character varying, character varying, character varying, character varying, text, text, text);

CREATE OR REPLACE FUNCTION public.get_employee_leave_balance(
	p_account_id character varying DEFAULT ''::character varying,
	p_emp_id character varying DEFAULT ''::character varying,
	p_geofenceid character varying DEFAULT ''::character varying,
	p_ou_ids character varying DEFAULT ''::character varying,
	p_post_offered text DEFAULT ''::text,
	p_posting_department text DEFAULT ''::text,
	p_unitparametername text DEFAULT ''::text)
    RETURNS TABLE(leave_bank_id character varying, emp_id character varying, template_id character varying, account_id character varying, template_name character varying, balance_txt jsonb, employee_detail jsonb) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
declare 

p_att_year int ;
p_att_month int;
v_p_geofenceid int;
/*
 select * from get_employee_leave_balance(p_account_id =>'3088',p_emp_id =>'378');
				  
   Vinod => dated.08.07.2025 Add Global Level Opening Balance		

	vinod dated . 29.11.2025 added changes for compoff opening balance
*/
v_other_leave_bal text;
v_check_gender varchar(1);

v_allow_requests_for_future_dates_yn varchar(10)='N';
v_requests_for_future_days_cnt_if_y varchar(10);
v_template_id  bigint;

v_typecode_arr_fullday TEXT[];
v_typecode_arr_halfday TEXT[];							  
 
begin

	p_att_year :=  EXTRACT(YEAR FROM current_date)::int;
	p_att_month :=  EXTRACT(MONTH FROM current_date)::int;
	p_emp_id= (CASE WHEN p_emp_id='0' THEN '' ELSE p_emp_id END );
	
	v_p_geofenceid:= (CASE WHEN p_geofenceid ='' OR p_geofenceid ='0' THEN '0' ELSE p_geofenceid END)::int;
	
	p_post_offered:= (CASE WHEN p_post_offered='All' THEN '' ELSE p_post_offered END) ;
	p_posting_department:= (CASE WHEN p_posting_department='All' THEN '' ELSE p_posting_department END) ;																					

			v_requests_for_future_days_cnt_if_y:= '30';
  

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
	
   
			IF p_emp_id <>''  THEN 
						select  a.template_id into v_template_id from tbl_employee_leavebank a
						where a.emp_id= p_emp_id::bigint and a.status='1';
  
																											   
																				
																					   
   
																  
												
		  
   
																  
																					 
	 
																 
	 
												   
					
						select tbl_tpleavebank.allow_requests_for_future_dates_yn,tbl_tpleavebank.requests_for_future_days_cnt_if_y 
						into v_allow_requests_for_future_dates_yn,v_requests_for_future_days_cnt_if_y
						from tbl_tpleavebank where tbl_tpleavebank.template_id=v_template_id and status='1';
						
						IF COALESCE(v_allow_requests_for_future_dates_yn,'N')='N'  then
								v_requests_for_future_days_cnt_if_y:= '30';
						ENd if;
						
						IF COALESCE(v_allow_requests_for_future_dates_yn,'N')='Y'  then
								v_requests_for_future_days_cnt_if_y:= trim(v_requests_for_future_days_cnt_if_y);
								
								IF trim(v_requests_for_future_days_cnt_if_y)::int > 180 then
								
										v_requests_for_future_days_cnt_if_y:= '180';
								
								END IF;
						ENd if;
			
						 
																		 
													 
  
																																					
																				
																					   
   
																								   
												
		  
   
																								   
																					 
	 
																								 
	 
																			
	 
			END IF;
		  
		 
		/*
		v_check_gender:='B';
	
		If (p_emp_id<>'' AND p_account_id <>'' ) then
		
			select UPPER(left(gender,1)) into v_check_gender
			from openappointments a where a.emp_id= p_emp_id::bigint 
			and a.customeraccountid= p_account_id::bigint;

			raise notice 'v_check_gender=>%',v_check_gender;
		
		end if;
		
		
	
		v_other_leave_bal:= (select array_to_json(array_agg(row_to_json(t)))::varchar from
							(   select (COALESCE(init_bal,'0') - COALESCE(leave_taken,'0')::int)::varchar cur_bal, init_bal::varchar init_bal,type_code,
								leave_taken ,is_spacial,type_name from
							   (select leave_days cur_bal,leave_days init_bal ,leavetypecode type_code, 
								leavetypename type_name,								
								(
								
								select count(a1.att_date) from tbl_monthly_attendance a1
									inner join openappointments tbl_open 
									on a1.emp_code= tbl_open.emp_code AND tbl_open.emp_id=(CASE WHEN  (p_emp_id='' OR p_emp_id IS NULL) THEN tbl_open.emp_id ELSE p_emp_id::bigint END)::bigint 
									AND  a1.leavetype=leavetypecode  and a1.customeraccountid=tbl_open.customeraccountid
									WHERE  tbl_open.emp_id=(CASE WHEN  (p_emp_id='' OR p_emp_id IS NULL) THEN tbl_open.emp_id ELSE p_emp_id::bigint END)::bigint 
									and tbl_open.customeraccountid=p_account_id::bigint and a1.isactive='1' 																
									)::varchar
									leave_taken, 'Y' is_spacial from mst_tp_leavetype where status='1' 
								and type_account_id=p_account_id::bigint and is_enable='Y' 
								and leave_days>0  AND  upper(t_gender) in ('B',v_check_gender) ) t 
							) t );
	   
	
		*/
      return query 					
		-- removed jivo account restriction: now need to show the leave for p_account_id='2719'
		 select tbl_final.leave_bank_id::varchar,tbl_final.emp_id,tbl_final.template_id,tbl_final.account_id,
		  tbl_final.template_name,
   
			CASE  /* WHEN p_account_id ='2719' then NULL -- now need to show the leave */ WHEN special_leave_txt is not null THEN 
		  (CASE WHEN tbl_final.comp_off_txt is not null AND (tbl_final.comp_off_txt::jsonb->>'is_comp_off_applicable')='Y' then   tbl_final.balance_txt::jsonb||tbl_final.comp_off_txt::jsonb ELSE 
																			
		   tbl_final.balance_txt END ) || special_leave_txt::jsonb ELSE  (CASE WHEN tbl_final.comp_off_txt is not null AND (tbl_final.comp_off_txt::jsonb->>'is_comp_off_applicable')='Y' then   tbl_final.balance_txt::jsonb||tbl_final.comp_off_txt::jsonb ELSE 
																			   
																	  
		   tbl_final.balance_txt END ) END balance_txt,
		  
		  tbl_final.employee_detail
		  
		  from ( select  rowid::varchar leave_bank_id  ,a.emp_id::varchar emp_id , a.template_id::varchar template_id, a.account_id::varchar account_id,
		a.template_name,--a.template_txt::jsonb, tot_credited::jsonb prev_bal,
		--  b.leave_taken_txt::jsonb ,
		  --, 
		--COALESCE(leave_taken2::varchar,'') leave_taken_tot, 	
		
		
		
		(select array_to_json(array_agg(row_to_json(t)))::varchar from
				(
					select t1.typecode type_code,initcap(t1.typename) type_name,
										(CASE WHEN (t1.prev_bal::numeric(18,1)- COALESCE(t2.leave_taken::numeric(18,1),0.0)) <0 THEN 
											0.0 ELSE (t1.prev_bal::numeric(18,1)- COALESCE(t2.leave_taken::numeric(18,1),0.0)) END )::varchar cur_bal
						   
										,t1.init_bal ,(COALESCE(t1.prev_taken::numeric(18,1),0.0) +COALESCE(t2.leave_taken::numeric(18,1),0.0))::varchar leave_taken
										,'N' is_spacial,v_requests_for_future_days_cnt_if_y future_days
					from (	select * from jsonb_populate_recordset(null::record,tot_credited::jsonb) 
					as ( typecode varchar,typename varchar,	prev_bal  varchar,init_bal varchar, prev_taken varchar ) ) as t1
					left join
					( select * from jsonb_populate_recordset(null::record,b.leave_taken_txt::jsonb) 
					as ( typecode varchar,	leave_taken  varchar) 
					) as t2 on t1.typecode=t2.typecode ) as t) ::jsonb 
		
		balance_txt,

		  jsonb_build_object('orgempcode',orgempcode,'cjcode', cjcode, 'emp_name',emp_name,
		 'employee_photo', (CASE WHEN tcdl.document_path in ('https://api.contract-jobs.com/crm_api/','http://1akal.in/crm_api/')
				THEN NULL ELSE tcdl.document_path END )::varchar ,
				
				'assignedous',(select string_agg(ton.org_unit_name::varchar,',') 
                              from public.tbl_org_unit_geofencing ton 
                              inner join (select * from string_to_table(tbl_op.assigned_ou_ids,',')   as t) t1
                              on t1.t::int=ton.id
                             
                             ),
				'email', tbl_op.email	,
				'vendor_name',tbl_op.agencyname ,
				'project_name' , tbl_op.project_title ,
				'salary_book_project',tbl_op.salary_book_project				
				
		  )::jsonb employee_detail
		  , tbl_comp_off.compoff_text::varchar comp_off_txt,
		  tbl_special_leave.special_leave_txt
		  --, 
		-- (select sum(t.prev_bal)::varchar from
		-- 		(
		-- 			select t1.typecode,initcap(t1.typename) typename,
		-- 								(t1.prev_bal::numeric(18,2)- COALESCE(t2.leave_taken::numeric(18,2),0.0)) prev_bal
		-- 			from (	select * from jsonb_populate_recordset(null::record,tot_credited::jsonb) 
		-- 			as ( typecode varchar,typename varchar,	prev_bal  varchar) ) as t1
		-- 			left join
		-- 			( select * from jsonb_populate_recordset(null::record,b.leave_taken_txt::jsonb) 
		-- 			as ( typecode varchar,	leave_taken  varchar) 
		-- 			) as t2 on t1.typecode=t2.typecode ) as t) ::varchar balance_tot
		from tbl_employee_leavebank a 
		inner join openappointments tbl_op on a.emp_id= tbl_op.emp_id
		AND tbl_op.appointment_status_id <>'13' AND tbl_op.customeraccountid=p_account_id::bigint	
		
		
		
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
			 and att_date between make_date(p_att_year::int,p_att_month::int,1)	and (date_trunc('month',((make_date(p_att_year::int,p_att_month::int,1) + INTERVAL '6 month')::date) + interval '1 month - 1 day')::date)
			-- as it not take future booked values			 
			 -- and att_date between make_date(p_att_year::int,p_att_month::int,1)	and eomonth(make_date(p_att_year::int,p_att_month::int,1) ) 
			and leavetype is not null
		 	 AND tbl_open.isactive='1'
			group by tbl_open.emp_id,a1.customeraccountid,leavebankid,
			leavetype ) t group by t.emp_id,customeraccountid,leavebankid
					

		) b on a.rowid= b.leavebankid and a.emp_id=b.emp_id 
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
				
					select  a0.typecode, initcap(a0.typename) typename,
											(CASE WHEN a0.accumulate='Monthly' AND is_carry_forward='Y' 
											then COALESCE(nullif(b.opening_bal,''),'0')::numeric(10,2)+(a0.days::numeric(18,2) * 				   
											
																																									 
																									
																								   
											round(
											abs(make_date(p_att_year::int,p_att_month::int,1)::Date - 
											/* OLD CODE BACKUP:
											(CASE WHEN b.periodfrom::date >=
											date_trunc('month', dateofjoining ::date)::date
											
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
											then COALESCE(nullif(b.opening_bal,''),'0')::numeric(10,2)+
											(a0.days::numeric(18,2) * 				   
											round(
											abs(make_date(p_att_year::int,p_att_month::int,1)::Date - 
											/* OLD CODE BACKUP:
											(CASE WHEN b.periodfrom::date >=
											date_trunc('month', dateofjoining ::date)::date
											
											THEN b.periodfrom::date ELSE date_trunc('month', dateofjoining ::date) ::date
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
											END)::varchar init_bal,
											
											COALESCE(tbl_prev_taken.leave_taken,0)::varchar prev_taken, 	(
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
 						- 
						-- COALESCE(tbl_prev_taken.leave_taken,0)
						
						COALESCE( CASE WHEN  a0.accumulate='Monthly' AND is_carry_forward='N' then 0.0
						 ELSE tbl_prev_taken.leave_taken END ,0.0)
												

				

													)::varchar prev_bal
					from
					(
							select * from jsonb_populate_recordset(null::record,((trim(trim(b.template_txt,']'),
							'[')::jsonb->>'leave_details')::jsonb->>'leave_type')::jsonb) 
							as ( days varchar,	typecode  varchar,	typename  varchar,	
							accumulate varchar,	maximum_limit varchar,	is_carry_forward varchar)
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
		
		  LEFT JOIN tbl_candidate_documentlist tcdl ON tcdl.candidate_id = tbl_op.emp_id 
		  AND tcdl.document_id = 17 AND tcdl.active='Y'
		
left join (

					select a1.emp_id, a1.customeraccountid,
						jsonb_build_object('leave_taken',tot_compoff_taken::varchar,
						'type_code',leavetypecode,'type_name',leavetypename,
						'is_comp_off_applicable',is_comp_off_applicable ,'init_bal',
							(CASE WHEN comp_request_mode_entry='application' then coalesce(btl_appl_comp_off.comp_off_bal_in_month,0.0)::varchar else per_month_max_comp_off end )
						,'comp_off_applicable_type',comp_off_applicable_type ,'comp_off_applicable_dayname',comp_off_applicable_dayname ,
						'cur_bal', 
						
						coalesce(
						
						 (CASE WHEN (CASE WHEN comp_request_mode_entry='application' then coalesce(btl_appl_comp_off.comp_off_bal_in_month,0.0) else 	
						coalesce(nullif(per_month_max_comp_off,'')::numeric(18,1),0.0) end ) - tot_compoff_taken < 0.0 					
						
						THEN 0.0 ELSE

						coalesce( (CASE WHEN comp_request_mode_entry='application' then coalesce(btl_appl_comp_off.comp_off_bal_in_month,0.0) else 	
						coalesce(nullif(per_month_max_comp_off,'')::numeric(18,1),0.0) end ),0.0)- tot_compoff_taken 	END ),	0.0 ) ::varchar,
						'is_spacial','N','future_days',v_requests_for_future_days_cnt_if_y 
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
					and att_date BETWEEN date_trunc('year',make_date(p_att_year::int,p_att_month::int,1))	and (date_trunc('month', make_date(p_att_year::int, p_att_month::int, 1))+ interval '1 month - 1 day')::date
																								   
					--and att_date BETWEEN make_date(p_att_year::int,p_att_month::int,1)	and eomonth(make_date(p_att_year::int,p_att_month::int,1))
					where  tbl_open.customeraccountid=p_account_id::bigint 						
					group  by tbl_open.emp_id,tbl_open.customeraccountid
					) a1
	 
					/* ,
						(select leavetypecode,leavetypename from 
						mst_tp_leavetype where status='1' 
						and leavetypecode='CO' and type_account_id='0'
						
						) a , 	
						(
						
						select tp_account_id ,is_comp_off_applicable,per_month_max_comp_off,comp_off_applicable_type,comp_off_applicable_dayname,
						leave_credit_count_for_wk, leave_credit_count_for_ho from public.mst_leave_general_settings 
						where tp_account_id= p_account_id::bigint and status='1'
						
						) b 
						
						*/
						
						LEFT JOIN  mst_tp_leavetype a ON a.leavetypecode = 'CO'
						AND a.type_account_id = '0'
						AND a.status = '1' 
						LEFT JOIN mst_leave_general_settings b ON b.tp_account_id = p_account_id::BIGINT
						AND b.status = '1'
						
						left join (				
										SELECT	SUM(comp_off_credit_value) AS comp_off_bal_in_month, tbl_compoff_request_application.accountid,	tbl_compoff_request_application.emp_id
										FROM tbl_compoff_request_application
										WHERE tbl_compoff_request_application.status = '1'  -- Approved status
										AND accountid = p_account_id::bigint and approval_status='Approved'
										-- AND comp_expiry_date::date >= make_date(p_att_year::int,p_att_month::int,1) 
										AND approvedon::date >= date_trunc('year', make_date(p_att_year::int,p_att_month::int,1)) 
										AND coalesce(approvedon,current_date) <= (date_trunc('month', make_date(p_att_year::int, p_att_month::int, 1))+ interval '1 month - 1 day')::date
																																																	 
										GROUP BY tbl_compoff_request_application.accountid,tbl_compoff_request_application. emp_id 
										
										) btl_appl_comp_off on btl_appl_comp_off.emp_id= a1.emp_id
										and btl_appl_comp_off.accountid= a1.customeraccountid
	
						
							)tbl_comp_off on  a.emp_id=tbl_comp_off.	emp_id	and tbl_comp_off.customeraccountid=a.account_id
				
				
				-- added on 12.02.2025 dated. 
			
					left join 	(
						select t .emp_id emp_id_1,t .customeraccountid , 
						('['||STRING_AGG(json_build_object('type_code',leavetypecode,'type_name',t.leavetypename
						,'init_bal',init_bal::varchar ,'leave_taken', 
						t.leave_taken::varchar ,	'cur_bal',cur_bal ::varchar,'is_spacial','Y','future_days',v_requests_for_future_days_cnt_if_y
						)::varchar,',')||']')::varchar  special_leave_txt
						from
						(
						select  tbl_open.emp_id, tbl_open.customeraccountid ,t_gender,	
						tl.leavetypecode ,tl.leavetypename, coalesce(tbl_global.opening_balance, leave_days) init_bal,
						count(a1.att_date) leave_taken,
						(coalesce(tbl_global.opening_balance, leave_days) - count(a1.att_date) ) cur_bal		
						from openappointments tbl_open  	
						inner join mst_tp_leavetype tl on  tl.type_account_id= tbl_open.customeraccountid
						and  is_enable='Y' 	and leave_days>0 AND  upper(tl.t_gender) in ('B',UPPER(left(tbl_open.gender,1))) 
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
						a1.customeraccountid=tbl_open.customeraccountid	and a1.isactive='1'		
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
					
				-- end 
	
		where a.account_id=p_account_id::bigint AND a.status='1'    
		AND a.emp_id= (CASE WHEN  (p_emp_id='' OR p_emp_id IS NULL) THEN a.emp_id ELSE p_emp_id::bigint END)
		AND ( coalesce( tbl_op.dateofrelieveing, current_date) >=  make_date(p_att_year::int,p_att_month::int,1)  OR tbl_op.dateofrelieveing is null )
		--AND COALESCE(tbl_op.geofencingid, 0) =	(CASE WHEN v_p_geofenceid=0 THEN COALESCE(tbl_op.geofencingid, 0) ELSE v_p_geofenceid END)	
		AND tbl_op.CONVERTed='Y'
		AND EXISTS
				(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(tbl_op.assigned_ou_ids, ''),
					COALESCE(NULLIF(tbl_op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(tbl_op.assigned_ou_ids, ''), COALESCE(NULLIF(tbl_op.geofencingid::TEXT, ''), '0')), ','))
				)
		-- added on 03.03.2025		
			AND (
				COALESCE(NULLIF(UPPER(p_post_offered), ''), '') = '' 
				OR EXISTS (
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_post_offered), ''), UPPER(tbl_op.post_offered)), ',')) AS input_designation
					WHERE input_designation = ANY (string_to_array(COALESCE(NULLIF(UPPER(tbl_op.post_offered), ''), ''), ','))
							)
			)

			AND (
				COALESCE(NULLIF(UPPER(p_posting_department), ''), '') = '' 
				OR EXISTS (
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(UPPER(p_posting_department), ''), UPPER(tbl_op.posting_department)), ',')) AS input_department
					WHERE input_department = ANY (string_to_array(COALESCE(NULLIF(UPPER(tbl_op.posting_department), ''), ''), ','))
							)
			)
			AND EXISTS
				(
					SELECT 1
					FROM unnest(string_to_array(COALESCE(NULLIF(p_unitparametername, ''), COALESCE(NULLIF(tbl_op.assigned_ou_ids, ''), COALESCE(NULLIF(tbl_op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
					WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(tbl_op.assigned_ou_ids, ''), COALESCE(NULLIF(tbl_op.geofencingid::TEXT, ''), '0')), ','))
				)
				
			-- end --
		
		--and b.status='1' 
		  ) tbl_final
		;
				  
   
END;
$BODY$;

ALTER FUNCTION public.get_employee_leave_balance(character varying, character varying, character varying, character varying, text, text, text)
    OWNER TO payrollingdb;

