#-*- mode: makefile; -*-

########################################################################
# SNS Lambda Handler test
# 
# make -f Makefile.poc PAYLOAD=payload-sns.json test-sns
#
########################################################################

test-sns: lambda-function $(PAYLOAD)
	aws lambda invoke \
	    --function-name $(FUNCTION_NAME) \
	    --payload file://$(PAYLOAD) \
	    --cli-binary-format raw-in-base64-out \
	    --profile $(AWS_PROFILE) \
	    $@ && cat $@
