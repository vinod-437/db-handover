# Shift Management Component Analysis

This document provides a comprehensive breakdown of the backend procedures, functions, and tables used by the frontend [shift-manage.component.html](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/shift-management/shift-manage/shift-manage.component.html) in the `tankhapay-web` application.

## Frontend to Backend API Mapping

The [shift-manage.component.html](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/shift-management/shift-manage/shift-manage.component.html) and its associated TypeScript file ([shift-manage.component.ts](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/shift-management/shift-manage/shift-manage.component.ts)) use the [ShiftManagementService](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/shift-management/shift-management.service.ts#7-30) and [ShiftDetailService](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/attendance/shift-detail.service.ts#6-56) to interact with the backend APIs. Three key API endpoints were identified in [constants.ts](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/shared/helpers/constants.ts):

1.  **Get Master Shift Details:** `/api/shift/getMasterShift`
2.  **Save/Update Shift details:** `/api/shift/saveUpdateShiftDetail`
3.  **Update Shift Policy Details:** `/api/attendancePolicy/UpdateShiftPolicyDetails`

*(Note: These requests are routed through the `tpaywfmapi` gateway to the core `tpay-business-hub-api` or `HRMSCore` depending on the exact route).*

---

## 1. Get Master Shift Data

**Frontend Source:** `constants.getMasterShift_url_new`
**Endpoint:** `/api/shift/getMasterShift`
**Backend Controller:** [tpay-business-hub-api/src/controllers/shift-management/shift-management.js](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tpay-business-hub-api/src/controllers/shift-management/shift-management.js) 
**Method:** [getMasterShift()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/shift-management/shift-management.service.ts#19-22)

### Database Objects Used:
*   **Stored Procedure / Function:** `public.usp_master_data_node`

This function is a comprehensive master data retrieval function that returns lists of options based on a `p_action` parameter (e.g., fetching grace period rules, attendance types, department lists).

### Tables Queried in `usp_master_data_node`:
*   `mst_attendance_modes`
*   `mst_attendance_leave_codes`
*   `trn_attendance_codes`
*   `mst_tp_att_departments`
*   `tbl_contractors`
*   `tbl_contractors_labour_rates`
*   `mst_approval_module`

---

## 2. Save / Update Shift Details

**Frontend Source:** `constants.saveUpdateShiftDetail_url`
**Endpoint:** `/api/shift/saveUpdateShiftDetail`
**Backend Controller:** [tpay-business-hub-api/src/controllers/shift-management/shift-management.js](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tpay-business-hub-api/src/controllers/shift-management/shift-management.js)
**Method:** [saveUpdateShiftDetail()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/shift-management/shift-management.service.ts#22-25)

### Database Objects Used:
*   **Stored Procedure / Function:** `public.usp_manage_shift_policy`
*   **Nested Database Function:** `public.usp_save_or_update_candidate_policy`
*   **Nested View:** `public.vw_shifts_emp_wise`

This procedure handles the core logic for creating new shifts (`add_shift`), updating existing shifts (`update_shift`), and soft-deleting shifts (`delete_shift`), including setting up shift slots and updating candidate policies.

### Tables / Views Used in `usp_manage_shift_policy` & nested functions:
*   `tbl_account` (Data Validation)
*   `mst_tp_att_shifts` (Main shift table — Insert / Update)
*   `tbl_shift_slots` (Shift slot details — Insert / Update)
*   `vw_shifts_emp_wise` (View used to fetch all employees mapped to a shift, references `mst_tp_att_shiftmapping` and `mst_tp_att_shifts`)
*   `mst_candidates_policies` (Lookups within nested policy function)
*   `tbl_candidates_policies` (Employee policy data — Insert / Update)

---

## 3. Update Shift Policy Details

**Frontend Source:** `constants.updateShiftPolicyDetails_url`
**Endpoint:** `/api/attendancePolicy/UpdateShiftPolicyDetails`
**Backend Controller:** [tpay-business-hub-api/src/controllers/attendance/attendancePolicyController.js](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tpay-business-hub-api/src/controllers/attendance/attendancePolicyController.js)
**Method:** [UpdateShiftPolicyDetails()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tpay-business-hub-api/src/controllers/attendance/attendancePolicyController.js#582-629)

### Database Objects Used:
*   **Stored Procedure / Function:** `public.usp_update_shift_policies`

This function is responsible for selectively updating the policy configurations (JSON objects) associated with a shift, such as the grace period, penalty, exemptions, and overtime policies.

### Tables Used in `usp_update_shift_policies`:
*   `mst_tp_att_shifts` (Updates the `grace_period_policy`, `penality_policy`, `exemptions_policy`, or `overtime_policy` fields based on the `p_action` argument)

---

## Summary of Key Database Tables Identified

If you are looking specifically at the relational data structure supporting the shift module, these are the core tables:

1.  **`mst_tp_att_shifts`**: The central table storing all shift configurations, timings, margin rules, and related JSON policy blobs.
2.  **`tbl_shift_slots`**: Stores detailed timeslot data for multiple-slot shifts.
3.  **`mst_tp_att_shiftmapping`**: Maps specific shifts to users/employees (accessed via the `vw_shifts_emp_wise` view).
4.  **`tbl_candidates_policies` / `mst_candidates_policies`**: Stores specific candidate-level feature enablement configs (like mobile push-in/app tracking) related to shifts.
5.  **`mst_tp_att_departments` & `mst_attendance_modes`**: Source tables for the dropdown values seen in the component.
