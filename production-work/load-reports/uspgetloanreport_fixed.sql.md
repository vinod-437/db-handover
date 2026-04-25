```sql
CREATE OR REPLACE FUNCTION public.uspgetloanreport(p_action text, p_customeraccountid bigint, p_ou_ids character varying DEFAULT NULL::character varying, p_tptype text DEFAULT 'TP'::text, p_post_offered text DEFAULT ''::text, p_posting_department text DEFAULT ''::text, p_unitparametername text DEFAULT ''::text)
 RETURNS refcursor
 LANGUAGE plpgsql
AS $function$
/*************************************************************************
Version         Date            Change                               Done_by
1.0             30-Aug-2024    INITIAL VERSION                      SIDDHARTH BANSAL
1.1             03-Sep-2024	   Payout Period Logic					SIDDHARTH BANSAL
1.2             05-Sep-2024    Adding Disbursement Date logic       SIDDHARTH BANSAL
1.3             05-Sep-2024    Update New logics			        Shiv Kumar
1.4             10-02-2025     New Filters			        		Siddharth Bansal
1.5             25-Apr-2026    Fix Pending Installments count       Antigravity
*************************************************************************/
DECLARE
    v_rfc refcursor;
    v_payout_day int;
    v_current_date date := CURRENT_DATE;
    v_current_month_start date;
    v_current_month_end date;
    v_last_payout_date date;
    v_recent_payout_date date;
    v_current_month_payout_date date;
    v_previous_month_payout_date date;
	v_payout_mode_type varchar;
	v_payout_period varchar;
	v_installment int;
	v_tbl_account tbl_account%rowtype;
BEGIN
    -- Retrieve payout day from tbl_account
     SELECT * INTO v_tbl_account FROM tbl_account WHERE id = p_customeraccountid;
	
    IF p_action = 'GetLoanReport' THEN
	
        if v_tbl_account.payout_mode_type = 'standard' then
            OPEN v_rfc FOR
            SELECT 
                lm.id AS loan_number,
                lm.emp_code AS emp_code,
                op.cjcode AS cjcode,
                op.orgempcode AS orgempcode,
                op.emp_name AS emp_name,
                lm.principal_amount AS loan_amount, -- principal amount
                lm.total_interest AS total_interest,
                lm.total_loan_amount AS opening_balance_amount, -- total loan amount(Principal + Interest)
                lm.emiamount AS installment_amount,
                lm.roi AS rate_of_interest,
                lm.tenure AS paid_in_period, -- total tenure of loan
                sum(case when tm.emp_code is not null and el.headname = 'Loan Recovery' then lm.principal_amount else 0 end) AS principal_paid,
                lm.total_loan_amount - coalesce(sum(case when tm.issalarydownloaded='P' and el.headname = 'Loan Recovery' then lm.principal_amount else 0 end),0) AS principal_balance,
				
                -- Antigravity Change 25-Apr-2026: Changed COUNT(1) to COUNT(DISTINCT el.id) to prevent cartesian product inflation
                (lm.tenure - coalesce(COUNT(DISTINCT case when tm.emp_code is not null and el.headname = 'Loan Recovery' then el.id else null end),0)) AS pending_installments,
                
                TO_CHAR(lm.loan_date,'DD/MM/YYYY') AS loan_date,
				TO_CHAR(lm.loan_sanction_date,'DD/MM/YYYY') AS loan_sanction_date,
				TO_CHAR(min(tm.salarydownloadedon),'DD/MM/YYYY') start_date,
				to_char(lm.emistartdate,'Mon-yyyy') emistartdate,
				to_char(lm.emienddate,'Mon-yyyy') as end_date,
                TO_CHAR(max(case when tm.emp_code is not null and el.headname = 'Loan Recovery' then tm.salarydownloadedon else null end),'DD/MM/YYYY') AS recent_payment_date,
				TO_CHAR(min(case when tm.emp_code is not null and el.headname = 'Loan' then tm.salarydownloadedon else null end),'DD/MM/YYYY')  disbursment_date
            FROM public.openappointments op inner join loan_master lm 
						on lm.isactive = '1' 
						AND op.emp_code = lm.emp_code
						AND op.customeraccountid = p_customeraccountid
            inner JOIN loan_repayment_schedule lrs 
					ON lm.id = lrs.loan_master_id 
					AND lrs.emp_code = op.emp_code
            inner JOIN tbl_employeeledger el 
						ON lm.emp_code = el.emp_code 
						AND el.loan_master_id = lm.id
						AND (el.headname = 'Loan' OR el.headname = 'Loan Recovery')
			left JOIN tbl_monthlysalary tm 
						ON tm.emp_code = el.emp_code
						AND tm.mprmonth = el.processmonth
						AND tm.mpryear = el.processyear
						AND tm.batchid = el.ledgerbatchid
						AND tm.issalarydownloaded = 'P'
			where op.isactive = '1'
			--SIDDHARTH BANSAL 10/02/2025
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
			AND EXISTS
                    (
                        SELECT 1
                        FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
                        WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
                    )
            GROUP BY 
                lm.id, lm.emp_code, op.cjcode, op.orgempcode, op.emp_name,
                lm.principal_amount, lm.emiamount, lm.tenure, lm.loan_date, lm.emistartdate, lm.emienddate
            ORDER BY 
                lm.id;
        END IF;
		-- other than standard
If v_tbl_account.payout_mode_type <> 'standard' then
        OPEN v_rfc FOR 
		SELECT 
                lm.id AS loan_number,
                lm.emp_code AS emp_code,
                op.cjcode AS cjcode,
                op.orgempcode AS orgempcode,
                op.emp_name AS emp_name,
                lm.principal_amount AS loan_amount, -- principal amount
                lm.total_interest AS total_interest,
                lm.total_loan_amount AS opening_balance_amount, -- total loan amount(Principal + Interest)
                lm.emiamount AS installment_amount,
                lm.roi AS rate_of_interest,
                lm.tenure AS paid_in_period, -- total tenure of loan
                coalesce(sum(case when make_date(emiyear,emimonth,1)<date_trunc('month',current_date) then lrs.principal_amount else 0 end),0) AS principal_paid,
                lm.total_loan_amount - coalesce(sum(case when make_date(emiyear,emimonth,1)<date_trunc('month',current_date) then lrs.principal_amount else 0 end),0) AS principal_balance,
				
                -- Antigravity Change 25-Apr-2026: Changed COUNT() to SUM() because COUNT() counts 0s as valid rows.
                (lm.tenure - coalesce(SUM(case when make_date(emiyear,emimonth,1)<date_trunc('month',current_date) then 1 else 0 end),0)) AS pending_installments,
                
                TO_CHAR(lm.loan_date,'DD/MM/YYYY') AS loan_date,
				TO_CHAR(lm.loan_sanction_date,'DD/MM/YYYY') AS loan_sanction_date,
				TO_CHAR(min(lm.loan_date),'DD/MM/YYYY') start_date,
				to_char(lm.emistartdate,'Mon-yyyy') emistartdate,
				to_char(lm.emienddate,'Mon-yyyy') as end_date,
                TO_CHAR(max(case when make_date(emiyear,emimonth,1)<date_trunc('month',current_date) then lrs.emidate else null end),'DD/MM/YYYY') AS recent_payment_date,
				TO_CHAR(min(lm.loan_date),'DD/MM/YYYY')  disbursment_date
            FROM public.openappointments op
			inner join public.loan_master lm on lm.isactive = '1' 
									AND op.emp_code = lm.emp_code
									AND op.customeraccountid = p_customeraccountid
            inner JOIN loan_repayment_schedule lrs ON lm.id = lrs.loan_master_id							
			where op.isactive = '1'
			--SIDDHARTH BANSAL 10/02/2025
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
			AND EXISTS
                    (
                        SELECT 1
                        FROM unnest(string_to_array(COALESCE(NULLIF(p_ou_ids, ''), COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0'))), ',')) AS input_ou_ids
                        WHERE input_ou_ids = ANY (string_to_array(COALESCE(NULLIF(op.assigned_ou_ids, ''), COALESCE(NULLIF(op.geofencingid::TEXT, ''), '0')), ','))
                    )			
            GROUP BY 
                lm.id, lm.emp_code, op.cjcode, op.orgempcode, op.emp_name,
                lm.principal_amount, lm.emiamount, lm.tenure, lm.loan_date, lm.emistartdate, lm.emienddate--,el.createdon
            ORDER BY 
                lm.id;
			end if;
    END IF;
    RETURN v_rfc;
END;
$function$;
```
