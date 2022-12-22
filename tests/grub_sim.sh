grub_sim() {
    echo "### [grub_sim]"

    # pass back out some paramters
    BOOTMODE="$1"

    local zfs_pool="$POOL"
    local zfs_base_fs="$BASE_FS"

    case $1 in
        rn|ra)
            bootfs=/$zfs_base_fs/boot/regular
            ;;
        cn|ca)
            bootfs=/$zfs_base_fs/boot/control
            ;;
        builder)
            bootfs=/$zfs_base_fs/root/boot
            ;;
        *)
            echo "Unknown bootmode: $1"
            exit 1
    esac

    # Better include pwd in PATH
    # Both zfs and zpool are in /sbin, so PATH needs to include that as well

    local path=$PWD:"$INITRD_DIR"/bin:"$INITRD_DIR"/sbin:/sbin
    
    # the ro in grub.cfg is useless -- removed
    echo "grub calling init with: \"${bootfs}@/vmlinuz bootmode=$1 root=ZFS=$zfs_pool/$zfs_base_fs\" \"$2\" \"$ROOT\" \"$3\""
    env -i PATH=$path ash init_sim.sh "${bootfs}@/vmlinuz bootmode=$1 root=ZFS=$zfs_pool/$zfs_base_fs" "$2" "$ROOT" "$3"
    # could use -x option to enable line by line output for debuging

    local retval=$?
    #TEST: is kexec handled properly?
    # kexec simulation continues here:
    if [ $retval = 100 ]; then
        log_event "kexec continues"
        env -i PATH=$path ash init_sim.sh "kexeced ${bootfs}@/vmlinuz bootmode=$1 root=ZFS=$zfs_pool/$zfs_base_fs" "$2" "$ROOT" "$3"
        retval=$?
        if [ $retval = 0 ]; then
            log_success "init_sim kexec done"
        else
            log_error "init_sim kexec failed"
        fi
    elif [ $retval = 50 ]; then
        : # Null command
    elif [ $retval = 0 ]; then
        log_success "init_sim done"
    else
        log_error "init_sim failed"
    fi
    return $retval
}
