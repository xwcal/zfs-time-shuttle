. sh/defs.sh

if [ "$3" = n ]; then
    cols=name
    vars=snap
    sep=
else
    cols=name,creation
    vars="snap birth"
    sep='\t'
fi
set -o pipefail
birth=
zfs list -d1 -tsnapshot -Sname -Hpo$cols "$BASE/$1/$2" | while IFS="$TABIFS" read $vars; do
    printf "${snap##*@}${sep}${birth}\n"
done
