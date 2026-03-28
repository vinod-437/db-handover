-- Table: public.mst_otherduction

-- DROP TABLE IF EXISTS public.mst_otherduction;

CREATE TABLE IF NOT EXISTS public.mst_otherduction
(
    id integer NOT NULL DEFAULT nextval('mst_otherduction_id_seq'::regclass),
    deduction_name character varying(100) COLLATE pg_catalog."default",
    deduction_description character varying(500) COLLATE pg_catalog."default",
    active character varying(1) COLLATE pg_catalog."default",
    created_by bigint,
    created_on timestamp without time zone,
    createdby_ip character varying(200) COLLATE pg_catalog."default",
    modified_by bigint,
    modified_on timestamp without time zone,
    modifiedby_ip character varying(200) COLLATE pg_catalog."default",
    is_taxable bit(1) DEFAULT '0'::"bit",
    transactiontype character varying(20) COLLATE pg_catalog."default",
    masterledgername character varying(100) COLLATE pg_catalog."default",
    parentid integer,
    applicationtype character varying(30) COLLATE pg_catalog."default" DEFAULT 'HubCentral'::character varying,
    tpactivestatus character varying(1) COLLATE pg_catalog."default",
    customeraccountid bigint,
    percentage_ctc numeric(18,2),
    percentage_fixed character varying(30) COLLATE pg_catalog."default",
    isperk character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    assetid integer,
    CONSTRAINT mst_otherduction_pkey PRIMARY KEY (id),
    CONSTRAINT mst_otherduction_tpactivestatus_check CHECK (tpactivestatus::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])),
    CONSTRAINT mst_otherduction_transactiontype_check CHECK (transactiontype::text = ANY (ARRAY['Debit'::character varying::text, 'Credit'::character varying::text]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.mst_otherduction
    OWNER to payrollingdb;
-- Index: idx_mst_otherduction_uq1

-- DROP INDEX IF EXISTS public.idx_mst_otherduction_uq1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mst_otherduction_uq1
    ON public.mst_otherduction USING btree
    (deduction_name COLLATE pg_catalog."default" ASC NULLS LAST, applicationtype COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default
    WHERE customeraccountid IS NULL AND tpactivestatus::text = 'Y'::text;
-- Index: idx_mst_otherduction_uq2

-- DROP INDEX IF EXISTS public.idx_mst_otherduction_uq2;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mst_otherduction_uq2
    ON public.mst_otherduction USING btree
    (deduction_name COLLATE pg_catalog."default" ASC NULLS LAST, applicationtype COLLATE pg_catalog."default" ASC NULLS LAST, customeraccountid ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default
    WHERE customeraccountid IS NOT NULL AND tpactivestatus::text = 'Y'::text;