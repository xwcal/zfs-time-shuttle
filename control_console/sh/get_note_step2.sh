. sh/defs.sh
if [ -n "$3" ]; then
    . sh/do_mount.sh "$3" || exit 1
fi
zfs diff "$BASE/.zfsrb/$1/home@$2" "$BASE/.zfsrb/$1/home"
