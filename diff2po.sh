#!/bin/bash

display_help() {
  cat <<EOF
Script transforms diff to PO file.
Usage: diff2po [-db|--dbcheck] [-dbro|--dbro]
               [-dbu|--dbuser user] [-dbp|--dbpass pass]
               [-dbn|--dbname name]
               [-dbh|--dbhost host[=localhost]] [-dbpr|--dbport port[=3306]]
               [-h|--help] INPUT_FILE
It may work with usual stdin flow.
If you need to check translation strings in the DB(mysql) use -db param and set access credentials.
If your DB works in read-only mode use -dbro parameter.
EOF
}

# Read arguments.
while :
  do
  case "$1" in
    -db|--dbcheck)
      DB_CHECK=1
    ;;
    -dbro|--dbro)
      DB_RO=1
    ;;
    -dbu|--dbuser)
      DB_USER="$2"
      shift
    ;;
    -dbp|--dbpass)
      DB_PASS="$2"
      shift
    ;;
    -dbn|--dbname)
      DB_NAME="$2"
      shift
    ;;
    -dbh|--dbhost)
      DB_HOST="$2"
      shift
    ;;
    -dbpr|--dbport)
      DB_PORT="$2"
      shift
    ;;
    -h|--help)
      display_help
      exit 1;
    ;;
    *)
      INPUT_FILE=$1
      break
    ;;
  esac
  shift
done

# Check DB settings.
if [ ! -z "$DB_CHECK" ]; then
  if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]  || [ -z "$DB_NAME" ]; then
    echo "Please enter proper DB credentials."
    echo
    display_help
    exit 1;
  fi

  if [ -z "$DB_SERVER" ]; then
    DB_SERVER="localhost"
  fi

  if [ -z "$DB_PORT" ]; then
    DB_PORT="3306"
  fi
fi

# Get messages from file of stdin.
if [ ! -z "$INPUT_FILE" -a -f "$INPUT_FILE" ]; then
  messages=$(cat $INPUT_FILE)
else
  messages=$(cat -)
fi

if [ -z "$messages" ]; then
  echo "There is nothing to process."
  echo
  exit 1
fi


# Regex matches all quoted strings.
# Take a look at http://www.metaltoad.com/blog/regex-quoted-string-escapable-quotes
read -r -d '' regex_string <<EOF
(                 # Capturing group 1 for single or double quotes without slash before them
  (?<![\\])       #  No slash before next symbol
  [\x27"]         #  Single or double quote symbols
)                 # End of group 1
(                 # Capturing group 2 for the string
  (?:             #  Non-capturing group needs for
    .(?!          #   continue matching any characters which are not followed by
      (?<![\\])\1 #    the string matched in the first backreference without a slash
    )             #
  )*              #
  .?              # Grab the last symbol before ending quote
)                 # End of group 2
\1                # Ending quote
EOF

read -r -d '' regex_t <<EOF
/
  [[:space:]\.=]    # Only space, dot or equal sign should be before function
  t                 # Function name
  \s*\(\s*          # Opening parenthesis of the function
  $regex_string     # Search for quoted strings
/gmx                # global, multi-line, extended
EOF

read -r -d '' regex_format_plural <<EOF
/
  [[:space:]\.=]               # Only space, dot or equal sign should be before function
  [format_plural|formatPlural] # Function name
  \s*\(\s*                     # Opening parenthesis of the function
  .*?,\s*                      # Any characters in first parameter of the function
  $regex_string                # Search for quoted strings in second parameter
  \s*,\s*                      # Comma separated parameters
  $regex_string                # Search for quoted strings in third parameter
/gmx                           # global, multi-line, extended
EOF

messages=$(
  echo "${messages}" |
  sed '/^[^\+].*/d'
)

# Extract messages from t() functions.
messages_t=$(
  echo "${messages}" |
  perl -ne 'while (/[[:space:]\.=]t\s*\(\s*((?<![\\])[\x27"])((?:.(?!(?<![\\])\1))*.?)\1/mgx) {print "$2\n"}'
)

# Extract messages from format_plural() functions.
messages_plural=$(
  echo "${messages}" |
  perl -ne 'while (/[[:space:]\.=](format_plural|formatPlural)\s*\(\s*.*?,\s*((?<![\\])[\x27"])((?:.(?!(?<![\\])\2))*.?)\2\s*,\s*((?<![\\])[\x27"])((?:.(?!(?<![\\])\4))*.?)\4/mgx) {print "$3\n$5\n"}'
)

# Merge 2 lists and sort them.
messages=$(
  echo "$messages_t
$messages_plural" |
  sort -u
)

# Check strings in the database.
if [ ! -z "$DB_CHECK" ]; then
  db_connection="mysql\
    --user=$DB_USER --password=$DB_PASS --database=$DB_NAME\
    --host=$DB_HOST --port=$DB_PORT\
    --skip-column-names --execute"

  if [ -z "$DB_RO" ]; then
    # Create temporary table for all strings
    tableName="UntranslatedStrings${RANDOM}"

    query="CREATE TEMPORARY TABLE ${tableName}(string TEXT);"

    while read message
      do
      # Escape double quotes.
      message=${message//\"/\\\"}

      # Insert strings into temporary table.
      query+="INSERT INTO ${tableName} VALUES (\"${message}\");";
    done <<< "$messages"

    # Try to find strings, which are not added to the DB.
    query+="SELECT us.string s FROM ${tableName} us WHERE us.string NOT IN (SELECT source FROM locales_source);";

    messages=$(${db_connection} "${query}")
  else
   # IF DB works in RO mode, check strings one by one.
   messages_processed=""
   while read message
      do
      # Escape double quotes.
      message=${message//\"/\\\"}

      query="SELECT ls.source FROM locales_source ls WHERE ls.source = \"${message}\";";

      result=$(${db_connection} "${query}")
      if [ -z "$result" ]; then
        messages_processed+=${message}
        messages_processed+=$IFS
      fi
   done <<< "$messages"

   messages=$messages_processed
  fi
fi

# Output untranslated string to PO file.
if [ ! -z "$messages" ]; then
  while read message
    do
    if [ -z "$message" ]; then
      continue
    fi

    # Escape double quote.
    message=${message//\"/\\\"}
    message=${message//\"/\\\"}
    printf "msgid \"$message\"\nmsgstr \"\"\n\n"
  done <<< "$messages"
else
  echo "Nothing to output."
  exit
fi
