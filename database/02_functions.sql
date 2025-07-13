--Простой анализ тональности на SQL
CREATE OR REPLACE FUNCTION analyze_review_sentiment_simple(
    input_review_id BIGINT
) RETURNS TABLE(
    output_review_id BIGINT,
    output_score DOUBLE PRECISION,
    output_label VARCHAR(20),
    output_created_at TIMESTAMP
) AS $$
DECLARE
    review_text TEXT;
    positive_count INTEGER := 0;
    negative_count INTEGER := 0;
    total_words INTEGER := 0;
    score DOUBLE PRECISION;
    label VARCHAR(20);
BEGIN
    -- Получаем текст отзыва
    SELECT text INTO review_text FROM reviews WHERE review_id = input_review_id;
    
    IF review_text IS NULL THEN
        RAISE EXCEPTION 'Отзыв с ID % не найден', input_review_id;
    END IF;
    
    -- Считаем положительные слова
    SELECT COUNT(*) INTO positive_count
    FROM regexp_matches(lower(review_text), 'отличн|хорош|рекоменд|доволен|супер', 'g');
    
    -- Считаем отрицательные слова
    SELECT COUNT(*) INTO negative_count
    FROM regexp_matches(lower(review_text), 'плох|ужас|разочарован|недоволен|кошмар', 'g');
    
    -- Расчет оценки
    total_words := positive_count + negative_count;
    score := CASE WHEN total_words > 0 THEN (positive_count - negative_count)::FLOAT / total_words ELSE 0 END;
    
    -- Определение категории
    label := CASE
        WHEN score > 0.3 THEN 'positive'
        WHEN score < -0.3 THEN 'negative'
        ELSE 'neutral'
    END;
    
    -- Сохранение результатов
    INSERT INTO review_sentiment
    VALUES (input_review_id, score, label, NOW())
    ON CONFLICT (review_id) DO UPDATE SET
        sentiment_score = EXCLUDED.sentiment_score,
        sentiment_label = EXCLUDED.sentiment_label,
        created_at = EXCLUDED.created_at;
    
    -- Возврат результатов
    output_review_id := input_review_id;
    output_score := score;
    output_label := label;
    output_created_at := NOW();
    
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

--Загрузка 100 обработынныз отзывов
SELECT analyze_review_sentiment_simple(r.review_id)
FROM reviews r
WHERE NOT EXISTS (
    SELECT 1 FROM sentiment_analysis as 
    WHERE as.review_id = r.review_id
)
LIMIT 100;



-- Анализ топ-5 ключевых фраз на SQL
CREATE OR REPLACE FUNCTION extract_top5_key_phrases()
RETURNS void AS $$
BEGIN
   
    -- Вставляем топ-5 фраз для каждого товара (исправленный запрос)
    INSERT INTO key_phrases (product_id, phrases, created_at)
    WITH product_reviews AS (
        SELECT 
            product_id,
            lower(trim(unnest(regexp_matches(lower(text), '\w{4,}', 'g')))) as phrase
        FROM reviews
        WHERE lower(trim(unnest(regexp_matches(lower(text), '\w{4,}', 'g')))) 
              NOT IN ('этот', 'очень', 'который', 'свой', 'есть', 'также')
    ),
    ranked_phrases AS (
        SELECT 
            product_id,
            phrase,
            COUNT(*) as frequency,
            ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY COUNT(*) DESC) as rank
        FROM product_reviews
        GROUP BY product_id, phrase
        HAVING COUNT(*) > 1
    )
    SELECT 
        product_id,
        ARRAY_AGG(phrase ORDER BY frequency DESC),
        NOW()
    FROM ranked_phrases
    WHERE rank <= 5
    GROUP BY product_id;
    
    RAISE NOTICE 'Успешно извлечены топ-5 ключевых фраз для всех товаров';
END;
$$ LANGUAGE plpgsql;


--Поиск аномальных отзывов на SQL
CREATE OR REPLACE FUNCTION detect_abnormal_reviews()
RETURNS TABLE(
    review_id BIGINT,
    product_id BIGINT,
    abnormal_reason TEXT,
    review_text TEXT,
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    WITH stats AS (
        SELECT
            AVG(LENGTH(text)) AS avg_length,
            STDDEV(LENGTH(text)) AS stddev_length,
            AVG(mark) AS avg_mark,
            STDDEV(mark) AS stddev_mark
        FROM reviews
    )
    SELECT
        r.review_id::BIGINT,  
        r.product_id::BIGINT, 
        CASE --Проводим различные анализы на аномалии
            WHEN LENGTH(r.text) > (s.avg_length + 3*s.stddev_length) THEN 'Очень длинный отзыв'
            WHEN r.mark < (s.avg_mark - 3*s.stddev_mark) THEN 'Аномально низкая оценка'
            WHEN r.mark > (s.avg_mark + 3*s.stddev_mark) THEN 'Аномально высокая оценка'
            WHEN r.text ~* '(.)\1{4,}' THEN 'Повторяющиеся символы (5+ одинаковых)'
            WHEN r.text ~* '[A-Z]{5,}' THEN 'Много заглавных букв (5+ подряд)'
            WHEN r.text ~* '[!?]{3,}' THEN 'Много знаков препинания (3+ подряд)'
            WHEN r.text ~* '\b([а-яёA-Za-z])\1\1+\b' THEN 'Повторяющиеся слова'
            ELSE 'Подозрительный шаблон'
        END::TEXT AS abnormal_reason,
        r.text::TEXT AS review_text,  
        r.created_at::TIMESTAMP       
    FROM reviews r
    CROSS JOIN stats s
    WHERE
        LENGTH(r.text) > (s.avg_length + 3*s.stddev_length) OR
        r.mark < (s.avg_mark - 3*s.stddev_mark) OR
        r.mark > (s.avg_mark + 3*s.stddev_mark) OR
        r.text ~* '(.)\1{4,}' OR
        r.text ~* '[A-Z]{5,}' OR
        r.text ~* '[!?]{3,}' OR
        r.text ~* '\b([а-яёA-Za-z])\1\1+\b'
    ORDER BY r.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Функция для поиска похожих отзывов по тексту 
CREATE OR REPLACE FUNCTION find_similar_reviews(query_text TEXT)
RETURNS TABLE(
    review_id INTEGER,
    similarity DOUBLE PRECISION,
    product_name TEXT,
    review_text TEXT,
    rating INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.review_id::INTEGER,
        similarity(r.text, query_text)::DOUBLE PRECISION,
        p.name::TEXT,
        r.text::TEXT,
        r.mark::INTEGER
    FROM reviews r
    JOIN products p ON r.product_id = p.product_id
    WHERE similarity(r.text, query_text) > 0.3
    ORDER BY similarity DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;


-- Функция для поиска похожих отзывов по эмбеддингам
CREATE OR REPLACE FUNCTION find_similar_reviews_by_embedding(
    input_embedding_id INTEGER,
    similarity_threshold FLOAT8 DEFAULT 0.7,  
)
RETURNS TABLE(
    review_id INTEGER,
    similarity FLOAT8,  
    product_name TEXT,
    review_text TEXT,
    rating INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.review_id::INTEGER,
        (1 - (e2.vector <=> e1.vector))::FLOAT8 AS similarity,  -- Явное приведение типов
        p.name::TEXT,
        r.text::TEXT,
        r.mark::INTEGER
    FROM embeddings e1
    JOIN reviews r ON e1.review_id = r.review_id
    JOIN products p ON r.product_id = p.product_id
    JOIN embeddings e2 ON e2.embedding_id != e1.embedding_id
    WHERE e1.embedding_id = input_embedding_id
    AND (1 - (e2.vector <=> e1.vector))::FLOAT8 > similarity_threshold::FLOAT8
    ORDER BY similarity DESC
    LIMIT max_results;
END;
$$ LANGUAGE plpgsql;


--Материализованные представления 
--Материализованное представление для группировки отзывов по оценке
CREATE MATERIALIZED VIEW reviews_by_mark AS
SELECT 
    mark,
    COUNT(*) AS review_count,
    ROUND(AVG(LENGTH(text)), 0) AS avg_review_length,
    MIN(created_at) AS first_review_date,
    MAX(created_at) AS last_review_date
FROM reviews
GROUP BY mark
ORDER BY mark;

-- Функция для обновления представления
CREATE OR REPLACE FUNCTION refresh_reviews_by_mark()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY reviews_by_mark;
END;
$$ LANGUAGE plpgsql;


--Материализованное представление для группировки отзывов по пользователю
CREATE MATERIALIZED VIEW reviews_by_user AS
SELECT 
    user_id,
    COUNT(*) AS total_reviews,
    COUNT(DISTINCT product_id) AS unique_products_reviewed,
    ROUND(AVG(mark), 2) AS avg_mark,
    SUM(CASE WHEN length(text) > 100 THEN 1 ELSE 0 END) AS long_reviews_count,
    MIN(created_at) AS first_review_date,
    MAX(created_at) AS last_review_date
FROM reviews
GROUP BY user_id
ORDER BY total_reviews DESC;


-- Функция для обновления
CREATE OR REPLACE FUNCTION refresh_reviews_by_user()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY reviews_by_user;
END;
$$ LANGUAGE plpgsql;