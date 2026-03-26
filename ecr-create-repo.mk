########################################################################
# create ECR repository
########################################################################
ecr-uri:
	@repo_uri=$$(aws ecr describe-repositories \
	        --profile $(AWS_PROFILE) \
	        --query "repositories[?repositoryName=='$(REPO_NAME)'].repositoryUri" \
	        --output text 2>/dev/null); \
	if [[ -z "$$repo_uri" ]] || echo "$$repo_uri" | grep -qv "$(REPO_NAME)"; then \
	  repo_uri=$$(aws ecr create-repository \
	        --repository-name $(REPO_NAME) \
	        --region $(REGION) \
	        --query "repository.repositoryUri" \
	        --output text \
	        --profile $(AWS_PROFILE)); \
	fi; \
	test -e $@ || echo "$$repo_uri" > $@

ecr-lifecycle-policy: ecr-uri
	lifecycle_policy=$$(aws ecr get-lifecycle-policy \
	  --repository-name $(REPO_NAME) \
	  --profile $(AWS_PROFILE) 2>&1 || true); \
	if echo "$$lifecycle_policy" | grep -q "LifecyclePolicyNotFoundException"; then \
	  lifecycle_policy=$$(aws ecr put-lifecycle-policy \
	    --repository-name $(REPO_NAME) \
	    --lifecycle-policy-text \
	    '{"rules":[{"rulePriority":1,"selection":{"tagStatus":"untagged","countType":"sinceImagePushed","countUnit":"days","countNumber":1},"action":{"type":"expire"}}]}' \
	    --profile $(AWS_PROFILE)); \
	fi; \
	test -e $@ || echo "$$lifecycle_policy" > $@

ecr-repo: ecr-uri ecr-lifecycle-policy
	cp $< $@
