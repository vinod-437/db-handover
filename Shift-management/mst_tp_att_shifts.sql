-- Table: public.mst_tp_att_shifts

-- DROP TABLE IF EXISTS public.mst_tp_att_shifts;

CREATE TABLE IF NOT EXISTS public.mst_tp_att_shifts
(
    shift_id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    customeraccountid bigint,
    shift_name character varying(200) COLLATE pg_catalog."default" NOT NULL,
    from_time time without time zone NOT NULL,
    to_time time without time zone NOT NULL,
    shift_margin character varying(1) COLLATE pg_catalog."default" DEFAULT (btrim('N'::text))::character varying,
    shift_margin_hours_from character varying(20) COLLATE pg_catalog."default",
    shift_margin_hours_to character varying(20) COLLATE pg_catalog."default",
    weekend character varying(500) COLLATE pg_catalog."default",
    is_weekend_working_day character varying(1) COLLATE pg_catalog."default" DEFAULT (btrim('N'::text))::character varying,
    weekend_id integer,
    weekend_txt text COLLATE pg_catalog."default",
    is_shift_allowance character varying(1) COLLATE pg_catalog."default" DEFAULT (btrim('N'::text))::character varying,
    rate_per_day character varying(500) COLLATE pg_catalog."default",
    applicable_for character varying(500) COLLATE pg_catalog."default",
    is_active boolean DEFAULT true,
    created_by character varying(200) COLLATE pg_catalog."default",
    created_date timestamp without time zone,
    ipadd_createdby character varying(200) COLLATE pg_catalog."default",
    modified_by character varying(200) COLLATE pg_catalog."default",
    modified_date timestamp without time zone,
    ipadd_modifiedby character varying(200) COLLATE pg_catalog."default",
    enable_multiple_slot character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    grace_period_policy text COLLATE pg_catalog."default",
    penality_policy text COLLATE pg_catalog."default",
    exemptions_policy text COLLATE pg_catalog."default",
    overtime_policy text COLLATE pg_catalog."default",
    break_policy text COLLATE pg_catalog."default",
    working_hours_policy text COLLATE pg_catalog."default",
    mobile_check_in_out_enabled character varying(1) COLLATE pg_catalog."default" DEFAULT 'Y'::character varying,
    calendar_enabled character varying(1) COLLATE pg_catalog."default" DEFAULT 'Y'::character varying,
    CONSTRAINT mst_tp_shifts_pkey PRIMARY KEY (shift_id),
    CONSTRAINT mst_tp_shifts_shift_name_from_time_to_time_key UNIQUE (customeraccountid, shift_name, from_time, to_time)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.mst_tp_att_shifts
    OWNER to payrollingdb;

-- Trigger: trg_mst_tp_att_shifts_history

-- DROP TRIGGER IF EXISTS trg_mst_tp_att_shifts_history ON public.mst_tp_att_shifts;

CREATE OR REPLACE TRIGGER trg_mst_tp_att_shifts_history
    BEFORE DELETE OR UPDATE 
    ON public.mst_tp_att_shifts
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_mst_tp_att_shifts_history();