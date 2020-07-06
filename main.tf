locals {
  deny_root_account_effect             = var.deny_root_account ? ["Deny"] : []
  deny_leaving_orgs_effect             = var.deny_leaving_orgs ? "Deny" : "Allow"
  deny_creating_iam_users_effect       = var.deny_creating_iam_users ? "Deny" : "Allow"
  deny_deleting_kms_keys_effect        = var.deny_deleting_kms_keys ? "Deny" : "Allow"
  deny_deleting_route53_zones_effect   = var.deny_deleting_route53_zones ? "Deny" : "Allow"
  require_s3_encryption_effect         = var.require_s3_encryption ? ["Deny"] : []
  deny_deleting_cloudwatch_logs_effect = var.deny_deleting_cloudwatch_logs ? "Deny" : "Allow"
  protect_s3_buckets_effect            = var.protect_s3_buckets ? ["Deny"] : []
  protect_iam_roles_effect             = var.protect_iam_roles ? ["Deny"] : []
  limit_regions_effect                 = var.limit_regions ? ["Deny"] : []
}

#
# Combine Policies
#

data "aws_iam_policy_document" "combined_policy_block" {

  #
  # Deny root account
  #

  dynamic "statement" {
    for_each = local.deny_root_account_effect
    content {
      sid       = "DenyRootAccount"
      actions   = ["*"]
      resources = ["*"]
      effect    = "Deny"
      condition {
        test     = "StringLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:aws:iam::*:root"]
      }
    }
  }

  #
  # Deny leaving AWS Organizations
  #

  statement {
    sid       = "DenyLeavingOrgs"
    effect    = local.deny_leaving_orgs_effect
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }

  #
  # Deny creating IAM users or access keys
  #

  statement {
    sid    = "DenyCreatingIAMUsers"
    effect = local.deny_creating_iam_users_effect
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey"
    ]
    resources = ["*"]
  }

  #
  # Deny deleting KMS Keys
  #

  statement {
    sid    = "DenyDeletingKMSKeys"
    effect = local.deny_deleting_kms_keys_effect
    actions = [
      "kms:ScheduleKeyDeletion",
      "kms:Delete*"
    ]
    resources = ["*"]
  }

  #
  # Deny deleting Route53 Hosted Zones
  #

  statement {
    sid    = "DenyDeletingRoute53Zones"
    effect = local.deny_deleting_route53_zones_effect
    actions = [
      "route53:DeleteHostedZone"
    ]
    resources = ["*"]
  }

  #
  # Require S3 encryption
  #
  # https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingServerSideEncryption.html

  dynamic "statement" {
    for_each = local.deny_root_account_effect
    content {
      sid       = "DenyIncorrectEncryptionHeader"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["*"]
      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption"
        values   = ["AES256"]
      }
    }
    statement {
      sid       = "DenyUnEncryptedObjectUploads"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["*"]
      condition {
        test     = "Null"
        variable = "s3:x-amz-server-side-encryption"
        values   = [true]
      }
    }
  }

  #
  # Deny deleting VPC Flow logs, cloudwatch log groups, and cloudwatch log streams
  #

  statement {
    sid    = "DenyDeletingCloudwatchLogs"
    effect = local.deny_deleting_cloudwatch_logs_effect
    actions = [
      "ec2:DeleteFlowLogs",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream"
    ]
    resources = ["*"]
  }

  #
  # Protect S3 Buckets
  #

  dynamic "statement" {
    for_each = local.protect_s3_buckets_effect
    content {
      sid    = "ProtectS3Buckets"
      effect = "Deny"
      actions = [
        "s3:DeleteBucket",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
      ]
      resources = var.protect_s3_bucket_resources
    }
  }

  #
  # Protect IAM Roles
  #
  dynamic "statement" {
    for_each = local.protect_iam_roles_effect
    content {
      sid    = "ProtectIAMRoles"
      effect = "Deny"
      actions = [
        "iam:AttachRolePolicy",
        "iam:DeleteRole",
        "iam:DeleteRolePermissionsBoundary",
        "iam:DeleteRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePermissionsBoundary",
        "iam:PutRolePolicy",
        "iam:UpdateAssumeRolePolicy",
        "iam:UpdateRole",
        "iam:UpdateRoleDescription"
      ]
      resources = var.protect_iam_role_resources
    }
  }

  #
  # Restrict Regional Operations
  #

  dynamic "statement" {
    for_each = local.limit_regions_effect
    content {
      sid    = "LimitRegions"
      effect = "Deny"

      # These actions do not operate in a specific region, or only run in
      # a single region, so we don't want to try restricting them by region.
      not_actions = [
        "iam:*",
        "organizations:*",
        "route53:*",
        "budgets:*",
        "waf:*",
        "cloudfront:*",
        "globalaccelerator:*",
        "importexport:*",
        "support:*",
        "sts:*"
      ]

      resources = ["*"]

      condition {
        test     = "StringNotEquals"
        variable = "aws:RequestedRegion"
        values   = var.allowed_regions
      }
    }
  }
}

#
# Deny all access
#

data "aws_iam_policy_document" "deny_all_access" {

  statement {
    sid       = "DenyAllAccess"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_organizations_policy" "generated" {
  name        = "${var.target.name}-generated-ou-scp"
  description = "${var.target.name} SCP generated by ou-scp module"
  content     = var.deny_all ? data.aws_iam_policy_document.deny_all_access.json : data.aws_iam_policy_document.combined_policy_block.json
}

resource "aws_organizations_policy_attachment" "generated" {
  policy_id = aws_organizations_policy.generated.id
  target_id = var.target.id
}