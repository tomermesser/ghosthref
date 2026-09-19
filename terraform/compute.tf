data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

// Security Groups
resource "aws_security_group" "k3s" {
  name        = "ghosthref-k3s-sg"
  description = "k3s node: SSH + HTTP from operator IP, API from Jenkins"
  vpc_id      = aws_vpc.ghosthref.id

  ingress {
    description = "SSH from operator IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "The public site"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Kubernetes API from Jenkins"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ghosthref-k3s-sg"
  }
}

resource "aws_security_group" "data" {
  name        = "ghosthref-data-sg"
  description = "Data host: SSH + Kibana from operator IP, Postgres/Redis/Elasticsearch from k3s nodes only"
  vpc_id      = aws_vpc.ghosthref.id

  ingress {
    description = "SSH from operator IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Kibana from operator IP"
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description     = "Postgres from k3s nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.k3s.id]
  }

  ingress {
    description     = "Redis from k3s nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.k3s.id]
  }

  ingress {
    description     = "Elasticsearch from k3s nodes"
    from_port       = 9200
    to_port         = 9200
    protocol        = "tcp"
    security_groups = [aws_security_group.k3s.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ghosthref-data-sg"
  }
}

resource "aws_security_group" "jenkins" {
  name        = "ghosthref-jenkins-sg"
  description = "Jenkins: SSH + UI from operator IP, webhook delivery from GitHub"
  vpc_id      = aws_vpc.ghosthref.id

  ingress {
    description = "SSH from operator IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Jenkins UI from operator IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "GitHub webhook delivery"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.github_webhook_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ghosthref-jenkins-sg"
  }
}

// Instances 
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_small
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.k3s.id]

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "ghosthref-k3s-server"
  }
}

resource "aws_instance" "data" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_data
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.data.id]

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_size = 30 # Postgres + Redis + Elasticsearch + Kibana
  }

  tags = {
    Name = "ghosthref-data"
  }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_small
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.jenkins.id]

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name = "ghosthref-jenkins"
  }
}
