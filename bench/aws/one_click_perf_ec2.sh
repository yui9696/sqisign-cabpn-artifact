#!/usr/bin/env bash
set -euo pipefail

# One-click: launch EC2 (Ubuntu 24.04, us-east-1), run perf sweep, fetch TSV, terminate instance.
# Cost limiter:
# - EC2 is configured to TERMINATE on shutdown
# - user-data schedules shutdown in 45 minutes
#
# You should only need to run:
#   bash bench/aws/one_click_perf_ec2.sh

REGION="${AWS_REGION:-us-east-1}"
AZ="${AWS_AZ:-}" # optional
INSTANCE_TYPE="${AWS_INSTANCE_TYPE:-t3.medium}"
VOLUME_GB="${AWS_VOLUME_GB:-20}"
RUNTIME_MINUTES="${AWS_RUNTIME_MINUTES:-45}"

KEY_NAME="${AWS_KEY_NAME:-cabpn_cursor_key}"
KEY_PATH="${AWS_KEY_PATH:-$HOME/.ssh/${KEY_NAME}.pem}"
SG_NAME="${AWS_SG_NAME:-cabpn_cursor_sg}"
TAG_NAME="${AWS_TAG_NAME:-cabpn-one-click}"

# conservative sweep defaults (keep cheap)
N="${N:-2048}"
ITERS="${ITERS:-80}"
REPEATS="${REPEATS:-6}"
ALPHA_LIST="${ALPHA_LIST:-500}"
STATE_BYTES_LIST="${STATE_BYTES_LIST:-512 1024 2048}"
FIXED_K_LIST="${FIXED_K_LIST:-8 16 32}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCAL_BUNDLE_PATH="${LOCAL_BUNDLE_PATH:-$ROOT_DIR/bench/out/aws_one_click/bundle.tar.gz}"

LOCAL_OUT_DIR="$ROOT_DIR/bench/out/aws_one_click"
mkdir -p "$LOCAL_OUT_DIR"

cleanup_instance() {
  local iid="${1:-}"
  if [[ -n "$iid" ]]; then
    echo "## terminating instance: $iid"
    aws ec2 terminate-instances --region "$REGION" --instance-ids "$iid" >/dev/null || true
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }
}

require_cmd aws
require_cmd ssh
require_cmd scp
require_cmd awk
require_cmd curl

if [[ ! -d "$ROOT_DIR/bench/linux" || ! -d "$ROOT_DIR/bench/rust_harness" ]]; then
  echo "ERROR: expected bench/linux and bench/rust_harness under: $ROOT_DIR"
  echo "Run this script from the project root: /Users/moe/paper_2026_2_18"
  exit 1
fi

echo "## creating local bundle (bench only) at $LOCAL_BUNDLE_PATH"
mkdir -p "$(dirname "$LOCAL_BUNDLE_PATH")"
tar -C "$ROOT_DIR" -czf "$LOCAL_BUNDLE_PATH" bench

echo "## region=$REGION instance_type=$INSTANCE_TYPE runtime_limit=${RUNTIME_MINUTES}min"

echo "## checking AWS identity"
aws sts get-caller-identity --region "$REGION" >/dev/null

echo "## getting latest Ubuntu 24.04 AMI via SSM"
AMI_ID="$(aws ssm get-parameter \
  --region "$REGION" \
  --name "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id" \
  --query "Parameter.Value" --output text)"
echo "AMI_ID=$AMI_ID"

echo "## ensuring keypair exists: $KEY_NAME"
if [[ ! -f "$KEY_PATH" ]]; then
  mkdir -p "$(dirname "$KEY_PATH")"
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --query "KeyMaterial" --output text > "$KEY_PATH"
  chmod 400 "$KEY_PATH"
  echo "WROTE_KEY=$KEY_PATH"
else
  echo "KEY_EXISTS=$KEY_PATH"
fi

echo "## ensuring security group exists: $SG_NAME"
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)"
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "## no default VPC found; creating one (safe, region-scoped)"
  VPC_ID="$(aws ec2 create-default-vpc --region "$REGION" --query "Vpc.VpcId" --output text)"
  echo "DEFAULT_VPC_CREATED=$VPC_ID"
fi
SG_ID="$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)"
if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID="$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" --description "cabpn one-click sg" --vpc-id "$VPC_ID" --query "GroupId" --output text)"
  echo "CREATED_SG=$SG_ID"
else
  echo "SG_ID=$SG_ID"
fi

echo "## allowing SSH only from your current IP"
if [[ -n "${AWS_SSH_CIDR:-}" ]]; then
  CIDR="$AWS_SSH_CIDR"
else
  MYIP="$(curl -s https://checkip.amazonaws.com | tr -d ' \n\r')"
  if [[ -z "$MYIP" ]]; then
    echo "ERROR: could not determine public IP (curl to checkip.amazonaws.com failed)"
    echo "Fix: re-run with AWS_SSH_CIDR='YOUR_IP/32' (e.g., AWS_SSH_CIDR='203.0.113.10/32')"
    exit 1
  fi
  CIDR="${MYIP}/32"
fi
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$CIDR,Description=cursor-one-click}]" \
  >/dev/null 2>&1 || true
echo "SSH_ALLOWED_FROM=$CIDR"

SUBNET_ID="$(aws ec2 describe-subnets --region "$REGION" --filters "Name=default-for-az,Values=true" --query "Subnets[0].SubnetId" --output text 2>/dev/null || true)"
if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
  SUBNET_ID="$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text)"
fi
echo "SUBNET_ID=$SUBNET_ID"

USER_DATA="$(cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
shutdown -h +${RUNTIME_MINUTES} || true
EOF
)"

RUN_ARGS=(
  --region "$REGION"
  --image-id "$AMI_ID"
  --instance-type "$INSTANCE_TYPE"
  --key-name "$KEY_NAME"
  --security-group-ids "$SG_ID"
  --subnet-id "$SUBNET_ID"
  --instance-initiated-shutdown-behavior terminate
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${VOLUME_GB},VolumeType=gp3,DeleteOnTermination=true}"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TAG_NAME}}]"
  --user-data "$USER_DATA"
)

echo "## launching instance"
INSTANCE_ID="$(aws ec2 run-instances "${RUN_ARGS[@]}" --query "Instances[0].InstanceId" --output text)"
echo "INSTANCE_ID=$INSTANCE_ID"
trap 'cleanup_instance "$INSTANCE_ID"' EXIT

echo "## waiting for instance running + status checks"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$INSTANCE_ID"

PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)"
echo "PUBLIC_IP=$PUBLIC_IP"

echo "## waiting for ssh"
for i in {1..60}; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY_PATH" "ubuntu@${PUBLIC_IP}" "echo ok" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "## uploading bundle"
scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "$LOCAL_BUNDLE_PATH" "ubuntu@${PUBLIC_IP}:~/cabpn_bundle.tar.gz" >/dev/null

echo "## running benchmark on EC2 (this may take several minutes)"
ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" "ubuntu@${PUBLIC_IP}" bash -lc "set -euo pipefail
  sudo apt-get update -y
  sudo apt-get install -y python3 linux-tools-common linux-tools-generic linux-tools-\$(uname -r) build-essential curl tar gzip || true
  mkdir -p paper_2026_2_18
  tar -xzf cabpn_bundle.tar.gz -C paper_2026_2_18
  cd paper_2026_2_18
  mkdir -p bench/out
  echo '## perf preflight' > bench/out/perf_preflight.txt
  (sudo -n perf stat -x \$'\\t' -e cycles,instructions -- true) 2>> bench/out/perf_preflight.txt || true
  bash bench/linux/setup_ubuntu.sh
  N=${N} ITERS=${ITERS} REPEATS=${REPEATS} \\
  ALPHA_LIST='${ALPHA_LIST}' \\
  STATE_BYTES_LIST='${STATE_BYTES_LIST}' \\
  FIXED_K_LIST='${FIXED_K_LIST}' \\
  bash bench/linux/run_perf_sweep.sh
  latest=\$(ls -1dt bench/out/perf_sweep_* | head -n1)
  echo LATEST_OUT=\$latest
  cp \"\$latest/summary_perf.tsv\" \"bench/out/summary_perf.tsv\"
  # grab one raw perf stderr as diagnostic (first run)
  diag=\"\$latest/raw/stderr_cabpn_a500_s512_r1.txt\"
  if [[ -f \"\$diag\" ]]; then
    cp \"\$diag\" bench/out/perf_diag.txt
  fi
"

echo "## downloading result TSV"
scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "ubuntu@${PUBLIC_IP}:~/paper_2026_2_18/bench/out/summary_perf.tsv" "$LOCAL_OUT_DIR/latest_summary_perf.tsv" >/dev/null
echo "SAVED=$LOCAL_OUT_DIR/latest_summary_perf.tsv"

echo "## downloading perf diagnostics (if available)"
scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "ubuntu@${PUBLIC_IP}:~/paper_2026_2_18/bench/out/perf_preflight.txt" "$LOCAL_OUT_DIR/perf_preflight.txt" >/dev/null 2>&1 || true
scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "ubuntu@${PUBLIC_IP}:~/paper_2026_2_18/bench/out/perf_diag.txt" "$LOCAL_OUT_DIR/perf_diag.txt" >/dev/null 2>&1 || true

echo "## validating TSV (must contain at least 1 data row)"
LINE_COUNT="$(wc -l < "$LOCAL_OUT_DIR/latest_summary_perf.tsv" | tr -d ' ')"
if [[ "${LINE_COUNT:-0}" -lt 2 ]]; then
  echo "ERROR: TSV has no data rows (only header)."
  echo "This usually means perf could not collect counters without sudo on the instance."
  echo "Re-run the script; it now auto-falls back to sudo perf."
  exit 2
fi

echo "## terminating instance (explicit)"
aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
trap - EXIT
echo "DONE"

