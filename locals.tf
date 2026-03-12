locals {
  ami               = data.aws_ami.joindevops.id
  catalogue         = data.aws_ssm_parameter.catalogue_sg.value
  private_subnet_id = split(",", data.aws_ssm_parameter.private_subnet_id.value)[0]
}