-- DROP TRIGGER IF EXISTS trg_update_passed ON public.grades_edition_stats;

CREATE TRIGGER trg_update_passed
  AFTER INSERT OR UPDATE
  ON public.grades_edition_stats
  FOR EACH ROW
  EXECUTE FUNCTION public.update_passed_status();

