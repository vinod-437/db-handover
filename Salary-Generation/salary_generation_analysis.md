# Salary Generation Analysis

This report provides an analysis of the tables and functions found in the `C:\Office_Work\Project2021\GitHub_Project_AG\db-handover\Salary-Generation` folder. This module is responsible for calculating employee wages, compliance deductions (PF, ESI, TDS, LWF), overtime (OT), tea allowances, and maintaining the processed payroll state.

## 1. Tables

### 1.1 `paymentadvice.table.sql`
- **Purpose**: Creates the `public.paymentadvice` table. This serves as the preliminary/staging table for salary processing before it is locked and finalized. It holds a very wide range of columns mapping out an employee's detailed monthly payroll.
- **Key Columns**:
  - **Employee Details**: `emp_code`, `emp_name`, `dateofjoining`, `pancard`, `pfnumber`, `uannumber`, `esinumber`, etc.
  - **Calculated Days**: `paiddays`, `monthdays`, `totalleavetaken`, `lossofpay`.
  - **Earings/Rates**: `ratebasic`, `ratehra`, `basic`, `hra`, `specialallowance`, `incentive`, `bonus`, `grossearning`, `advance`.
  - **Deductions**: `epf`, `vpf`, `tds`, `loan`, `lwf`, `grossdeduction`, `netpay`.
  - **Employer Contributions**: `ac_1`, `ac_10`, `ac_2`, `ac21` (various PF admin/pension accounts), `employeresirate`.
  - **Status**: `lockstatus` (Locked, Unlocked, Rejected), `is_workflow_approved`, `advicelockstatus`.
- **Primary Key**: Composite key `(emp_code, mprmonth, mpryear, salaryid, batch_no, multipayoutrequestid)`.

### 1.2 `tbl_monthlysalary.table.sql`
- **Purpose**: Creates the `public.tbl_monthlysalary` table. This is the finalized counterpart to `paymentadvice`. It stores the approved, locked, and disbursed monthly salary history for employees. It mirrors most of the columns of `paymentadvice` but adds fields for tracking historical processes like arrears, vouchers, disbursement status, rejection status, and HR generation timestamps.
- **Key Columns**:
  - Mirror of `paymentadvice` columns for earnings, deductions, and employee demographic data.
  - **Audit & Metadata**: `createdby`, `createdon`, `modifiedon`, `rejected_by`, `rejected_on`, `hrgeneratedon`, `salarydownloadedon`.
  - **Arrear Specifics**: `isarear`, `isarearprocessed`, `incrementarear`, `totalarear`, `arearids`, `account1_7q_dues` (dues for delay), etc.
- **Primary Key**: `id` (bigint identity column).

---

## 2. Functions

### 2.1 `uspwagesfromattendance_pregenerate`
- **Purpose**: Acts as an entry point for processing wages based directly on attendance logs (`tbl_monthly_attendance`). It prepares the parameters (e.g., determining calculating "paid days" or "loss of pay") and invokes a deeper calculation function to "pre-generate" the advice.
- **Core Logic**:
  - Calculates start/end dates for calculations correctly aligned with custom or forward/backward month directions using `mst_account_custom_month_settings`.
  - Parses strict/lenient shift minutes, unpaid breaks, and manually input shift hours.
  - Sums up hours worked (`no_of_hours_worked`) to establish `v_paiddays` and `v_leavetaken`.
  - Pours this data into a temporary/working table (`pg_temp.cmsdownloadedwages_pregenerate`).
  - Converts variables to a JSON string `v_advice_attendancerecord` and passes execution to `uspgetorderwisewages_pregenerate`.

### 2.2 `uspgetorderwisewages_pregenerate.function.sql`
- **Purpose**: A heavy-duty calculation engine designed to execute against a temporary table (`cmsdownloadedwages_pregenerate`) for preview purposes before saving into `paymentadvice` or when simulating a payout.
- **Core Logic**:
  - Over 1900 lines of complex calculations involving almost every sub-component of Indian Payroll (PF, ESI, PT, LWF, Overtime).
  - Handles complex conditional checks for EPF/ESI calculation based on limits (e.g., `pfcapapplied`, 15,000 threshold), employer contributions (Accounts 1, 10, 2, 21).
  - Incorporates dynamic, user-specific configurations for Tea allowance, overtime caps, weekend consecutive overtime rules (`tbl_tp_ot_rules_trn`), delayed/fines parsing (Early Leave / Late Come).
  - Selects data merging Employee Salary Master (`empsalaryregister`), Arrears, Deductions (`trn_candidate_otherduction`), and Overtime into massive flat records predicting `GrossEarning`, `GrossDeduction` and `NetPay`.

### 2.3 `uspgetorderwisewages.function.sql`
- **Purpose**: Very similar to the `_pregenerate` script, but processes "actual" batch wage executions instead of just preview simulations. It often reads from the concrete staging table (`cmsdownloadedwages`) or saves the outputs directly into `tbl_monthlysalary` or `paymentadvice`.
- **Core Logic**:
  - Handles the dual actions: `p_action='Save_Salary'` or `p_action='Retrieve_Salary'`.
  - It uses essentially identical logic as the `_pregenerate` function regarding the underlying tax, ESI, PF, and variable pay rules, but finalizes them in the persistent schema.

### 2.4 `uspgetincrementdiff.function.sql`
- **Purpose**: Calculates the difference in salary components specifically when an employee receives an increment (appraisal / mid-month salary change). It computes "Arrear" values to ensure the employee is retroactively compensated.
- **Core Logic**:
  - Determines when the increment takes effect (e.g. `empsalaryregister.effectivefrom`).
  - Pulls the "Already Paid" records from `tbl_monthlysalary`.
  - Checks current active salary structures to find the new rates (`basic`, `hra`, `specialallowance`).
  - Runs massive comparative subqueries deducting what was already paid from what *should* have been paid to find the difference (Arrear Gross, Arrear Net Pay).
  - Handles PF and ESI implications correctly (e.g., handles late payment penalties like 7Q and 14B under PF rules).

---

## 💡 Summary

The `db-handover\Salary-Generation` module is the core computational backbone of the application's payroll engine.
1. The **Functions** represent a sequence of actions:
   Attendance Parsing -> Pre-generation / Simulation -> Final Generation -> Support for retroactive changes (Increments).
2. The **Tables** act as stages:
   `paymentadvice` (Draft state) -> `tbl_monthlysalary` (Final/Locked State).

Noticeable themes include deep reliance on `empsalaryregister` for static rates, heavy calculation rules specifically adapted for compliance (PF 15k limit rules, ESI logic, 14B penalty calculations), and intricate handling of overtime and allowance configurations.
