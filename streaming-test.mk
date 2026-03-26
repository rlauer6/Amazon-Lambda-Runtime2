#-*- mode: makefile; -*-

INVOKE_MODE ?= RESPONSE_STREAM

lambda-function-url: lambda-function-url-permission lambda-function-url-invoke-permission
	@url="$$(aws lambda get-function-url-config \
	        --function-name $(FUNCTION_NAME) \
	        --profile $(AWS_PROFILE) \
	        --query FunctionUrl --output text 2>&1 || true)"; \
	if echo "$$url" | grep -q 'ResourceNotFoundException'; then \
	    url="$$(aws lambda create-function-url-config \
	        --function-name $(FUNCTION_NAME) \
	        --auth-type NONE \
	        --invoke-mode $(INVOKE_MODE) \
	        --profile $(AWS_PROFILE) \
	        --query FunctionUrl --output text)"; \
	elif echo "$$url" | grep -q 'error\|Error'; then \
	    echo "ERROR: get-function-url-config failed: $$url" >&2; \
	    exit 1; \
	fi; \
	test -e $@ || echo "$$url" > $@

lambda-function-url-permission: lambda-function
	@permission="$$(aws lambda get-policy \
	        --function-name $(FUNCTION_NAME) \
	        --profile $(AWS_PROFILE) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 'InvokeFunctionUrl'; then \
	    permission="$$(aws lambda add-permission \
	        --function-name $(FUNCTION_NAME) \
	        --statement-id allow-public-url \
	        --action lambda:InvokeFunctionUrl \
	        --principal '*' \
	        --function-url-auth-type NONE \
	        --profile $(AWS_PROFILE))"; \
	fi; \
	test -e $@ || echo "$$permission" > $@

lambda-function-url-invoke-permission: lambda-function
	@permission="$$(aws lambda get-policy \
	        --function-name $(FUNCTION_NAME) \
	        --profile $(AWS_PROFILE) 2>&1 || true)"; \
	if echo "$$permission" | grep -q 'ResourceNotFoundException' || \
	   ! echo "$$permission" | grep -q 'allow-public-url-invoke'; then \
	    permission="$$(aws lambda add-permission \
	        --function-name $(FUNCTION_NAME) \
	        --statement-id allow-public-url-invoke \
	        --action lambda:InvokeFunction \
	        --principal '*' \
	        --profile $(AWS_PROFILE))"; \
	fi; \
	test -e $@ || echo "$$permission" > $@


test-streaming: lambda-function-url
	curl -sN $$(cat lambda-function-url)
