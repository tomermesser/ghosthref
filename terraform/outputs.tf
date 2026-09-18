output "k3s_server_public_ip" {
  value = aws_instance.k3s_server.public_ip
}

output "data_public_ip" {
  value = aws_instance.data.public_ip
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}
