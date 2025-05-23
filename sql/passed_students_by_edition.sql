CREATE VIEW passed_students_by_edition AS
SELECT e.ano AS ano, COUNT(*) AS passed_students_count FROM edition_stats es
JOIN edition e ON e.id = es.edition_id
WHERE es.passed = TRUE
GROUP BY e.ano;
