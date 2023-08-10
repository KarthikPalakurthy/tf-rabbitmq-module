resource "aws_security_group" "rabbitmq" {
  name        = "${var.env}-rabbitmq-security-group"
  description = "${var.env}-rabbitmq-security-group"
  vpc_id      = var.vpc_id

  ingress {
    description      = "rabbitmq"
    from_port        = 5672
    to_port          = 5672
    protocol         = "tcp"
    cidr_blocks      = var.allow_cidr_blocks
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.bastion_cidr
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    { Name = "${var.env}-rabbitmq-security-group"}
  )
}

resource "aws_iam_role" "role" {
  name = "${var.env}-${var.component}-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = merge(
    local.common_tags,
    { Name = "${var.env}-${var.component}-security-group"}
  )
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.env}-${var.component}-role"
  role = aws_iam_role.role.name
}

resource "aws_iam_policy" "policy" {
  name        = "${var.env}-${var.component}-aws-parameter-policy"
  path        = "/"
  description = "${var.env}-${var.component}-aws-parameter-policy"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": [
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ],
        "Resource": ["arn:aws:ssm:us-east-1:515990482874:parameter/${var.env}.${var.component}*",

        ]
      },
      {
        "Sid": "VisualEditor1",
        "Effect": "Allow",
        "Action": "ssm:DescribeParameters",
        "Resource": "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attachment" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}


resource "aws_mq_broker" "rabbitmq" {
  broker_name = "${var.env}-rabbitmq"
  engine_type        = var.engine_type
  engine_version     = var.engine_version
  host_instance_type = var.host_instance_type
  security_groups    = [aws_security_group.rabbitmq.id]
  subnet_ids = var.deployment_mode == "SINGLE_INSTANCE" ? [var.subnet_ids[0]] : var.subnet_ids

  user {
    username = data.aws_ssm_parameter.USER.value
    password = data.aws_ssm_parameter.PASS.value
  }

  encryption_options {
    use_aws_owned_key = false
    kms_key_id = data.aws_kms_key.key.arn
  }
}

# This is to be used for spot instance creation
resource "aws_spot_instance_request" "rabbitmq" {
  ami           = data.aws_ami.centos8.id
  instance_type = "t3.small"
  vpc_security_group_ids = [aws_security_group.rabbitmq.id]
  subnet_id = var.subnet_ids[0]
  wait_for_fulfillment = true
  user_data = base64encode(templatefile("${path.module}/user-data.sh", { component = var.component , env = var.env} ))
  iam_instance_profile = aws_iam_instance_profile.profile.name


  tags = merge(
    local.common_tags,
    { Name = "${var.env}-rabbitmq"}
  )
}

resource "aws_ssm_parameter" "rabbitmq_endpoint" {
  name  = "${var.env}.rabbitmq.ENDPOINT"
  type  = "String"
  value = aws_mq_broker.rabbitmq.instances.0.endpoint.0
}

# Use only if spot instance creation fails
#resource "aws_instance" "rabbitmq" {
#  ami           = data.aws_ami.centos8.id
#  instance_type = "t3.micro"
#  vpc_security_group_ids = [aws_security_group.rabbitmq.id]
#  subnet_id = var.subnet_ids[0]
#  user_data = base64encode(templatefile("${path.module}/user-data.sh", { component = var.component , env = var.env} ))
#  iam_instance_profile = aws_iam_instance_profile.profile.name
#
#  tags = merge(
#    local.common_tags,
#    { Name = "${var.env}-rabbitmq"}
#  )
#}


resource "aws_route53_record" "rabbitmq" {
  zone_id = "Z0636942108K930OU3P3D"
  name    = "rabbitmq-${var.env}.devpractice.online"
  type    = "A"
  ttl     = 30
  records = [aws_spot_instance_request.rabbitmq.private_ip]
#  records = [aws_instance.rabbitmq.private_ip]
}