output "bastion_host_public_ip" {
  value = aws_instance.bastion_host.public_ip
}

output "mysql_instance_private_ip" {
  value = aws_instance.mysql_instance.private_ip
}

output "mysql_load_balancer_dns" {
  description = "DNS of the MySQL load balancer"
  value       = aws_lb.mysql_lb.dns_name
}
