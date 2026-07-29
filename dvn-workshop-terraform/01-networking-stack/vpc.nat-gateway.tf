resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = var.vpc.nat_eip_name
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.vpc.public_subnets[0].name].id

  tags = {
    Name = var.vpc.nat_gateway_name
  }

  depends_on = [aws_internet_gateway.this]
}
