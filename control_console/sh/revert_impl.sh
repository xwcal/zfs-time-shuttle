# CDDL HEADER START
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# https://www.opensource.org/licenses/CDDL-1.0
#
# CDDL HEADER END
#
# Copyright (C) 2019 Xiao Wan

. sh/defs.sh

rootbr="$1"
rootsnp="$2"
homebr="$3"
homesnp="$4"
bc="$5"

base="$BASE"

bail() {
    echo "$1" > /dev/stderr
    log "$1"
    exit 1
}

log() {
    local t="$(date --rfc-3339=seconds)"
    echo "$t
errmsg=$1
sd=$sd
rootbr=$rootbr
rootsnp=$rootsnp
homebr=$homebr
homesnp=$homesnp
bc=$bc
base=$base
" >> errlog
}

# using bash's regexp feature:
# taken from boot_customization/custom2/zfs_custom_boot
# -- didn't do all that in vain ...
BMRE='rn|ra|cn|ca'
TSRE='[0-9]{10}'
sd="$($ZFS_GET $ZPROP_SD "$base")" || bail "$ZFS_GET $ZPROP_SD $base returned $?"
[[ "${sd}" =~ ^(${BMRE}):(${TSRE}):(${TSRE}):(${TSRE}):(${TSRE}):(${TSRE}):(${TSRE}|_):(${TSRE}|_)$ ]] ||
    bail "Illegal sd: $sd"
csbm=${BASH_REMATCH[1]}
csts=${BASH_REMATCH[2]}
rbp=${BASH_REMATCH[3]}
rsp=${BASH_REMATCH[4]}
cbp=${BASH_REMATCH[5]}
csp=${BASH_REMATCH[6]}
ncbp=${BASH_REMATCH[7]}
ncsp=${BASH_REMATCH[8]}

[ $csts -ge $rsp ] || bail "csts $csts is less than rsp $rsp"
[ $rsp -ge $rbp ] || bail "rsp $rsp is less than rbp $rbp"
[ $csts -ge $csp ] || bail "csts $csts is less than csp $csp"
[ $csp -ge $cbp ] || bail "csp $csp is less than cbp $cbp"
{ [ $ncbp = _ ] && [ $ncsp = _ ]; } || { [ $ncbp != _ ] && [ $ncsp != _ ]; } ||
    bail "Illegal ncbp $ncbp and ncsp $ncsp"

case "$bc" in
    .zfscb|.zfsrb)
    ;;
    *)
        bail "Illegal branch container: $bc"
esac

# using bash's array feature
branches=($(. sh/list_branches_impl.sh "$bc" n)) ||
    bail ". sh/list_branches_impl.sh $bc n returned $?"

[[ "$rootbr" =~ ^${TSRE}$ ]] || bail "Illegal rootbr: $rootbr"
[[ "$rootsnp" =~ ^${TSRE}$ ]] || bail "Illegal rootsnp: $rootsnp"
[[ "$homebr" =~ ^${TSRE}$ ]] || bail "Illegal homebr: $homebr"
[[ "$homesnp" =~ ^${TSRE}$ ]] || bail "Illegal homesnp: $homesnp"
[[ "${branches[0]}" =~ ^${TSRE}$ ]] ||
    bail "Illegal branch name encountered: $base/$bc/${branches[0]}"
        
[ $csts -ge ${branches[0]} ] ||
    bail "csts $csts is less than last branch ${branches[0]}"


# Note the script is only designed to handle previous reverts in the current session,
# failed or successful. It does not deal with messes created by other means. Nor is
# it designed to handled concurrent access to zfs. With these assumptions, as long as
# the bootfs is ok and the sd is correct, we know we have done a successful revert.

# (the filesystem has to be mounted for this command to work)
ZFS_DIFF='zfs diff -H' # use 'zfs diff -FHt' if want sophisticated checks
bootfs_ok() {
    local orig="$($ZFS_GET origin "$base/boot/$bootfs")" || return 1
    local expected="$base/$bc/$rootbr/boot@$rootsnp"
    local mtpt="$RVT_MNT"
    local chng

    # Do some checking like that in kupdated() of zfs_custom_boot
    # return true if expected is same as orig, or is newer but with
    # unchanged vmlinuz|initrd|initramfs
    # return false otherwise
    if [ "$orig" = "$expected" ]; then
        # zfs diff wants arg1 to be an earlier snapshot on the same fs
        # as arg2, or fails with return code 1
        # so deal with the case of arg1 = arg2 first
        return 0
    fi
    if ! [ -d "$mtpt" ]; then
        mkdir "$mtpt" || return 1
    fi
    mount -t zfs -o ro "${orig%@*}" "$mtpt" || return 1
    chng="$($ZFS_DIFF "$orig" "$expected")" || {
        # if expected is older than orig, or on a different fs
        umount "$mtpt"
        return 1
    }
    umount "$mtpt"    
    ! echo "$chng" | grep -E 'vmlinuz|initrd|initramfs' >/dev/null
}

if [ $rootbr = $csts ] && [ $homebr = $csts ]; then
    case $bc in
        .zfscb)
            bootfs=control
            if [ $ncbp = $rootbr ] && [ $ncsp = $rootsnp ] && bootfs_ok; then
                exit 0
            else
                bail "Illegal combination of ncbp $ncbp, rootbr $rootbr, and homebr $homebr"
            fi
            ;;
        .zfsrb)
            bootfs=regular
            if [ $rbp = $rootbr ] && [ $rsp = $rootsnp ] && bootfs_ok; then
                exit 0
            else
                bail "Illegal combination of rbp $rbp, rootbr $rootbr, and homebr $homebr"
            fi
    esac
fi

if [ $rootbr != $homebr ] && [ $rootbr = $csts ] || [ $homebr = $csts ]; then
    bail "Illegal combination of csts $csts, rootbr $rootbr, and homebr $homebr"
fi

zfs_exist() {
    # $1: fs path
    zfs list "$1" >/dev/null 2>&1
}

zfs_exist "$base/$bc/$rootbr" || bail "$base/$bc/$rootbr does not exist!"
zfs_exist "$base/$bc/$homebr" || bail "$base/$bc/$homebr does not exist!"


cleanup_prevrevert() {
    local cl
    local -i n subct snpct
    local branch="$base/$bc/$csts"
    if [ $csts != ${branches[0]} ]; then return 0; fi
    # do some checks first lest we delete a valuable branch:
    cl=$(zfs list -Hpoclones "$branch@$csts") || return 1
    if [ -n "$cl" ]; then
        echo "$branch@$csts has clones: $cl" >> /dev/stderr
        return 1
    fi
    n=$(set -o pipefail; zfs list -d1 -tsnapshot -Hproname "$branch" | wc -l) ||
        return 1
    if [ $n != 1 ]; then
        echo "$branch has more than 1 snapshots: $n" > /dev/stderr
        return 1
    fi
    subct=$(set -o pipefail; zfs list -tfilesystem -Hproname "$branch" | wc -l) ||
        return 1
    snpct=$(set -o pipefail; zfs list -tsnapshot -Hproname "$branch" | wc -l) ||
        return 1
    if [ $subct -lt $snpct ]; then
        echo "More snaps than subs: subct=$subct, snpct=$snpct" > /dev/null
        return 1
    fi
    zfs destroy -R "$branch"
}


# Actually start to perform the revert
# There are two cases:

# (A) if rootbr and homebr are the same and their snaps are the latest
# in that branch, then we can simply update the pointers.
# Note we don't rollback since the last snaps are identical to the heads (INV_ID)
# -- with one exception:
# When we are in a control mode session, we are ahead of $cbp/home@"somets",
# and in case of ca, of $cbp@$csp.
# Nontheless, just treat an attempt to revert to them as a no-op.

# (B) otherwise

selected=
select_case() {
    local last_rootsnp
    local last_homesnp
    if [ $rootbr != $homebr ]; then
        selected=B
        return 0
    fi
    last_rootsnp="$(set -o pipefail; . sh/list_snaps_impl.sh "$bc" "$rootbr" n | head -n1)" || {
        # https://stackoverflow.com/questions/19120263/why-exit-code-141-with-grep-q
        if [ $? != 141 ]; then
            echo "Exception at: . sh/list_snaps_impl.sh $bc $rootbr n | head -n1"
            return 1
        fi
    }
    if [ $rootsnp != "$last_rootsnp" ]; then
        selected=B
        return 0
    fi
    last_homesnp="$(set -o pipefail; . sh/list_snaps_impl.sh "$bc" "$rootbr/home" n | head -n1)" || {
        if [ $? != 141 ]; then
            echo "Exception at: . sh/list_snaps_impl.sh $bc $rootbr/home n | head -n1"
            return 1
        fi
    }
    if [ $homesnp != "$last_homesnp" ]; then
        selected=B
        return 0
    fi
    selected=A
}

select_case || bail "select_case failed"

cleanup_prevrevert || bail "cleanup_prevrevert failed"

ZFS_CLONE="zfs clone -o mountpoint=legacy"

if [ $selected = A ]; then
    branch="$base/$bc/$rootbr"
    case $bc in
        .zfscb)
            bootfs=control
            if [ $cbp = $rootbr ] && [ $csp = $rootsnp ]; then
                if [ $ncbp = _ ] && [ $ncsp = _ ] && bootfs_ok; then
                    exit 0
                fi
                ncbp=_
                ncsp=_
            elif [ $ncbp = $rootbr ] && [ $ncsp = $rootsnp ] && bootfs_ok; then
                exit 0
            else
                # leave cbp and csp unchanged
                ncbp=$rootbr
                ncsp=$rootsnp
            fi
            ;;
        .zfsrb)
            bootfs=regular
            if [ $rbp = $rootbr ] && [ $rsp = $rootsnp ] && bootfs_ok; then
                exit 0
            fi
            rbp=$rootbr
            rsp=$rootsnp
    esac
else
    branch="$base/$bc/$csts"
    case $bc in
        .zfscb)
            bootfs=control
            # leave cbp and csp unchanged
            ncbp=$csts
            ncsp=$csts
            ;;
        .zfsrb)
            bootfs=regular
            rbp=$csts
            rsp=$csts
    esac

    # -- the part below is based on zfs_custom_boot ( particularly set_things_up() ):
    ZFS_LIST_NPREMNT_FSTREE="zfs list -Hproname,devices,setuid,exec,$ZPROP_MT -sname -tfilesystem"

    # 1) clone everything but /home
    b="$base/$bc/$rootbr"
    snp=$rootsnp
    expectedmt=auto
    fsls="$($ZFS_LIST_NPREMNT_FSTREE "$b")" ||
        bail "Exception at: $ZFS_LIST_NPREMNT_FSTREE $b"

    echo "$fsls" |  while IFS="$TABIFS" read fs devices setuid exec mt; do
        if [ $mt = $expectedmt ]; then
            $ZFS_CLONE -o devices=$devices -o setuid=$setuid \
                       -o exec=$exec -o $ZPROP_MT=$mt "$fs@$snp" "$branch${fs#$b}" ||
                bail "Exception at: $ZFS_CLONE -o devices=$devices -o setuid=$setuid \
                   -o exec=$exec -o $ZPROP_MT=$mt $fs@$snp $branch${fs#$b}"
        fi
    done || exit 1

    # 2) clone /home using the same (overkill) procedure as above
    # Just ZFS_LIST_NPREMNT_FSTREE without r
    ZFS_LIST_HOME="zfs list -Hponame,devices,setuid,exec,$ZPROP_MT -sname -tfilesystem"
    b="$base/$bc/$homebr"
    snp=$homesnp
    expectedmt=snap
    fsls="$($ZFS_LIST_HOME "$b/home")" ||
        bail "Exception at: $ZFS_LIST_HOME $b/home"

    echo "$fsls" | while IFS="$TABIFS" read fs devices setuid exec mt; do
        if [ $mt = $expectedmt ]; then
            $ZFS_CLONE -o devices=$devices -o setuid=$setuid \
                       -o exec=$exec -o $ZPROP_MT=$mt "$fs@$snp" "$branch${fs#$b}" ||
                bail "Exception at: $ZFS_CLONE -o devices=$devices -o setuid=$setuid \
                   -o exec=$exec -o $ZPROP_MT=$mt $fs@$snp $branch${fs#$b}"
        fi
    done || exit 1

    # 3) take snapshots
    ZFS_RSNAP="zfs snapshot -r"
    $ZFS_RSNAP "$branch@$csts" || bail "Exception at: $ZFS_RSNAP $branch@$csts"
fi

# Proceed from either A or B

# update bootfs (based on update_bootfs())
if zfs_exist "$base/boot/$bootfs"; then
    if orig="$($ZFS_GET origin "$base/boot/$bootfs")"; then
        orig="${orig##*/}"
        origbp="${orig%%@*}"
        origsp="${orig#*@}"
        zfs rename "$base/boot/$bootfs" "$base/boot/${bootfs}_${origbp}_$origsp" ||
            zfs destroy "$base/boot/$bootfs"
    else
        zfs destroy "$base/boot/$bootfs"
    fi
fi
if [ $selected = A ]; then
    snp=$rootsnp
else
    snp=$csts
fi
$ZFS_CLONE "$branch/boot@$snp" "$base/boot/$bootfs" ||
    bail "Exception at: $ZFS_CLONE $branch/boot@$snp $base/boot/$bootfs"

# finally, update the pointers:
new_sd=$csbm:$csts:$rbp:$rsp:$cbp:$csp:$ncbp:$ncsp
zfs set $ZPROP_SD=$new_sd "$base"
