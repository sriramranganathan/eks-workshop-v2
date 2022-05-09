resource "aws_cloud9_environment_ec2" "c9_workspace" {
  instance_type               = var.instance_type
  name                        = var.environment_name
  automatic_stop_time_minutes = 90

  tags = {
    Cloud9Bootstrap = "Active"
  }

  provisioner "local-exec" {
    command = "aws cloud9 update-environment --environment-id ${self.id} --managed-credentials-action DISABLE"
  }
}

resource "aws_cloud9_environment_membership" "user" {
  count = length(var.cloud9_user_arns)

  environment_id = aws_cloud9_environment_ec2.c9_workspace.id
  permissions    = "read-write"
  user_arn       = var.cloud9_user_arns[count.index]
}

data "aws_instance" "cloud9_instance" {
  filter {
    name = "tag:aws:cloud9:environment"
    values = [
      aws_cloud9_environment_ec2.c9_workspace.id
    ]
  }
}

resource "aws_iam_role" "cloud9_role" {
  name = "Cloud9Role-${var.environment_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloud9_policy_ssm_core" {
  role       = aws_iam_role.cloud9_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "cloud9_additional_policy" {
  count = length(var.additional_cloud9_policies)

  name = "Cloud9Policy-${var.environment_name}-${count.index}"

  policy = jsonencode(var.additional_cloud9_policies[count.index])
}

resource "aws_iam_role_policy_attachment" "cloud9_additional_policy" {
  count = length(var.additional_cloud9_policies)

  role       = aws_iam_role.cloud9_role.name
  policy_arn = aws_iam_policy.cloud9_additional_policy[count.index].arn
}


resource "aws_iam_instance_profile" "cloud9_ssm_instance_profile" {
  name = "Cloud9InstanceProfile-${var.environment_name}"
  role = aws_iam_role.cloud9_role.name
}

resource "aws_lambda_invocation" "cloud9_instance_profile" {
  function_name = module.cloud9_bootstrap_lambda.lambda_function_name

  input = jsonencode({
    instance_id           = data.aws_instance.cloud9_instance.id
    instance_profile_arn  = aws_iam_instance_profile.cloud9_ssm_instance_profile.arn
    instance_profile_name = aws_iam_instance_profile.cloud9_ssm_instance_profile.name
    disk_size             = var.disk_size
  })
}