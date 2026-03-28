-- Table: public.mst_tp_att_shiftmapping

-- DROP TABLE IF EXISTS public.mst_tp_att_shiftmapping;

CREATE TABLE IF NOT EXISTS public.mst_tp_att_shiftmapping
(
    shiftmapping_id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    customeraccountid bigint,
    shift_name_id character varying(100) COLLATE pg_catalog."default" NOT NULL,
    dt_from timestamp without time zone,
    dt_to timestamp without time zone,
    applicable_type character varying(100) COLLATE pg_catalog."default",
    applicable_for character varying(500) COLLATE pg_catalog."default",
    reason character varying(500) COLLATE pg_catalog."default",
    is_update_past_attendance_entries character varying(1) COLLATE pg_catalog."default" DEFAULT (btrim('N'::text))::character varying,
    is_active boolean DEFAULT true,
    created_by character varying(200) COLLATE pg_catalog."default",
    created_date timestamp without time zone,
    ipadd_createdby character varying(200) COLLATE pg_catalog."default",
    modified_by character varying(200) COLLATE pg_catalog."default",
    modified_date timestamp without time zone,
    ipadd_modifiedby character varying(200) COLLATE pg_catalog."default",
    CONSTRAINT mst_tp_att_shiftmapping_pkey PRIMARY KEY (shiftmapping_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.mst_tp_att_shiftmapping
    OWNER to payrollingdb;