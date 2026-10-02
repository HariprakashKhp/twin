# Terraform Explanation

This Terraform folder provisions the AWS infrastructure for the project.

In simple terms, it creates:

- An S3 bucket for conversation memory
- An S3 bucket for the frontend website files
- A Lambda function that runs the Python backend
- API Gateway routes that expose the Lambda as HTTP endpoints
- A CloudFront distribution to serve the frontend over HTTPS
- Optional custom-domain DNS and SSL setup in Route 53 and ACM

## What this stack is for

This project looks like an AI chat app or digital twin app:

- The frontend is a static website
- The backend is a Python FastAPI app packaged as a Lambda function
- The backend calls AWS Bedrock for model responses
- Conversation history is stored in S3 instead of only on disk

## Main Resources

### 1. S3 memory bucket

`aws_s3_bucket.memory` stores chat history files.

- Bucket name includes the project name, environment, and AWS account ID
- Public access is blocked
- Object ownership is enforced so AWS account ownership is clear

This is the private storage the backend uses when `USE_S3 = true`.

### 2. S3 frontend bucket

`aws_s3_bucket.frontend` stores the static frontend site.

- It is configured as a website bucket
- `index.html` is the default page
- `404.html` is used for not-found pages
- A bucket policy allows public `s3:GetObject` access

This bucket is meant to hold the built frontend files.

### 3. Lambda role and permissions

`aws_iam_role.lambda_role` is the IAM role the Lambda function runs as.

It gets these AWS managed policies:

- `AWSLambdaBasicExecutionRole` for CloudWatch logs
- `AmazonBedrockFullAccess` to call Bedrock
- `AmazonS3FullAccess` to read/write conversation memory

This is broad access, so it is easy to use but not tightly locked down.

### 4. Lambda function

`aws_lambda_function.api` deploys the backend code from:

- `../backend/lambda-deployment.zip`

It uses:

- Python 3.12
- Handler `lambda_handler.handler`
- A timeout from `var.lambda_timeout`

It also sets environment variables for:

- `CORS_ORIGINS`
- `S3_BUCKET`
- `USE_S3`
- `BEDROCK_MODEL_ID`

So the Lambda knows where to store memory and which Bedrock model to use.

### 5. API Gateway

`aws_apigatewayv2_api.main` creates an HTTP API.

Routes exposed:

- `GET /`
- `POST /chat`
- `GET /health`

These routes all point to the Lambda function through an AWS proxy integration.

The default stage is auto-deployed and has basic throttling limits.

### 6. CloudFront

`aws_cloudfront_distribution.main` serves the frontend through a CDN.

- It uses the frontend S3 website endpoint as the origin
- It redirects HTTP to HTTPS
- It serves `index.html` by default
- It can optionally use custom domain aliases

If no custom domain is enabled, CloudFront uses its default AWS domain.

### 7. Optional custom domain

If `use_custom_domain = true`, Terraform also tries to create:

- A Route 53 hosted zone lookup for `root_domain`
- An ACM certificate for the root domain and `www` subdomain
- DNS validation records
- `A` and `AAAA` alias records for both the root domain and `www`

## Variables

Important inputs in `variables.tf`:

- `project_name`: name prefix for all resources
- `environment`: must be `dev`, `test`, or `prod`
- `bedrock_model_id`: Bedrock model to call
- `lambda_timeout`: Lambda timeout in seconds
- `api_throttle_burst_limit`: API burst limit
- `api_throttle_rate_limit`: API request rate limit
- `use_custom_domain`: enables custom domain setup
- `root_domain`: apex domain like `example.com`

## How the pieces connect

1. CloudFront serves the frontend site.
2. The frontend calls the API Gateway HTTP API.
3. API Gateway invokes the Lambda function.
4. Lambda uses Bedrock to generate responses.
5. Lambda stores conversation history in S3.

## Important notes

- The Lambda deployment uses a prebuilt zip file, so Terraform does not build the backend code itself.
- The custom-domain block uses the Mumbai provider alias (`aws.ap_south_1`).
- The deploy script sets `AWS_DEFAULT_REGION` and `AWS_REGION` to `ap-south-1` for this session.
- The Lambda role uses very broad AWS-managed policies, which is convenient but not least-privilege.

## Files in this folder

- `main.tf`: all AWS resources and wiring
- `variables.tf`: configurable inputs and validation
- `versions.tf`: Terraform and provider version requirements
