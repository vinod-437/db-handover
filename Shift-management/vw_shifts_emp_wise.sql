-- View: public.vw_shifts_emp_wise

-- DROP VIEW public.vw_shifts_emp_wise;

CREATE OR REPLACE VIEW public.vw_shifts_emp_wise
 AS
 WITH shift_details AS (
         SELECT shifts.shift_id,
            shifts.shift_name,
                CASE
                    WHEN (shifts.from_time IS NOT NULL OR shifts.to_time IS NOT NULL) AND shifts.to_time < shifts.from_time THEN 'Y'::text
                    ELSE 'N'::text
                END AS is_night_shift,
            shifts.from_time::text AS default_shift_time_from,
            shifts.to_time::text AS default_shift_time_to,
            COALESCE(NULLIF(shifts.shift_margin::text, ''::text), '00:00:00'::text) AS shift_margin,
            COALESCE(NULLIF(shifts.shift_margin_hours_from::text, ''::text), '00:00:00'::text) AS shift_margin_hours_from,
            COALESCE(NULLIF(shifts.shift_margin_hours_to::text, ''::text), '00:00:00'::text) AS shift_margin_hours_to,
            shift_mapping.shiftmapping_id AS setting_id,
            NULL::text AS settings_name,
            shift_mapping.shiftmapping_id AS attendance_policy_id,
            'user_shift_specific'::text AS attendance_policy_type,
            shift_mapping.applicable_for::bigint AS emp_code,
            shift_mapping.customeraccountid,
            shifts.mobile_check_in_out_enabled AS is_mobile_check_in_out_enabled,
            shifts.calendar_enabled,
            NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'total_working_hours_calculation'::text AS total_working_hours_calculation,
            NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'min_working_hrs_request_mode'::text AS min_working_hrs_request_mode,
            NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'min_working_hrs_request_mode_type'::text AS min_working_hrs_request_mode_type,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'strict_manual_full_day_hrs'::text, '00:00:00'::text) AS strict_manual_full_day_hrs,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'strict_manual_half_day_hrs'::text, '00:00:00'::text) AS strict_manual_half_day_hrs,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'lenient_per_day_hrs'::text, '00:00:00'::text) AS lenient_per_day_hrs,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'is_max_hours_required'::text, 'N'::text) AS is_max_hours_required,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'max_per_day_hrs'::text, '00:00:00'::text) AS max_per_day_hrs,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'max_full_day_hrs'::text, '00:00:00'::text) AS max_full_day_hrs,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'max_half_day_hrs'::text, '00:00:00'::text) AS max_half_day_hrs,
            COALESCE(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'is_round_off'::text, 'N'::text) AS is_round_off,
            COALESCE(NULLIF(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'firstcheckin_round_off'::text, ''::text), '0'::text)::integer AS firstcheckin_round_off_minutes,
            COALESCE(NULLIF(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'last_check_out_round_off'::text, ''::text), '0'::text)::integer AS last_check_out_round_off_minutes,
            COALESCE(NULLIF(NULLIF(shifts.working_hours_policy, ''::text)::jsonb ->> 'worked_hours_round_off'::text, ''::text), '0'::text)::integer AS worked_hours_round_off_minutes,
            shifts.break_policy,
            breaks.break_total_time::text AS break_total_time,
            ''::text AS break_pay_type,
            shifts.working_hours_policy,
            shifts.grace_period_policy,
            shifts.penality_policy,
            shifts.exemptions_policy,
            shifts.overtime_policy,
            shifts.is_active,
            row_number() OVER (PARTITION BY (shift_mapping.shift_name_id::bigint) ORDER BY shift_mapping.shiftmapping_id DESC) AS rnk
           FROM mst_tp_att_shiftmapping shift_mapping
             JOIN mst_tp_att_shifts shifts ON shifts.shift_id = shift_mapping.shift_name_id::bigint AND shifts.is_active = true
             LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('break_type', elem.value ->> 'break_type'::text, 'break_type_timing', ((elem.value ->> 'break_start_time'::text) || ' - '::text) || (elem.value ->> 'break_end_time'::text), 'break_type_duration', (EXTRACT(epoch FROM (elem.value ->> 'break_type_duration'::text)::interval) / 60::numeric)::integer || ' Minutes'::text, 'break_type_paid_unpaid', elem.value ->> 'break_type_paid_unpaid'::text)) AS break_total_time
                   FROM jsonb_array_elements(shifts.break_policy::jsonb) elem(value)) breaks ON true
          WHERE shift_mapping.is_active = true AND NULLIF(shift_mapping.applicable_for::text, ''::text) IS NOT NULL
        )
 SELECT shift_id,
    shift_name,
    is_night_shift,
    default_shift_time_from,
    default_shift_time_to,
        CASE
            WHEN default_shift_time_from < default_shift_time_to THEN ((((CURRENT_DATE || ' '::text) || default_shift_time_to)::timestamp without time zone) - (((CURRENT_DATE || ' '::text) || default_shift_time_from)::timestamp without time zone))::text
            ELSE (((((CURRENT_DATE + 1) || ' '::text) || default_shift_time_to)::timestamp without time zone) - (((CURRENT_DATE || ' '::text) || default_shift_time_from)::timestamp without time zone))::text
        END AS default_shift_full_hours,
        CASE
            WHEN default_shift_time_from < default_shift_time_to THEN (((((CURRENT_DATE || ' '::text) || default_shift_time_to)::timestamp without time zone) - (((CURRENT_DATE || ' '::text) || default_shift_time_from)::timestamp without time zone)) / 2::double precision)::text
            ELSE ((((((CURRENT_DATE + 1) || ' '::text) || default_shift_time_to)::timestamp without time zone) - (((CURRENT_DATE || ' '::text) || default_shift_time_from)::timestamp without time zone)) / 2::double precision)::text
        END AS default_shift_half_hours,
    shift_margin,
    shift_margin_hours_from,
    shift_margin_hours_to,
    setting_id,
    settings_name,
    attendance_policy_id,
    attendance_policy_type,
    emp_code,
    customeraccountid,
    is_mobile_check_in_out_enabled,
    calendar_enabled,
    total_working_hours_calculation,
    min_working_hrs_request_mode,
    min_working_hrs_request_mode_type,
    strict_manual_full_day_hrs,
    strict_manual_half_day_hrs,
    lenient_per_day_hrs,
    is_max_hours_required,
    max_per_day_hrs,
    max_full_day_hrs,
    max_half_day_hrs,
    is_round_off,
    firstcheckin_round_off_minutes,
    last_check_out_round_off_minutes,
    worked_hours_round_off_minutes,
    break_total_time,
    break_pay_type,
    break_policy,
    working_hours_policy,
    grace_period_policy,
    penality_policy,
    exemptions_policy,
    overtime_policy,
    is_active
   FROM shift_details
  ORDER BY emp_code;

ALTER TABLE public.vw_shifts_emp_wise
    OWNER TO payrollingdb;

