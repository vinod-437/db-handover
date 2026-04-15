-- FUNCTION: public.usp_update_weekly_off_holiday(character varying, character varying, character varying, character varying, character varying, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.usp_update_weekly_off_holiday(character varying, character varying, character varying, character varying, character varying, character varying, character varying);

CREATE OR REPLACE FUNCTION public.usp_update_weekly_off_holiday(
	p_action character varying,
	p_account_id character varying DEFAULT ''::character varying,
	p_emp_code character varying DEFAULT ''::character varying,
	p_month character varying DEFAULT ''::character varying,
	p_year character varying DEFAULT ''::character varying,
	p_user_by character varying DEFAULT ''::character varying,
	p_user_ip character varying DEFAULT ''::character varying)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$

declare
	v_month_start_date date;
	v_month_end_date date;
	v_blank_days int;
	v_account_id bigint;
	v_check_account_flag varchar(20);
	v_is_bypass_future_dt varchar(2);
	v_attendancedatesJSON text;
	r_inner record;
	v_start_date date;
	v_end_date date;
	v_p_emp_id bigint;	
	v_attended_dates date[];
	
	v_rfc refcursor;
 /* *********************************  Version **************************/
/*
v1.  Vinod Maurya  20 Feb 2024 created on 20.02.2025   for update the WO/HO

select * from usp_update_weekly_off_holiday(
		p_action =>'update_weekly_off',
		p_account_id =>'653',
		p_emp_code =>'6327',
		p_month =>'2',
		p_year =>'2025',
		p_user_by =>'1',
		p_user_ip =>'Loal'
);
*/
/************************** END ***************************/
BEGIN
	-- setps 1 get the employee list who marked attednace 
	if (p_action='update_weekly_off') then
			v_start_date := to_date(p_year || '-' || p_month || '-01', 'YYYY-MM-DD');
    v_end_date := date_trunc('month', v_start_date) + interval '1 month' - interval '1 day';

	-- OPTIMIZATION: Fetch all attended dates for this employee in one go to an array variable
	SELECT array_agg(att_date) INTO v_attended_dates
	FROM tbl_monthly_attendance 
	WHERE emp_code=p_emp_code::bigint 
	  AND customeraccountid=p_account_id::bigint 
	  AND isactive='1' 
	  AND att_date BETWEEN v_start_date AND v_end_date;

	-- If array_length is NULL, array is empty -> No records found.
	if array_length(v_attended_dates, 1) IS NULL THEN

				 return  
						(
						SELECT row_to_json(t)::text as data_t from	
						(select  '0' msgcd , 'No Attednace Marked for updated the WO/HO' msg ) t 
						);
		

	 end if;

	-- Fetching emp_id natively since we already know attendance records exist
				select  emp_id into v_p_emp_id 
				from openappointments where emp_code=p_emp_code ::bigint
				and customeraccountid=p_account_id::bigint and isactive='1';
		
				SELECT array_to_json(array_agg(row_to_json(t)))::text as data_t  into v_attendancedatesJSON 
						from
						(
							select to_char(weekly_off_ho_date,'dd/mm/yyyy')::varchar attendancedate,	
							wo_ho_type::varchar attendancetype	
							, '' leavetype
							from public.usp_get_weekly_off_n_holiday_dates(
							p_accountid =>p_account_id::bigint,
							p_emp_id  =>v_p_emp_id::bigint,
							p_month =>p_month::int,
							p_year =>p_year::int
							) where weekly_off_ho_date <> ALL (v_attended_dates) --and weekly_off_ho_date <= CURRENT_DATE

						 
		
					) t;
					
					if (v_attendancedatesJSON <>'' AND v_attendancedatesJSON is not null) then		

					raise notice '%',v_attendancedatesJSON;
						select  uspsavebulkattendance_business
                            (
                                p_action => 'SaveBulkAttendance'::character varying,
                                p_emp_code => p_emp_code::integer,
                                p_marked_by_usertype => 'Employer'::character varying,
                                p_attendancedates => v_attendancedatesJSON::text,
                                p_customeraccountid => p_account_id::integer,
                                p_leavebankid => 0,
                                p_createdby => p_user_by::integer,
                                p_createdbyip => p_user_ip::character varying
                            )  into v_rfc ;
					
					END IF;
					
					return  
						(
						SELECT row_to_json(t)::text as data_t from	
						(select  '1' msgcd , 'Record has been updated successfully' msg ) t 
						);
					
	end if;
	

  return  
		(
		SELECT row_to_json(t)::text as data_t from	
		(select  '0' msgcd , 'Something went wrong. Some parameters are missing. Please check' msg ) t 
		);
END
$BODY$;

ALTER FUNCTION public.usp_update_weekly_off_holiday(character varying, character varying, character varying, character varying, character varying, character varying, character varying)
    OWNER TO payrollingdb;

