# AWS one-click runners (us-east-1)

Two shell scripts that provision a single EC2 instance, run the perf sweep, copy
results back to the local machine, and terminate the instance. Both scripts
include explicit cost limiters.

## Cost limiters (read before running)

The scripts enforce three independent safeguards:

1. **In-instance shutdown timer.** The instance runs `shutdown -h +45` at boot,
   so the host powers itself off after 45 minutes regardless of what the script
   is doing.
2. **Shutdown == terminate.** The instance is launched with
   `instance-initiated-shutdown-behavior=terminate`. When the timer fires, the
   instance is destroyed, not stopped (no further EBS charges).
3. **Trap on script exit.** The local script also issues an explicit
   `terminate-instances` call on exit, regardless of success or failure.

This redundancy is intentional. If you fork the scripts, keep all three.

## Prerequisites (one-time)

```bash
# 1. Install AWS CLI v2
#    https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

# 2. Configure credentials (region: us-east-1)
aws configure
```

The IAM principal needs permission to create, describe, and terminate EC2
instances; a broad `AmazonEC2FullAccess` works for ad-hoc experiments. For
production use, scope it down.

## 1. Standard EC2 (wall-clock + best-effort perf)

```bash
bash bench/aws/one_click_perf_ec2.sh
```

This uses a general-purpose instance class. On most non-metal instance classes
`perf stat` reports the hardware events as `<not supported>` because the
hypervisor does not expose performance counters to guests; wall-clock timings
still record correctly.

## 2. Bare-metal EC2 (full perf counters)

```bash
AWS_RUNTIME_MINUTES=10 bash bench/aws/one_click_perf_ec2_metal.sh
```

`*.metal` instance classes expose hardware performance counters directly. The
script iterates through a small list of metal instance types, picking the first
one that can be launched in the configured AZ. `AWS_RUNTIME_MINUTES` tightens
the in-instance shutdown timer for a shorter, cheaper run.

## Outputs

Successful runs deposit:

- `bench/out/aws_one_click/latest_summary_perf.tsv` — perf-counter sweep summary
- `bench/out/aws_one_click/perf_diag.txt` — diagnostic snapshot from the host
- `bench/out/aws_one_click/perf_preflight.txt` — capability probe output
- `bench/out/aws_one_click/bundle.tar.gz` — raw artefacts

## Troubleshooting

If a run fails, capture:

- `aws --version`
- `aws sts get-caller-identity`
- The last ~30 lines of the script output

before opening an issue.

## Notes

- The scripts upload the local `bench/` tree to the instance over SSH, so they
  do not depend on any pre-built archive being current.
- AMI selection, key-pair handling, and security-group provisioning are all
  ephemeral: nothing persists in the account after the run terminates.
