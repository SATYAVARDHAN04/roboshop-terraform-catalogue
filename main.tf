resource "aws_lb_target_group" "catalogue" {
  name     = "${var.project}-${var.environment}-catalogue"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value
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

  connection {
    type     = "ssh"      # SSH or WinRM
    user     = "ec2-user" # Remote username
    password = "DevOps321"
    host     = aws_instance.catalogue.private_ip # Remote address
  }

  provisioner "file" {
    source      = "catalogue.sh"      # Local file/directory to copy
    destination = "/tmp/catalogue.sh" # Remote path to place file/content
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/catalogue.sh",
      "sudo sh /tmp/catalogue.sh catalogue ${var.environment}"
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
  tags = {
    Name = "${var.project}-${var.environment}-AMI"
  }
}

# terminate the instance 
resource "terraform_data" "catalogue_terminate" {
  triggers_replace = [
    aws_instance.catalogue.id
  ]

  connection {
    type     = "ssh"      # SSH or WinRM
    user     = "ec2-user" # Remote username
    password = "DevOps321"
    host     = aws_instance.catalogue.private_ip # Remote address
  }

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.catalogue.id}"
  }
  depends_on = [aws_ami_from_instance.catalogue]
}

resource "aws_launch_template" "catalogue" {
  name                                 = "${var.project}-${var.environment}-catalogue"
  image_id                             = aws_ami_from_instance.catalogue.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "t3.micro"
  vpc_security_group_ids               = [local.catalogue]
  update_default_version               = true # each time we update new version will be default
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project}-${var.environment}-catalogue"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project}-${var.environment}-catalogue"
    }
  }

  # launch template tags
  tags = {
    Name = "${var.project}-${var.environment}-catalogue"
  }
}

resource "aws_autoscaling_group" "catalogue" {
  name                      = "${var.project}-${var.environment}-catalogue"
  max_size                  = 5
  min_size                  = 1
  desired_capacity          = 2
  health_check_grace_period = 120
  health_check_type         = "ELB"
  target_group_arns         = aws_lb_target_group.catalogue.arn
  vpc_zone_identifier       = local.private_subnet_ids
  launch_template {
    id      = aws_launch_template.catalogue.id
    version = aws_launch_template.catalogue.latest_version
  }

  dynamic "tag" {
    for_each = merge(local.ec2_tags, {
      Name = "${var.project}-${var.environment}-catalogue"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  timeouts {
    delete = "8m"
  }

}

resource "aws_autoscaling_policy" "catalogue" {
  name                   = "${var.project}-${var.environment}-catalogue"
  autoscaling_group_name = aws_autoscaling_group.catalogue.id
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 70.0
  }
}

resource "aws_lb_listener_rule" "catalogue" {
  listener_arn = local.backend_alb_listerner_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = [aws_lb_target_group.catalogue.arn]
  }

  condition {
    host_header {
      values = ["catalogue.backend-${var.environment}.${var.zone_name}"]
    }
  }
}