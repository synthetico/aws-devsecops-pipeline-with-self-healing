"""
AWS Lambda function for self-healing security groups.
Automatically reverts manual security group changes to a predefined golden state.
"""

import json
import os
import boto3
import logging
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
ec2_client = boto3.client('ec2')
config_client = boto3.client('config')

# Golden state from environment variable
GOLDEN_RULES = json.loads(os.environ.get('GOLDEN_RULES', '[]'))

# Tag to identify security groups that should be self-healed
SELF_HEALING_TAG = 'SelfHealing'


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for Config compliance change events.

    Args:
        event: EventBridge event from AWS Config
        context: Lambda context

    Returns:
        Response dict with status
    """
    logger.info(f"Received event: {json.dumps(event)}")

    try:
        # Extract event details
        detail = event.get('detail', {})
        config_rule_name = detail.get('configRuleName')
        compliance_type = detail.get('newEvaluationResult', {}).get('complianceType')
        resource_type = detail.get('resourceType')
        resource_id = detail.get('resourceId')

        logger.info(f"Config Rule: {config_rule_name}")
        logger.info(f"Compliance: {compliance_type}")
        logger.info(f"Resource Type: {resource_type}")
        logger.info(f"Resource ID: {resource_id}")

        # Only process NON_COMPLIANT security groups
        if compliance_type != 'NON_COMPLIANT':
            logger.info("Resource is compliant, no action needed")
            return {'statusCode': 200, 'body': 'Resource is compliant'}

        if resource_type != 'AWS::EC2::SecurityGroup':
            logger.info("Not a security group resource, skipping")
            return {'statusCode': 200, 'body': 'Not a security group'}

        # Get security group details
        sg_id = resource_id
        logger.info(f"Processing security group: {sg_id}")

        # Check if security group should be self-healed
        if not should_self_heal(sg_id):
            logger.info(f"Security group {sg_id} is not tagged for self-healing, skipping")
            return {'statusCode': 200, 'body': 'Security group not tagged for self-healing'}

        # Restore security group to golden state
        restore_security_group(sg_id)

        logger.info(f"Successfully restored security group {sg_id} to golden state")
        return {
            'statusCode': 200,
            'body': f'Security group {sg_id} restored to golden state'
        }

    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': f'Error: {str(e)}'
        }


def should_self_heal(sg_id: str) -> bool:
    """
    Check if a security group should be self-healed based on tags.

    Args:
        sg_id: Security group ID

    Returns:
        True if security group should be self-healed, False otherwise
    """
    try:
        response = ec2_client.describe_security_groups(GroupIds=[sg_id])

        if not response['SecurityGroups']:
            logger.warning(f"Security group {sg_id} not found")
            return False

        sg = response['SecurityGroups'][0]
        tags = {tag['Key']: tag['Value'] for tag in sg.get('Tags', [])}

        # Check if self-healing tag exists and is set to 'true'
        return tags.get(SELF_HEALING_TAG, '').lower() == 'true'

    except Exception as e:
        logger.error(f"Error checking security group tags: {str(e)}")
        return False


def restore_security_group(sg_id: str) -> None:
    """
    Restore security group ingress rules to golden state.

    Args:
        sg_id: Security group ID to restore
    """
    try:
        # Get current security group configuration
        response = ec2_client.describe_security_groups(GroupIds=[sg_id])

        if not response['SecurityGroups']:
            logger.error(f"Security group {sg_id} not found")
            return

        sg = response['SecurityGroups'][0]
        current_ingress = sg.get('IpPermissions', [])

        logger.info(f"Current ingress rules: {json.dumps(current_ingress, default=str)}")
        logger.info(f"Golden state rules: {json.dumps(GOLDEN_RULES)}")

        # Step 1: Remove all current ingress rules
        if current_ingress:
            logger.info(f"Revoking {len(current_ingress)} current ingress rules")
            ec2_client.revoke_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=current_ingress
            )

        # Step 2: Apply golden state rules
        if GOLDEN_RULES:
            golden_permissions = []

            for rule in GOLDEN_RULES:
                permission = {
                    'IpProtocol': rule['protocol'],
                    'FromPort': rule['from_port'],
                    'ToPort': rule['to_port'],
                    'IpRanges': [
                        {'CidrIp': cidr, 'Description': rule.get('description', '')}
                        for cidr in rule['cidr_blocks']
                    ]
                }
                golden_permissions.append(permission)

            logger.info(f"Authorizing {len(golden_permissions)} golden state ingress rules")
            ec2_client.authorize_security_group_ingress(
                GroupId=sg_id,
                IpPermissions=golden_permissions
            )

        logger.info(f"Security group {sg_id} restored to golden state successfully")

    except Exception as e:
        logger.error(f"Error restoring security group {sg_id}: {str(e)}", exc_info=True)
        raise


def get_security_group_details(sg_id: str) -> Dict[str, Any]:
    """
    Get detailed information about a security group.

    Args:
        sg_id: Security group ID

    Returns:
        Security group details dict
    """
    try:
        response = ec2_client.describe_security_groups(GroupIds=[sg_id])

        if response['SecurityGroups']:
            return response['SecurityGroups'][0]

        return {}

    except Exception as e:
        logger.error(f"Error getting security group details: {str(e)}")
        return {}
