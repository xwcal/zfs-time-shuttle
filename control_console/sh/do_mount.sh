if ! [ -d "$LST_MNT" ]; then
    mkdir "$LST_MNT" || exit 1
elif mountpoint -q "$LST_MNT"; then
    umount "$LST_MNT" || exit 1
fi

mount -t zfs -o ro "$BASE/.zfsrb/$1" "$LST_MNT" 
