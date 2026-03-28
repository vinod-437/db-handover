-- Table: public.tbl_shift_slots

-- DROP TABLE IF EXISTS public.tbl_shift_slots;

CREATE TABLE IF NOT EXISTS public.tbl_shift_slots
(
    shift_slot_id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    shift_id bigint NOT NULL,
    slot_name character varying(200) COLLATE pg_catalog."default" NOT NULL,
    customeraccountid bigint NOT NULL,
    slot_start_time character varying(10) COLLATE pg_catalog."default" NOT NULL,
    slot_end_time character varying(10) COLLATE pg_catalog."default" NOT NULL,
    slot_duration character varying(10) COLLATE pg_catalog."default",
    status character varying(1) COLLATE pg_catalog."default" DEFAULT '1'::character varying,
    created_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by character varying(100) COLLATE pg_catalog."default",
    created_ip character varying(200) COLLATE pg_catalog."default",
    modified_date timestamp without time zone,
    modified_by character varying(100) COLLATE pg_catalog."default",
    modified_ip character varying(200) COLLATE pg_catalog."default",
    remark character varying(200) COLLATE pg_catalog."default",
    CONSTRAINT tbl_shift_slots_pkey PRIMARY KEY (shift_slot_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.tbl_shift_slots
    OWNER to payrollingdb;
-- Index: idx_tbl_shift_slots_cust_shift

-- DROP INDEX IF EXISTS public.idx_tbl_shift_slots_cust_shift;

CREATE INDEX IF NOT EXISTS idx_tbl_shift_slots_cust_shift
    ON public.tbl_shift_slots USING btree
    (customeraccountid ASC NULLS LAST, shift_id ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

-- Trigger: trg_shift_slots_hist

-- DROP TRIGGER IF EXISTS trg_shift_slots_hist ON public.tbl_shift_slots;

CREATE OR REPLACE TRIGGER trg_shift_slots_hist
    AFTER DELETE OR UPDATE 
    ON public.tbl_shift_slots
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_shift_slots_hist();