-- FUNCTION: public.usp_master_data_node(text, bigint)

-- DROP FUNCTION IF EXISTS public.usp_master_data_node(text, bigint);

CREATE OR REPLACE FUNCTION public.usp_master_data_node(
	p_action text,
	p_customer_account_id bigint DEFAULT '-9999'::bigint)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
/*************************************************************************
Version    Date			    Done_by				Change
1.0		   21-Jun-2025		Vinod Kumar		Initial Version
1.1		   22-July-2025		Parveen Kumar		Add GraceMaster
1.2		   25-Sept-2025		Parveen Kumar		Add AttendanceCodesMaster, LeavesCodesMaster, AttendanceLeavesCodesMaster
1.3		   13-Nov-2025		Parveen Kumar		Add GetDepartmentList
1.4		   25-Nov-2025		Shiv Kumar			Add Deduction Heads
*************************************************************************/

/***************************|| Response Details ||***************************
0 - Record not found
1 - success and return List
2 - success and return object

SELECT * FROM public.usp_master_data_node(p_action => 'GraceMaster'::text)
SELECT * FROM public.usp_master_data_node(p_action => 'AttendanceCodesMaster'::text, p_customer_account_id => '653'::bigint)
SELECT * FROM public.usp_master_data_node(p_action => 'AttendanceCodesMaster'::text)
************************************************************************/

DECLARE
	-- response refcursor;
	v_advicemonthjson  text;

BEGIN
/************************Change 1.4 starts**********************************************/

	IF p_action = 'GetDeductionHeads' THEN

	return 	(

			SELECT json_build_object(
			    'status', t.status,
			    'msg', t.msg,
			    'common_data', t.common_data
			)
			
				FROM (	SELECT '1' status,'Deduction heads fetched successfully.' AS msg,
						response_data.details common_data
			FROM
			(
				SELECT
					json_agg
					(
						json_build_object
						(
							'headname', headname,
							'headvalue', headvalue
						)
					) details
				FROM (
							SELECT 'PF' as headname,'PF' as headvalue
							union all
							SELECT 'ESIC' as headname,'ESIC' as headvalue
							union all
							SELECT 'TDS' as headname,'TDS' as headvalue
							union all
							SELECT 'GROUP INSURANCE' as headname,'GROUP INSURANCE' as headvalue
						)tmp
			) response_data ) t );
	END IF;
/************************Change 1.4 ends**********************************************/

	-- SIDDHARTH BANSAL 07/06/2024
	IF p_action = 'GetValidActions' THEN
		RETURN
		(
			SELECT array_to_json(array_agg(row_to_json(t)))::text as data_t
			FROM (
				SELECT
					1 AS status, 'Valid Actions fetch successfully.' AS msg,
					json_build_array
					(
						json_build_object('shortCode', 'GetValidActions', 'Description', 'GetValidActions'),
						json_build_object('shortCode', 'GetAllPaymentPurposes', 'Description', 'GetAllPaymentPurposes'),
						json_build_object('shortCode', 'GetTicketsStatus', 'Description', 'GetTicketsStatus'),
						json_build_object('shortCode', 'getreimbursementfilter', 'Description', 'getreimbursementfilter'),
						json_build_object('shortCode', 'Reimbursement', 'Description', 'Reimbursement'),
						json_build_object('shortCode', 'GetAttendanceTypes', 'Description', 'GetAttendanceTypes'),
						json_build_object('shortCode', 'FaceCheckInstructions', 'Description', 'FaceCheckInstructions'),
						json_build_object('shortCode', 'MasterJobTypes', 'Description', 'MasterJobTypes'),
						json_build_object('shortCode', 'GetPayoutDaysDetails', 'Description', 'GetPayoutDaysDetails'),
						json_build_object('shortCode', 'GetAdviceMonths', 'Description', 'GetAdviceMonths'),
						json_build_object('shortCode', 'GetOrganisationWorkingDays', 'Description', 'GetOrganisationWorkingDays'),
						json_build_object('shortCode', 'GetMeetingsAndFeedbacks', 'Description', 'GetMeetingsAndFeedbacks'),
						json_build_object('shortCode', 'GetMasterExitTypes', 'Description', 'GetMasterExitTypes'),
						json_build_object('shortCode', 'LetterTemplateCategories', 'Description', 'LetterTemplateCategories'),
						json_build_object('shortCode', 'GetEmployerEmployessRegisteredFaces', 'Description', 'GetEmployerEmployessRegisteredFaces'),
						json_build_object('shortCode', 'GetPostingDepartments', 'Description', 'GetPostingDepartments'),
						json_build_object('shortCode', 'GetMasterPostOffered', 'Description', 'GetMasterPostOffered'),
						json_build_object('shortCode', 'GetMasterUnitNames', 'Description', 'GetMasterUnitNames'),
						json_build_object('shortCode', 'JoiningsExceptionStatus', 'Description', 'JoiningsExceptionStatus'),
						json_build_object('shortCode', 'AttendanceTicketStages', 'Description', 'AttendanceTicketStages'),
						json_build_object('shortCode', 'PayrollProcessTypes', 'Description', 'PayrollProcessTypes'),
						json_build_object('shortCode', 'MonthwiseOnboardEmployeeCount', 'Description', 'MonthwiseOnboardEmployeeCount'),
						json_build_object('shortCode', 'AttendanceCodesMaster', 'Description', 'AttendanceCodesMaster'),
						json_build_object('shortCode', 'LeavesCodesMaster', 'Description', 'LeavesCodesMaster'),
						json_build_object('shortCode', 'AttendanceLeavesCodesMaster', 'Description', 'AttendanceLeavesCodesMaster'),
						json_build_object('shortCode', 'GetDepartmentList', 'Description', 'GetDepartmentList'),
						json_build_object('shortCode', 'GetContractorsList', 'Description', 'GetContractorsList')
					) AS common_data 
			) t
		);
	END IF;

	IF p_action = 'GetAttendanceTypes' THEN
			return 	(
								SELECT array_to_json(array_agg(row_to_json(t)))::text as data_t

									FROM ( SELECT
				CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
				CASE WHEN response_data.details IS NULL THEN 'Attendance type not found.' ELSE 'Attendance type details fetched successfully.' END AS msg,
				response_data.details common_data
			FROM
			(
				SELECT
					json_agg
					(
						json_build_object
						(
							'id', COALESCE(id::TEXT, ''),
							'attendance_type', COALESCE(attendance_type::TEXT, ''),
							'attendance_type_desc', COALESCE(attendance_type_desc::TEXT, '')
						)
					) details
				FROM mst_attendance_modes
				WHERE isactive = '1'
			) response_data ) t 
			);
	END IF;

	IF p_action = 'GraceMaster' THEN
		return (
			SELECT json_build_object(
				'status', 1,
				'msg', 'Grace Master fetched successfully.',
				'common_data', json_build_object(
					'deviation_type_master', (
						SELECT json_agg(json_build_object('value', value, 'label', label))
						FROM (
						VALUES
							('check-in', 'First check-in is late by'),
							('check-out', 'Last check-out is early by'),
							('monthly-hours', 'Monthly Hours')
					  	) AS deviation_type_master(value, label)
					),
					'reset_period_master', (
					  	SELECT json_agg(json_build_object('value', value, 'label', label))
					  	FROM (
							VALUES
							('monthly', 'Monthly'),
							('weekly', 'Weekly'),
							('quarterly', 'Quarterly'),
							('yearly', 'Yearly')
					  	) AS reset_period_master(value, label)
					),
					'ot_calculation_mode', (
					  	SELECT json_agg(json_build_object('value', value, 'label', label))
					  	FROM (
							VALUES
								('daily', 'Daily'),
								('weekly', 'Weekly'),
								('bi-monthly', 'Bi-Monthly'),
								('monthly', 'Monthly')
						  ) AS ot_calculation_mode(value, label)
					),
					'grace_master', (
					  	SELECT json_agg(json_build_object('label', label, 'description', description))
					  	FROM (
							VALUES
						  	('Bad Weather Extension', 'Additional grace during bad weather'),
						  	('Public Transport Delays', 'Additional grace for transport delays'),
						  	('New Employee Grace', 'Multiplier for new employee grace period'),
						  	('Medical Appointments', 'Extended grace with prior approval'),
						  	('Post-Overtime Grace', 'Additional grace after overtime shifts')
					  	) AS grace_master(label, description)
					),
					'penalty_type_master', (
					  	SELECT json_agg(json_build_object('value', value, 'label', label))
					  	FROM (
							VALUES
							('fixed_amount', 'Fixed Amount Only'),
							('per_minute', 'Per Minute Only'),
							('time_deduction', 'Time Deduction in Quarters (Qtrs)'),
							('same_as_ot_config', 'Same as OT Config'),
							('leave', 'Leave Deduction')
					  	) AS penalty_type_master(value, label)
					),
					'time_deduction_master', (
					  	SELECT json_agg(json_build_object('value', value, 'label', label))
					  	FROM (
							VALUES
							('0.5', '0.5 Qtrs'),
							('1', '1 Qtrs'),
							('1.5', '1.5 Qtrs'),
							('2', '2 Qtrs'),
							('2.5', '2.5 Qtrs'),
							('3', '3 Qtrs'),
							('3.5', '3.5 Qtrs')
					  	) AS time_deduction_master(value, label)
					),
					'deduction_from_master', (
					  	SELECT json_agg(json_build_object('value', value, 'label', label))
					  	FROM (
							VALUES
						  	('salary', 'Salary')
					  	) AS deduction_from_master(value, label)
					),
					'rounding_master', (
						SELECT json_agg(json_build_object('value', value, 'label', label))
						FROM (
							VALUES
								('', 'Select time rounding'),
								('5', '5 minutes'),
								('15', '15 minutes'),
								('30', '30 minutes')
						) AS rounding_master(value, label)
					),
					'rate_multiplier_master', (
						SELECT json_agg(json_build_object('value', value, 'label', label))
						FROM (
							VALUES
								('', 'Select rate Multiplier'),
								('1', '1x (0% extra)'),
								('1.5', '1.5x (50% extra)'),
								('1.75', '1.75x (75% extra)'),
								('2', '2x (100% extra)'),
								('2.5', '2.5x (125% extra)')
						) AS rate_multiplier_master(value, label)
					),
					'pay_on_salary_heads', (
						SELECT json_agg(json_build_object('value', value, 'label', label))
						FROM (
							VALUES
								('fixed_amount', 'Fixed Amount Only'),
								('gross', 'Gross Salary'),
								('ctc', 'CTC'),
								('salaryinhand', 'Salary In-Hand'),
								('monthlyofferedpackage', 'Monthly Offered Package')
						) AS rate_multiplier_master(value, label)
					),
					'weekdays_master', (
						SELECT json_agg(json_build_object('value', value, 'label', label))
						FROM (
							VALUES
							('Monday', 'Monday'),
							('Tuesday', 'Tuesday'),
							('Wednesday', 'Wednesday'),
							('Thursday', 'Thursday'),
							('Friday', 'Friday'),
							('Saturday', 'Saturday'),
							('Sunday', 'Sunday')
						) AS weekdays_master(value, label)
					),
					'exemptions_master', (
						SELECT
							json_agg(
								json_build_object(
								   'approval_module_id', approval_module_id,
								   'approval_module_name', approval_module_name,
								   'approval_module_name_desc', approval_module_name_desc,
								   'master_module_name', master_module_name,
								   'workflow_type', workflow_type
							   	)
						   ) AS result_json
						FROM mst_approval_module
						WHERE status = '1' AND master_module_name = 'Shift Management'
					),
					'leave_deduction', (
						SELECT json_agg(json_build_object('value', value, 'label', label))
						FROM (
							VALUES
								('', 'Select leave deduction'),
								('0.5', 'Half Day'),
								('1', 'Full Day')
						) AS leave_deduction(value, label)
					)
				)
			)::text AS data_t
		);
	END IF;

	IF p_action = 'FaceCheckInstructions' THEN
		return 	(
								SELECT array_to_json(array_agg(row_to_json(t)))::text as data_t

									FROM (	SELECT
				CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
				CASE WHEN response_data.details IS NULL THEN 'Face check instructions not found.' ELSE 'Face check instructions details fetched successfully.' END AS msg,
				response_data.details common_data
			FROM
			(
				SELECT
					json_agg
					(
						json_build_object
						(
							'id', COALESCE(id::TEXT, ''),
							'facecheck_instructions', COALESCE(facecheck_instructions::TEXT, ''),
							'instructions_details', COALESCE(instructions_details::TEXT, '')
						)
					) details
				FROM tbl_facecheck_instructions
				WHERE isactive = '1'
			) response_data ) t );
	END IF;

	IF p_action = 'LeavesCodesMaster' THEN
		return 	(
			SELECT json_build_object(
			    'status', t.status,
			    'msg', t.msg,
			    'common_data', t.common_data
			)
			FROM (
			    SELECT
			        CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
			        CASE WHEN response_data.details IS NULL THEN 'Attendance & Leaves codes master not found.' ELSE 'Attendance & Leaves codes master details fetched successfully.' END AS msg,
			        response_data.details AS common_data
			    FROM (
			        SELECT
			            json_agg(
			                json_build_object(
			                    'id', id,
			                    'code', code,
			                    'display_code', display_code,
			                    'name', name,
			                    'description', description,
			                    'font_color', font_color,
			                    'background_color', background_color,
			                    'category', category
			                )
			            ) AS details
			        FROM mst_attendance_leave_codes
					WHERE is_active = true AND category = 'Leave'
			    ) AS response_data
			) AS t
		);
	END IF;

	IF p_action = 'AttendanceCodesMaster' THEN
		return 	(
			SELECT json_build_object(
			    'status', t.status,
			    'msg', t.msg,
			    'common_data', t.common_data
			)
			FROM (
			    SELECT
			        CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
			        CASE WHEN response_data.details IS NULL THEN 'Attendance & Leaves codes master not found.' ELSE 'Attendance & Leaves codes master details fetched successfully.' END AS msg,
			        response_data.details AS common_data
			    FROM (
			        SELECT json_agg(
			           json_build_object(
			               'id', id,
			               'code', code,
			               'display_code', display_code,
			               'name', name,
			               'description', description,
			               'font_color', font_color,
			               'background_color', background_color,
			               'category', category,
			               'action_type', action_type
			           )
			       	) AS details
					FROM (
					    SELECT
					        id, code, display_code, name, description,
					        font_color, background_color, category, 'UpdateAttendanceCodes' action_type
					    FROM trn_attendance_codes
					    WHERE is_active = true AND category = 'Attendance' AND customer_account_id = p_customer_account_id

					    UNION ALL
					    SELECT
					        -9999 id, m.code, m.display_code, m.name, m.description,
					        m.font_color, m.background_color, m.category, 'AddAttendanceCodes' AS action_type
					    FROM mst_attendance_leave_codes m
					    WHERE m.is_active = true AND m.category = 'Attendance'
					      AND NOT EXISTS (
					          SELECT 1
					          FROM trn_attendance_codes t
					          WHERE t.is_active = true AND t.category = 'Attendance' AND t.customer_account_id = p_customer_account_id AND t.code = m.code
					      )
					) AS combined
			    ) AS response_data
			) AS t
		);
	END IF;

	IF p_action = 'AttendanceLeavesCodesMaster' THEN
		return 	(
			SELECT json_build_object(
			    'status', t.status,
			    'msg', t.msg,
			    'common_data', t.common_data
			)
			FROM (
			    SELECT
			        CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
			        CASE WHEN response_data.details IS NULL THEN 'Attendance & Leaves codes master not found.' ELSE 'Attendance & Leaves codes master details fetched successfully.' END AS msg,
			        response_data.details AS common_data
			    FROM (
			        SELECT
			            json_agg(
			                json_build_object(
			                    'id', id,
			                    'code', code,
			                    'display_code', display_code,
			                    'name', name,
			                    'description', description,
			                    'font_color', font_color,
			                    'background_color', background_color,
			                    'category', category
			                )
			            ) AS details
			        FROM mst_attendance_leave_codes
					WHERE is_active = true
			    ) AS response_data
			) AS t
		);
	END IF;

	IF p_action = 'GetDepartmentList' THEN
		RETURN
		(
			SELECT json_build_object(
			    'status', t.status,
			    'msg', t.msg,
			    'common_data', t.common_data
			)
			FROM
			(
				SELECT
					CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
					CASE WHEN response_data.details IS NULL THEN 'Department not found.' ELSE 'Departments details fetched successfully.' END AS msg,
					response_data.details common_data
				FROM
				(
					SELECT
						json_agg
						(
							json_build_object
							(
								'id', COALESCE(id::TEXT, ''),
								'department_name', COALESCE(departmentname::TEXT, ''),
								'department_description', COALESCE(departmentdescription::TEXT, '')
							)
						) details
					FROM mst_tp_att_departments
					WHERE customeraccountid = p_customer_account_id AND isactive = '1' AND organization_unit_id IS NULL
				) response_data
			) t 
		);
	END IF;

	IF p_action = 'GetContractorsList' THEN
		RETURN
		(
			SELECT json_build_object(
			    'status', t.status,
			    'msg', t.msg,
			    'common_data', t.common_data
			)
			FROM
			(
				SELECT
					CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
					CASE WHEN response_data.details IS NULL THEN 'Contractors not found.' ELSE 'Contractors details fetched successfully.' END AS msg,
					response_data.details common_data
				FROM
				(
					SELECT
						json_agg
						(
							json_build_object
							(
								'contractor_id', COALESCE(id::TEXT, ''),
								'contractor_name', COALESCE(contractor_name::TEXT, ''),
								'mobile', COALESCE(mobile::TEXT, ''),
								'email', COALESCE(email::TEXT, ''),
								'address', COALESCE(address::TEXT, ''),
								'status', CASE WHEN is_active = '0' THEN 'Inactive' WHEN is_active = '1' THEN 'Active' ELSE '' END,
								'created_by', COALESCE(created_by::TEXT, ''),
								'created_on', COALESCE(TO_CHAR((created_on + INTERVAL '5 HOURS 30 MINUTES'), 'dd/mm/yyyy HH24:MI:SS')::TEXT, ''),
								'modified_by', COALESCE(modified_by::TEXT, ''),
								'modified_on', COALESCE(TO_CHAR((modified_on + INTERVAL '5 HOURS 30 MINUTES'), 'dd/mm/yyyy HH24:MI:SS')::TEXT, '')
							)
						) details
					FROM tbl_contractors
					WHERE customeraccountid = p_customer_account_id AND is_active = '1'
				) response_data
			) t 
		);
	END IF;

	IF p_action = 'GetContractorsListWithDetails' THEN
		RETURN
		(
			SELECT json_build_object(
			    'status', t.status,
			    'msg', t.msg,
			    'common_data', t.common_data
			)
			FROM
			(
				SELECT
					CASE WHEN response_data.details IS NULL THEN 0 ELSE 1 END AS status,
					CASE WHEN response_data.details IS NULL THEN 'Contractors not found.' ELSE 'Contractors details fetched successfully.' END AS msg,
					response_data.details common_data
				FROM
				(
					SELECT
						json_agg(
							json_build_object(
								'contractor_id', COALESCE(tc.id::TEXT, ''),
								'contractor_name', COALESCE(tc.contractor_name::TEXT, ''),
								'mobile', COALESCE(tc.mobile::TEXT, ''),
								'email', COALESCE(tc.email::TEXT, ''),
								'address', COALESCE(tc.address::TEXT, ''),
								'status', CASE WHEN tc.is_active = '0' THEN 'Inactive' WHEN tc.is_active = '1' THEN 'Active' ELSE '' END,
								'created_by', COALESCE(tc.created_by::TEXT, ''),
								'created_on', COALESCE(TO_CHAR((tc.created_on + INTERVAL '5 HOURS 30 MINUTES'), 'dd/mm/yyyy HH24:MI:SS'), ''),
								'modified_by', COALESCE(tc.modified_by::TEXT, ''),
								'modified_on', COALESCE(TO_CHAR((tc.modified_on + INTERVAL '5 HOURS 30 MINUTES'), 'dd/mm/yyyy HH24:MI:SS'), ''),
								'labour_types', COALESCE(lr.labour_types, ''),
								'labour_configuration', COALESCE(lr.workers_count, 0) || ' rates configured',
								'rate_range', COALESCE(lr.rate_range, ''),
								'workers_count', COALESCE(lr.workers_count, 0),
								'days_count', COALESCE(lr.days_count, 0)
							)
						) AS details
					FROM tbl_contractors tc
					LEFT JOIN LATERAL (
						SELECT
							STRING_AGG(
								CASE 
							        WHEN labour_type = 'Other' AND labour_type_custom_name IS NOT NULL 
							            THEN labour_type || ' (' || labour_type_custom_name || ')'
							        ELSE labour_type
							    END, ', ' ORDER BY labour_type
							) AS labour_types,
							'₹' || MIN(daily_rate)::TEXT || ' - ₹' || MAX(daily_rate)::TEXT AS rate_range,
							COUNT(*) AS workers_count,
							COUNT(DISTINCT DATE(created_on)) AS days_count
						FROM tbl_contractors_labour_rates tclr
						WHERE tclr.is_active = TRUE AND tclr.customeraccountid = tc.customeraccountid AND tc.id = tclr.contractor_id
					) lr ON TRUE
					WHERE customeraccountid = p_customer_account_id -- AND is_active = '1'
				) response_data
			) t 
		);
	END IF;

	EXCEPTION WHEN OTHERS THEN 
		RETURN (
			SELECT
				array_to_json(array_agg(row_to_json(t)))::text as data_t
			FROM (
        		SELECT -1 status, 'An error occurred: ' || SQLERRM msg
			) t
		);
END;
$BODY$;

ALTER FUNCTION public.usp_master_data_node(text, bigint)
    OWNER TO payrollingdb;

