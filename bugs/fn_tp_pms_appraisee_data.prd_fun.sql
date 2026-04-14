-- FUNCTION: public.fn_tp_pms_appraisee_data_09_04_2026(text, integer, integer, text, text, text, integer, integer)

-- DROP FUNCTION IF EXISTS public.fn_tp_pms_appraisee_data_09_04_2026(text, integer, integer, text, text, text, integer, integer);

CREATE OR REPLACE FUNCTION public.fn_tp_pms_appraisee_data(
	action text,
	p_customeraccountid integer,
	p_appraisalcycleid integer DEFAULT 0,
	p_emp_searchtext text DEFAULT NULL::text,
	p_dept_searchtext text DEFAULT NULL::text,
	p_status text DEFAULT NULL::text,
	p_reviewerid integer DEFAULT 0,
	p_deptid integer DEFAULT 0)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    query_main TEXT;
	query_common TEXT;
    query_excluded TEXT;						
	query_where TEXT;
    final_query TEXT;
	row_count INT;
    result TEXT;
	DECLARE emp_record RECORD;
	Declare p_reviewerid_where TEXT := '';
BEGIN
	
/*********************************************************************************************************************************
S.No.		Date			Remarks																					Done By                        
1.0							Initial Version                                                             
1.1			18/02/2025		Reviewer(p_reviewerid where added), 
							'GET_APPRAISE' action (reviewers left join added), review_status change					Daksh Malhotra
							
1.2 		21/02/2025		'GET_APPRAISE' action || Intial -> no rating_score,rating was present in data set       Ritik Verma
                            in reveiwer array || Change-> Added rating_score and rating in reveiwer array , 
                            removed rating from individual key 

1.3 		24/02/2025		'GET_APPRAISE' -> status changes added join												Daksh Malhotra
1.4 		27/02/2025		'GET_APPRAISE' -> Added self_appraisal_rating and self_appraisal_rating_score				Sidharth
1.5 		20/03/2025		'GET_APPRAISE' -> Added publish status                                     				Sidharth
1.6 		02/04/2025		'GET_APPRAISE' -> Added emp_id                                     				        Sidharth
1.7         08/04/2025      'GET_APPRAISE' -> Added summary_id                                                        Shubham Tiwari
1.8         09/04/2025      'GET_APPRAISE' ->  Added final_rating_id                                                  Shubham Tiwari
1.9         28/07/2025       'GET_APPRAISE' -> Add self_appraisal and Appraiser,                                      Shubham Tiwari
                              Reviewers all Questions(eg-> KRA,Competency,Goals etc)
***********************************************************************************************************************************/

	query_common := ' from vw_openappointments as Emp Inner join (Select ar.emp_code as Employee_Code, ar.customeraccountid as Employee_customeraccountid, ar.departmentid from  tbl_account_resources ar JOIN mst_tp_att_departments at ON at.id=ar.departmentid  and at.isactive=''1''
	and ar.customeraccountid=at.customeraccountid
	Inner join vw_openappointments oa on oa.emp_code=ar.emp_code and ar.customeraccountid=oa.customeraccountid
	where  ar.isactive=''1'' and oa.isactive=''1'' and deputeddate is not null and relieveddate is null 
	and oa.appointment_status_id <> 13  and oa.converted =''Y'' and ar.customeraccountid= ' || p_customeraccountid || ') 
	as AccRes_Emp_Dept on AccRes_Emp_Dept.Employee_Code=Emp.emp_code and AccRes_Emp_Dept.Employee_customeraccountid =  Emp.customeraccountid 
	and Emp.customeraccountid = ' || p_customeraccountid || ' ';

	query_where := ' WHERE isactive=1::bit and appointment_status_id <> 13  and converted =''Y'' and  Emp.customeraccountid = ' || p_customeraccountid || '';
	
	--Adding search filter based on the value for search text
	IF p_dept_searchText IS NOT NULL THEN
        p_dept_searchText := TRIM(p_dept_searchText);
		-- query_where := query_where || ' AND LOWER(Emp.posting_department) LIKE ''%' || LOWER(p_dept_searchText) || '%''';
   query_where := query_where || ' AND Emp.posting_department = ANY(string_to_array(''' || p_dept_searchText || ''', '','')) ';
	
END IF;
 IF p_reviewerid<> 0 THEN
      query_where := query_where || ' AND Emp.emp_code IN (select er_emp_code from tp_pms_employee_reviewer where er_reviewer_id=' || p_reviewerid || '
	 and er_appraisal_cycleid=' || p_appraisalcycleid || ' and er_customeraccountid=' || p_customeraccountid || ')';
	
	 p_reviewerid_where := ' and rs.created_by = '|| p_reviewerid ||' ';
	 
	 RAISE NOTICE 'p_reviewerid_where: %', p_reviewerid_where;
	
	END IF;
 IF p_deptid<> 0 THEN
      query_where := query_where || ' AND Emp.emp_code IN (select ar.emp_code from tbl_account_resources ar where ar.departmentid =' || p_deptid || '
	  and ar.customeraccountid=' || p_customeraccountid || ')';
		END IF;

    IF p_emp_searchText IS NOT NULL THEN
     p_emp_searchText := TRIM(p_emp_searchText);
		-- query_where := query_where || ' AND LOWER(Emp.emp_name) LIKE ''%' || LOWER(p_emp_searchText) || '%''';
    query_where := query_where || ' AND Emp.emp_name = ANY(string_to_array(''' || p_emp_searchtext || ''', '','')) ';
		END IF;
	IF p_status = 'completed' THEN
        query_where := query_where || ' AND EXISTS (SELECT 1 FROM tp_pms_appraisal_review_summary rs WHERE rs.employeeid = emp_code AND rs.review_status = ''Submitted'' AND rs.review_type = ''manager_review'' AND appraisalcycleid = ' || p_appraisalcycleid || ' AND customeraccountid = ' || p_customeraccountid || ')';
    ELSIF p_status = 'pending' THEN
        query_where := query_where || ' AND (NOT EXISTS (SELECT 1 FROM tp_pms_appraisal_review_summary rs WHERE rs.employeeid = emp_code AND rs.review_type = ''manager_review'' AND appraisalcycleid = ' || p_appraisalcycleid || ' AND customeraccountid = ' || p_customeraccountid || ') 
                                        OR EXISTS (SELECT 1 FROM tp_pms_appraisal_review_summary rs WHERE rs.employeeid = emp_code AND rs.review_status != ''Submitted'' AND rs.review_type = ''manager_review'' AND appraisalcycleid = ' || p_appraisalcycleid || ' AND customeraccountid = ' || p_customeraccountid || '))';
    END IF;
	FOR emp_record IN
       	Select aca_fieldId,aca_ruleId,acf_columnname,acf_tablename,acr_rulename,--STRING_AGG(CASE  WHEN aca_fieldId = 5 then quote_literal(departmentname)  else aca_criteriaValue end, ', ')
        STRING_AGG(aca_criteriavalue,',') as aca_criteriavalue from tp_Pms_ac_Applicability inner join mst_tp_pms_ac_fields on aca_appraisalcycleId= p_appraisalcycleid
		and aca_Customeraccountid=p_customeraccountid
		and aca_fieldId=acf_fieldId  
-- 		LEFT JOIN mst_tp_att_departments dept ON 
-- 									CASE 
--                                          WHEN aca_fieldId = 5 THEN aca_criteriavalue::int = dept.id
--                                          ELSE FALSE
--                                     END
		inner join mst_tp_pms_ac_rule on aca_ruleId=acr_ruleId  Group by aca_fieldId,aca_ruleId,acf_columnname,acf_tablename,acr_rulename
    LOOP
		if emp_record.acf_tablename='openappointments' then
			if emp_record.acf_columnname='dateofjoining' and emp_record.acr_rulename='Until' then
			-- Enter for other rules of date 
				 query_where := query_where || ' and dateofjoining <=''' || emp_record.aca_criteriavalue ||'''';

			End If;
        if emp_record.acf_columnname='dateofjoining' and emp_record.acr_rulename='From & To' then
			 -- DECLARE
    --             from_date text;
    --             to_date text;
    --         BEGIN
    --             -- Extract dates from the JSON array
    --             SELECT jsonb_array_elements_text(emp_record.aca_criteriavalue::jsonb) INTO from_date FROM generate_series(0, 0);
    --             SELECT jsonb_array_elements_text(emp_record.aca_criteriavalue::jsonb) INTO to_date FROM generate_series(1, 1);
                
    --             -- Construct the BETWEEN condition
    --             query_where := query_where || ' AND dateofjoining BETWEEN ''' || from_date || ''' AND ''' || to_date || '''';
    --         END;
			 DECLARE
                from_date text;
                to_date text;
            BEGIN
                -- Extract dates from the JSON array
                SELECT emp_record.aca_criteriavalue::jsonb->>0 INTO from_date;
                SELECT emp_record.aca_criteriavalue::jsonb->>1 INTO to_date;
                
                -- Construct the BETWEEN condition
                query_where := query_where || ' AND dateofjoining BETWEEN ''' || from_date || ''' AND ''' || to_date || '''';
            END;

			End If;
			if emp_record.acf_columnname='jobtype' and emp_record.acr_rulename='Is' then
			 	query_where := query_where || ' and jobtype =''' || emp_record.aca_criteriavalue ||'''';
			End If;
if action<>'GET_EMPLOYEE_TO_INCLUDE' then
	if emp_record.acf_columnname='posting_department' and emp_record.acr_rulename='Is' then
				-- if aca_field id is 5 (means department) then it would have joined and department would have been set
			 	query_where := query_where || ' AND AccRes_Emp_Dept.departmentid in (' || emp_record.aca_criteriavalue ||')';
			End If;
End If;
			
			if emp_record.acf_columnname='post_offered' and emp_record.acr_rulename='Is' then
			 	query_where := query_where || ' and post_offered =''' || emp_record.aca_criteriavalue ||'''';
			End If;
			if emp_record.acf_columnname='posting_location' and emp_record.acr_rulename='Is' then
			 	query_where := query_where || ' and posting_location =''' || emp_record.aca_criteriavalue ||'''';
			End If;
		END If;
	END LOOP;

	
-- select * from public.fn_tp_pms_appraisee_data('GET_APPRAISE','653','163',NULL,NULL,NULL,NULL)	

	If action='GET_APPRAISE' Then
		query_common := query_common || query_where ;
		
		--Checking if there are employees excluded for this customer accID
		If exists (select 1 from tp_pms_ac_excluded_employees  WHERE  ace_customeraccountid = p_customeraccountid and ace_appraisalcycleid= p_appraisalcycleid) then
		 	--query_common := query_common || ' AND emp_code NOT IN (SELECT ace_empcode FROM tp_pms_ac_excluded_employees WHERE ace_customeraccountid = ' || p_customeraccountid || ' and ace_appraisalcycleid = ' || p_appraisalcycleid || '  AND (ace_isactive = true OR ace_isactive IS NULL)  )';
			 query_excluded=' Left outer join tp_pms_ac_excluded_employees on tblmain.emp_code=ace_empcode and ace_appraisalcycleid=' || p_appraisalcycleid || ' and ace_customeraccountid=' || p_customeraccountid || ' AND (ace_isactive = true OR ace_isactive IS NULL) where ace_empcode is null';
			-- Combine queries based on row_count
			query_main := 'Select tblmain.* from ( select emp_id,emp_name,dateofjoining,jobtype,emp_code,post_offered,posting_department ,orgempcode, cjcode ' || query_common ||' ) as tblmain ' || query_excluded ;
		else
			-- Combine queries based on row_count
			query_main := ' select emp_id,emp_name,dateofjoining,jobtype,emp_code,post_offered,posting_department ,orgempcode, cjcode ' || query_common ;
			
		End If;
		
		 -- Construct query to include employees from tp_pms_ac_included_employees
        row_count := (SELECT COUNT(*) FROM tp_pms_ac_included_employees WHERE aci_customeraccountid =  p_customeraccountid AND aci_appraisalcycleid =  p_appraisalcycleid AND COALESCE(aci_isactive,TRUE)<>false) ;
		
       
        IF row_count > 0 THEN
            final_query := query_main || ' UNION ' ||
                           'SELECT   emp_id,emp_name,dateofjoining,jobtype,emp_code,post_offered,posting_department,orgempcode, cjcode FROM vw_openappointments 
                            WHERE emp_code IN (SELECT aci_empcode FROM tp_pms_ac_included_employees WHERE aci_customeraccountid = ' || p_customeraccountid || ' AND aci_appraisalcycleid = ' || p_appraisalcycleid || ' AND COALESCE(aci_isactive,TRUE)<>false)';
 -- Apply search filters to included employees as well
 IF p_reviewerid<> 0 THEN
      final_query := final_query || ' AND vw_openappointments.emp_code IN (select er_emp_code from tp_pms_employee_reviewer where er_reviewer_id=' || p_reviewerid || '
	 and er_appraisal_cycleid=' || p_appraisalcycleid || ' and er_customeraccountid=' || p_customeraccountid || ')';
	 
	 p_reviewerid_where := ' and rs.created_by = '|| p_reviewerid ||' ';
	 
	 RAISE NOTICE 'p_reviewerid_where: %', p_reviewerid_where;
	 
		END IF;
 IF p_deptid<> 0 THEN
      query_where := query_where || ' AND vw_openappointments.emp_code IN (select ar.emp_code from tbl_account_resources ar where ar.departmentid =' || p_deptid || '
	  and ar.customeraccountid=' || p_customeraccountid || ')';
		END IF;
            IF p_dept_searchText IS NOT NULL THEN
                final_query := final_query || ' AND posting_department = ANY(string_to_array(''' || p_dept_searchText || ''', '','')) ';
            END IF;
            IF p_emp_searchText IS NOT NULL THEN
                final_query := final_query || ' AND emp_name = ANY(string_to_array(''' || p_emp_searchText || ''', '','')) ';
            END IF;  
 IF p_status = 'completed' THEN
        final_query := final_query || ' AND EXISTS (SELECT 1 FROM tp_pms_appraisal_review_summary rs WHERE rs.employeeid = emp_code AND rs.review_status = ''Submitted'' AND rs.review_type = ''manager_review'' AND appraisalcycleid = ' || p_appraisalcycleid || ' AND customeraccountid = ' || p_customeraccountid || ')';
    ELSIF p_status = 'pending' THEN
        final_query := final_query || ' AND (NOT EXISTS (SELECT 1 FROM tp_pms_appraisal_review_summary rs WHERE rs.employeeid = emp_code AND rs.review_type = ''manager_review'' AND appraisalcycleid = ' || p_appraisalcycleid || ' AND customeraccountid = ' || p_customeraccountid || ') 
                                        OR EXISTS (SELECT 1 FROM tp_pms_appraisal_review_summary rs WHERE rs.employeeid = emp_code AND rs.review_status != ''Submitted'' AND rs.review_type = ''manager_review'' AND appraisalcycleid = ' || p_appraisalcycleid || ' AND customeraccountid = ' || p_customeraccountid || '))';
    END IF;
ELSE
            final_query := query_main;
        END IF;
		
	final_query := 'Select json_agg(json_build_object(
    ''emp_id'',emp_id,
    ''emp_name'',emp_name,
    ''tpcode'',cjcode,
    ''orgempcode'',orgempcode,
    ''dateofjoining'',dateofjoining,
    ''jobtype'',jobtype ,
    ''emp_code'',emp_code,
    ''post_offered'',post_offered,
    ''posting_department'',posting_department,
    ''manager_review_startdate'', COALESCE(
        (SELECT ac.manager_review_startdate::text
         FROM tp_pms_appraisalCycle ac
         WHERE ac.appraisalcycleid = ' || p_appraisalcycleid || ' 
         AND ac.customeraccountid = ' || p_customeraccountid || '), 
        ''Not Available''
    ),
    ''manager_review_enddate'', COALESCE(
        (SELECT ac.manager_review_enddate::text
         FROM tp_pms_appraisalCycle ac
         WHERE ac.appraisalcycleid = ' || p_appraisalcycleid || ' 
         AND ac.customeraccountid = ' || p_customeraccountid || '), 
        ''Not Available''
    ),
    ''self_appraisal'',COALESCE(
        (SELECT rs.review_status
         FROM tp_pms_appraisal_review_summary rs
         WHERE rs.employeeid=emp_code and rs.review_type=''selfappraisal'' 
         and appraisalcycleid= ' || p_appraisalcycleid || ' 
         and customeraccountid= ' || p_customeraccountid || ' ),
        ''pending''
    ),
    ''self_appraisal_rating'',COALESCE(
        (SELECT rs.final_rating
         FROM tp_pms_appraisal_review_summary rs
         WHERE rs.employeeid=emp_code and rs.review_type=''selfappraisal'' 
         and appraisalcycleid= ' || p_appraisalcycleid || ' 
         and customeraccountid= ' || p_customeraccountid || ' ),
        ''pending''
    ),
    ''self_appraisal_rating_score'',COALESCE(
        (SELECT rs.final_score
         FROM tp_pms_appraisal_review_summary rs
         WHERE rs.employeeid=emp_code and rs.review_type=''selfappraisal'' 
         and appraisalcycleid= ' || p_appraisalcycleid || ' 
         and customeraccountid= ' || p_customeraccountid || ' ),
        NULL
    ), 
    ''publish'',COALESCE(
        (SELECT rs.ispublished
         FROM tp_pms_appraisal rs
         WHERE rs.employeeid=emp_code and appraisalcycleid= ' || p_appraisalcycleid || ' 
         and customeraccountid= ' || p_customeraccountid || ' ),''0''),
    ''status'',COALESCE(
        (SELECT rs.review_status
         FROM tp_pms_appraisal_review_summary rs
         inner join tp_pms_ac_manager_reviewer_level mrl 
           on mrl.acrl_levelid = rs.tpars_levelid
          and rs.review_type = ''manager_review'' 
          and mrl.acrl_customeraccountid = rs.customeraccountid
          and mrl.acrl_appraisalcycleid = rs.appraisalcycleid 
         inner join mst_tp_pms_reviewers mtpr 
           on mtpr.reviewer_id = mrl.acrl_reviewer_id 
          and mtpr.show_rating = true
         WHERE rs.employeeid=emp_code and rs.review_type=''manager_review'' 
           and rs.appraisalcycleid= ' || p_appraisalcycleid || ' 
           and rs.customeraccountid= ' || p_customeraccountid || p_reviewerid_where || ' 
           AND mtpr.show_rating = true
         order by summary_id desc limit 1),
        ''pending''
    ),
    ''reviewer_name'',COALESCE(
        (SELECT er.er_reviewer_name
         FROM tp_pms_employee_reviewer er
         WHERE er.er_emp_code=emp_code and er_appraisal_cycleid= ' || p_appraisalcycleid || ' 
           and er_customeraccountid= ' || p_customeraccountid || ' order by emp_reviewer_id limit 1),
        (select tbl_tp_user_login.user_fullname 
         from tbl_tp_user_login 
         where tbl_tp_user_login.account_id_id_fk=' || p_customeraccountid || ' 
           and tbl_tp_user_login.enable_login=''1'' order by tbl_tp_user_login.user_id limit 1)
    ),
    ''reviewer_id'',COALESCE(
        (SELECT er.er_reviewer_id
         FROM tp_pms_employee_reviewer er
         WHERE er.er_emp_code=emp_code and er_appraisal_cycleid= ' || p_appraisalcycleid || ' 
           and er_customeraccountid= ' || p_customeraccountid || ' order by emp_reviewer_id limit 1),
        (select tbl_tp_user_login.user_id from tbl_tp_user_login 
         where tbl_tp_user_login.account_id_id_fk=' || p_customeraccountid || ' 
           and tbl_tp_user_login.enable_login=''1'' order by tbl_tp_user_login.user_id limit 1) 
    ),
    ''reviewers'', ( 
        SELECT array_to_json(array_agg(row_to_json(t)))::jsonb  
        from (
            (SELECT erlvl.acrl_reviewer_id review_level_keyid, 
                    mst_tpr.reviewer_name review_level,
                    er.er_reviewer_id,	
                    er_reviewer_name,
                    er.acrl_levelid,  
                    emp_reviewer_id emp_reviewer_row_id, 
                    COALESCE(rs.review_status,''pending'') review_status,
                    COALESCE(rs.final_rating::text,''To be provided'') rating,
                    COALESCE(rs.final_score::text,''To be provided'') rating_score, 
                    case when rev_emp.orgempcode='''' 
                         then rev_emp.cjcode 
                         else rev_emp.orgempcode end  as final_orgempcode,
                    rs.customsectiondata,
                    tblRev.kra_questions,
                    tblRev.competency_questions,
                    tblRev.goal_questions,
                    tblRev.review_questions
             FROM tp_pms_employee_reviewer er 
             inner join tp_pms_ac_manager_reviewer_level erlvl 
               on erlvl.acrl_levelid=er.acrl_levelid 
              and erlvl.acrl_customeraccountid=er.er_customeraccountid 
              and erlvl.acrl_appraisalcycleid=er.er_appraisal_cycleid
             inner join mst_tp_pms_reviewers mst_tpr 
               on mst_tpr.reviewer_id = erlvl.acrl_reviewer_id 
             inner join vw_openappointments rev_emp 
               on rev_emp.emp_Code=er.er_reviewer_id 
              and rev_emp.customeraccountid=er.er_customeraccountid
             and er.er_emp_code=subquery.emp_Code
             left join tp_pms_appraisal_review_summary rs 
               on rs.employeeid = er.er_emp_code 
              and rs.appraisalcycleid = er.er_appraisal_cycleid 
              and rs.customeraccountid = er.er_customeraccountid 
              and rs.created_by=er.er_reviewer_id
             Left outer join (
                SELECT tblreview.reviewed_by AS reviewed_by,
                       json_agg(json_build_object(
                            ''method_text'', tblmethod.method_text,
                            ''review'', tblreview.review,
                            ''weightage'', tblmethod.method_weightage
                        )) FILTER (WHERE tblmethod.appraisal_method_type = ''kra'') AS kra_questions,
                       json_agg(json_build_object(
                            ''method_text'', tblmethod.method_text,
                            ''review'', tblreview.review,
                            ''weightage'', tblmethod.method_weightage
                        )) FILTER (WHERE tblmethod.appraisal_method_type = ''competency'') AS competency_questions,
                       json_agg(json_build_object(
                            ''method_text'', tblmethod.method_text,
                            ''review'', tblreview.review,
                            ''weightage'', tblmethod.method_weightage
                        )) FILTER (WHERE tblmethod.appraisal_method_type = ''goals'') AS goal_questions,
                       json_agg(json_build_object(
                            ''method_text'', tblmethod.method_text,
                            ''review'', tblreview.review,
                            ''weightage'', tblmethod.method_weightage
                        )) FILTER (WHERE tblmethod.appraisal_method_type = ''reviewquestion'') AS review_questions
                FROM tp_pms_appraisal_review AS tblreview
                INNER JOIN tp_pms_appraisal_methods AS tblmethod 
                  ON tblreview.appraisal_method_id = tblmethod.appraisal_method_Id
                 AND tblreview.customeraccountid = tblmethod.customeraccountid
                 AND tblreview.review_type = ''manager_review''
                INNER JOIN tp_pms_appraisal AS tblappraisal 
                  ON tblappraisal.appraisalId = tblmethod.appraisalId
                 AND tblmethod.customeraccountid = tblappraisal.customeraccountid
                WHERE tblappraisal.employeeId = subquery.emp_code
                  AND tblappraisal.appraisalcycleid = ' || p_appraisalcycleid || '
                  AND tblappraisal.customeraccountid = ' || p_customeraccountid || '
                GROUP BY tblreview.reviewed_by
             ) as tblRev on tblRev.reviewed_by = er.er_reviewer_id
             WHERE er.er_emp_code=subquery.emp_code  
               and er_appraisal_cycleid= ' || p_appraisalcycleid || '  
               and er_customeraccountid= ' || p_customeraccountid || ' 
             order by erlvl.acrl_reviewer_id asc )			
        ) t
    ),
    ''self_appraisal_questions'', json_build_object(
         ''kra_questions'', tblSelf.kra_questions,
         ''competency_questions'', tblSelf.competency_questions,
         ''goal_questions'', tblSelf.goal_questions,
         ''review_questions'', tblSelf.review_questions
    ),
    ''final_rating'',COALESCE(
        (SELECT rs.final_rating FROM tp_pms_appraisal_review_summary rs 
         inner join tp_pms_ac_manager_reviewer_level mrl 
           on mrl.acrl_levelid = rs.tpars_levelid
          and rs.review_type = ''manager_review'' 
          and mrl.acrl_customeraccountid = rs.customeraccountid 
          and mrl.acrl_appraisalcycleid = rs.appraisalcycleid 
         inner join mst_tp_pms_reviewers mtpr 
           on mtpr.reviewer_id = mrl.acrl_reviewer_id and mtpr.show_rating = true
         WHERE rs.employeeid=emp_code and rs.review_type=''manager_review'' 
           and rs.appraisalcycleid= ' || p_appraisalcycleid || ' 
           and rs.customeraccountid= ' || p_customeraccountid || p_reviewerid_where || ' 
           AND mtpr.show_rating = true and rs.review_status = ''Submitted''
         order by summary_id desc limit 1),''
         To be provided''
    ),
    ''final_rating_score'',COALESCE(
        (SELECT rs.final_score::text FROM tp_pms_appraisal_review_summary rs 
         inner join tp_pms_ac_manager_reviewer_level mrl 
           on mrl.acrl_levelid = rs.tpars_levelid
          and rs.review_type = ''manager_review'' 
          and mrl.acrl_customeraccountid = rs.customeraccountid 
          and mrl.acrl_appraisalcycleid = rs.appraisalcycleid 
         inner join mst_tp_pms_reviewers mtpr 
           on mtpr.reviewer_id = mrl.acrl_reviewer_id and mtpr.show_rating = true
         WHERE rs.employeeid=emp_code and rs.review_type=''manager_review'' 
           and rs.appraisalcycleid= ' || p_appraisalcycleid || ' 
           and rs.customeraccountid= ' || p_customeraccountid || p_reviewerid_where || ' 
           AND mtpr.show_rating = true and rs.review_status = ''Submitted''
         order by summary_id desc limit 1),
        ''To be provided''
    ),
    ''final_rating_id'',COALESCE(
        (SELECT rs.final_rating_id::integer FROM tp_pms_appraisal_review_summary rs 
         inner join tp_pms_ac_manager_reviewer_level mrl 
           on mrl.acrl_levelid = rs.tpars_levelid
          and rs.review_type = ''manager_review'' 
          and mrl.acrl_customeraccountid = rs.customeraccountid 
          and mrl.acrl_appraisalcycleid = rs.appraisalcycleid 
         inner join mst_tp_pms_reviewers mtpr 
           on mtpr.reviewer_id = mrl.acrl_reviewer_id and mtpr.show_rating = true
         WHERE rs.employeeid=emp_code and rs.review_type=''manager_review'' 
           and rs.appraisalcycleid= ' || p_appraisalcycleid || ' 
           and rs.customeraccountid= ' || p_customeraccountid || p_reviewerid_where || ' 
           AND mtpr.show_rating = true and rs.review_status = ''Submitted''
         order by summary_id desc limit 1)
    ),
    ''summary_id'',COALESCE(
        (SELECT rs.summary_id::bigint FROM tp_pms_appraisal_review_summary rs 
         inner join tp_pms_ac_manager_reviewer_level mrl 
           on mrl.acrl_levelid = rs.tpars_levelid
          and rs.review_type = ''manager_review'' 
          and mrl.acrl_customeraccountid = rs.customeraccountid 
          and mrl.acrl_appraisalcycleid = rs.appraisalcycleid 
         inner join mst_tp_pms_reviewers mtpr 
           on mtpr.reviewer_id = mrl.acrl_reviewer_id and mtpr.show_rating = true
         WHERE rs.employeeid=emp_code and rs.review_type=''manager_review'' 
           and rs.appraisalcycleid= ' || p_appraisalcycleid || ' 
           and rs.customeraccountid= ' || p_customeraccountid || p_reviewerid_where || ' 
           AND mtpr.show_rating = true and rs.review_status = ''Submitted''
         order by summary_id desc limit 1)
    ),
    ''levelforappcycle'',COALESCE(
        (SELECT STRING_AGG(DISTINCT reviewer_name,'','') FROM mst_tp_pms_reviewers 
         INNER JOIN tp_pms_ac_manager_reviewer_level 
           ON reviewer_id = acrl_reviewer_id
         WHERE acrl_appraisalcycleid = ' || p_appraisalcycleid || ' 
           AND acrl_customeraccountid = ' || p_customeraccountid || ' AND isactive = true),
        ''To be provided''
    ),
    ''average_rating'',COALESCE(
        (SELECT (avg(rs.final_score)::numeric(18,2))::text rating_score 
         FROM tp_pms_employee_reviewer er 
         inner join tp_pms_ac_manager_reviewer_level erlvl 
           on erlvl.acrl_levelid=er.acrl_levelid 
          and erlvl.acrl_customeraccountid=er.er_customeraccountid 
          and erlvl.acrl_appraisalcycleid=er.er_appraisal_cycleid
         inner join mst_tp_pms_reviewers mst_tpr 
           on mst_tpr.reviewer_id = erlvl.acrl_reviewer_id 
         left join tp_pms_appraisal_review_summary rs 
           on rs.employeeid = er.er_emp_code 
          and rs.appraisalcycleid = er.er_appraisal_cycleid 
          and rs.customeraccountid = er.er_customeraccountid 
          and rs.created_by=er.er_reviewer_id
         WHERE er.er_emp_code=emp_code  
           and er_appraisal_cycleid=' || p_appraisalcycleid || '  
           and er_customeraccountid=' || p_customeraccountid || '  
           and rs.final_score is not null group by emp_code),
        ''NA''
    )
)) as employees 
FROM (
    '|| final_query ||' ORDER BY emp_name
) AS subquery
LEFT JOIN (
    SELECT tblappraisal.employeeId AS employeeid,
           json_agg(json_build_object(
               ''method_text'', tblmethod.method_text,
               ''review'', tblreview.review,
               ''weightage'', tblmethod.method_weightage
           )) FILTER (WHERE tblmethod.appraisal_method_type = ''kra'') AS kra_questions,
           json_agg(json_build_object(
               ''method_text'', tblmethod.method_text,
               ''review'', tblreview.review,
               ''weightage'', tblmethod.method_weightage
           )) FILTER (WHERE tblmethod.appraisal_method_type = ''competency'') AS competency_questions,
           json_agg(json_build_object(
               ''method_text'', tblmethod.method_text,
               ''review'', tblreview.review,
               ''weightage'', tblmethod.method_weightage
           )) FILTER (WHERE tblmethod.appraisal_method_type = ''goals'') AS goal_questions,
           json_agg(json_build_object(
               ''method_text'', tblmethod.method_text,
               ''review'', tblreview.review,
               ''weightage'', tblmethod.method_weightage
           )) FILTER (WHERE tblmethod.appraisal_method_type = ''reviewquestion'') AS review_questions
    FROM tp_pms_appraisal_review AS tblreview
    INNER JOIN tp_pms_appraisal_methods AS tblmethod 
      ON tblreview.appraisal_method_id = tblmethod.appraisal_method_Id
     AND tblreview.customeraccountid = tblmethod.customeraccountid
     AND tblreview.review_type = ''selfappraisal''
    INNER JOIN tp_pms_appraisal AS tblappraisal 
      ON tblappraisal.appraisalId = tblmethod.appraisalId
     AND tblmethod.customeraccountid = tblappraisal.customeraccountid
    WHERE tblappraisal.appraisalcycleid = ' || p_appraisalcycleid || ' 
      AND tblappraisal.customeraccountid = ' || p_customeraccountid || '
    GROUP BY tblappraisal.employeeId
) AS tblSelf 
ON tblSelf.employeeid = subquery.emp_code';
		
		-- ''81''  (select user_fullname from tbl_tp_user_login where user_id=81)
		
		RAISE NOTICE 'Final SQL Query: %', final_query;
 		-- Execute the dynamic query
		
    	EXECUTE final_query INTO result;

    	-- Return the result
    	RETURN result;
	End IF ;
	
	--GET_EMPLOYEE_TO_EXCLUDE
	if action = 'GET_EMPLOYEE_TO_EXCLUDE' Then

		query_main := 'Select json_agg(json_build_object(''emp_name'',emp_name,''tpcode'',cjcode,''orgempcode'',orgempcode,
		''dateofjoining'',dateofjoining,
		''jobtype'',jobtype ,''emp_code'',emp.emp_code,''post_offered'',post_offered,''posting_department'',posting_department
		)) as employees '; 
		 
		--EXCLUDED EMPLOYEES CHANGES (Not Already Excluded) 
		
		final_query := query_main || query_common || 
		' Left Join tp_pms_ac_excluded_employees on Emp.emp_code = tp_pms_ac_excluded_employees.ace_empcode
		and tp_pms_ac_excluded_employees.ace_customeraccountid = ' || p_customeraccountid ||
		' and tp_pms_ac_excluded_employees.ace_appraisalcycleid  = ' || p_appraisalcycleid || 
		query_where || ' and tp_pms_ac_excluded_employees.ace_empcode is NULL ';
		
		RAISE NOTICE 'Final SQL Query: %', final_query;
 		
		-- Execute the dynamic query
    	EXECUTE final_query INTO result;

    	-- Return the result
    	RETURN result;
		
	end if;
-- select * from public.fn_tp_pms_appraisee_data('GET_EMPLOYEE_TO_INCLUDE','653','163',NULL,NULL,NULL,NULL)	
	if action = 'GET_EMPLOYEE_TO_INCLUDE' Then

		query_main := 'Select json_agg(json_build_object(
		                 ''emp_name'',emp_name,
						 ''tpcode'',cjcode,
						 ''orgempcode'',orgempcode,
		                 ''dateofjoining'',dateofjoining,
		                 ''jobtype'',jobtype,
						 ''emp_code'',Employee.emp_code,
						 ''post_offered'',post_offered,
						 ''posting_department'',posting_department)
						 ORDER BY emp_name) as employees from tbl_account_resources a join vw_openappointments as Employee on a.emp_code=Employee.emp_code
		and a.customeraccountid=Employee.customeraccountid and Employee.isactive=''1'' and a.isactive=''1'' and deputeddate is not null and relieveddate is null';  
	 
		--INCLUDED EMPLOYEES CHANGES (Not Already Included) 
		
		query_main := query_main || ' Left Join tp_pms_ac_included_employees on Employee.emp_code = tp_pms_ac_included_employees.aci_empcode
		and tp_pms_ac_included_employees.aci_customeraccountid = ' || p_customeraccountid ||
		'   and COALESCE(tp_pms_ac_included_employees.aci_isactive, TRUE)<>false
			and tp_pms_ac_included_employees.aci_appraisalcycleid  = ' || p_appraisalcycleid || ' ';
	
		--EXCLUDED EMPLOYEES CHANGES (Not Already Excluded)
		
		query_main := query_main || ' Left Join tp_pms_ac_excluded_employees on Employee.emp_code = tp_pms_ac_excluded_employees.ace_empcode
		and tp_pms_ac_excluded_employees.ace_customeraccountid = ' || p_customeraccountid || 
		'  and COALESCE(tp_pms_ac_excluded_employees.ace_isactive,TRUE)<>false and tp_pms_ac_excluded_employees.ace_appraisalcycleid  = ' || p_appraisalcycleid || ' ';
	
		--Falling in Appraisal Cycle (Applicability rules applied)
		
		query_main := query_main || ' Left Join (Select Emp.emp_code,Emp.customeraccountid from vw_openappointments as Emp ' ||
		query_where || ' and emp_code Not in (
					  Select ace_empcode from tp_pms_ac_excluded_employees where
		 tp_pms_ac_excluded_employees.ace_customeraccountid = ' || p_customeraccountid || ' 
			 AND (tp_pms_ac_excluded_employees.ace_isactive = true OR tp_pms_ac_excluded_employees.ace_isactive IS NULL)	
					  and tp_pms_ac_excluded_employees.ace_appraisalcycleid= ' || p_appraisalcycleid || ' ) ) as Employee_falling_in_appraisalcycle
		on Employee_falling_in_appraisalcycle.emp_code = Employee.emp_code 
		and Employee_falling_in_appraisalcycle.customeraccountid = ' || p_customeraccountid || '';
	
		--OUTER WHERE CLAUSE (Not Falling in Appraisal Cycle)(Not Already Included)(Not Already Excluded)
		
		final_query := query_main ||  ' WHERE appointment_status_id <> 13 and employee.isactive = 1::bit and converted =''Y'' and  Employee.customeraccountid = ' || p_customeraccountid || 
		' and  Employee_falling_in_appraisalcycle.emp_code is NULL and
		tp_pms_ac_included_employees.aci_empcode is NULL';

		--and tp_pms_ac_excluded_employees.ace_empcode is NULL
		RAISE NOTICE 'Final SQL Query: %', final_query;
 		
		-- Execute the dynamic query
    	EXECUTE final_query INTO result;

    	-- Return the result
    	RETURN result;
		
	end if;
	RAISE NOTICE 'sql: %', final_query;
END;
$BODY$;



