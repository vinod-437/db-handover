-- Table: public.unprocessed_epfecrreport

-- DROP TABLE IF EXISTS public.unprocessed_epfecrreport;

CREATE TABLE IF NOT EXISTS public.unprocessed_epfecrreport
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    appointment_id bigint,
    rpt_month integer,
    rpt_year integer,
    uan character varying(50) COLLATE pg_catalog."default",
    member_name character varying(150) COLLATE pg_catalog."default",
    gross_wages double precision,
    epf_wages double precision,
    eps_wages double precision,
    edli_wages double precision,
    epf_contri_remitted double precision,
    eps_contri_remitted double precision,
    epf_eps_diff_remitted double precision,
    ncp_days double precision,
    refund_of_advances double precision,
    created_by bigint,
    createdon timestamp without time zone,
    createdbyip character varying(200) COLLATE pg_catalog."default",
    mdified_by bigint,
    mdified_on timestamp without time zone,
    mdified_byip character varying(200) COLLATE pg_catalog."default",
    emp_code bigint,
    batchid character varying(150) COLLATE pg_catalog."default",
    wagestatus character varying(30) COLLATE pg_catalog."default" DEFAULT 'InProcess'::character varying,
    isreportdownloaded bit(1) DEFAULT '0'::"bit",
    downloadedby bigint,
    downloadedon timestamp without time zone,
    downloadedbyip character varying(200) COLLATE pg_catalog."default",
    esicnumber character varying(50) COLLATE pg_catalog."default",
    esic_amt numeric(18,2),
    lastworkingday date,
    fathername character varying(150) COLLATE pg_catalog."default",
    emplocation character varying(150) COLLATE pg_catalog."default",
    doj date,
    employeelwf numeric(18,2),
    employerlwf numeric(18,2),
    totallwf numeric(18,2),
    address character varying(300) COLLATE pg_catalog."default",
    reporttype character varying(50) COLLATE pg_catalog."default",
    salaryid bigint,
    vpf numeric(18,2),
    lwfstatecode integer,
    monthdays double precision,
    gross_earning double precision,
    govt_bonus_amt double precision,
    otherbonuswithesi double precision,
    totalarear double precision,
    otherledgerarears double precision,
    otherdeductions numeric(18,2),
    arearaddedmonths character varying(150) COLLATE pg_catalog."default",
    CONSTRAINT unprocessed_epfecrreport_pkey PRIMARY KEY (id),
    CONSTRAINT unprocessed_epfecrreport_uq UNIQUE (appointment_id, rpt_month, rpt_year, batchid, reporttype),
    CONSTRAINT unprocessed_epfecrreport_reporttype_check CHECK (reporttype::text = ANY (ARRAY['EPF'::character varying::text, 'ESIC'::character varying::text, 'LWF'::character varying::text])),
    CONSTRAINT unprocessed_epfecrreport_wagestatus_check CHECK (wagestatus::text = ANY (ARRAY['Processed'::character varying::text, 'InProcess'::character varying::text]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.unprocessed_epfecrreport
    OWNER to payrollingdb;
-- Index: idx_unpepfecrreport1

-- DROP INDEX IF EXISTS public.idx_unpepfecrreport1;

CREATE INDEX IF NOT EXISTS idx_unpepfecrreport1
    ON public.unprocessed_epfecrreport USING btree
    (rpt_year ASC NULLS LAST, rpt_month ASC NULLS LAST, emp_code ASC NULLS LAST, batchid COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: idx_unpepfecrreport2

-- DROP INDEX IF EXISTS public.idx_unpepfecrreport2;

CREATE INDEX IF NOT EXISTS idx_unpepfecrreport2
    ON public.unprocessed_epfecrreport USING btree
    (rpt_month ASC NULLS LAST, rpt_year ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

-- Trigger: trgunprocessed_epfecrreport_history

-- DROP TRIGGER IF EXISTS trgunprocessed_epfecrreport_history ON public.unprocessed_epfecrreport;

CREATE OR REPLACE TRIGGER trgunprocessed_epfecrreport_history
    BEFORE DELETE OR UPDATE 
    ON public.unprocessed_epfecrreport
    FOR EACH ROW
    EXECUTE FUNCTION public.uspunprocessed_epfecrreport_history();