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
    zsh \
    neovim \
    apt-transport-https \
    gnupg \
    lsb-release \
    yamllint \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Azure CLI
# -----------------------------------------------------------------------------
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# -----------------------------------------------------------------------------
# Docker Engine
# -----------------------------------------------------------------------------
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
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
# Argo CD CLI
# -----------------------------------------------------------------------------
RUN ARCH_TYPE=$(cat /tmp/arch) && \
    ARGOCD_VERSION=$(curl -fsSL https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION) && \
    curl -fsSL -o /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH_TYPE}" && \
    chmod +x /usr/local/bin/argocd

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
# yq
# -----------------------------------------------------------------------------
RUN ARCH_TYPE=$(cat /tmp/arch) && \
    YQ_VERSION=v4.47.2 && \
    curl -fsSL \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH_TYPE}" \
    -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# -----------------------------------------------------------------------------
# Kubeseal
# -----------------------------------------------------------------------------
RUN ARCH_TYPE=$(cat /tmp/arch) && \
    KUBESEAL_VERSION=$(curl -fsSL https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | jq -r .tag_name) && \
    curl -fsSL -o kubeseal.tar.gz \
    "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION#v}-linux-${ARCH_TYPE}.tar.gz" && \
    tar -xzf kubeseal.tar.gz && \
    install -m 755 kubeseal /usr/local/bin/kubeseal && \
    rm -f kubeseal kubeseal.tar.gz

# -----------------------------------------------------------------------------
# k9s
# -----------------------------------------------------------------------------
RUN ARCH_TYPE=$(cat /tmp/arch) && \
    K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name) && \
    curl -fsSL -o k9s.tar.gz \
    "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH_TYPE}.tar.gz" && \
    tar -xzf k9s.tar.gz && \
    mv k9s /usr/local/bin/ && \
    rm -f LICENSE README.md k9s.tar.gz

# -----------------------------------------------------------------------------
# Verify Tooling
# -----------------------------------------------------------------------------
RUN kubectl version --client=true && \
    helm version && \
    argocd version --client && \
    terraform version && \
    ansible --version && \
    az version && \
    docker --version && \
    docker compose version

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
RUN rm -f /tmp/arch
