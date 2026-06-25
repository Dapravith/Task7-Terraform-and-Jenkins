data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "foodexpress_key" {
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_security_group" "foodexpress_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for FoodExpress API"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    # Assignment only. For production, restrict this to your Jenkins IP.
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow FoodExpress API on port 7000"
    from_port   = 7000
    to_port     = 7000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

resource "aws_instance" "foodexpress_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.foodexpress_key.key_name
  vpc_security_group_ids = [aws_security_group.foodexpress_sg.id]

  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }
}