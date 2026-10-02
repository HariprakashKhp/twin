param(
    [string]$Environment = "dev",   # dev | test | prod
    [string]$ProjectName = "twin"
)
$ErrorActionPreference = "Stop"
$env:AWS_DEFAULT_REGION = "ap-south-1"
$env:AWS_REGION = "ap-south-1"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$BackendDir = Join-Path $ProjectRoot "backend"
$FrontendDir = Join-Path $ProjectRoot "frontend"
$TerraformDir = Join-Path $ProjectRoot "terraform"

Write-Host "Deploying $ProjectName to $Environment ..." -ForegroundColor Green

# 1. Build Lambda package
Set-Location $ProjectRoot
Write-Host "Building Lambda package..." -ForegroundColor Yellow
Set-Location $BackendDir
uv run deploy.py
if ($LASTEXITCODE -ne 0) { throw "backend package build failed." }
Set-Location $ProjectRoot

# 2. Terraform workspace & apply
# New lines:
$awsAccountId = aws sts get-caller-identity --query Account --output text
$awsRegion = if ($env:DEFAULT_AWS_REGION) { $env:DEFAULT_AWS_REGION } else { "ap_south_1" }
terraform init -input=false `
  -backend-config="bucket=twin-terraform-state-$awsAccountId" `
  -backend-config="key=$Environment/terraform.tfstate" `
  -backend-config="region=$awsRegion" `
  -backend-config="dynamodb_table=twin-terraform-locks" `
  -backend-config="encrypt=true"
if ($LASTEXITCODE -ne 0) { throw "terraform init failed." }

$WorkspaceList = & terraform -chdir="$TerraformDir" workspace list
if ($LASTEXITCODE -ne 0) { throw "terraform workspace list failed." }

if (-not ($WorkspaceList | Select-String $Environment)) {
    terraform -chdir="$TerraformDir" workspace new $Environment
    if ($LASTEXITCODE -ne 0) { throw "terraform workspace new failed." }
} else {
    terraform -chdir="$TerraformDir" workspace select $Environment
    if ($LASTEXITCODE -ne 0) { throw "terraform workspace select failed." }
}

if ($Environment -eq "prod") {
    terraform -chdir="$TerraformDir" apply -var-file="prod.tfvars" -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
} else {
    terraform -chdir="$TerraformDir" apply -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
}
if ($LASTEXITCODE -ne 0) { throw "terraform apply failed." }

$ApiUrl = & terraform -chdir="$TerraformDir" output -raw api_gateway_url
if ($LASTEXITCODE -ne 0) { throw "terraform output api_gateway_url failed." }
$ApiUrl = $ApiUrl.Trim()

$FrontendBucket = & terraform -chdir="$TerraformDir" output -raw s3_frontend_bucket
if ($LASTEXITCODE -ne 0) { throw "terraform output s3_frontend_bucket failed." }
$FrontendBucket = $FrontendBucket.Trim()

try {
    $CustomUrl = & terraform -chdir="$TerraformDir" output -raw custom_domain_url
    if ($LASTEXITCODE -ne 0) { $CustomUrl = "" }
    else { $CustomUrl = $CustomUrl.Trim() }
} catch {
    $CustomUrl = ""
}

if (-not $FrontendBucket) {
    throw "Terraform output 's3_frontend_bucket' was empty. Check the terraform apply output before syncing the frontend."
}

if (-not $ApiUrl) {
    throw "Terraform output 'api_gateway_url' was empty. Check the terraform apply output before building the frontend."
}

# 3. Build + deploy frontend
Set-Location $FrontendDir

# Create production environment file with API URL
Write-Host "Setting API URL for production..." -ForegroundColor Yellow
"NEXT_PUBLIC_API_URL=$ApiUrl" | Out-File .env.production -Encoding utf8

npm install
if ($LASTEXITCODE -ne 0) { throw "npm install failed." }
npm run build
if ($LASTEXITCODE -ne 0) { throw "frontend build failed." }
aws s3 sync .\out "s3://$FrontendBucket/" --delete
if ($LASTEXITCODE -ne 0) { throw "frontend upload failed." }
# 4. Final summary
$CfUrl = terraform -chdir="$TerraformDir" output -raw cloudfront_url
if ($LASTEXITCODE -ne 0) { throw "terraform output cloudfront_url failed." }
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "CloudFront URL : $CfUrl" -ForegroundColor Cyan
if ($CustomUrl) {
    Write-Host "Custom domain  : $CustomUrl" -ForegroundColor Cyan
}
Write-Host "API Gateway    : $ApiUrl" -ForegroundColor Cyan
