# Check-in Reprocess Punches Analysis

This document outlines the backend flow and database objects triggered when a user clicks the **Re-Process** or **Advance Re-Process** buttons in the [check-in-by-emp-code.component.html](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/reports/check-in/check-in-by-emp-code/check-in-by-emp-code.component.html) page.

## Frontend to Backend API Mapping

In [check-in-by-emp-code.component.ts](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/reports/check-in/check-in-by-emp-code/check-in-by-emp-code.component.ts), there are two main methods corresponding to the buttons:
1.  [reprocess_punches()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/reports/check-in/check-in-by-emp-code/check-in-by-emp-code.component.ts#659-684)
2.  [advance_reprocess_punches()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/reports/check-in/check-in-by-emp-code/check-in-by-emp-code.component.ts#717-743)

Both methods utilize the [AttendanceService](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/attendance/attendance.service.ts#5-403) to make API calls to the gateway, which then routes them to `HRMSCore`.

---

## 1. Re-Process Attendance

**Frontend Method:** [reprocess_punches()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/reports/check-in/check-in-by-emp-code/check-in-by-emp-code.component.ts#659-684)
**Service Method:** [attendanceProcessEmployeeAttendance()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/attendance/attendance.service.ts#254-257)
**API Endpoint:** `/api/attendance/reProcessEmployeeAttendance`
**API Routing:** Requests to this endpoint in `tpaywfmapi` are directly forwarded to the core engine at `HUB_API_URL + 'TPReProcessAttendance/ReProcessEmployeeAttendance'`.
**Core Engine Controller:** [HRMSCore/Controllers/TPReProcessAttendanceController.cs](file:///c:/Office_Work/Project2021/GitHub_Project_AG/HRMSCore/Controllers/TPReProcessAttendanceController.cs) -> [ReProcessEmployeeAttendance()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/HRMSCore/Models/TPReProcessAttendanceModel.cs#21-44)
**Core Engine Model:** `TPReProcessAttendanceModel.ReProcessEmployeeAttendance()`

### Database Objects Used:
*   **Stored Procedure:** `public.usp_reprocess_employee_attendance`

### Tables, Views, and Nested Functions used in the procedure:
*   **`openappointments`**: Used to verify if the employee is currently active and mapped to the customer.
*   **`cmsdownloadedwages`**: Used to verify if the salary has already been generated for the month (halts reprocessing if it has).
*   **`tbl_attendance`**: Queried to fetch the raw daily `check_in_time` and `check_out_time` for the employee.
*   **`tbl_monthly_attendance`**: The primary table being updated or inserted into. The exact row for the specific date is either updated with newly calculated values or inserted if missing.
*   **`vw_shifts_emp_wise`**: A view used to check if the employee currently has an active shift/policy mapping.
*   **`public.calculate_advance_employee_attandance_policy()`**: Nested database function called to recalculate attendance fields if advanced shift logic is detected.
*   **`public.calculate_employee_attandance_policy()`**: Nested database function called for standard policy calculations.

---

## 2. Advance Re-Process Attendance

**Frontend Method:** [advance_reprocess_punches()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/reports/check-in/check-in-by-emp-code/check-in-by-emp-code.component.ts#717-743)
**Service Method:** [attendanceAdvanceProcessEmployeeAttendance()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/attendance/attendance.service.ts#347-350)
**API Endpoint:** `/api/attendance/reProcessEmployeeAttendanceAdvance`
**API Routing:** Requests to this endpoint in `tpaywfmapi` are directly forwarded to the core engine at `HUB_API_URL + 'TPReProcessAttendance/ReProcessEmployeeAttendanceAdvance'`.
**Core Engine Controller:** [HRMSCore/Controllers/TPReProcessAttendanceController.cs](file:///c:/Office_Work/Project2021/GitHub_Project_AG/HRMSCore/Controllers/TPReProcessAttendanceController.cs) -> [ReProcessEmployeeAttendanceAdvance()](file:///c:/Office_Work/Project2021/GitHub_Project_AG/HRMSCore/Models/TPReProcessAttendanceModel.cs#45-68)
**Core Engine Model:** `TPReProcessAttendanceModel.ReProcessEmployeeAttendanceAdvance()`

### Database Objects Used:
*   **Stored Procedure:** `public.usp_reprocess_employee_attendance_advance`

### Tables, Views, and Nested Functions used in the procedure:
*(Note: The structure and tables queried are practically identical to the standard reprocess function, but handled by a dedicated [advance](file:///c:/Office_Work/Project2021/GitHub_Project_AG/tankhapay-web/src/app/modules/shift-management/shift-manage/shift-manage.component.ts#791-794) procedure specifically tailored for advanced logic cases.)*
*   **`openappointments`**
*   **`cmsdownloadedwages`**
*   **`tbl_attendance`**
*   **`tbl_monthly_attendance`** (Main insert/update target)
*   **`vw_shifts_emp_wise`**
*   **`public.calculate_advance_employee_attandance_policy()`**
*   **`public.calculate_employee_attandance_policy()`**

---

## Summary

When either button is clicked:
1. The frontend gathers the target dates and employee codes.
2. The payload traverses through the API gateway (`tpaywfmapi`) and reaches the core processing engine (`HRMSCore`).
3. `HRMSCore` invokes the relevant PostgreSQL stored procedure (`usp_reprocess_employee_attendance` or `usp_reprocess_employee_attendance_advance`).
4. The database procedure fetches the raw timestamps from `tbl_attendance`, computes applying policies via sub-functions like `calculate_advance_employee_attandance_policy`, and finally upserts the summarized daily record into **`tbl_monthly_attendance`**.
