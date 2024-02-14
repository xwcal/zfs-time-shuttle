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

## Getting Started

(It's been a long time since 2018 and a lot of things happened. Grub's zfs.mod no longer follows ZFS's evolution, and even the grub2 compatibility mode seems to fail occasionally as reported [here](https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/2041739) and [here](https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/2047173). This section needs to be rewritten from scratch. Please stay tuned.)

## Possible Improvements/Wishlist
Having come from the Windows world and remembering the early days when improper shutdowns were likely to cause consistency issues, when designing ZTS, I decided to be conservative. However, it's easy to add a few commands to allow mid-session snapshots.

A ZTS based system can be hardened by guarding the core components of the system with zfs allow/unallow, apparmor, capabilities, etc. Ideally ZTS state maintainance should require some special privilege not needed for apt install/upgrade (except when `/boot` must be modified).

The setup can be modified to enable network boot so that a cluster can be centrally managed. 

The python part can be eliminated by migrating control_console to Electron, or enhanced if we move in the remote management direction.

## References
TODO


