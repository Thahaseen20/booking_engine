SET @theatre_id = 1;
SET @show_date = '2026-10-16';

SELECT
    m.movie_id,
    m.title AS movie_title,
    sh.show_id,
    sh.starts_at AS show_start,
    sh.ends_at AS show_end
FROM theatres AS t
JOIN screens AS sc
    ON sc.theatre_id = t.theatre_id
JOIN shows AS sh
    ON sh.screen_id = sc.screen_id
JOIN movies AS m
    ON m.movie_id = sh.movie_id
WHERE t.theatre_id = @theatre_id
  AND sh.status = 'scheduled'
  AND sh.starts_at >= CAST(@show_date AS DATE)
  AND sh.starts_at < DATE_ADD(CAST(@show_date AS DATE), INTERVAL 1 DAY)
ORDER BY sh.starts_at, m.title, sh.show_id;
