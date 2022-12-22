POOL=testpool
BASE_FS=ubuntu

# init_sim.sh also has a ROOT, but there isn't a conflict as long as init_sh.sh is only invoked by grub_sim.sh through ash and we don't export ROOT elsewhere
ROOT=/dev/shm/root # and use it below

# need to extract the image first:
# unmkinitramfs /boot/initrd.img-4.15.0-48-generic /dev/shm/initrd/
INITRD_DIR=/dev/shm/initrd/main

DEV_SIZE=1G

SESSION_COUNT=100

# starting unix timestamp (updated by grub_ia):
# NOWTS=1552871903
NOWTS=$(date +%s)

# seed for repeatability (do_writes in user_ia.sh is the only place multiprocessing is used, and doesn't use RANDOM):
RANDOM=123 # with SESSION_COUNT=50, got no error with RANDOM=123 and RANDOM=321

BIG_FILE_SOURCE=/boot/vmlinuz-4.15.0-48-generic # 8M

BIG_FILE=/dev/shm/vmlinuz-4.15.0-48-generic

KEEP_BIG_FILE=n # if y, user_ia keeps the big file at the end of each session

REVERT_SCRIPT_SOURCE=../control_console/sh/

REVERT_SCRIPT_DEST=/dev/shm/ttc # could put on zfs, but then up to date errlog would be hard to find 


SF_NPROC=10
SF_REP=1
BF_NPROC=3
BF_REP=2

PN_MNT=/dev/shm/pn_mnt # don't use /dev/shm/mnt -- revert_impl.sh uses it to check if bootfs is ok
