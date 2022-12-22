# note NOWTS is expected to be -eq to csts, but not necessarily =
CSTS=
OLD_SD=

user_ia() {
    echo "### [user_ia]"
    CSTS=$(printf '%010d' $NOWTS)
    OLD_SD=$PS_SD
    PS_SD="$($ZFS_GET $ZPROP_SD "$BASE")" || bail "Cannot $ZFS_GET $ZPROP_SD $BASE"
    echo "sd=$PS_SD"
    do_writes
    do_reads
    maybe_changebootfs
    do_reverts
}

do_writes() {
    # a wrong ROOT could cause some serious damage, so guard against that:
    [ "$ROOT" = /dev/shm/root ] || bail "Unexpected ROOT=$ROOT"

    local -i n
    log_event "Launching $BF_NPROC bf_writer_proc(s) and $SF_NPROC sf_writer_proc(s)"
    for ((n=0; n<BF_NPROC; n++)); do
        # get rid of the job launching messages:
        # https://stackoverflow.com/a/27340076
        { bf_writer_proc "BF$n" $BF_REP 2>&3 &} 3>&2 2>/dev/null
    done
    for ((n=0; n<SF_NPROC; n++)); do
        # get rid of the job launching messages:
        # https://stackoverflow.com/a/27340076
        { sf_writer_proc "SF$n" $SF_REP 2>&3 &} 3>&2 2>/dev/null
    done
    wait 2>/dev/null
    log_event "writer procs completed"

    record_snapnote

    write_home
}

sf_writer_proc() {
    local id="$1"
    local -i rep="$2"
    local -i n
    for ((n=1; n<=rep; n++)); do
        sf_write "${CSTS}_$id" $n || log_error "sf_write ${CSTS}_$id $n"
        delete "${CSTS}_$id" || log_error "delete ${CSTS}_$id"
    done
    sf_write "${CSTS}_$id" $rep || log_error "sf_write ${CSTS}_$id $rep"
}

bf_writer_proc() {
    local id="$1"
    local -i rep="$2"
    local -i n
    for ((n=1; n<=rep; n++)); do
        bf_write "${CSTS}_$id" || log_error "bf_write ${CSTS}_$id"
        delete "${CSTS}_$id" || log_error "delete ${CSTS}_$id"
    done
    if [ "$KEEP_BIG_FILE" = y ]; then
        bf_write "${CSTS}_$id" || log_error "bf_write ${CSTS}_$id"
    fi
}

sf_write() {
    mkdir "$ROOT/$1" || return 1
    local -i n
    for ((n=0; n<$2; n++)); do
        echo "$1" >> "$ROOT/$1/$1" || return 1
    done
}

bf_write() {
    mkdir "$ROOT/$1" || return 1
    cp "$BIG_FILE" "$ROOT/$1/$1"
}

delete() {
    rm "$ROOT/$1/$1" || return 1
    rmdir "$ROOT/$1"
}

record_snapnote() {
    if [ $BOOTMODE != ra ]; then return; fi

    local rbp=${PS_SD#*:*:}
    rbp=${rbp%%:*}
    if ! [ -d "$ROOT/zts" ]; then
        mkdir "$ROOT/zts" || {
            log_error "Cannot mkdir $ROOT/zts"
            return 1
        }
    fi
    echo "branch@snap:
$rbp@$CSTS
sd:
$PS_SD
date time:
$(date --rfc-3339=seconds)
" > "$ROOT/zts/${rbp}_$CSTS" || {
        log_error "Failed to write $ROOT/zts/${rbp}_$CSTS"
        return 1
    }
}

write_home() {
    echo $CSTS >> "$ROOT/home/all_ts"
    echo $CSTS > "$ROOT/home/$CSTS"
    mkdir "$ROOT/home/dir_$CSTS"
    echo $CSTS > "$ROOT/home/dir_$CSTS/$CSTS"
}


do_reads() {
    local bc
    local sbc
    local bp
    local sp
    local ts
    local -i sf_ok_ct
    local -i bf_ok_ct

    local psbm
    local psts
    local rbp
    local rsp
    local cbp
    local csp
    local ncbp
    local ncsp
    local sd
    
    read_current_normal
    read_previous_normal
}

read_current_normal() {
    read_normal_common_init $PS_SD || return 0
    log_event "read_current_normal"
    if [ $bp = $sp ]; then
        # first snap in a branch doesn't have files of its own
        # have to check the origin's ts
        local orig
        while true; do
            echo "snap $sp is the first of branch $bp, tracing origin ..."
            orig="$($ZFS_GET origin "$BASE/$bc/$bp")" ||
                bail "Cannot $ZFS_GET origin $BASE/$bc/$bp"
            orig="${orig##*/}"
            bp="${orig%%@*}"
            sp="${orig#*@}"
            if [ "$bp" != "$sp" ]; then break; fi
        done
        if [ $sp = baseline ]; then
            echo "reached baseline -- no reads necessary"
            return 0
        fi
    fi
    ts=$sp
    # no need to check short sessions
    local ss
    case $psbm in
        rn)
            ss=${RASS[$ts]}
            ;;
        cn)
            ss=${CASS[$ts]}
    esac
    if [ -n "$ss" ]; then
        log_event "$bc/$bp@$sp is a short session -- no reading needed"
        return 0
    fi
    read_normal_common "$ROOT" "curr"
}

read_previous_normal() {
    read_normal_common_init $OLD_SD || return 0
    log_event "read_previous_normal"
    ts=$psts
    if ! [ -d "$PN_MNT" ]; then
        mkdir "$PN_MNT" || bail "Cannot mkdir $PN_MNT"
    fi
    $ZFS_MOUNT "$BASE/$sbc/archive/${bp}_${sp}_$psts" "$PN_MNT" ||
        bail "Cannot $ZFS_MOUNT $BASE/$sbc/archive/${bp}_${sp}_$psts to $PN_MNT"
    read_normal_common "$PN_MNT" "prev"
    $ZFS_UNMOUNT "$PN_MNT" || bail "Cannot $ZFS_UNMOUNT $PN_MNT"
}

read_normal_common_init() {
    sd=$1
    if [ -z "$sd" ]; then return 1; fi
    parse_sd
    case $psbm in
        rn)
            bc=$RBC
            sbc=$RSBC
            bp=$rbp
            sp=$rsp
            ;;
        cn)
            bc=$CBC
            sbc=$CSBC
            bp=$cbp
            sp=$csp
            ;;
        ra|ca)
            return 1
    esac
}

read_normal_common() {
    local mtpt="$1"
    local caller="$2"
    
    read_either "small"
    
    if [ "$KEEP_BIG_FILE" != y ]; then return 0; fi

    read_either "big"
}

read_either() {
    local -i nproc
    local -i n
    local read_func
    local tp
    local -i ok_ct=0
    if [ "$1" = "big" ]; then
        nproc=$BF_NPROC
        read_func=bf_read
        tp=BF
    else
        nproc=$SF_NPROC
        read_func=sf_read
        tp=SF
    fi
    for ((n=0; n<nproc; n++)); do
        if $read_func "${ts}_$tp$n"; then
            ok_ct+=1
        else
            log_error "$caller $read_func failed at ${ts}_$tp$n"
        fi
    done
    if [ $ok_ct -eq $nproc ]; then
        log_success "$caller $read_func got $ok_ct/$nproc successes"
    else
        log_error "$caller $read_func got only $ok_ct/$nproc successes"
    fi
}

sf_read() {
    local wcl=$(set -o pipefail; grep -e "^$1\$" "$mtpt/$1/$1"| wc -l) || return 1
    [  "$wcl" = "$SF_REP" ]
}

bf_read() {
    local chksum
    checksum chksum "$mtpt/$1/$1"
    [ "$chksum" = "$BIG_FILE_HASH" ]
}

maybe_changebootfs() {
    case $BOOTMODE in rn|cn) return; esac
    
    # 30% chance there is a change:
    if [ $((RANDOM%100)) -lt 30 ]; then
        BOOTFS_CHANGED=y
        echo "$CSTS" >> "$ROOT/boot/vmlinuz"
        log_event "Changed bootfs"
    fi
}

do_reverts() {
    case $BOOTMODE in rn|ra) return; esac
    
    local -i count=$((RANDOM%5))
    local -i n
    local -i fails=0
    log_event "Doing $count reverts:"
    for ((n=0; n<$count; n++)); do
        REVERTED=y # in case count is 0
        do_one_revert || fails+=1
    done
    log_event "$((count-fails)) reverts done."
}

do_one_revert() {
    local bc
    local -a branches
    local -a rootsnaps
    local -a homesnaps
    local rootbr rootsnp
    local homebr homesnp
    local sd
    local retval
    
    pushd "$REVERT_SCRIPT_DEST"
    
    schoice bc BCS
    branches=($(list_branches "$bc")) || {
        log_error "list_branches $bc returned $?"
        popd
        return 1
    }
    
    lchoice rootbr branches
    rootsnaps=($(list_snaps "$bc" "$rootbr")) || {
        log_error "list_snaps $bc $rootbr returned $?"
        popd
        return 1
    }
    lchoice rootsnp rootsnaps
    
    lchoice homebr branches
    homesnaps=($(list_snaps "$bc" "$homebr")) || {
        log_error "list_snaps $bc $homebr returned $?"
        popd
        return 1
    }
    lchoice homesnp homesnaps

    revert_it
    retval=$?
    if [ $retval = 0 ]; then
        log_success "revert_it on $rootbr@$rootsnp $homebr@$homesnp $bc succeeded!"
    elif revert_it_error_expected; then
        log_success "revert_it successfully detected error"
        popd
        return 1
    else
        log_error "revert_it on $rootbr@$rootsnp $homebr@$homesnp $bc returned $retval"
        popd
        return 1
    fi

    PS_SD_RVTD="$($ZFS_GET $ZPROP_SD "$BASE")" || bail "Cannot $ZFS_GET $ZPROP_SD $BASE"
    if [ $PS_SD_RVTD != $PS_SD ] && [ "$bc" = "$CBC" ]; then
        log_event "Changed bootfs through revert"
        BOOTFS_CHANGED=y
    fi
    
    popd
}


list_branches() {
    bash sh/list_branches_impl.sh "$1" n
}

list_snaps() {
    bash sh/list_snaps_impl.sh "$1" "$2" n
}

revert_it() {
    bash sh/revert_impl.sh "$rootbr" "$rootsnp" "$homebr" "$homesnp" "$bc"
}

revert_it_error_expected() {
    if [ $rootbr != $homebr ] && [ $rootbr = $CSTS ] || [ $homebr = $CSTS ]; then
        return 0
    fi
    return 1
}
