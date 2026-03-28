-- FUNCTION: public.usp_manage_shift_policy(character varying, bigint, character varying, character varying, character varying, character varying, character varying, character varying, integer, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, bigint)

-- DROP FUNCTION IF EXISTS public.usp_manage_shift_policy(character varying, bigint, character varying, character varying, character varying, character varying, character varying, character varying, integer, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, bigint);

CREATE OR REPLACE FUNCTION public.usp_manage_shift_policy(
	p_action character varying,
	p_customeraccountid bigint,
	p_shift_name character varying DEFAULT ''::character varying,
	p_from_time character varying DEFAULT ''::character varying,
	p_to_time character varying DEFAULT ''::character varying,
	p_shift_margin character varying DEFAULT ''::character varying,
	p_shift_margin_hours_from character varying DEFAULT ''::character varying,
	p_shift_margin_hours_to character varying DEFAULT ''::character varying,
	p_weekend_id integer DEFAULT 0,
	p_weekend character varying DEFAULT ''::character varying,
	p_is_weekend_working_day character varying DEFAULT 'N'::character varying,
	p_weekend_json character varying DEFAULT ''::character varying,
	p_is_shift_allowance character varying DEFAULT 'N'::character varying,
	p_rate_per_day character varying DEFAULT '0'::character varying,
	p_departmet_json character varying DEFAULT ''::character varying,
	p_mobile_check_in_out_enabled character varying DEFAULT 'Y'::character varying,
	p_calendar_enabled character varying DEFAULT 'Y'::character varying,
	p_working_hrs_json character varying DEFAULT ''::character varying,
	p_enable_multiple_slot character varying DEFAULT 'N'::character varying,
	p_slot_data character varying DEFAULT ''::character varying,
	p_break_policy_json character varying DEFAULT ''::character varying,
	p_userby character varying DEFAULT ''::character varying,
	p_userip character varying DEFAULT ''::character varying,
	p_shift_id bigint DEFAULT NULL::bigint)
    RETURNS TABLE(msgcd character varying, msg character varying) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 10

AS $BODY$
/*************************************************************************************************
SELECT * FROM usp_manage_shift_policy (
    p_action => 'add_shift',
    p_customeraccountid => 653,
    p_shift_name => 'Morning Shift 4',
    p_from_time => '2024-04-19 08:00:00',
    p_to_time => '2024-04-19 14:00:00',
    p_shift_margin => '',
    p_shift_margin_hours_from => '',
    p_shift_margin_hours_to => '',
    p_weekend_id => '0',
    p_weekend => '',
    p_is_weekend_working_day => '',
    p_weekend_json => '',
    p_is_shift_allowance => '',
    p_rate_per_day => '',
    p_departmet_json => '',
    p_mobile_check_in_out_enabled => 'Y',
    p_calendar_enabled => 'N',
    p_working_hrs_json => '{"total_working_hours_calculation": "Y","min_working_hrs_request_mode": "Strict","min_working_hrs_request_mode_type": "Manual","strict_manual_full_day_hrs": "00:00:00","strict_manual_half_day_hrs": "00:00:00","lenient_per_day_hrs": "00:00:00","is_max_hours_required": "Y","max_per_day_hrs": "00:00:00","max_full_day_hrs": "00:00:00","max_half_day_hrs": "00:00:00","is_round_off": "Y","first_checkin_round_off": "00:00:00","last_check_out_round_off": "00:00:00","worked_hours_round_off": "00:00:00"}',
    p_enable_multiple_slot => 'Y',
    p_slot_data => '[{"shift_slot_id":"","shift_id":"","slot_name":"Slot-1","slot_start_time":"10:20","slot_end_time":"11:20","slot_duration":"01:00"},{"shift_slot_id":"","shift_id":"","slot_name":"Slot-2","slot_start_time":"12:20","slot_end_time":"12:40","slot_duration":"00:20"}]',
    p_break_policy_json => '[{"shift_slot_id":"","shift_id":"","slot_name":"Slot-1","slot_start_time":"10:20","slot_end_time":"11:20","slot_duration":"01:00"},{"shift_slot_id":"","shift_id":"","slot_name":"Slot-2","slot_start_time":"12:20","slot_end_time":"12:40","slot_duration":"00:20"}]',
    p_userby => 'teset user',
    p_userip => '::1',
    p_shift_id => NULL
);
*************************************************************************************************
Version     Date			Done_by              Change
1.0		    19-Apr-2024		Parveen Kumar        Initial Version
**************************************************************************************************/
DECLARE
    v_p_shift_id bigint;
    i json;
    r_inner record;
	v_emp_codes TEXT := NULL;

BEGIN
    -- VALIDATIONS START - Common for all actions
        IF NULLIF(p_action, '') IS NULL THEN
            RETURN QUERY SELECT '0' ::varchar, 'MISSING: - Action Type.'::varchar; RETURN;
        END IF;

        IF p_customeraccountid IS NULL THEN
            RETURN QUERY SELECT '0' ::varchar, 'MISSING: - Customer Account ID.'::varchar; RETURN;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM tbl_account WHERE status = '1' AND id = p_customeraccountid::BIGINT) THEN
            RETURN QUERY SELECT '0' ::varchar, 'INVALID: - This account is currently inactive.'::varchar; RETURN;
        END IF;
    -- VALIDATIONS - Common for all actions

    -- START - Add New Shift
        IF p_action = 'add_shift' THEN
            IF NULLIF(p_shift_name, '') IS NULL THEN
                RETURN QUERY SELECT '0' ::varchar, 'MISSING: - Shift Name.'::varchar; RETURN;
            END IF;

            IF NULLIF(p_from_time, '') IS NULL THEN
                RETURN QUERY SELECT '0' ::varchar, 'MISSING: - Shift Start Date.'::varchar; RETURN;
            END IF;

            IF NULLIF(p_to_time, '') IS NULL THEN
                RETURN QUERY SELECT '0' ::varchar, 'MISSING: - Shift End Date.'::varchar; RETURN;
            END IF;

           /* 
		    IF p_to_time::timestamp < p_from_time::timestamp THEN
                RETURN QUERY SELECT '0' ::varchar, 'INVALID: - Shift start time can not be later than the shift end time.'::varchar; RETURN;
            END IF;
			*/

            IF EXISTS (SELECT 1 FROM mst_tp_att_shifts WHERE is_active = '1' AND customeraccountid = p_customeraccountid::BIGINT AND lower(trim(shift_name)) = lower(trim(p_shift_name))) THEN
                RETURN QUERY SELECT '0' ::varchar, 'This shift name you entered already exists.'::varchar; RETURN;
            END IF;

            INSERT INTO mst_tp_att_shifts
            (
                customeraccountid, shift_name, from_time, to_time,
				shift_margin, shift_margin_hours_from, shift_margin_hours_to,
                weekend, is_weekend_working_day, weekend_id, weekend_txt,
				is_shift_allowance, rate_per_day, applicable_for, working_hours_policy,
				mobile_check_in_out_enabled, calendar_enabled,
                created_by, created_date, ipadd_createdby, enable_multiple_slot, break_policy
            )
            VALUES
            (
                p_customeraccountid::BIGINT, p_shift_name, CAST(p_from_time AS timestamp), CAST(p_to_time AS timestamp),
				COALESCE(NULLIF(p_shift_margin, ''), 'N'), NULLIF(p_shift_margin_hours_from, ''), NULLIF(p_shift_margin_hours_to, ''),
                NULLIF(p_weekend, ''), COALESCE(NULLIF(p_is_weekend_working_day, ''), 'N'), p_weekend_id::int, NULLIF(p_weekend_json, ''),
				COALESCE(NULLIF(p_is_shift_allowance, ''), 'N'), NULLIF(p_rate_per_day, ''), NULLIF(p_departmet_json, ''), NULLIF(p_working_hrs_json, ''),
				COALESCE(NULLIF(p_mobile_check_in_out_enabled, ''), 'Y'), COALESCE(NULLIF(p_calendar_enabled, ''), 'Y'),
                p_userby, CURRENT_TIMESTAMP, p_userip, COALESCE(NULLIF(p_enable_multiple_slot, ''), 'N'), NULLIF(p_break_policy_json, '')
            )
            RETURNING shift_id INTO v_p_shift_id;

            IF (COALESCE(NULLIF(p_enable_multiple_slot, ''), 'N') = 'Y' AND v_p_shift_id IS NOT NULL AND p_slot_data <> '' AND p_slot_data <> '[]') THEN
                FOR r_inner IN SELECT * FROM jsonb_populate_recordset(null::record, p_slot_data::jsonb) AS (shift_slot_id varchar, shift_id varchar, slot_name varchar, slot_start_time varchar, slot_end_time varchar, slot_duration varchar) LOOP
                    IF NOT EXISTS (SELECT 1 FROM tbl_shift_slots WHERE customeraccountid = p_customeraccountid::BIGINT AND shift_id = v_p_shift_id::bigint AND status = '1' AND LOWER(slot_name) = LOWER(r_inner.slot_name)) THEN
                        INSERT INTO tbl_shift_slots
                        (
                            shift_id, slot_name, customeraccountid,
                            slot_start_time, slot_end_time, slot_duration,
                            status, created_by, created_ip
                        )
                        VALUES
                        (
                            v_p_shift_id::bigint, r_inner.slot_name, p_customeraccountid::BIGINT,
                            r_inner.slot_start_time, r_inner.slot_end_time, r_inner.slot_duration,
                            '1', p_userby, p_userip
                        );
                    END IF;
                END LOOP;
            END IF;

			IF v_p_shift_id IS NOT NULL THEN
	            RETURN QUERY SELECT '1' ::varchar, 'Shift created successfully.'::varchar; RETURN;
			ELSE
	            RETURN QUERY SELECT '0' ::varchar, 'Unable to craete shift'::varchar; RETURN;
            END IF;
        END IF;
    -- END - Add New Shift

    -- START - Update Shift
        IF p_action = 'update_shift' THEN
            IF p_shift_id IS NULL THEN
                RETURN QUERY SELECT '0' ::varchar, 'MISSING: - Shift ID.'::varchar; RETURN;
            END IF;

            IF EXISTS (SELECT 1 FROM mst_tp_att_shifts WHERE is_active='0' AND shift_id = p_shift_id ORDER BY 1 DESC LIMIT 1) THEN
                RETURN QUERY SELECT '0' ::varchar, 'Apologies, but the shift you are attempting to access is currently inactive.'::varchar; RETURN;
            END IF;

            IF EXISTS (SELECT 1 FROM tbl_account WHERE status = '0' AND id = p_customeraccountid::BIGINT ORDER BY 1 DESC LIMIT 1) THEN
                RETURN QUERY SELECT '0' ::varchar, 'This account is currently inactive. Please try.'::varchar; RETURN;
            END IF;
        
            IF EXISTS (SELECT 1 FROM mst_tp_att_shifts WHERE is_active = '1' AND customeraccountid = p_customeraccountid::BIGINT AND shift_id = p_shift_id ORDER BY 1 DESC LIMIT 1) THEN
                UPDATE mst_tp_att_shifts
                SET
                    shift_name = p_shift_name,
                    from_time = CAST(p_from_time AS timestamp),
                    to_time = CAST(p_to_time AS timestamp),
                    shift_margin = COALESCE(NULLIF(p_shift_margin, ''), 'N'),
                    shift_margin_hours_from = NULLIF(p_shift_margin_hours_from, ''),
                    shift_margin_hours_to = NULLIF(p_shift_margin_hours_to, ''),
                    weekend = NULLIF(p_weekend, ''),
                    is_weekend_working_day = COALESCE(NULLIF(p_is_weekend_working_day, ''), 'N'),
                    weekend_id = p_weekend_id::int,
                    weekend_txt = NULLIF(p_weekend_json, ''),
                    is_shift_allowance = COALESCE(NULLIF(p_is_shift_allowance, ''), 'N'),
                    rate_per_day = NULLIF(p_rate_per_day, ''),
                    applicable_for = NULLIF(p_departmet_json, ''),
                    working_hours_policy = NULLIF(p_working_hrs_json, ''),
                    modified_by = p_userby,
                    modified_date = CURRENT_TIMESTAMP,
                    ipadd_modifiedby = p_userip,
                    enable_multiple_slot = COALESCE(NULLIF(p_enable_multiple_slot, ''), 'N'),
                    break_policy = NULLIF(NULLIF(p_break_policy_json, '[]'), ''),
					mobile_check_in_out_enabled = COALESCE(NULLIF(p_mobile_check_in_out_enabled, ''), 'Y'),
					calendar_enabled = COALESCE(NULLIF(p_calendar_enabled, ''), 'Y')
                WHERE shift_id = p_shift_id AND customeraccountid = p_customeraccountid::BIGINT AND is_active = '1';

				UPDATE tbl_shift_slots
				SET
					status = '0',
					modified_date = CURRENT_TIMESTAMP,
					modified_by = p_userby,
					modified_ip = p_userip
				WHERE shift_id = p_shift_id AND status = '1' AND customeraccountid = p_customeraccountid::BIGINT;					

                IF (COALESCE(NULLIF(p_enable_multiple_slot, ''), 'N') = 'Y' AND p_shift_id IS NOT NULL AND p_slot_data <>'' AND p_slot_data <>'[]') THEN
                    FOR r_inner IN SELECT * FROM jsonb_populate_recordset(null::record,p_slot_data::jsonb) AS ( shift_slot_id varchar,	shift_id varchar, slot_name varchar, slot_start_time  varchar, slot_end_time varchar, slot_duration varchar) LOOP
                        -- raise notice 'r_inner.shift_id=>%', r_inner.shift_id;
                        IF EXISTS (SELECT  1 FROM tbl_shift_slots WHERE customeraccountid = p_customeraccountid::BIGINT AND shift_id = p_shift_id AND status = '1' AND shift_slot_id=nullif(r_inner.shift_slot_id ,'')::bigint) THEN
                            UPDATE tbl_shift_slots
                            SET
                                slot_name = COALESCE(NULLIF(r_inner.slot_name, ''), r_inner.slot_name),
                                slot_start_time = COALESCE(NULLIF(r_inner.slot_start_time, ''),  r_inner.slot_start_time),
                                slot_end_time = COALESCE(NULLIF(r_inner.slot_end_time, ''),  r_inner.slot_end_time),
                                slot_duration = COALESCE(NULLIF(r_inner.slot_duration, ''),  r_inner.slot_duration),
                                modified_date = CURRENT_TIMESTAMP,
                                modified_by = p_userby,	modified_ip = p_userip
                            WHERE shift_slot_id = nullif(r_inner.shift_slot_id ,'')::bigint AND customeraccountid= p_customeraccountid::BIGINT AND status = '1' AND shift_id = p_shift_id;
                        END IF;

                        IF NOT EXISTS (SELECT 1 FROM tbl_shift_slots WHERE customeraccountid = p_customeraccountid::BIGINT AND shift_id = p_shift_id AND status = '1' AND LOWER(slot_name) = LOWER(r_inner.slot_name)) THEN 											
                            INSERT INTO tbl_shift_slots
                            (
                                shift_id, slot_name, customeraccountid,
                                slot_start_time, slot_end_time, slot_duration, status,
                                created_by, created_ip
                            )
                            VALUES
                            (
                                p_shift_id, r_inner.slot_name, p_customeraccountid::BIGINT,
                                r_inner.slot_start_time, r_inner.slot_end_time, r_inner.slot_duration,
                                '1', p_userby, p_userip
                            );
                        END IF;
                    END LOOP;
                END IF;

				-- START - Update Each Employee Policy thats exists into this shift
				    SELECT string_agg(emp_code::TEXT, ',') INTO v_emp_codes
					FROM vw_shifts_emp_wise
					WHERE is_active = '1' AND customeraccountid = p_customeraccountid AND shift_id = p_shift_id;
				
				    IF v_emp_codes IS NOT NULL THEN
				        PERFORM public.usp_save_or_update_candidate_policy(
				            p_action => 'insert_update',
				            p_policy_id => '4'::int, -- Mobile Check In/Out Enable/Disable
				            p_policy_status => p_mobile_check_in_out_enabled::varchar,
				            p_emp_code_list => v_emp_codes::varchar,
				            p_customeraccountid => p_customeraccountid::bigint,
				            p_remarks => 'Update shift settings.',
				            p_record_type => 'Employee',
				            p_user => p_customeraccountid::varchar
				        );

				        PERFORM public.usp_save_or_update_candidate_policy(
				            p_action => 'insert_update',
				            p_policy_id => '5'::int, -- Attendance Calendar Enable/Disable
				            p_policy_status => p_calendar_enabled::varchar,
				            p_emp_code_list => v_emp_codes::varchar,
				            p_customeraccountid => p_customeraccountid::bigint,
				            p_remarks => 'Update shift settings.',
				            p_record_type => 'Employee',
				            p_user => p_customeraccountid::varchar
				        );
				    END IF;
				-- END - Update Each Employee Policy thats exists into this shift

				RETURN QUERY SELECT '1' ::varchar, 'Update Successfully'::varchar; RETURN;
            ELSE
                RETURN QUERY SELECT '0' ::varchar, 'not UPDATE'::varchar  ; RETURN;
            END IF;
        END IF;
    -- END - Update Shift

    -- START - Delete Shift
        IF p_action = 'delete_shift' THEN
            IF p_shift_id IS NULL THEN
                RETURN QUERY SELECT '0' ::varchar, 'MISSING: - Shift ID.'::varchar; RETURN;
            END IF;

            IF EXISTS (SELECT 1 FROM mst_tp_att_shifts WHERE is_active = '0' AND shift_id = p_shift_id ORDER BY 1 DESC LIMIT 1) THEN
                RETURN QUERY SELECT '0' ::varchar, 'Apologies, but the shift you are attempting to access is currently inactive.'::varchar; RETURN;
            END IF;

            IF EXISTS (SELECT 1 FROM mst_tp_att_shifts WHERE is_active = '1' AND customeraccountid = p_customeraccountid::BIGINT AND shift_id = p_shift_id ORDER BY 1 DESC LIMIT 1) THEN
                UPDATE mst_tp_att_shifts
                SET
                    is_active = '0'::BOOLEAN,
                    modified_by = p_userby,
                    modified_date = CURRENT_TIMESTAMP,
                    ipadd_modifiedby = p_userip
                WHERE shift_id = p_shift_id AND customeraccountid = p_customeraccountid::BIGINT AND is_active = '1';

                UPDATE tbl_shift_slots
                SET
                    status = '0',
                    modified_date = CURRENT_TIMESTAMP,
                    modified_by = p_userby,
                    modified_ip = p_userip
                WHERE shift_id = p_shift_id AND status = '1';

                RETURN QUERY SELECT '1' ::varchar, 'Delete Successfully'::varchar; RETURN;
            ELSE
                RETURN QUERY SELECT '0' ::varchar, 'Unable to delete shift'::varchar; RETURN;
            END IF;
        END IF;
    -- END - Delete Shift

	RETURN QUERY SELECT '0' ::varchar, 'invalid parameter input'::varchar; RETURN;
END
$BODY$;

ALTER FUNCTION public.usp_manage_shift_policy(character varying, bigint, character varying, character varying, character varying, character varying, character varying, character varying, integer, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, bigint)
    OWNER TO payrollingdb;

