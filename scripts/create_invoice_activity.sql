-- FUNCTION: public.create_invoice_activity()
-- DROP FUNCTION IF EXISTS public.create_invoice_activity();

CREATE OR REPLACE FUNCTION public.create_invoice_activity()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
  v_amount NUMERIC(10,2);
BEGIN
  SELECT d.cost
    INTO v_amount
  FROM activity d
  WHERE d.id = NEW.activity_id;

  INSERT INTO invoices(students_id, cost)
  VALUES (
    NEW.students_id,
    v_amount
  );

  RETURN NEW;
END;

$BODY$;

ALTER FUNCTION public.create_invoice_activity()
    OWNER TO postgres;
