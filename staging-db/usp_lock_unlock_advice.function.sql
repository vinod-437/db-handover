-- FUNCTION: public.usp_lock_unlock_advice(bigint, character varying, integer, integer, bigint)

-- DROP FUNCTION IF EXISTS public.usp_lock_unlock_advice(bigint, character varying, integer, integer, bigint);

CREATE OR REPLACE FUNCTION public.usp_lock_unlock_advice(
	p_customer_account_id bigint,
	p_action character varying,
	p_month integer,
	p_year integer,
	p_emp_code bigint DEFAULT '-9999'::integer)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    ref_cursor refcursor;
    v_message VARCHAR;
    v_total_rows INT;
    v_locked_count INT;
    v_unlocked_count INT;
    v_locked_check INT;
    v_status BOOLEAN;	
	v_rec_payrolldates record;
	v_paymentadvice paymentadvice%rowtype;

BEGIN
/*******|***************************|*******************************************|*******************|
Version |			Date			|	Change									|	Done_by			|
********|***************************|*******************************************|*******************|
1.0		| 							| Initial Version							| Siddharth Bansal	|
1.1		| 28-Mar-2025				| Unapprove attendance on clear Advice		| Shiv Kumar		|								  
1.2		| 24-JUN-2025				| Add cross month backwrod and froward 		| Vinod Kumar		|								  
1.3		| 26-Sep-2025				| Multipayout Advice deletion				| Shiv Kumar		|								  
1.4		| 23-Dec-2025				| Delete Increment Arrear(Advice Mode)		| Shiv Kumar		|								  
****************************************************************************************************/
    -- Count total rows with paid days (For given employee if p_emp_code is provided)
    SELECT COUNT(*) INTO v_total_rows
    FROM paymentadvice
    WHERE customeraccountid = p_customer_account_id
        AND mprmonth = p_month
        AND mpryear = p_year
        AND paiddays > 0
        AND (p_emp_code = -9999 OR emp_code = p_emp_code);

    -- Count locked rows
    SELECT COUNT(*) INTO v_locked_count
    FROM paymentadvice
    WHERE customeraccountid = p_customer_account_id
        AND mprmonth = p_month
        AND mpryear = p_year
        AND paiddays > 0
        AND advicelockstatus = 'Locked'
        AND (p_emp_code = -9999 OR emp_code = p_emp_code);

    -- Count unlocked rows
    SELECT COUNT(*) INTO v_unlocked_count
    FROM paymentadvice
    WHERE customeraccountid = p_customer_account_id
        AND mprmonth = p_month
        AND mpryear = p_year
        AND paiddays > 0
        AND advicelockstatus IS NULL
        AND (p_emp_code = -9999 OR emp_code = p_emp_code);

    -- Lock advice
    IF p_action = 'Lock' THEN
        IF v_locked_count = v_total_rows THEN
            v_message := 'Selected advice records are already locked or advice is Deleted.';
            v_status := false;
        ELSE
            UPDATE paymentadvice
            SET advicelockstatus = 'Locked'
            WHERE customeraccountid = p_customer_account_id
                AND mprmonth = p_month
                AND mpryear = p_year 
                AND paiddays > 0
                AND (p_emp_code = -9999 OR emp_code = p_emp_code);

            v_message := 'Advice Locked Successfully';
            v_status := true;
        END IF;

    -- Unlock advice
    ELSIF p_action = 'Unlock' THEN
        IF v_unlocked_count = v_total_rows THEN
            v_message := 'Selected advice records are already unlocked or advice is Deleted.';
            v_status := false;
        ELSE
            UPDATE paymentadvice
            SET advicelockstatus = NULL
            WHERE customeraccountid = p_customer_account_id
                AND mprmonth = p_month
                AND mpryear = p_year
                AND paiddays > 0
                AND (p_emp_code = -9999 OR emp_code = p_emp_code);
            v_message := 'Advice Unlocked Successfully';
            v_status := true;
        END IF;

    -- Delete advice (Check if already locked)
    ELSIF p_action = 'DeleteAdvice' THEN
        -- Count locked records
        SELECT COUNT(*) INTO v_locked_check
        FROM paymentadvice
        WHERE customeraccountid = p_customer_account_id
            AND mprmonth = p_month
            AND mpryear = p_year
            AND paiddays > 0
            AND advicelockstatus = 'Locked'
            AND (p_emp_code = -9999 OR emp_code = p_emp_code);

        -- Prevent deletion if advice is locked
        IF v_locked_check > 0 THEN
            v_message := 'Cannot delete advice as some records are locked.';
            v_status := false;
        ELSE
            DELETE FROM paymentadvice
            WHERE ctid = (
                SELECT ctid
                FROM paymentadvice
                WHERE customeraccountid = p_customer_account_id
                    AND (
                        (mprmonth = p_month AND mpryear = p_year AND paiddays > 0 AND coalesce(attendancemode,'') <> 'Manual')
                        OR 
                        (to_char(make_date(p_year, p_month, 1), 'Mon yyyy') = substring(hrgeneratedon, 4, 8) AND coalesce(attendancemode,'') = 'Manual')
                    )
                    AND emp_code = p_emp_code
                ORDER BY 
                    CASE WHEN coalesce(attendancemode,'') = 'MPR' THEN 1
                         WHEN coalesce(attendancemode,'') = 'Ledger' THEN 2 
                         WHEN coalesce(attendancemode,'') = 'Manual' THEN 3 
                    END
                LIMIT 1    
            )
            AND customeraccountid = p_customer_account_id
            AND emp_code = p_emp_code
            RETURNING * INTO v_paymentadvice;
update cmsdownloadedwages set isactive='0' 
where empcode = p_emp_code::varchar
and mprmonth = v_paymentadvice.mprmonth
and mpryear = v_paymentadvice.mpryear
and batch_no = v_paymentadvice.batch_no;
/**************************Change 1.1 starts****************************************/
SELECT
	-- added on 23.06.2025 vinod
		(CASE WHEN month_direction='F' THEN make_date(p_year::int, p_month::int,month_start_day)::date
		ELSE (make_date(p_year::int, p_month::int,month_start_day)- interval '1 month') END)::date  start_dt,
		
		CASE WHEN month_direction='F' THEN (make_date(p_year::int, p_month::int,month_end_day)+ interval '1 month')::date  
		ELSE make_date(p_year::int, p_month::int,month_end_day)::date  END end_dt
		-- added on 23.06.2025			
		
	/* make_date(p_year::int, p_month::int, month_start_day)::date start_dt,
	(make_date(p_year::int, p_month::int, month_end_day) + INTERVAL '1 month')::date end_dt
	*/
-- Change - END [3.1]
into v_rec_payrolldates
from mst_account_custom_month_settings 
where account_id= p_customer_account_id and status='1'  AND month_start_day <>0;
v_rec_payrolldates.start_dt:=coalesce(v_rec_payrolldates.start_dt,make_date(p_year::int, p_month::int,1));
v_rec_payrolldates.end_dt:=coalesce(v_rec_payrolldates.end_dt,(make_date(p_year::int, p_month::int,1)+ interval '1 month -1 day')::date);

update tbl_monthly_attendance 
set approval_status='P',modifiedon=current_timestamp
where customeraccountid = p_customer_account_id
	 and multipayoutrequestid=0
     AND (emp_code = p_emp_code)
	and tbl_monthly_attendance.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	and (tbl_monthly_attendance.isactive='1' or tbl_monthly_attendance.attendance_salary_status='1');
/*************************Change 1.1 ends****************************/
/*************************Change 1.3 starts****************************/
with tmp1 as
(
update tbl_monthlysalary
set is_rejected='1'
,rejected_on=current_timestamp
,reject_reason='Multipayout Advice Rejected'
,remarks='Multipayout Advice Rejected'
where emp_code=p_emp_code
	and mprmonth = p_month
	AND mpryear = p_year
	and is_rejected='0'
	and is_advice='Y'
	and multipayoutrequestid>0
	and recordscreen<>'Increment Arear'
returning *	
),
tmp2 as(
	update cmsdownloadedwages
	set isactive='0'
	,remark='Multipayout Advice Rejected'
	where empcode = p_emp_code::varchar
		and mprmonth = p_month
		AND mpryear = p_year
		and isactive='1'
		and multipayoutrequestid>0
		and multipayoutrequestid in (select t1.multipayoutrequestid from tmp1 t1)
)
update tbl_monthly_attendance 
set approval_status='P',modifiedon=current_timestamp
,payout_frequencytype='SAP'
,multipayoutrequestid=0
,remarks='Multipayout Advice Rejected'
where customeraccountid = p_customer_account_id
     AND emp_code = p_emp_code
	 and multipayoutrequestid>0
	and tbl_monthly_attendance.att_date between v_rec_payrolldates.start_dt and v_rec_payrolldates.end_dt
	and (tbl_monthly_attendance.isactive='1' or tbl_monthly_attendance.attendance_salary_status='1')
	and multipayoutrequestid in (select t1.multipayoutrequestid from tmp1 t1);
/*************************Change 1.3 ends****************************/
/************************Change 1.4 starts*****************************/
		update tbl_monthlysalary
		set is_rejected='1'
			,rejected_on=current_timestamp
			,reject_reason='Advice Rejected'
			,remarks='Advice Rejected'
		where emp_code=p_emp_code
			and arearprocessmonth=p_month
			and arearprocessyear=p_year
			and recordscreen ='Increment Arear'
			and is_advice='Y'
			and is_rejected='0';
/************************Change 1.4 ends*****************************/
	
            v_message := 'Advice Deleted Successfully.';
            v_status := true;
        END IF;

    ELSE
        v_message := 'Invalid action';
        v_status := false;
    END IF;

    -- Open refcursor to return a result set
    OPEN ref_cursor FOR 
    SELECT v_status::text AS status, v_message AS msg;

    RETURN ref_cursor;
END;
$BODY$;

ALTER FUNCTION public.usp_lock_unlock_advice(bigint, character varying, integer, integer, bigint)
    OWNER TO stagingpayrolling_app;

