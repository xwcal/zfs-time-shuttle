. sh/defs.sh
if [ "$2" = n ]; then
    cols=name
    vars=br
    sep=
else
    cols=name,origin
    vars="br orig"
    sep='\t'
fi
set -o pipefail
orig=
zfs list -d1 -Sname -Hpo$cols "$BASE/$1" | head -n -1 | while IFS="$TABIFS" read $vars; do
    printf "${br##*/}${sep}${orig##*/}\n"
done
