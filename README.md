# wildberries_reviews_analysis
Итоговый проект по курсу SQL

Схема файлов проекта
wildberries_reviews_analysis/
│
├── database/
│ ├── 01_tables.sql # создание таблиц и индексов
│ ├── 02_functions.sql # PL/pgSQL функции для анализа
│ └── 03_sample_data.sql # тестовые данные для проверки
│
├── python/
│ ├── db_connection.py #подключение к PostgreSQL
│ ├── data_loader.py # загрузка CSV в БД
│ ├── nlp_processor.py # обработка текста (тональность, ключевые фразы)
│ └── embedding_generator.py # генерация векторных представлений
│
├── analysis/
│ ├── basic_analysis.sql # стандартные аналитические запросы
│ └── advanced_analysis.py # Python-скрипты для сложной аналитики
│
├── requirements.txt # зависимости Python
│ 
│
└── README.md # Краткое описание проекта и выводы
