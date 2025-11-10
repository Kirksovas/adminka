#!/bin/bash

# ==============================================================================
# ОБЩИЕ ФУНКЦИИ И ПЕРЕМЕННЫЕ
# ==============================================================================

error_exit() {
  echo "ОШИБКА: $1" >&2
  exit 1
}

# ==============================================================================
# ЗАДАНИЕ 1: ШАХМАТНАЯ ДОСКА (Функция)
# ==============================================================================
draw_chessboard() {
  local size="$1"
  if ! [[ "$size" =~ ^[1-9][0-9]*$ ]]; then
    error_exit "Внутренняя ошибка: размер доски должен быть числом."
  fi

  echo "Рисуем доску $size x $size ..."
  local color1='\e[44m'
  local color2='\e[42m'
  local reset_color='\e[0m'

  for (( i=0; i<size; i++ )); do
    for (( j=0; j<size; j++ )); do
      local total=$((i + j))
      if [ $((total % 2)) -eq 0 ]; then
        echo -en "${color1}  ${reset_color}"
      else
        echo -en "${color2}  ${reset_color}"
      fi
    done
    echo
  done
}

# ==============================================================================
# ЗАДАНИЕ 2: АНАЛОГ du (Функции)
# ==============================================================================

format_size_simple() {
  local bytes=$1
  local kb=$((1024))
  local mb=$((kb * 1024))
  local gb=$((mb * 1024))

  if (( bytes >= gb )); then
    echo "$((bytes / gb))G"
  elif (( bytes >= mb )); then
    echo "$((bytes / mb))M"
  elif (( bytes >= kb )); then
    echo "$((bytes / kb))K"
  else
    echo "${bytes}B"
  fi
}

calculate_sizes_recursive() {
  local dir_path="$1"
  local total_size=0
  local current_files_size=0

  while IFS= read -r -d $'\0' entry; do
    if [ -f "$entry" ] && [ ! -L "$entry" ]; then
      local file_size
      file_size=$(stat -c %s "$entry" 2>/dev/null)
      if [ $? -eq 0 ] && [[ "$file_size" =~ ^[0-9]+$ ]]; then
        current_files_size=$((current_files_size + file_size))
      else
        echo "Предупреждение: Не удалось получить размер '$entry'" >&2
      fi
    elif [ -d "$entry" ] && [ ! -L "$entry" ]; then
      local sub_dir_size
      sub_dir_size=$(calculate_sizes_recursive "$entry")
      if [ $? -eq 0 ] && [[ "$sub_dir_size" =~ ^[0-9]+$ ]]; then
        total_size=$((total_size + sub_dir_size))
      else
        echo "Предупреждение: Ошибка обработки поддиректории '$entry'" >&2
      fi
  fi
  done < <(find "$dir_path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

  total_size=$((total_size + current_files_size))
  echo "$total_size"
  return 0
}

run_du_analog() {
  local target_dir="$1"
  target_dir="${target_dir%/}"

  if [ ! -d "$target_dir" ]; then
    error_exit "Директория '$target_dir' не найдена."
  fi
  if [ ! -r "$target_dir" ] || [ ! -x "$target_dir" ]; then
    error_exit "Нет прав на чтение или вход в директорию '$target_dir'."
  fi

  echo "Подсчет размеров в '$target_dir'..."
  local total
  total=$(calculate_sizes_recursive "$target_dir")
  if [[ "$total" =~ ^[0-9]+$ ]]; then
    local formatted_size
    formatted_size=$(format_size_simple "$total")
    echo "$target_dir: $formatted_size"
  else
    error_exit "Ошибка: невозможно определить размер директории."
  fi
}

# ==============================================================================
# ЗАДАНИЕ 3: СОРТИРОВКА ФАЙЛОВ ПО РАСШИРЕНИЯМ (Функция)
# ==============================================================================
sort_files_by_extension() {
  local target_dir="$1"
  target_dir="${target_dir%/}"

  if [ ! -d "$target_dir" ]; then
    error_exit "Директория '$target_dir' не найдена."
  fi
  if [ ! -r "$target_dir" ] || [ ! -w "$target_dir" ] || [ ! -x "$target_dir" ]; then
    error_exit "Нет прав на чтение/запись/вход в директорию '$target_dir'."
  fi

  echo "Сортировка файлов в '$target_dir' по расширениям..."
  find "$target_dir" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' file_path; do
    local filename
    filename=$(basename "$file_path")
    local extension="${filename##*.}"
    local subdir_name

    if [[ "$filename" == "$extension" ]] || [[ "$filename" == .* && "${filename#.*}" == "" ]]; then
        subdir_name="no_extension"
    else
        subdir_name="${extension,,}"
    fi

    local dest_dir="$target_dir/$subdir_name"
    mkdir -p "$dest_dir"
    if [ $? -ne 0 ]; then
        echo "Предупреждение: Не удалось создать папку '$dest_dir'. Пропуск файла '$filename'." >&2
        continue
    fi

    echo "Перемещение: '$filename' -> '$subdir_name/'"
    mv -f "$file_path" "$dest_dir/"
    if [ $? -ne 0 ]; then
        echo "Предупреждение: Не удалось переместить '$filename' в '$dest_dir'." >&2
    fi
  done
  echo "Сортировка завершена."
}

# ==============================================================================
# ЗАДАНИЕ 4: РЕЗЕРВНОЕ КОПИРОВАНИЕ С РОТАЦИЕЙ (Функция)
# ==============================================================================
create_backup_with_rotation() {
  local source_dir="$1"
  local backup_dir="$2"
  source_dir="${source_dir%/}"
  backup_dir="${backup_dir%/}"
  local days_to_keep=7

  # Проверка на совпадение путей
  if [ "$source_dir" = "$backup_dir" ]; then
    error_exit "Исходная директория и директория для бэкапов не могут совпадать."
  fi

  # Проверка что backup_dir не находится внутри source_dir
  if [[ "$backup_dir" == "$source_dir"/* ]]; then
    error_exit "Директория для бэкапов не может находиться внутри исходной директории."
  fi

  if [ ! -d "$source_dir" ]; then
    error_exit "Исходная директория '$source_dir' не найдена."
  fi
  if [ ! -r "$source_dir" ] || [ ! -x "$source_dir" ]; then
    error_exit "Нет прав на чтение или вход в исходную директорию '$source_dir'."
  fi

  if [ ! -d "$backup_dir" ]; then
    echo "Инфо: Создаю директорию для бэкапов '$backup_dir'..."
    mkdir -p "$backup_dir" || error_exit "Не удалось создать директорию '$backup_dir'."
  fi
  if [ ! -w "$backup_dir" ] || [ ! -x "$backup_dir" ]; then
    error_exit "Нет прав на запись или вход в директорию для бэкапов '$backup_dir'."
  fi

  local datestamp
  datestamp=$(date +%Y-%m-%d_%H%M%S)
  local source_basename
  source_basename=$(basename "$source_dir")
  local archive_name="${source_basename}_${datestamp}.tar.gz"
  local archive_path="$backup_dir/$archive_name"
  local source_parent_dir
  source_parent_dir=$(dirname "$source_dir")
  echo "Создание бэкапа '$source_dir' в '$archive_path'..."
  tar -czf "$archive_path" -C "$source_parent_dir" "$source_basename"

  if [ $? -eq 0 ]; then
    echo "Бэкап успешно создан: '$archive_name'"
  else
    rm -f "$archive_path"
    error_exit "Не удалось создать бэкап."
  fi

  echo "Удаление старых бэкапов (старше $days_to_keep дней) в '$backup_dir'..."
  find "$backup_dir" -name "${source_basename}_*.tar.gz" -type f -mtime "+$((days_to_keep - 1))" -print -delete
  if [ $? -ne 0 ]; then
    echo "Предупреждение: Возникли ошибки при поиске или удалении старых бэкапов." >&2
  fi
  echo "Резервное копирование и ротация завершены."
}

# ==============================================================================
# ЗАДАНИЕ 5: АНАЛИЗ ЧАСТОТЫ СЛОВ (Функция)
# ==============================================================================
analyze_word_frequency() {
  local search_dir="$1"
  local extension="$2"
  local top_n="$3"
  search_dir="${search_dir%/}"
  if [ ! -d "$search_dir" ]; then
    error_exit "Директория '$search_dir' не найдена."
  fi
  if ! [[ "$top_n" =~ ^[1-9][0-9]*$ ]]; then
    error_exit "Внутренняя ошибка: <top_n> должно быть числом."
  fi
  if [ ! -r "$search_dir" ] || [ ! -x "$search_dir" ]; then
    error_exit "Нет прав на чтение или вход в директорию '$search_dir'."
  fi

  echo "Анализ частоты слов для .$extension в '$search_dir' (Топ-$top_n)..."
  local result
  result=$(find "$search_dir" -type f -name "*.$extension" -print0 2>/dev/null | \
           xargs -0 cat -- 2>/dev/null | \
           grep -ohE '\w+' | \
           tr '[:upper:]' '[:lower:]' | \
           sort | \
           uniq -c | \
           sort -nr | \
           head -n "$top_n" | \
           awk '{print $2 ": " $1}')

  if [ -z "$result" ]; then
    echo "Предупреждение: Слова не найдены в файлах с расширением '.$extension' или подходящие файлы отсутствуют."
  else
    echo "--- Топ-$top_n слов ---"
    echo "$result"
    echo "-----------------"
  fi
}

# ==============================================================================
# ГЛАВНАЯ ЧАСТЬ СКРИПТА: МЕНЮ И ЗАПУСК ЗАДАЧ
# ==============================================================================

echo "-----------------------------------------"
echo "Доступные задачи:"
echo "  1. Шахматная доска"
echo "  2. Аналог 'du' (размер директорий)"
echo "  3. Сортировка файлов по расширениям"
echo "  4. Резервное копирование с ротацией"
echo "  5. Анализ частоты слов"
echo "  0. Выход"
echo "-----------------------------------------"

read -p "Введите номер задачи (1-5) или 0 для выхода: " task_choice

case "$task_choice" in
  1)
    echo "--- Задача 1: Шахматная доска ---"
    read -p "Введите размер доски (например, 8): " board_size
    if ! [[ "$board_size" =~ ^[1-9][0-9]*$ ]]; then
      error_exit "Неверный ввод. Размер должен быть положительным числом."
    fi
   draw_chessboard "$board_size"
    ;;
  2)
    echo "--- Задача 2: Аналог 'du' ---"
    read -e -p "Введите путь к директории для анализа: " du_dir
    if [ -z "$du_dir" ]; then
      error_exit "Путь к директории не может быть пустым."
    fi
    run_du_analog "$du_dir"
    ;;
  3)
    echo "--- Задача 3: Сортировка файлов ---"
    read -e -p "Введите путь к директории для сортировки файлов: " sort_dir
    if [ -z "$sort_dir" ]; then
      error_exit "Путь к директории не может быть пустым."
    fi
    sort_files_by_extension "$sort_dir"
    ;;
  4)
    echo "--- Задача 4: Резервное копирование ---"
    read -e -p "Введите путь к ИСХОДНОЙ директории для бэкапа: " backup_source
    read -e -p "Введите путь к директории для СОХРАНЕНИЯ бэкапов: " backup_dest
    if [ -z "$backup_source" ] || [ -z "$backup_dest" ]; then
      error_exit "Пути к директориям не могут быть пустыми."
    fi
    create_backup_with_rotation "$backup_source" "$backup_dest"
    ;;
  5)
    echo "--- Задача 5: Анализ частоты слов ---"
    read -e -p "Введите путь к директории для поиска файлов: " stats_dir
    read -p "Введите расширение файлов (например, txt или log): " stats_ext
    read -p "Введите количество топ-слов для вывода (N): " stats_top_n
    if [ -z "$stats_dir" ] || [ -z "$stats_ext" ]; then
      error_exit "Путь к директории и расширение не могут быть пустыми."
    fi
    if ! [[ "$stats_top_n" =~ ^[1-9][0-9]*$ ]]; then
      error_exit "Количество топ-слов (N) должно быть положительным числом."
    fi
    analyze_word_frequency "$stats_dir" "$stats_ext" "$stats_top_n"
    ;;
  0)
    echo "Выход."
    exit 0
    ;;
  *)
    error_exit "Неверный выбор '$task_choice'. Запустите скрипт заново."
    ;;
esac

exit 0

