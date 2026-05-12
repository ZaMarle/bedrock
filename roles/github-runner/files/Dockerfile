# =============================================================================
# GITHUB ACTIONS RUNNER - Custom image with kubectl and helm
# =============================================================================
#
# This Dockerfile extends the official GitHub Actions runner image with
# kubectl and helm so that CI/CD workflows can deploy directly to the
# Kubernetes cluster using in-cluster credentials (the ServiceAccount
# token mounted into the pod automatically by Kubernetes).
# =============================================================================

# Start from the official GitHub Actions runner image
FROM ghcr.io/actions/actions-runner:latest

# Install jq (and clean up apt cache to keep image small)
USER root
# Set versions explicitly to match your cluster
ENV KUBECTL_VERSION=v1.33.3 \
    HELM_VERSION=v3.12.2

RUN rm -f /root/.kube/config

# Install jq, kubectl, and helm
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq curl ca-certificates tar gzip sudo && \
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl && \
    # Install helm
    curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz && \
    tar -xzf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf helm.tar.gz linux-amd64 && \
    # Clean stale kubeconfig
    rm -f /root/.kube/config && \
    # Cleanup
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Add wrapper script for Helm to use in-cluster credentials
RUN mkdir -p /usr/local/bin/helm-incluster
RUN echo '#!/bin/sh\n\
helm "$@" \\\n\
  --kube-apiserver https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT \\\n\
  --kube-token $(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \\\n\
  --kube-ca-file /var/run/secrets/kubernetes.io/serviceaccount/ca.crt' \
> /usr/local/bin/helm-incluster.sh && chmod +x /usr/local/bin/helm-incluster.sh

RUN mv /usr/local/bin/helm /usr/local/bin/helm.real && \
    mv /usr/local/bin/helm-incluster.sh /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm

# Entrypoint: configure the runner from env vars then start it
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Switch back to runner user (the default in base image)
USER runner

ENTRYPOINT ["/entrypoint.sh"]
