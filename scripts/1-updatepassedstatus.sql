CREATE OR REPLACE FUNCTION public.update_passed_status()
  RETURNS trigger
  LANGUAGE plpgsql
AS $$
DECLARE
  total_weighted NUMERIC;
BEGIN
  SELECT SUM(g.grade * p.weight_pct / 100)
    INTO total_weighted
  FROM grades_edition_stats g
  JOIN evaluation_period p
    ON g.period_id = p.period_id
   AND g.students_person_id = NEW.students_person_id
   AND g.edition_id         = NEW.edition_id;
  IF total_weighted >= 50 THEN
    UPDATE edition_stats
       SET passed = TRUE
     WHERE students_person_id = NEW.students_person_id
       AND edition_id         = NEW.edition_id
       AND passed             = FALSE;
  END IF;

  RETURN NEW;
END;
$$;

