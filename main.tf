/**
  * # terraform-aws-eipattach
  *
  * Terraform module to automatically attach an Elastic IP address to an instance on startup.
  *
  * This module will automatically attach an appropriately tagged Elastic IP address to an
  * appropriately tagged AWS instance when that instance is created (presumably via autoscaling).
  *
  * ## License
  *
  * MIT
  *
  * ## Usage examples
  *
  * ### Simple
  *
  * Give the instance tagged `EIP foobar` the EIP tagged `EIP foobar`, and disable
  * source/dest checking.
  *
  * ```hcl
  * module "eipattach" {
  *   source              = "claranet/eipattach/aws"
  *   disable_source_dest = true
  * }
  *
  * resource "aws_eip" "test" {
  *   tags {
  *     EIP = "foobar"
  *   }
  * }
  *
  * resource "aws_autoscaling_group" "test" {
  *   name                 = "test"
  *   max_size             = 1
  *   min_size             = 1
  *   launch_configuration = "${aws_launch_configuration.test.name}"
  *   vpc_zone_identifier  = ["${aws_subnet.test.id}"]
  *
  *   tag {
  *     key                 = "EIP"
  *     value               = "foobar"
  *     propagate_at_launch = true
  *   }
  * }
  * ```
  *
  * ### Machines with multiple ENIs
  *
  * If you have machines with multiple ENIs, you must tag the ENI appropriately rather
  * than the instance:
  *
  * ```hcl
  * resource "aws_eip" "test_eni" {
  *   tags {
  *     EIP = "barbaz"
  *   }
  * }
  *
  * resource "aws_network_interface" "test_eni" {
  * subnet_id = "${aws_subnet.test.id}"
  *
  *   tags {
  *     EIP = "barbaz"
  *   }
  * }
  * ```
  *
  * ## Contributing
  *
  * Please submit pull requests at https://github.com/claranet/terraform-aws-eipattach/
  *
  * The README.md is generated with
  * [terraform-docs](https://github.com/segmentio/terraform-docs) - to generate run
  * `terraform-docs md . > README.md`
  *
  */

module "lambda" {
  source  = "claranet/lambda/aws"
  version = "0.8.3"

  function_name = "${var.name}"
  description   = "Attaches Elastic IPs to instances"
  handler       = "main.lambda_handler"
  runtime       = "python3.6"
  timeout       = "${var.timeout}"
  source_path   = "${path.module}/lambda"
  attach_policy = true
  policy        = "${data.aws_iam_policy_document.lambda.json}"

  environment {
    variables {
      TAG_KEY             = "${var.tag_name}"
      DISABLE_SOURCE_DEST = "${var.disable_source_dest}"
    }
  }
}

data "aws_iam_policy_document" "lambda" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeAddresses",
      "ec2:DescribeTags",
      "ec2:AssociateAddress",
      "ec2:ModifyInstanceAttribute",
    ]

    resources = [
      "*",
    ]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"

      values = ["${var.tag_name}"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.name}-schedule"
  schedule_expression = "${var.schedule}"
}

resource "aws_cloudwatch_event_target" "schedule" {
  target_id = "${var.name}-schedule"
  rule      = "${aws_cloudwatch_event_rule.schedule.name}"
  arn       = "${module.lambda.function_arn}"
}

resource "aws_lambda_permission" "schedule" {
  statement_id  = "${var.name}-schedule"
  action        = "lambda:InvokeFunction"
  function_name = "${module.lambda.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.schedule.arn}"
}
