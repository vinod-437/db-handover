-- Table: public.inv_declr_duration_employee

-- DROP TABLE IF EXISTS public.inv_declr_duration_employee;

CREATE TABLE IF NOT EXISTS public.inv_declr_duration_employee
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    financialyear character varying(9) COLLATE pg_catalog."default",
    openfrom date,
    opento date,
    created_by integer,
    created_on timestamp without time zone,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_by integer,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    active bit(1),
    declaration_or_proof character varying(1) COLLATE pg_catalog."default" NOT NULL DEFAULT 'D'::character varying,
    proofapplicabledate date,
    is_fianncialyearcompleted character varying(1) COLLATE pg_catalog."default" DEFAULT 'R'::character varying,
    employeecode bigint NOT NULL,
    customeraccountid bigint,
    CONSTRAINT inv_declr_duration_employee_pkey PRIMARY KEY (id),
    CONSTRAINT chk_declaration_or_proof CHECK (declaration_or_proof::text = ANY (ARRAY['D'::character varying, 'P'::character varying]::text[]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.inv_declr_duration_employee
    OWNER to payrollingdb;

-- Trigger: trginv_declr_duration_employee_history

-- DROP TRIGGER IF EXISTS trginv_declr_duration_employee_history ON public.inv_declr_duration_employee;

CREATE OR REPLACE TRIGGER trginv_declr_duration_employee_history
    BEFORE DELETE OR UPDATE 
    ON public.inv_declr_duration_employee
    FOR EACH ROW
    EXECUTE FUNCTION public.uspinv_declr_duration_employee_history();