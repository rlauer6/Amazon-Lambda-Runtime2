#-*- mode: makefile; -*-

########################################################################
# EventBridge Lambda Handler test
# 
# make -f Makefile.build lambda-eventbridge-trigger
# make -f Makefile.build delete-eventbridge-rule
########################################################################

SCHEDULE_EXPRESSION ?= rate(1 minute)
RULE_NAME           ?= lambda-handler-test

lambda-eventbridge-rule:
	@rule="$$(aws events describe-rule \
	        --name $(RULE_NAME) \
	        --profile $(AWS_PROFILE) 2>&1 || true)"; \
	if echo "$$rule" | grep -q 'ResourceNotFoundException'; then \
	    rule="$$(aws events put-rule \
	        --name $(RULE_NAME) \
	        --schedule-expression "$(SCHEDULE_EXPRESSION)" \
	        --state ENABLED \
	        --profile $(AWS_PROFILE))"; \
	elif echo "$$rule" | grep -q 'error\|Error'; then \
	    echo "ERROR: describe-rule failed: $$rule" >&2; \
	    exit 1; \
	fi; \
	test -e $@ || echo "$$rule" > $@

lambda-eventbridge-permission: lambda-function lambda-eventbridge-rule
	@permission="$$(aws lambda get-policy \
	        --function-name $(FUNCTION_NAME) \
	        --profile $(AWS_PROFILE) 2>/dev/null)"; \
	if ! echo "$$permission" | grep -q events.amazonaws.com; then \
	  permission="$$(aws lambda add-permission \
	        --function-name $(FUNCTION_NAME) \
	        --statement-id eventbridge-trigger-$(RULE_NAME) \
	        --action lambda:InvokeFunction \
	        --principal events.amazonaws.com \
	        --source-arn $$(cat lambda-eventbridge-rule | \
	            perl -MJSON -n0 -e '$$r=decode_json($$_); print $$r->{RuleArn}') \
	        --profile $(AWS_PROFILE))"; \
	fi; \
	test -e $@ || echo "$$permission" > $@

lambda-eventbridge-trigger: lambda-eventbridge-permission
	@function_arn=$$(cat lambda-function | \
	    perl -MJSON -n0 -e '$$l=decode_json($$_); print $$l->{Configuration}->{FunctionArn}'); \
	targets="[{ Id => q{lambda-handler}, Arn => q{"$$function_arn"} }]"; \
	targets="$$(targets=$$targets perl -MJSON -e 'print JSON->new->pretty->encode(eval $$ENV{targets});')"; \
	temp=$$(mktemp); \
	echo "$$targets" >$$temp; \
	trigger="$$(aws events put-targets \
	    --rule $(RULE_NAME) \
	    --targets file://$$temp \
	    --profile $(AWS_PROFILE))"; \
	test -e $@ || echo "$$trigger" > $@; \
	echo "$(RULE_NAME) running...$(SCHEDULE_EXPRESSION). To delete rule:"; \
	echo "make -f Makefile.build delete-eventbridge-rule"

.PHONY: disable-eventbridge-rule

disable-eventbridge-rule:
	@aws events disable-rule \
	    --name $(RULE_NAME) \
	    --profile $(AWS_PROFILE); \
	echo "$(RULE_NAME) disabled"

.PHONY: enable-eventbridge-rule

enable-eventbridge-rule:
	@aws events enable-rule \
	    --name $(RULE_NAME) \
	    --profile $(AWS_PROFILE); \
	echo "$(RULE_NAME) enabled"

.PHONY: delete-eventbridge-rule

delete-eventbridge-rule:
	@aws events remove-targets \
	    --rule $(RULE_NAME) \
	    --ids lambda-handler \
	    --profile $(AWS_PROFILE) >/dev/null; \
	aws events delete-rule \
	    --name $(RULE_NAME) \
	    --profile $(AWS_PROFILE) >/dev/null; \
	rm -f lambda-eventbridge-rule lambda-eventbridge-permission lambda-eventbridge-trigger
