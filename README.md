# torchcomms-perf-alcf

Collective-communication benchmarking for [torchcomms](https://github.com/meta-pytorch/torchcomms)
on ALCF Intel GPU systems (Sunspot, Aurora), using the perf harness from
upstream **draft PR #2633**. 

Works against **any torchcomms installation** — the harness runs from a
standalone directory and imports `torchcomms` from wherever it happens to be
installed. Nothing here ever writes to your torchcomms install.

```bash
git clone <this-repo> && cd torchcomms-perf-alcf
./bin/tc-perf-setup     # fetch the harness, flatten it, patch it
./bin/tc-perf-doctor    # preflight
qsub -A <Project> jobs/smoke.pbs
```
## Acknowledgement

**Panagiotis Kourdis** of Intel is the owner of the PR that is the basis of this work
- `panagiotis.kourdis@intel.com` 
- [pkourdis](https://github.com/pkourdis)
**Tanima Dey** of Intel have done thorough testing on the harness
- `tanima.dey@intel.com`

---

## Why this repo exists

The collective perf benchmarks live only on
[PR #2633](https://github.com/meta-pytorch/torchcomms/pull/2633), which is an
**open draft that we assume will never merge**. More details are in 
`docs/README_DETAILS.md`
