CREATE TRIGGER trg_create_invoice_activity
  AFTER INSERT
  ON public.students_activity
  FOR EACH ROW
  EXECUTE FUNCTION public.create_invoice_activity();
