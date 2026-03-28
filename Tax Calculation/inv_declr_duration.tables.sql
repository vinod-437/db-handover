-- Table: public.inv_declr_duration

-- DROP TABLE IF EXISTS public.inv_declr_duration;

CREATE TABLE IF NOT EXISTS public.inv_declr_duration
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
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
    declaration_or_proof character varying(1) COLLATE pg_catalog."default" DEFAULT 'D'::character varying,
    proofapplicabledate date,
    is_fianncialyearcompleted character varying(1) COLLATE pg_catalog."default" DEFAULT 'R'::character varying,
    customeraccountid bigint,
    CONSTRAINT inv_declr_duration_pk PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.inv_declr_duration
    OWNER to payrollingdb;

COMMENT ON COLUMN public.inv_declr_duration.is_fianncialyearcompleted
    IS 'C=>complete, R=>Running';

-- Trigger: trginv_declr_duration_history

-- DROP TRIGGER IF EXISTS trginv_declr_duration_history ON public.inv_declr_duration;

CREATE OR REPLACE TRIGGER trginv_declr_duration_history
    BEFORE DELETE OR UPDATE 
    ON public.inv_declr_duration
    FOR EACH ROW
    EXECUTE FUNCTION public.uspinv_declr_duration_history();