resource "aws_lb_target_group" "catalogue" {
  name     = "${var.project}-${var.environment}-catalogue"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.id
  health_check {
    healthy_threshold   = 2
    interval            = 5
    matcher             = "200-299"
    path                = "/health"
    port                = 8080
    timeout             = 2
    unhealthy_threshold = 3
  }
}

resource "aws_instance" "catalogue" {
  ami                    = local.ami
  instance_type          = var.instance_type
  vpc_security_group_ids = [local.catalogue]
  subnet_id              = local.private_subnet_id
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}-catalogue"
  })
}

resource "terraform_data" "catalogue" {
  triggers_replace = [
    aws_instance.catalogue.id
  ]

  provisioner "file" {
    source      = "catalogue.sh"       # Local file/directory to copy
    destination = "/temp/catalogue.sh" # Remote path to place file/content

    connection {
      type     = "ssh"      # SSH or WinRM
      user     = "ec2-user" # Remote username
      password = "DevOps321"
      host     = aws_instance.catalogue.private_ip # Remote address
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /temp/catalogue.sh",
      "sudo sh /temp/catalogue.sh catalogue ${var.environment}"
    ]
  }
}

# stop the instance
resource "aws_ec2_instance_state" "catalogue" {
  instance_id = aws_instance.catalogue.id
  state       = "stopped"
  depends_on  = [terraform_data.catalogue]
}

# take note of the AMI of instance
resource "aws_ami_from_instance" "catalogue" {
  name               = "${var.project}-${var.environment}-catalogue"
  source_instance_id = aws_instance.catalogue.id
  depends_on         = [aws_ec2_instance_state.catalogue]
}