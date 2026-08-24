# mds-core-wall

Software mitigation for MDS (Microarchitectural Data Sampling, CVE-2018-12126 /
12127 / 12130, CVE-2019-11091) on machines where you refuse to disable
Hyper-Threading: **put every untrusted tenant — Docker containers and KVM
guests — onto dedicated physical cores**, so hostile code never shares the
silicon it samples from.

## Why this works

MDS does not leak across arbitrary CPUs. It lets a thread sample stale data
from core-internal buffers (line-fill buffers, load ports) **shared by the two
sibling hyperthreads of one physical core**. The kernel's own mitigations are:

1. microcode (`VERW` buffer clear on kernel exit) — needs a CPU microcode
   update; many old Xeons never got one (`Vulnerable: Clear CPU buffers
   attempted, no microcode`), and
2. `nosmt` — effective, but halves your logical CPU count.

There is a third lever nobody mentions: the attack requires *same-core*
co-location. If untrusted workloads are pinned to whole physical cores that
nothing else uses, there is no victim thread to snoop. SMT stays on, all 24
threads stay available — they are just partitioned.

## Topology first

Sibling pairs live in sysfs. On our 12c/24t Xeon each pair is `i, i+12`:

```console
$ ./detect-topology.sh
logical CPUs: 24
core  0: threads 0,12
core  1: threads 1,13
...
core 10: threads 10,22
core 11: threads 11,23
```

Partition used here (adjust to your box):

| Cores        | Threads       | Tenant                     |
|--------------|---------------|----------------------------|
| 0–7          | 0–7, 12–19    | trusted host workloads     |
| 8–9          | 8, 9, 20, 21  | **KVM guests**             |
| 10–11        | 10, 11, 22, 23| **Docker containers**      |

## Docker wall

Two pieces:

`/etc/docker/daemon.json` — make dockerd place every container scope under
`docker.slice` (Docker ≥ 29; older versions called the flag
`default-cgroup-parent`):

```json
{
  "cgroup-parent": "docker.slice"
}
```

> Note: with the systemd cgroup driver the value is a bare slice name,
> `"docker.slice"` — not `/docker.slice`.

`/etc/systemd/system/docker.slice` — confine the slice itself:

```ini
[Slice]
AllowedCPUs=10 11 22 23
```

Then:

```console
# systemctl daemon-reload
# systemctl restart docker
```

**The wall cannot be escaped from inside.** A container may pass
`--cpuset-cpus=0-23`; cgroup cpusets intersect parent and child masks, so the
effective affinity can only ever shrink, never grow past the slice.

## KVM wall

libvirt (systemd cgroup driver) puts every guest into a scope below
`machine.slice`. One drop-in covers all VMs, present and future:

```console
# install -Dm644 systemd/machine.slice.d/10-mds-wall.conf \
      /etc/systemd/system/machine.slice.d/10-mds-wall.conf
# systemctl daemon-reload
```

QEMU vCPU/emulator pinning from `<cputune>` also intersects with the slice
mask (sched_setaffinity cannot widen a cpuset), so per-VM tuning stays legal
but stays inside the fence.

## Verify

```console
$ ./verify.sh            # sudo for the machine.slice probe
== Docker ==
Cpus_allowed_list:	10-11,22-23
== systemd slice configs ==
docker.slice   AllowedCPUs=10-11 22-23
machine.slice  AllowedCPUs=8-9 20-21
== KVM (machine.slice) ==
Cpus_allowed_list:	8-9,20-21
```

## Honest limits

* This removes the *cross-tenant* vector. Sampling between threads you already
  trust on shared cores remains theoretically possible — irrelevant if it's
  all your code.
* It is an access-control workaround, not a CPU bug fix. No software stops
  the sampling itself on hardware without updated microcode.
* Other side channels (cache timing etc.) exist; this raises the bar, it does
  not raise a castle.

## References

* [Kernel MDS documentation](https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/mds.html)
* [systemd slice resource control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html)

MIT licensed; see [LICENSE](LICENSE).
