# Detailed Salary Structure Database Analysis

## 1. Database Entity Relationship Diagram (ERD)
The following is a comprehensive ERD mapping the foreign keys and core transaction structures.

```mermaid
erDiagram
    %% Core Entities
    openappointments {
        int emp_id PK
        bigint emp_code
        varchar minwagesstate
        int appointment_status_id
        varchar gender
    }

    empsalaryregister {
        int id PK
        int appointment_id FK "References openappointments(emp_id)"
        double_precision basic "Core salary"
        double_precision hra "House Rent"
        double_precision allowances "Other allowances"
        double_precision gross "Gross Salary"
        double_precision ctc "Total Cost to Company"
        double_precision salaryinhand "Net Pay"
        double_precision employerepfrate "Employer EPF"
        double_precision employeresirate "Employer ESI"
        double_precision employeeepfrate "Employee EPF"
        double_precision employeeesirate "Employee ESI"
        double_precision pt "Professional Tax"
        double_precision employerlwf "Employer LWF"
        double_precision employeelwf "Employee LWF"
        varchar isactive "Flag to map current active row"
    }
    
    mst_otherduction {
        int id PK
        varchar deduction_name "E.g. Meal Voucher, Medical"
        varchar transactiontype "Debit or Credit"
        bit is_taxable
        varchar applicationtype
    }
    
    trn_candidate_otherduction {
        int id PK
        int candidate_id FK "References openappointments(emp_id)"
        int deduction_id FK "References mst_otherduction(id)"
        bigint salaryid FK "References empsalaryregister(id)"
        double_precision deduction_amount
        varchar deduction_frequency "Monthly, Annually"
        varchar includedinctc "Yes/No flag"
    }

    tbl_account {
        bigint id PK
        varchar compliancemodeltype
        int number_of_employees
        varchar minwagestatus
    }

    mst_employer_compliance_settings {
        int id PK
        bigint customer_account_id FK "Ref tbl_account"
        varchar employerpfincludeinctc
        varchar edli_adminchargesincludeinctc
        varchar pfcapapplied
    }

    %% Relationships
    openappointments ||--o{ empsalaryregister : "Has Salary Details"
    openappointments ||--o{ trn_candidate_otherduction : "Has Deductions/Allowances"
    empsalaryregister ||--o{ trn_candidate_otherduction : "Groups Deductions for Salary Month"
    mst_otherduction ||--o{ trn_candidate_otherduction : "Types of Deductions"
    tbl_account ||--o{ mst_employer_compliance_settings : "Employer Setup"

```

---

## 2. Process Flowchart: `uspcreatecustomsalarystructure`
This function is responsible for building the customized breakdown when provided explicit parameters (often a JSON array of specific components).

```mermaid
flowchart TD
    Start([Execute uspcreatecustomsalarystructure])
    Input[Get Appointment ID, Customer ID, CTC, Components JSON]
    CheckApprentice{Is Apprentice?}
    
    CheckApprentice -->|Yes| DisableStatutory[Disable PT, LWF, PF, ESI, Gratuity]
    CheckApprentice -->|No| FetchCompliance[Fetch Employer Compliance Settings\ne.g., EDLI Admin Charges included in CTC?]
    DisableStatutory --> FetchCompliance

    FetchCompliance --> Val[Validate PF / ESI Settings vs Existing Salary records]
    
    Val --> SumDeductions[Sum Other Deductions & Variables from trn_candidate_otherduction\nEx. Meal Vouchers, Monthly Taxable Bonus]
    
    SumDeductions --> ParseJSON{Parse Expected Components\np_salarystructure JSON}
    
    ParseJSON --> DeriveBase[Extract Basic, HRA, Conveyance, Allowances, etc.]
    
    DeriveBase --> CheckComplianceApplicability{Is LWF / ESI / PF Applicable?}
    
    CheckComplianceApplicability --> CalcStatutory[Calculate ESI Employer/Employee Rates\nCalculate EPF Employer/Employee Rates based on Cap Rules]
    
    CalcStatutory --> CalculateGross[Sum Base components to calculate GROSS]
    
    CalculateGross --> CalculateTaxNet[Calculate CTC = Gross + ER_Statutory\nCalculate Net In Hand = Gross - EE_Statutory - Deductions]

    CalculateTaxNet --> FormatOutput[Format Result Array and Return Set/Recordset]
    FormatOutput --> End([End Procedure Execution])

```

---

## 3. Process Flowchart: `uspccalcgrossfromctc_withoutconveyance`
This function is a reverse-calculator. Given a target CTC, it figures out the basic pay, statutory compliances, and balances out `allowances` to precisely match the target CTC.

```mermaid
flowchart TD
    Start([Execute uspccalcgrossfromctc_withoutconveyance])
     InputCTC[Input Target CTC: p_monthlyofferedpackage, basic option]
     
     LoadEnv[Load Compliance Models, State Mins, PF Cap Rules]
     LoadEnv --> PreTaxSum[Sum Candidate Specific Other Deductions/Variables]
     
     PreTaxSum --> DetermineBasic{Basic Option Selected?}
     DetermineBasic -->|Option 1 or 5| StandardBasic[Derive Base=CTC/Certain % \n Calculate HRA]
     DetermineBasic -->|Option 2| FixedBasic[Use Provided Basic \n Set HRA/Allowances = 0]
     
     StandardBasic --> InitStat1[Init EPF: Calculate Employer & Employee EPF 12-13%]
     FixedBasic --> InitStat1
     
     InitStat1 --> InitStat2[Init NPS & Govt Bonus if opted]
     
     InitStat2 --> ESICheck{Is ESI Applicable?}
     ESICheck -->|Yes| RevCalcESI[Reverse Calculate ESI:\nGross = (TargetCTC - ER_EPF - ER_LWF) / 1.0325\nAllowances = Gross - Basic - HRA]
     ESICheck -->|No| RevCalcNormal[Normal Calculation:\nGross = TargetCTC - ER_EPF - ER_LWF\nAllowances = Gross - Basic - HRA]
     
     RevCalcESI --> ComputeStatutory[Calculate Explicit ESI (3.25% & 0.75%) locally]
     RevCalcNormal --> ComputeStatutory
     
     ComputeStatutory --> CalcTaxes[Calculate Gratuity, LWF, Professional Tax based on Target Gross]
     
     CalcTaxes --> FinalizePay[Calculate Final Net Salary In Hand & Confirm Target CTC match]
     
     FinalizePay --> OutputSet[Assemble Final Response RefCursor Row]
     OutputSet --> End([End Procedure Execution])

```

---

## 4. Process Flowchart: `uspsavecustomsalarystructure`
This flowchart handles what happens when a computed salary is formally saved to the employee database.

```mermaid
flowchart TD
    Start([Execute uspsavecustomsalarystructure])
    Input[Takes exact values derived from previous procs]
    
    Input --> HistoryCheck{Does Employee have Active Salary?}
    HistoryCheck -->|Yes| DisableOld[Update empsalaryregister\nSet isactive='0'\nSet effectiveto = effectivedate - 1 day]
    HistoryCheck -->|No| SaveNew[Skip to Save]
    
    DisableOld --> SaveNew
    
    SaveNew --> InsertSalary[INSERT INTO empsalaryregister\nWITH isactive='1']
    
    InsertSalary --> LinkOther[Update trn_candidate_otherduction\nSet salaryid = New Salary Record ID]
    
    LinkOther --> SetupLeaves[Generate / Update leave templates in tbl_tpemp_leavetemplates based on parameters]
    
    SetupLeaves --> CheckEmployee{Is candidate mapped as Employee?}
    CheckEmployee -->|No| GenerateEmpCode[Generate openappointments emp_code, Create System User & Profile]
    GenerateEmpCode --> FinalUpdate[Update openappointments status and links]
    CheckEmployee -->|Yes| FinalUpdate
    
    FinalUpdate --> End([Return Final Success Row JSON])
```
