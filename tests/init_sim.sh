echo "### [init_sim]"

_proc_cmdline="$1"

timestamp="$2"

export rootmnt="$3"

kexec_fail="$4"

# so that zfs_custom_boot has something to call:

panic() {
    echo "$1"
}

log_begin_msg() {
    : # echo "Begin running: $1"
}

run_scripts() {
    : # echo "Running it ..."
}

log_end_msg() {
    : # echo "Done"
}

# overwrites the date command so that unixts() in zfs_custom_boot uses the timestamp passed in
date() {
    echo "$timestamp"
}

# overwrites kexec to simulate a shutdown
# -- counting on grub_sim to simulate the reboot
kexec() {
    if [ -n "$kexec_fail" ]; then
        echo "EVENT: kexec failing"
        return 1
    else
        echo "EVENT: kexec initiated"
        exit 100
    fi
}

reboot() {
    echo "EVENT: rebooting"
    exit 50
}

# got from /usr/share/initramfs-tools/init:
for x in $_proc_cmdline; do
	case $x in
	init=*)
		init=${x#init=}
		;;
	root=*)
		ROOT=${x#root=}
		if [ -z "${BOOT}" ] && [ "$ROOT" = "/dev/nfs" ]; then
			BOOT=nfs
		fi
                ;;
	rootflags=*)
		ROOTFLAGS="-o ${x#rootflags=}"
		;;
	rootfstype=*)
		ROOTFSTYPE="${x#rootfstype=}"
		;;
	rootdelay=*)
		ROOTDELAY="${x#rootdelay=}"
		case ${ROOTDELAY} in
		*[![:digit:].]*)
			ROOTDELAY=
			;;
		esac
		;;
	resumedelay=*)
		RESUMEDELAY="${x#resumedelay=}"
		;;
	loop=*)
		LOOP="${x#loop=}"
		;;
	loopflags=*)
		LOOPFLAGS="-o ${x#loopflags=}"
		;;
	loopfstype=*)
		LOOPFSTYPE="${x#loopfstype=}"
		;;
	cryptopts=*)
		cryptopts="${x#cryptopts=}"
		;;
	nfsroot=*)
		NFSROOT="${x#nfsroot=}"
		;;
	netboot=*)
		NETBOOT="${x#netboot=}"
		;;
	ip=*)
		IP="${x#ip=}"
		;;
	ip6=*)
		IP6="${x#ip6=}"
		;;
	boot=*)
		BOOT=${x#boot=}
		;;
	ubi.mtd=*)
		UBIMTD=${x#ubi.mtd=}
		;;
	resume=*)
		RESUME="${x#resume=}"
		case $RESUME in
	        UUID=*)
			RESUME="/dev/disk/by-uuid/${RESUME#UUID=}"
		esac
		;;
	resume_offset=*)
		resume_offset="${x#resume_offset=}"
		;;
	noresume)
		noresume=y
		;;
	drop_capabilities=*)
		drop_caps="-d ${x#drop_capabilities=}"
		;;
	panic=*)
		panic="${x#panic=}"
		case ${panic} in
		*[![:digit:].]*)
			panic=
			;;
		esac
		;;
	quiet)
		quiet=y
		;;
	ro)
		readonly=y
		;;
	rw)
		readonly=n
		;;
	debug=*)
		debug=y
		quiet=n
		set -x
		;;
	break=*)
		break=${x#break=}
		;;
	break)
		break=premount
		;;
	blacklist=*)
		blacklist=${x#blacklist=}
		;;
	BOOTIF=*)
		BOOTIF=${x#BOOTIF=}
		;;
	hwaddr=*)
		BOOTIF=${x#hwaddr=}
		;;
	fastboot|fsck.mode=skip)
		fastboot=y
		;;
	forcefsck|fsck.mode=force)
		forcefsck=y
		;;
	fsckfix|fsck.repair=yes)
	    fsckfix=y
		;;
	fsck.repair=no)
		fsckfix=n
		;;
	recovery)
		recovery=y
		;;
	esac
done

. ../scripts/zfs_custom_boot

# overwriting parse_kargs()
# keep in sync with zfs_custom_boot, but replace $(cat /proc/cmdline) with $_proc_cmdline
parse_kargs() {
    # IN/OUT:
    # $csbm
    # $rebtfs
    # $builder_mode
    # $delay
    local x
    for x in $_proc_cmdline; do
        case $x in
            bootmode=*)
                csbm=${x#bootmode=}
                ;;
            kexeced)
                rebtfs=y
        esac
    done
    case $csbm in
        rn|ra|cn|ca)
        # can't use $BMRE here, which unlike in [[ =~ ]], would be taken as a literal string (even without double quote)
            ;;
        builder)
            builder_mode=y
            ;;
        *)
            cbpanic "Unknown bootmode: $csbm"
            return 1
    esac
    delay=$(echo "$ROOTDELAY"| sed -rn 's,(^[0-9]*$),\1,p')
    delay=${delay:-0}
}

#overwriting import_pool()
import_pool() {
    # IN:
    # $pool
    # $delay
    # $csbm
    local op
    case $csbm in
        rn|ra)
            op=-L
    esac
    
    local stat=
    local ac=0
    while ! try_import_pool && [ $ac -lt $delay ]; do
        ac=$((ac+1))
        /bin/sleep 1
    done
    if [ "$stat" != ONLINE ]; then
        cbpanic "Unable to import $pool; try to do it manually.
Hint: Try:  zpool import -f -R / -N $pool"
        if ! [ "$($ZFS_HEALTH "$pool")" = ONLINE ]; then
            return 1
        fi
    fi
}

# overwriting try_import_pool()
try_import_pool() {
    # IN:
    # $pool
    # $op
    # IN/OUT:
    # $stat
    set -x
    if ! zpool import $op "$pool" -d /dev/shm/ -R "$rootmnt"; then
        return 1
        set +x
    fi
    set +x
    if ! stat="$($ZFS_HEALTH "$pool")"; then
        cbpanic "Exception at: $ZFS_HEALTH $pool"
    fi
    [ "$stat" = ONLINE ]
}

mountroot

retval=$?

unset rootmnt

exit $retval
