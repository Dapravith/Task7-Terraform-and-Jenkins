output "public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.foodexpress_ec2.public_ip
}

output "app_url" {
  description = "Application URL"
  value       = "http://${aws_instance.foodexpress_ec2.public_ip}"
}

output "health_url" {
  description = "Health check URL"
  value       = "http://${aws_instance.foodexpress_ec2.public_ip}/health"
}