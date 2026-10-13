# Набор эмодзи

Собран скриптом `tools/build-emoji.ps1`, руками не правится.

- `img/` — картинки 64×64 из Noto Color Emoji. Имя файла — коды символов
  через дефис, как в `emoji-datasource`.
- `catalog.json` — вкладки, порядок, русские названия и слова для поиска.

Из полного набора убраны варианты цвета кожи, профессии, семьи, спорт с
человечками и большая часть флагов стран: для кнопок они не нужны, а
вкладки с сотнями почти одинаковых картинок мешают выбирать.

## Лицензии

- Noto Color Emoji — © Google, Apache License 2.0,
  <https://www.apache.org/licenses/LICENSE-2.0>.
- emoji-datasource, emoji-datasource-google — © Cal Henderson, MIT.
- Unicode CLDR annotations — © Unicode, Inc., Unicode License v3,
  <https://www.unicode.org/license.txt>.
