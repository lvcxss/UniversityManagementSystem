CREATE TRIGGER trg_create_invoice_degree
  AFTER INSERT
  ON public.students_degree
  FOR EACH ROW
  EXECUTE FUNCTION public.create_invoice_degree();
