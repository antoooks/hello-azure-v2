<!-- # hello-azure-v2
📋 Run Unique on Microsoft Azure with a simple, secure, and fully automated setup triggered on every release. -->

# Hello Azure Repository

This repository contains a complete Hello Azure infrastructure deployment solution using Terraform, designed for automated and manual deployment workflows.
It also includes a setup of ArgoCD used for deploying workloads to the AKS cluster.

## 🏗️ Infrastructure Overview

- **01_bootstrap**: Bootstrap the tenant and set up the remote Terraform state storage.
- **02_infrastructure**: Deploy the infrastructure.
- **03_applications**: Bootstrap ArgoCD and deploy the workloads to the AKS cluster.

## 🚀 Quick Start

### Prerequisites
- Azure CLI installed and logged in (`az login`)
- Terraform 1.5+ installed
- [Helmfile](https://helmfile.readthedocs.io/) installed, together with Helm and the `helm-diff` plugin (used by `03_applications` to bootstrap Argo CD; `helmfile apply` and `helmfile diff` need `helm-diff`):
  ```bash
  # macOS (Homebrew)
  brew install helm helmfile
  helmfile init   # installs the required Helm plugins, including helm-diff

  # verify
  helmfile --version && helm plugin list
  ```
  Other platforms: see the [Helmfile installation guide](https://helmfile.readthedocs.io/en/latest/#installation).


**Ready to get started?** Begin with the [Configuration Guide](/01_bootstrap/README.md) to understand how to create remote Terraform state storage, then follow the guides in 02_infrastructure and 03_applications.