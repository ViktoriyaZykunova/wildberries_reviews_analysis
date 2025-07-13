-- Простые аналитические запросы

--Количество отзывов по оценкам
SELECT 
    mark,
    COUNT(*) AS review_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM reviews), 1) AS percentage
FROM reviews
GROUP BY mark
ORDER BY mark;

--Средняя оценка по продуктам с более чем 10 отзывами
SELECT 
    product_id,
    AVG(mark) AS avg_mark,
    COUNT(*) AS review_count
FROM reviews
GROUP BY product_id
HAVING COUNT(*) > 10
ORDER BY avg_mark DESC
LIMIT 20;

--Отзывы с максимальной длиной текста
SELECT 
    review_id,
    product_id,
    LENGTH(text) AS text_length,
    mark,
    created_at
FROM reviews
ORDER BY text_length DESC
LIMIT 10;

