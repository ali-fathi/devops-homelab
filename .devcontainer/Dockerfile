FROM mcr.microsoft.com/devcontainers/base:ubuntu

ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Base packages
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    jq \
    ca-certificates \
    python3 \
    python3-pip \
    ansible \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Detect CPU architecture
# -----------------------------------------------------------------------------
RUN ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) ARCH_TYPE="amd64" ;; \
        aarch64|arm64) ARCH_TYPE="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    echo ${ARCH_TYPE} > /tmp/arch

# -----------------------------------------------------------------------------
# kubectl
# -----------------------------------------------------------------------------
RUN ARCH_TYPE=$(cat /tmp/arch) && \
    curl -fsSL -o kubectl \
    "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH_TYPE}/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl

# -----------------------------------------------------------------------------
# Helm
# -----------------------------------------------------------------------------
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# -----------------------------------------------------------------------------
# Terraform
# -----------------------------------------------------------------------------
RUN ARCH_TYPE=$(cat /tmp/arch) && \
    TERRAFORM_VERSION="1.12.2" && \
    curl -fsSL -o terraform.zip \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH_TYPE}.zip" && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/ && \
    rm terraform.zip

# -----------------------------------------------------------------------------
# Kustomize
# -----------------------------------------------------------------------------
RUN ARCH_TYPE=$(cat /tmp/arch) && \
    KUSTOMIZE_VERSION=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/kustomize\///') && \
    curl -fsSL -o kustomize.tar.gz \
    "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${ARCH_TYPE}.tar.gz" && \
    tar -xzf kustomize.tar.gz && \
    mv kustomize /usr/local/bin/ && \
    rm -f kustomize.tar.gz

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
RUN rm -f /tmp/arch
