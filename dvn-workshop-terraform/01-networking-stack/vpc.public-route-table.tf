resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = var.default_route_cidr
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = var.vpc.public_route_table_name
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
