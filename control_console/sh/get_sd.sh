. sh/defs.sh
sd="$($ZFS_GET $ZPROP_SD "$BASE")" || exit 1
tsmin="$($ZFS_GET creation "$BASE/.zfsrb/0000000000@0000000000")" || exit 1
echo "$sd:$tsmin"
