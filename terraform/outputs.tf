output "public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.foodexpress_ec2.public_ip
}

output "app_url" {
  description = "FoodExpress API URL"
  value       = "http://${aws_instance.foodexpress_ec2.public_ip}:7000"
}

output "health_url" {
  description = "FoodExpress health check URL"
  value       = "http://${aws_instance.foodexpress_ec2.public_ip}:7000/health"
}