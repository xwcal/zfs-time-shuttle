grub_ia() {
    echo "### [grub_ia]"
    # local -a incs=(0 $RANDOM)
    local retval
    local bm inc
    local kexec_fail
    
    schoice bm BOOTMODES
    # schoice inc incs
    inc=$RANDOM
    NOWTS=$((NOWTS+inc))
    # 30% chance kexec fails:
    if [ $((RANDOM%100)) -lt 50 ]; then
        kexec_fail=y
    else
        kexec_fail=n
    fi
    grub_sim $bm $NOWTS $kexec_fail
    retval=$?

    if [ $retval = 0 ]; then
        grub_ia_tests
    elif [ $retval = 50 ]; then
        # log short admin session
        if [ $bm = ca ]; then
            CASS[$NOWTS]=y
        elif [ $bm = ra ]; then
            RASS[$NOWTS]=y
        fi
        # when 50, everything except mounting is done, so can do tests as usual:
        grub_ia_tests
    else
        # don't want to mess with zfs_custom_boot for this, so just add a note:
        if [ $inc = 0 ]; then
            echo "EXPECTED ERROR: zfs_custom_boot: unix time stamp of current session ..." >&2
        fi
    fi
    return $retval
}

grub_ia_tests() {
    local bootfs
    local actual_orig
    local expected_orig
    local psbm
    local psbm_saved
    local psts
    local rbp
    local rsp
    local cbp
    local csp
    local ncbp
    local ncsp
    local sd

    # TEST: Have the snapshots been taken? Has old session branch been archived?
    while [ $REVERTED = y ]; do
        REVERTED=n

        # Could be that the revert never touched the control branch,
        # in which case the test doesn't hurt.
        # But just in case it was a "branching under the foot" --
        # has the old branch got its snapshot?

        local fn
        
        sd=$PS_SD
        parse_sd
        if [ $psbm = ca ]; then
            fn="$BASE/$CBC/$cbp@$psts"
            if zfs_exist "$fn"; then
                log_success "After $psbm branching, snapshot exists: $fn"
            else
                log_error "After $psbm branching, missing snapshot: $fn"
            fi
        elif [ $psbm = cn ]; then
            fn="$BASE/$CSBC/archive/${cbp}_${csp}_$psts"
            if zfs_exist "$fn"; then
                log_success "After $psbm branching, archive exists: $fn"
            else
                log_error "After $psbm branching, missing archive: $fn"
            fi
        else
            bail "REVERTED=y for psbm $psbm"
        fi
        fn="$BASE/$CBC/$cbp/home@$psts"
        if zfs_exist "$fn"; then
            log_success "After $psbm branching, snapshot exists: $fn"
        else
            log_error "After $psbm branching, missing snapshot: $fn"
        fi
        
        break; # use while to allow early break; but remember this break!
    done

    # TEST: Is bootfs updated?
    if [ $BOOTFS_CHANGED = y ]; then
        BOOTFS_CHANGED=n

        # get boot mode first
        sd=$PS_SD
        parse_sd
        psbm_saved=$psbm
        # then get up to date pointers
        sd="$($ZFS_GET $ZPROP_SD "$BASE")" || bail "Cannot $ZFS_GET $ZPROP_SD $BASE"
        parse_sd
        case "$psbm_saved" in
            ra)
                bootfs=regular
                expected_orig="$BASE/$RBC/$rbp/boot@$rsp"
            ;;
            ca|cn)
                bootfs=control
                expected_orig="$BASE/$CBC/$cbp/boot@$csp"
            ;;
            *)
                bail "BOOTFS_CHANGED=y for psbm_saved $psbm_saved"
        esac
        actual_orig="$($ZFS_GET origin "$BASE/boot/$bootfs")" ||
            bail "Cannot $ZFS_GET origin $BASE/boot/$bootfs"
        if [ "$actual_orig" = "$expected_orig" ]; then
            log_success "bootfs updated!"
        else
            log_error "bootfs not updated: actual_orig $actual_orig != expected_orig $expected_orig"
        fi
    fi
}

