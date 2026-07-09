\# Cloud-Native DevSecOps Lab: Infrastructure Automation \& Kernel-Level Auditing



\## 🚀 Project Overview

This repository contains the full implementation of an advanced cloud-native security laboratory designed under the \*\*DevSecOps\*\* methodology. The project establishes a secure, automated framework that bridges the gap between proactive static analysis (Shift-Left) and reactive kernel-space runtime observability.



For a comprehensive, step-by-step breakdown of the architecture, compliance analysis, and attack simulations, read the full \[17-Page Technical Documentation (PDF)](./documentation/DevSecOps\_eBPF\_Ansible\_Lab\_RRG.pdf).



\## 🛠️ Core Pillars \& Architecture



\*   \*\*Automation (IaC):\*\* Idempotent provisioning of the production target infrastructure using \*\*Ansible\*\*.

\*   \*\*Static Prevention (Shift-Left):\*\* Software Composition Analysis (SCA) and secret tracking inside container layers using \*\*Trivy\*\*.

\*   \*\*Runtime Interception:\*\* Invisible system call monitoring directly within the Linux Kernel space using \*\*eBPF (Cilium Tetragon)\*\*.



\## 📁 Repository Structure

\*   `/automation`: Contains the declarative Ansible playbooks and inventory configurations used to orchestrate the infrastructure.

\*   `/documentation`: Contains the final analytical PDF report detailing the experimental phase, command outputs, and logs.



\## 💻 Technical Stack

\*   \*\*Orchestration:\*\* Ansible

\*   \*\*Container Engine:\*\* Docker CE

\*   \*\*Security Agents:\*\* Cilium Tetragon (eBPF) \& Aqua Security Trivy

\*   \*\*Target Environment:\*\* OWASP Juice Shop (Vulnerable Microservice)

