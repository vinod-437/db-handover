# Group Medical Insurance Deduction Fix

I have investigated the logic behind the prorated Group Medical Insurance deductions. As requested, the deduction must remain a **fixed amount** for the entire month irrespective of the attendance days, when the `isgroupinsurance` flag is set to `'Y'` for the employee. 

## Changes Made
The prorated calculation logic was found in the dynamic SQL generation blocks of two key stored procedures:
1. `public.uspgetorderwisewages_pregenerate`
2. `public.uspgetorderwisewages`

I have modified both procedures to implement a conditional check. The changes bypass the existing attendance-based proration formula and use the static `insuranceamount`, `familyinsuranceamount`, and `employerinsuranceamount` when `empsalaryregister.isgroupinsurance = 'Y'`.

### Modified Logic Example:
```diff
- case when openappointments.customeraccountid in(6927,7416) then (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))-coalesce(alreadyinsurance,0) else
- (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))*(case when coalesce(salaryindaysopted,'N')='N' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,'N')='N'  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''='Y' then '||v_monthdays||'  else salarydays end/*-coalesce(alreadyinsurance,0)*/ end Insurance,

+ case when openappointments.customeraccountid in(6927,7416) then (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))-coalesce(alreadyinsurance,0) 
+ when empsalaryregister.isgroupinsurance='Y' then (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))
+ else
+ (coalesce(insuranceamount,0)+coalesce(familyinsuranceamount,0))*(case when coalesce(salaryindaysopted,'N')='N' or empsalaryregister.salarydays=1 then (totalpaiddays+totalleavetaken) else least(salarydays,(totalpaiddays+totalleavetaken)) end)/case when coalesce(salaryindaysopted,'N')='N'  or '''||coalesce(v_empsalaryregister.flexiblemonthdays,'N')||'''='Y' then '||v_monthdays||'  else salarydays end/*-coalesce(alreadyinsurance,0)*/ end Insurance,
```
*(Similar changes were applied for `familyinsuranceamount` and `employerinsuranceamount` in the respective columns of the procedures.)*

## Action Required

Since I cannot directly execute `CREATE OR REPLACE FUNCTION` on your PostgreSQL database due to missing authentication/`psql` access in this environment, I have saved the fully updated SQL scripts in the local scratch directory.

Please execute the following files on your database to apply the changes:

1. [uspgetorderwisewages_pregenerate.sql](file:///C:/Users/VinodMaurya/.gemini/antigravity/brain/869ab518-6db6-4539-9e76-d15af8662388/scratch/uspgetorderwisewages_pregenerate.sql)
2. [uspgetorderwisewages.sql](file:///C:/Users/VinodMaurya/.gemini/antigravity/brain/869ab518-6db6-4539-9e76-d15af8662388/scratch/uspgetorderwisewages.sql)

You can copy the contents of these files into pgAdmin or run them directly via `psql`. Let me know if you would like me to assist with any further verification after you have applied them!
