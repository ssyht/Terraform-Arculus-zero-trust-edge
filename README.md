# Terraform-Arculus-zero-trust-edge

## Chapter 1 - Overview

-> Understand Zero Trust at Edge
(i) Identity First, Least Privelage

-> Terraform Overview
(i) Provider, resources, variables, output.tf

Potential Idea: Zero Trust Pillars (IAMs, SGs, KMS, VPC, Endpoints)

## Chapter 2 — Provision ONE EC2 (Mgmt/Jump Host) with Terraform in CloudShell
**Objective**

Students learn Terraform basics by creating a minimal VPC and one EC2 that’s managed via AWS Systems Manager (SSM) (no SSH keys, no user_data yet).

Pre-class checklist (instructor)

Confirm student IAM permissions: VPC, EC2, IAM (roles/instance profiles), SSM.

Pick a region (e.g., us-east-1) for the whole class.
