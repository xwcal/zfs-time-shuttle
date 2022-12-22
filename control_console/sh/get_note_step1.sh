. sh/defs.sh
if [ -n "$4" ]; then
    . sh/do_mount.sh "$4" || exit 1
fi
cat "$LST_MNT/.zfs/snapshot/$1/$ZTS_DIR/${2}_$3"
# name each note as ${rbp}_$csts when creating the note -- so that just in case the mounting in list_snaps.sh misbehaves, we still get the correct note if we get one at all.
