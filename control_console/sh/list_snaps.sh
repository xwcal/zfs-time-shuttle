. sh/defs.sh

. sh/do_mount.sh "$1" || exit 1

# now list snaps
set .zfsrb "$1"
. sh/list_snaps_impl.sh
