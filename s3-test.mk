#-*- mode: makefile; -*-

########################################################################
# S3 Lambda Handler test
# 
#  make -f Makefile.poc BUCKET_NAME=my-bucket lambda-s3-trigger
#
########################################################################

BUCKET_NAME ?= my-bucket
S3_EVENT    ?= s3:ObjectCreated:*

s3-bucket:
	@bucket="$$(aws s3api list-buckets --query 'Buckets[?Name==`$(BUCKET_NAME)`].Name' --output text --profile $(AWS_PROFILE))"; \
	if [[ -z "$$bucket" ]]; then \
	  aws s3 mb s3://$(BUCKET_NAME) --profile $(AWS_PROFILE); \
	  bucket="$(BUCKET_NAME)"; \
	fi; \
	test -e $@ || echo "$$bucket" > $@;

lambda-s3-permission: lambda-function s3-bucket
	@permission="$$(aws lambda get-policy \
	        --function-name $(FUNCTION_NAME) \
	        --profile $(AWS_PROFILE) 2>&1)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q s3.amazonaws.com; then \
	    permission="$$(aws lambda add-permission \
	        --function-name $(FUNCTION_NAME) \
	        --statement-id s3-trigger-$(BUCKET_NAME) \
	        --action lambda:InvokeFunction \
	        --principal s3.amazonaws.com \
	        --source-arn arn:aws:s3:::$(BUCKET_NAME) \
	        --profile $(AWS_PROFILE))"; \
	elif echo "$$permission" | grep -q 'error\|Error'; then \
	    echo "ERROR: get-policy failed: $$permission" >&2; \
	    exit 1; \
	fi; \
	if [[ -n "$$permission" ]]; then \
	    test -e $@ || echo "$$permission" > $@; \
	else \
	    rm -f $@; \
	fi

define notification_configuration = 
use JSON;

my $lambda_function = $ENV{lambda_function};
my $function_arn = decode_json($lambda_function)->{Configuration}->{FunctionArn};

my $configuration = {
 LambdaFunctionConfigurations => [ { 
   LambdaFunctionArn => $function_arn,
   Events => [ split ' ', $ENV{s3_event} ],
  }
 ]
};

print encode_json($configuration);
endef

export s_notification_configuration = $(value notification_configuration)

lambda-s3-trigger: lambda-s3-permission
	@temp="$$(mktemp)"; trap 'rm -f "$$temp"' EXIT; \
	lambda_function="$$(cat lambda-function)"; \
	echo $$(s3_event="$(S3_EVENT)" lambda_function="$$lambda_function" \
	  perl -e "$$s_notification_configuration") > $$temp; \
	trigger="$$(aws s3api put-bucket-notification-configuration \
	    --bucket $(BUCKET_NAME) \
	    --notification-configuration file://$$temp \
	    --profile $(AWS_PROFILE) && cat $$temp)"; \
	test -e $@ || echo "$$trigger" > $@
