-- FUNCTION: public.create_invoice_degree()
-- DROP FUNCTION IF EXISTS public.create_invoice_degree();

CREATE OR REPLACE FUNCTION public.create_invoice_degree()
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
  FROM degree d
  WHERE d.id = NEW.degree_id;

  INSERT INTO invoices(students_id, staff_id,cost)
  VALUES (
    NEW.students_id,
    NEW.staff_id,
    v_amount
  );

  RETURN NEW;
END;
$BODY$;

ALTER FUNCTION public.create_invoice_degree()
    OWNER TO postgres;
