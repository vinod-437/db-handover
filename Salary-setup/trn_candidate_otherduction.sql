-- Table: public.trn_candidate_otherduction

-- DROP TABLE IF EXISTS public.trn_candidate_otherduction;

CREATE TABLE IF NOT EXISTS public.trn_candidate_otherduction
(
    id integer NOT NULL DEFAULT nextval('trn_candidate_otherduction_id_seq'::regclass),
    deduction_id integer,
    candidate_id integer,
    deduction_amount double precision,
    active character varying(1) COLLATE pg_catalog."default",
    created_by bigint,
    created_on timestamp without time zone,
    createdby_ip character varying(200) COLLATE pg_catalog."default",
    modified_by bigint,
    modified_on timestamp without time zone,
    modifiedby_ip character varying(200) COLLATE pg_catalog."default",
    deduction_frequency character varying(30) COLLATE pg_catalog."default",
    includedinctc character varying(1) COLLATE pg_catalog."default",
    isvariable character varying(1) COLLATE pg_catalog."default",
    salaryid bigint,
    is_taxable character varying(1) COLLATE pg_catalog."default",
    customeraccountid bigint,
    unitid bigint,
    departmentid bigint,
    designationid bigint,
    trn_otherduction_type character varying(10) COLLATE pg_catalog."default" DEFAULT 'candidate'::character varying,
    unit_salary_id bigint,
    CONSTRAINT trn_candidate_otherduction_pkey PRIMARY KEY (id),
    CONSTRAINT trn_candidate_otherduction_candidate_id_fkey FOREIGN KEY (candidate_id)
        REFERENCES public.openappointments (emp_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT trn_candidate_otherduction_deduction_id_fkey FOREIGN KEY (deduction_id)
        REFERENCES public.mst_otherduction (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT trn_candidate_otherduction_salaryid_fkey FOREIGN KEY (salaryid)
        REFERENCES public.empsalaryregister (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT trn_candidate_otherduction_unit_salary_id_fkey FOREIGN KEY (unit_salary_id)
        REFERENCES public.unitsalaryregister (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT chk_trn_otherduction_type CHECK (trn_otherduction_type::text = ANY (ARRAY['unit'::character varying::text, 'candidate'::character varying::text])),
    CONSTRAINT trn_candidate_otherduction_deduction_frequency_check CHECK (deduction_frequency::text = ANY (ARRAY['Monthly'::character varying::text, 'Quarterly'::character varying::text, 'Half Yearly'::character varying::text, 'Annually'::character varying::text]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.trn_candidate_otherduction
    OWNER to payrollingdb;