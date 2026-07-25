resource "aws_subnet" "private" {
  for_each = { for s in var.vpc.private_subnets : s.name => s }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = each.value.name
    type = "private"
  }
}
