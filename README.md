# ZFS Time Shuttle

## History

Back in late 2017, when I finally decided to migrate from Windows to Linux, I discovered ZFS and it was like a dream come true: over the many years I had spent with Windows countless problems could have been easily fixed by cleanly reverting the system to an earlier good state.

ZFS Time Shuttle (ZTS) was designed with the following users in mind:
- those who are not tech savvy and are tired of having to deal with irreversible changes to their systems by unknown forces;
- those who are tech savvy but don't make frequent big changes to their systems.

The acronym collision is unfortunate but context should make it clear which ZTS we are talking about (I did not initially have plans to [mess with ZFS internals](https://github.com/xwcal/zfs-unlimited) so wasn't aware of the other ZTS; fortunately we don't need to worry about testing ZFS here).

I only learned much later that Ubuntu was also building its own ZFS based operating system versioning solution, called [ZSys](https://github.com/ubuntu/zsys).

My design doesn't require editing C code and compiling grub, so flexibility is probably its biggest advantage. Also, the on-disk layout is simple enough to be managed manually so there is no lock-in concerns. Moreover, the control console runs in a complete OS environment, allowing potentially unlimited possibilities.


## Design

ZTS manages datasets under a base file system (recall in ZFS nomenclature, a dataset is either a filesystem, a volume, or a snapshot) such that
each state has three dimensions: `/`, `/boot`, and `/home`
and is captured by a point in time snapshot on these three dimensions, identified by the corresponding unix time (whole seconds).

There are four types of sessions:
- rn -- regular normal
- ra -- regular admin
- cn -- control normal
- ca -- control admin

Once a baseline state has been set up, a two sided tree grows out of the baseline: the regular side and the control side.

The regular side is for daily use (rn) and routine maintainance (ra) while the control side is for doing recovery (cn) in case something goes wrong on the regular side.

At boot, grub (with specially configured stage 1.5) reads grub.cfg on the current `/boot` of the control side and displays the options specified therein.

The user chooses which type of session they want to start, and grub (stage 2, also on the aforementioned `/boot`) passes control to the kernel and initramfs on the current `/boot` of the side corresponding to the user's choice.

To make grub's job easier, ZFS clones are used to "link" to the current `/boot` of both sides from a fixed location: under the `boot/` sub file system of the base file system.

ZTS's core logic then runs in initramfs and is responsible for the following:
If the previous session is an admin type, capture the state at the end of the session by taking a snapshot (of each of the three dimensions). In this case, if `/boot` has changed, also update the "links".
If the current session is a normal type, fork from the most recent state of the current side along the `/` and `/root` dimensions, and snapshot the `/home` dimension.

If something goes wrong in an admin session, the user can boot into cn the next time and revert to the previous good state.

If something goes wrong in a normal session, say /usr gets deleted, the next normal session on the same side won't even feel the difference, unless the problem involves `/home`, in which case a revert will also fix the problem.

By design, a revert doesn't destroy any existing state. You pick a good snapshot on a `/` branch and a good snapshot on a `/home` branch as shown in the demo below, and ZTS will create a new state by branching off at those snapshots:
![demo animation](../2cbbd50198cbbe7c1af9fd4992ad35c97cc7e86e/demo.gif)

## Getting Started (for the tech savvy)

CAUTION:
A ZTS based system is not nearly as easy to set up as it is to maintain (unless you have a system that is already set up in which case simply replicate using zfs send/recv and run a few more commands). Whereas maintaining ZTS is an end user's job, setting is up is more like an OEM/livecd packer's job. If you are new to linux the following steps might be too difficult to follow. Otherwise, it's recommended you perform the following steps in a virtual environment, and replicate the result to bare metal afterwards. I am writing everything from 3+ year old memory and notes scattered in many places so the instructions are very beta. Proceed at your own risk. However, I will try my best to help if you have tried your best :)

You need to change `rpool` to your pool name in `grub.cfg` (line 1) and `control_console/sh/defs.sh` (line 6) if your pool name is different. 

Similarly, the name of the base file system, by default `ubuntu`, can be customized in `grub.cfg` (line 2) and `control_console/sh/defs.sh` (line 6).

In the steps below, `rpool` and `ubuntu` are assumed. We also assume you have the MBR partition scheme on a single hard drive and ZFS occupies the first partition.

### Steps
#### Build your system, rooting on ZFS
Follow OpenZFS's "Root on ZFS" tutorial that matches your desired Linux flavor, except the following datasets should be used instead, with the corresponding mountpoints:
```
rpool/ubuntu/root	on	/
rpool/ubuntu/root/boot	on	/boot
rpool/ubuntu/root/home	on	/home
```
In the Linux world, the overloaded "root" can be a source of confusion. Here `root` means the root of the "two sided tree" as discussed above.

When the build is complete, (if you are working in a virtual environment, create a save point first, then) proceed with the following (still in the chroot environment):

#### Generate custom initramfs

Install `kexec-tools` so that `/sbin/kexec` is available for our custom initramfs.

Copy the following files under `scripts/` to their designated places (see comments inside files):
```
  zfs
  zfs_custom_boot
  zfs_custom_boot_hook
```

Generate the initramfs:
```
# update-initramfs -uv -k <your kernel release>
```
Note since you are building your system in a chroot environment, `<your kernel release>` isn't necessarily the same as the output of `uname -r`.

#### Prepare grub and `/boot`
We want a custom `core.img` file (stage 1.5) that takes the boot process to the `grub.cfg` on the current `/boot` of the control side (see
Design
above), so run this command to generate one (the output is not yet used):
```
# grub-mkimage --verbose --directory=/usr/lib/grub/i386-pc --prefix='(hd0,msdos1)/ubuntu/boot/control@/grub' --output=/boot/grub/i386-pc/core.img --format=i386-pc --compression=auto  zfs part_msdos biosdisk
```

Also, copy the custom `grub.cfg` to `/boot/grub/`, and create hardlinks `vmlinuz` and `initrd.img` under `/boot` to the kernel and initramfs, respectively. 

#### Hold grub still
Because grub serves as the fixed link that carries the boot process towards ZTS, if anything changes the link the boot process will fail.
Without concerning ourselves with grub integration, the simplest solution is to hold all grub related components still when the build is over.
On my ubuntu 18.04 I did:
```
# apt-mark hold grub-pc
# apt-mark hold grub-pc-bin
# apt-mark hold grub-common
# apt-mark hold grub2-common
# apt-mark hold grub-gfxpayload-lists
```

#### Reboot
Hopefully when the machine reboots, you see the custom grub menu with these options:
```
Normal
Admin
Recovery
```
None of these works yet, so move the cursor quickly to cancel the timeout or you will end up in a grub error screen and have to reboot.

Move the cursor to `Recovery` and press `e` to edit the entry, replacing `${bootfs}` with `/ubuntu/root/boot` on the `linux` line and `initrd` line. This tells grub to find the kernel and initramfs where they currently reside: `/ubuntu/root/boot`.

Finally `ctrl+x` to continue to boot. The custom initramfs you generated previously will work to set up the ZTS structure.

#### Put the custom core.img in place
Once the boot completes, run this command to put `core.img` in place (in the "MBR gap"):
```
# grub-bios-setup --verbose --directory='/boot/grub/i386-pc/' /dev/sda
```

#### Add control console

It's really up to you how to set it up. Maybe add a systemd unit to run the server on boot, then a shortcut to open `127.0.0.1:8000` in the browser.

## Possible Improvements/Wishlist
Having come from the Windows world and remembering the early days when improper shutdowns were likely to cause consistency issues, when designing ZTS, I decided to be conservative. However, it's easy to add a few commands to allow mid-session snapshots.

A ZTS based system can be hardened by guarding the core components of the system with zfs allow/unallow, apparmor, capabilities, etc. Ideally ZTS state maintainance should require some special privilege not needed for apt install/upgrade (except when `/boot` must be modified).

The setup can be modified to enable network boot so that a cluster can be centrally managed. 

The python part can be eliminated by migrating control_console to Electron, or enhanced if we move in the remote management direction.

## References
TODO


