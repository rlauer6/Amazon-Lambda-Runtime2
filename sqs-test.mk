#-*- mode: makefile; -*-

########################################################################
# SQS Lambda Handler test
# 
# make -f Makefile.poc QUEUE_NAME=fu-man-queue lambda-sqs-trigger
#
########################################################################

QUEUE_NAME ?= lambda-runtime
BATCH_SIZE ?= 10

sqs-queue:
	@queue="$$(aws sqs list-queues \
	    --query 'QueueUrls[?contains(@, `$(QUEUE_NAME)`)]|[0]' \
	    --output text --profile $(AWS_PROFILE) 2>&1)"; \
	if echo "$$queue" | grep -q 'error\|Error'; then \
	    echo "ERROR: list-queues failed: $$queue" >&2; \
	    exit 1; \
	elif [[ -z "$$queue" || "$$queue" = "None" ]]; then \
	    queue="$(QUEUE_NAME)"; \
	    aws sqs create-queue --queue-name $(QUEUE_NAME) \
	        --profile $(AWS_PROFILE); \
	fi; \
	test -e $@ || echo "$$queue" > $@

lambda-sqs-trigger: lambda-function sqs-queue
	@trigger="$$(aws lambda list-event-source-mappings \
	        --function-name $(FUNCTION_NAME) \
	        --event-source-arn arn:aws:sqs:$(REGION):$(AWS_ACCOUNT):$(QUEUE_NAME) \
	        --profile $(AWS_PROFILE) \
	        --query 'EventSourceMappings[0].UUID' \
	        --output text 2>/dev/null)"; \
	if [[ -z "$$trigger" || "$$trigger" = "None" ]]; then \
	  trigger="$$(aws lambda create-event-source-mapping \
	        --function-name $(FUNCTION_NAME) \
	        --event-source-arn arn:aws:sqs:$(REGION):$(AWS_ACCOUNT):$(QUEUE_NAME) \
	        --batch-size $(BATCH_SIZE) \
	        --profile $(AWS_PROFILE))"; \
	fi; \
	test -e $@ || echo "$$trigger" > $@
