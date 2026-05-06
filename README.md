# Bedrock

Ansible playbook that bootstraps a single-node Kubernetes cluster on an Ubuntu server. Manages the full stack from static IP assignment through to a self-hosted GitHub Actions runner.

Runs from WSL on your Windows machine and configures the server remotely over SSH.

## What it does

| Role | Purpose |
|---|---|
| `network` | Assigns a static IP via netplan so the address never drifts |
| `prerequisites` | Disables swap, loads kernel modules, sets sysctl params |
| `containerd` | Installs and configures the container runtime |
| `kubernetes` | Installs kubeadm/kubelet/kubectl, initializes the cluster |
| `calico` | Installs the Calico CNI plugin for pod networking |
| `github-runner` | Deploys a self-hosted GitHub Actions runner to the cluster |

The playbook is idempotent — it checks whether the cluster is healthy before deciding to reset and reinitialize. Safe to re-run.

## Prerequisites

- An Ubuntu 22.04 server on your local network
- WSL (Windows Subsystem for Linux) on your Windows machine
- A GitHub PAT with `read:packages` scope (for pulling the runner image from ghcr.io)
- A GitHub runner registration token (generated right before running)

## One-time setup

### 1. Install Ansible in WSL

```bash
sudo apt update && sudo apt install -y ansible
```

### 2. Set up SSH key authentication

```bash
# Generate a key (press enter through all prompts)
ssh-keygen -t ed25519

# Copy it to the server
ssh-copy-id zac@192.168.1.100

# Verify it works (should connect without a password)
ssh zac@192.168.1.100
```

### 3. Set up secrets

Secrets are stored outside the project directory so they never end up in git or get read by any tools. They live on the WSL filesystem at `~/.secrets/bedrock.env`.

You need two secrets:

**`GHCR_PAT`** — a GitHub Personal Access Token for pulling the runner image from ghcr.io.
You already have one stored in your GitHub Actions secrets at
https://github.com/ZaMarle/vevous/settings/secrets/actions — use the same token value.
If you need to create a new one: https://github.com/settings/tokens → `read:packages` scope.

**`GITHUB_RUNNER_TOKEN`** — a registration token that lets the runner register with your GitHub org.
Generate at: https://github.com/organizations/zamarle/settings/actions/runners/new
Look for the `--token` value in the "Configure" section. This expires after 1 hour,
so regenerate it right before running the playbook.

Create the secrets file:

```bash
# Create the directory
mkdir -p ~/.secrets
chmod 700 ~/.secrets

# Create the file with your actual token values
cat > ~/.secrets/bedrock.env << 'EOF'
export GHCR_PAT="ghp_your_pat_here"
export GITHUB_RUNNER_TOKEN="AXXXXXXXXXXXXXXXX"
EOF

chmod 600 ~/.secrets/bedrock.env
```

The `chmod` commands restrict access so only your user can read these files.

To update the runner token later (since it expires hourly), just edit the file:

```bash
nano ~/.secrets/bedrock.env
```

## Running the playbook

From WSL:

```bash
# Load secrets into the current shell
source ~/.secrets/bedrock.env

# Run the playbook
cd /mnt/c/Users/qu4ck/source/bedrock
ansible-playbook -i inventory/hosts.yaml -K playbooks/cluster.yaml \
  --extra-vars "github_runner_token=$GITHUB_RUNNER_TOKEN ghcr_pat=$GHCR_PAT"
```

The `source` command reads the secrets file and makes the variables available in your shell.
The `$VARIABLE_NAME` syntax in `--extra-vars` gets replaced with the actual values at runtime,
so the secrets never end up in any project file.

| Flag | Purpose |
|---|---|
| `-i inventory/hosts.yaml` | Points Ansible to the server inventory |
| `-K` | Prompts for the sudo password on the remote server |
| `--extra-vars "..."` | Passes secrets from environment variables into the playbook |

## Verifying it worked

After the playbook completes, SSH into the server and check:

```bash
kubectl get nodes         # should show 'zama' as Ready
kubectl get pods -A       # all pods should be Running
```

## How it works

### Execution flow

When you run the playbook, Ansible reads three things in order:

1. **`inventory/hosts.yaml`** — the "who": which server to connect to and how (SSH as `zac` to `192.168.1.100`)
2. **`group_vars/all.yaml`** — the "config": all variables (IP addresses, versions, CIDRs) that get plugged into every role. Change a value here and every role picks it up automatically.
3. **`playbooks/cluster.yaml`** — the "what": lists the roles to run, top to bottom, sequentially.

Then each role runs in order:

```
You run the playbook (from WSL)
  |
  |  SSH into 192.168.1.100
  |
  |--> network          "Make sure the IP never changes"
  |--> prerequisites    "Make sure the OS is ready for k8s"
  |--> containerd       "Make sure there's something to run containers"
  |--> kubernetes       "Make sure the cluster exists and is healthy"
  |--> calico           "Make sure pods can talk to each other"
  '--> github-runner    "Make sure CI/CD can deploy to the cluster"
```

Each layer depends on the one above it. If any role fails, execution stops.

### Role details

**`roles/network/`** — Switches from DHCP to a static IP via netplan. This prevents the IP-drift problem that originally broke the cluster.

**`roles/prerequisites/`** — Prepares the OS: turns off swap, loads kernel modules (`overlay`, `br_netfilter`), sets sysctl networking params, installs base apt packages. These are hard requirements from Kubernetes.

**`roles/containerd/`** — Installs the container runtime. Kubernetes tells containerd "run this container" and containerd does the actual work. The `files/config.toml` sets `SystemdCgroup = true` so containerd and kubelet use the same cgroup manager. The `handlers/main.yaml` restarts containerd if the config changes.

**`roles/kubernetes/`** — The biggest role, with three phases:
1. **Install** — adds the k8s apt repo, installs kubeadm/kubelet/kubectl, holds package versions
2. **Init** — checks cluster health, resets if broken, runs `kubeadm init` to create a fresh cluster
3. **Setup** — copies kubeconfig to your user, removes the control-plane taint so pods can schedule on this single node

**`roles/calico/`** — Installs pod networking. Without this, the node stays `NotReady` and pods can't get IP addresses. Installs the Tigera operator, then applies a config telling it what pod IP range to use.

**`roles/github-runner/`** — Creates a namespace, ServiceAccount with cluster-admin RBAC, image pull secret for ghcr.io, and a Deployment running the custom runner image. The runner registers itself with the `zamarle` GitHub org on startup. The Dockerfile for the runner image is stored in `files/Dockerfile`.

## Project structure

```
bedrock/
├── inventory/hosts.yaml              # Server connection details (IP, SSH user)
├── group_vars/all.yaml               # Shared variables (IPs, versions, CIDRs)
├── playbooks/cluster.yaml            # Main playbook — run this
└── roles/
    ├── network/
    │   └── tasks/main.yaml           # Static IP via netplan
    ├── prerequisites/
    │   └── tasks/main.yaml           # Swap, kernel modules, sysctl, apt deps
    ├── containerd/
    │   ├── tasks/main.yaml           # Install and configure containerd
    │   ├── files/config.toml         # Containerd config (SystemdCgroup=true)
    │   └── handlers/main.yaml        # Restarts containerd on config change
    ├── kubernetes/
    │   └── tasks/main.yaml           # K8s packages, cluster health check, init
    ├── calico/
    │   └── tasks/main.yaml           # Tigera operator + Calico custom resources
    └── github-runner/
        ├── tasks/main.yaml           # Namespace, RBAC, image pull secret, Deployment
        └── files/Dockerfile          # Custom runner image with kubectl + helm
```
