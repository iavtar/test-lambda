# --- IAM role ---

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project_name
  }
}

# Grants logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Grants ec2:CreateNetworkInterface / DescribeNetworkInterfaces / DeleteNetworkInterface
# needed for Lambda to place ENIs in the VPC private subnets
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# --- CloudWatch Log Group ---
# Created explicitly so we control retention; without this Lambda auto-creates
# the group with no expiry and logs accumulate forever.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-greeting"
  retention_in_days = var.log_retention_days

  tags = {
    Project = var.project_name
  }
}

# --- Security group ---

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group for the greeting Lambda function"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-lambda-sg"
    Project = var.project_name
  }
}

# --- Lambda function ---

resource "aws_lambda_function" "greeting" {
  function_name = "${var.project_name}-greeting"
  role          = aws_iam_role.lambda.arn

  # Quarkus Amazon Lambda produces build/function.zip
  filename         = "../build/function.zip"
  source_code_hash = filebase64sha256("../build/function.zip")

  # Quarkus bootstrap handler — dispatches to GreetingLambda via quarkus.lambda.handler
  handler = "io.quarkus.amazon.lambda.runtime.QuarkusStreamHandler::handleRequest"
  runtime = "java21"

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds
  publish     = true

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      QUARKUS_LAMBDA_HANDLER = "greeting"
    }
  }

  tags = {
    Project = var.project_name
  }
}
