# Enhanced Database Architecture: Salary Types & Arrear Horizons

You are right on the money. I had previously categorized `tbl_monthlysalary` basically around whether a row was a `Salary` vs `Liability` and whether it was locked (`P` vs `H`).

However, I missed the critical **classifier dimension** describing what `Salary` actually represents (is it a current month pay, or an arrear generated from back-dating?).

I ran empirical diagnostic queries directly against `tbl_monthlysalary` and extracted the following architectural constraints to add to heavily enhance the `tbl_monthlysalary` documentation card:

## 1. The Classifier: `recordscreen`
This column categorizes the payroll row. It acts as the routing flag deciding if this processing block strictly handles standard wages, back-dated wages, or increments.
- **`Current Wages`**: The vast majority of standard payroll (5,378 rows).
- **`Previous Wages`**: Holds off-cycle structural releases (109 rows).
- **`Increment Arear`**: Isolates mathematical diff rows calculated over previous months specifically tracking increment bumps (50 rows).

## 2. The Time Horizon: `arearprocessmonth` & `arearaddedmonths`
While `mprmonth` dictates standard biological attendance, these two metrics are essential for Arrear blocks. 
- **`arearprocessmonth`**: Locks the numerical calendar month (1-12) the arrear mathematical diff structurally belongs to.

## Proposed Execution Action
I will inject these explicit schema features straight into the **Pillar 3: Core Payroll Engine** inside the `tbl_monthlysalary` card. I will include the literal values for `recordscreen` as value-tags so anyone auditing the database understands exactly how the batch distinguishes arrears from current disbursements.

Do you approve this final addition to the schema dictionary?
