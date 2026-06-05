CAPSTONE PROJECT
AltSchool of Cloud Engineering Karatu 2025 Third Semester Month [4] Project Examination  CAPSTONE PROJECT
In Progress
InnovateMart’s Inaugural EKS Deployment
Company: InnovateMart Inc.

Role: Cloud DevOps Engineer

Mission: “Project Bedrock” – Production-Grade Microservices on AWS EKS

1. Technical Standards & Constraints (CRITICAL)
WARNING: To support automated grading, you MUST adhere to the following naming conventions and configuration standards. Failure to follow these constraints will result in script failure and a grade of zero for the automated portion.

Resource	Constraint Value / Requirement
AWS Region	us-east-1 (N. Virginia)
EKS Cluster Name	project-bedrock-cluster
VPC Name Tag	project-bedrock-vpc
Application Namespace	retail-app
IAM User (Developer)	bedrock-dev-view
S3 Bucket (Assets)	bedrock-assets-[your-student-id]
Lambda Function	bedrock-asset-processor
Resource Tagging	All resources must have the tag Project: karatu-2025-capstone
Terraform Outputs	Root module must output: cluster_endpoint, cluster_name, region, vpc_id, assets_bucket_name
2. Introduction & Company Background
Welcome to InnovateMart! We are a rapidly growing e-commerce startup scaling our operations globally after a successful Series A round. Our engineering team has refactored our legacy monolith into a modern microservices architecture.

As our new Cloud DevOps Engineer, you are entrusted with “Project Bedrock.” Your mission is to provision our first production-grade Kubernetes environment on AWS and deploy the new Retail Store Application. This foundation will dictate our ability to deliver a world-class shopping experience.

3. Your Mission
Your objective is to provision a secure Amazon EKS cluster and deploy the AWS Retail Store Sample App. You must automate the infrastructure, secure developer access, implement observability, and extend the architecture with event-driven serverless components.

Success looks like: A fully automated infrastructure pipeline, a running application, centralized logging, and a secured cluster ready for developer hand-off.

4. Core Requirements (Mandatory)
You must complete all sections below to pass.

4.1. Infrastructure as Code (IaC)
Provision all AWS infrastructure using Terraform (strongly recommended) or Pulumi.

VPC: Create a new VPC (project-bedrock-vpc) with public and private subnets across at least two Availability Zones (AZs) in us-east-1.
EKS Cluster: Provision a functional EKS cluster (>= v1.34.0) named project-bedrock-cluster.
IAM: Create necessary roles for the Cluster and Node Groups adhering to least-privilege principles.
State Management – Crucial: You must configure a secure remote state management (e.g., S3 + DynamoDB for state locking) to ensure your CI/CD pipeline functions correctly. Local state files are not accepted.

Recent information shows that remote state can be set up using only S3. Hence a Dynamo table may not be needed to facilitate remote state management for your Terraform IaC.
4.2. Application Deployment
Deploy the retail-store-sample-app to your EKS cluster in the retail-app namespace.

 Method: You may deploy using standard Kubernetes manifests (YAML). Kustomize is also acceptable for managing environment overlays.
Data Layer — Managed AWS Resources (Required): The application’s default Helm chart runs all databases in-cluster. You must override this behaviour and replace the in-cluster database containers with managed AWS services:
MySQL → Amazon RDS (MySQL engine)
PostgreSQL → Amazon RDS (PostgreSQL engine)
DynamoDB → Amazon DynamoDB table(s)
Data Layer — Security: Provision the RDS instances inside private subnets. Create dedicated Security Groups that allow inbound database traffic only from the EKS node/pod CIDR or security group. Database credentials must be stored securely (e.g., AWS Secrets Manager or SSM Parameter Store) and injected into the application — never hardcoded in Helm values files committed to source control.
In-Cluster Services: Message brokers (RabbitMQ, Redis) may run as pods within the cluster (the Helm chart default is acceptable here).
Ingress Controller: Install the AWS Load Balancer Controller.
Ingress Resource: Create an Ingress resource to expose the ui service via an Application Load Balancer (ALB).
4.3. Secure Developer Access
Enable the development team to troubleshoot the application and infrastructure without administrative privileges. You must create an IAM user (bedrock-dev-view) with two layers of access:

AWS Console Access: Attach the AWS managed policy ReadOnlyAccess to this user. This allows them to log in to the AWS Console and view resources (EC2, EKS, CloudWatch) but not modify them.
Kubernetes Cluster Access: Map this IAM user to a Kubernetes RBAC role that grants read-only access (e.g., the view ClusterRole).
Verification: This user must be able to run kubectl get pods -n retail-app but fail to run kubectl delete pod.
Deliverable: You must submit the Access Key ID and Secret Access Key, as well as console credentials, for this specific user.
4.4. Observability (Logging)
A production cluster is a black box without logs. You must configure the cluster to ship logs to Amazon CloudWatch.

Control Plane Logging: Enable EKS Control Plane logging (API, Audit, Authenticator, ControllerManager, Scheduler) so they appear in CloudWatch Log Groups.
Application Logging: Install and configure the Amazon CloudWatch Observability EKS Add-on (or FluentBit) to ship container logs to CloudWatch.
Goal: We should be able to see the retail-store-sample-app logs in the CloudWatch console.
4.5. Event-Driven Extension (Serverless)
InnovateMart’s marketing team needs a place to upload product images that are automatically processed.

S3 Bucket: Create a private S3 bucket named bedrock-assets-[your-student-id] (replace suffix with your ID/Name to ensure uniqueness).
Lambda Function: Create a Lambda function named bedrock-asset-processor (Python or Node.js).
Trigger: Configure an S3 Event Notification such that when a file is uploaded to the bucket, the Lambda function is triggered.
Logic: The Lambda function code can be simple; it should print/log the name of the uploaded file to CloudWatch Logs. “Image received: [filename]”.

Note: The bedrock-dev-view IAM user has been granted s3:PutObject on this bucket (see Section 4.3). The grader will use those credentials to upload a test file and verify the Lambda is invoked.
4.6. CI/CD Automation
Implement a CI/CD pipeline (e.g., GitHub Actions) to automate infrastructure changes.

Pull Request: Triggers terraform plan. The plan output should be posted as a PR comment for review.
Merge to Main: Triggers terraform apply.
Security: AWS credentials must be stored as repository secrets (OIDC preferred, or Access Keys as a fallback) — never hardcoded in workflow files.
Note: Be aware that terraform apply on merge will make real changes to live infrastructure. Review the plan carefully before merging, and consider using -target flags or Terraform workspaces to limit blast radius during development.

5. Bonus Objectives (Extra Marks)
Completing these objectives demonstrates Senior-level capability.

5.1. Helm-Based Deployment
Refactor your application deployment to use a Helm chart instead of raw Kubernetes manifests.

 Package your manifests as a Helm chart, or use the upstream retail-store-sample-app Helm chart with a custom values.yaml overriding the data layer to point at RDS/DynamoDB.
The chart must be committed to your repository and deployable with a single helm upgrade –install command documented in your README.
5.2. Advanced Networking & Ingress
Expose the application securely to the public internet.

DNS & TLS:
Configure a custom domain (or use a magic DNS like nip.io if you do not own a domain).
Terminate TLS (HTTPS) at the ALB using a certificate from AWS Certificate Manager (ACM).
WARNING: Be careful with all resources created. Ensure you review and understand the benefits and cost implications of all resources and configurations. Only create and configure minimally with respect to the task required.

6. Deliverables
Submit a single Google Document, uploaded to google drive and Viewer privilege shared with Innocent Chukwuemeka, containing the following links and details:

Tagging: Make sure all infrastructure resources on AWS are tagged with the tag Project: karatu-2025-capstone .
Git Repository Link: Source code for Terraform, Pipeline YAML, Lambda Code, and Application manifests/values. Ensure the repo is public or access is granted.
Architecture Diagram: A high-level visual of your VPC, EKS, Data Layer, and the S3-Lambda flow.
Deployment Guide:
How to trigger the pipeline.
The URL to access the running Retail Store.
Grading Credentials: Access Key and Secret Key, along with console credentials, for the bedrock-dev-view user.
Grading Data:
You must generate a JSON output file of your infrastructure to assist the grading script.
Run the following command in your Terraform root and commit the resulting file to the root of your repo: terraform output -json > grading.json
7. Grading Rubric
Category	Requirement	Weight
Core: Standards	Adherence to naming conventions and Region.	5%
Core: Infra	VPC, EKS, and configured correctly via IaC. Remote State also setup properly.	15%
Core: App	Retail Store App running in retail-app namespace; all pods healthy. Store accessible and interactive.	15%
Core: Security	Developer IAM User (Console ReadOnly + PutObject for specified S3 bucket + K8s RBAC View) configured correctly.	15%
Core: Observability	CloudWatch Logs enabled for Control Plane and Containers.	10%
Core: Serverless	S3 Bucket triggers Lambda; Lambda logs successfully to CloudWatch.	10%
Core: CI/CD	Pipeline successfully Plans on PR and Applies on Merge.	10%
Core: Architecture Diagram	The submitted diagram clearly shows VPC/subnet layout, EKS cluster, managed data layer, ALB ingress, and S3-Lambda flow.	5%
Bonus	Extra Objectives	15%
⚠ COST REMINDER: EKS clusters, NAT Gateways, RDS instances, and ALBs incur ongoing AWS charges. Provision only what is required for the assessment. Tear down or stop resources (especially EKS node groups and RDS) when not actively working on the project to avoid unexpected bills.