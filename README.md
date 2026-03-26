# NAME

Amazon::Lambda::Runtime

# SYNOPSIS

    package MyLambda;

    use strict;
    use warnings;

    use parent qw(Amazon::Lambda::Runtime);
    use JSON qw(encode_json);

    sub handler {
      my ($self, $event, $context) = @_;
      return encode_json({ message => 'Hello!', input => $event });
    }

    1;

# DESCRIPTION

Base class for creating Perl Lambda functions using the AWS Lambda
Custom Runtime API. The runtime implements the polling loop that
retrieves events from the Lambda service, invokes your handler, and
returns responses or errors.

The distribution ships the following components:

- `Amazon::Lambda::Runtime` - the polling loop and base handler class
- `Amazon::Lambda::Runtime::Context` - Lambda invocation metadata
- `Amazon::Lambda::Runtime::Event` - event source factory and registry
- `Amazon::Lambda::Runtime::Event::SQS` - SQS event handler base class
- `Amazon::Lambda::Runtime::Event::SNS` - SNS event handler base class
- `Amazon::Lambda::Runtime::Event::S3` - S3 event handler base class
- `Amazon::Lambda::Runtime::Event::EventBridge` - EventBridge handler base class
- `Amazon::Lambda::Runtime::Writer` - streaming response writer
- `bootstrap` - Lambda bootstrap script installed to `/usr/local/bin/bootstrap`

This distribution uses a container image deployment model. Any Linux
base image is supported. Development and testing is done on
`debian:trixie-slim`. No Amazon Linux, no layer ARN management, no
pre-built images required.

## Design Philosophy

`Amazon::Lambda::Runtime` is a Perl Lambda runtime you can read.
Every component is visible, documented, and replaceable. Install it
from CPAN like any other module. Your `cpanfile` is your bill of
materials. Your Dockerfile is your image. Nothing is hidden behind a
pre-built base image or a layer ARN maintained by someone else.

Think of it as a grandfather clock in a glass case with the door
unlocked. Every gear is visible. You understand exactly why it keeps
time. If you want to change the chime, open the door.

If you are evaluating Perl Lambda runtime options, you may find other
implementations on CPAN. This one prioritizes transparency,
compatibility with standard Perl idioms, and integration with existing
Perl AWS infrastructure over convenience wrappers or pre-built images.
If you can read a Perl class and a Dockerfile, you understand
everything this distribution does.

## Event Framework

`Amazon::Lambda::Runtime` ships a structured event dispatch framework
covering the four most common Lambda event sources - SQS, SNS, S3, and
EventBridge. The base `handler` method detects the event source and
dispatches to the appropriate handler class via a registry.

Register event handler classes in your Lambda module:

    package MyLambda;

    use parent qw(Amazon::Lambda::Runtime);
    use Amazon::Lambda::Runtime::Event qw(:all);

    __PACKAGE__->register_event_handler($EVENT_SQS => 'MyLambda::SQS');
    __PACKAGE__->register_event_handler($EVENT_S3  => 'MyLambda::S3');

    1;

    package MyLambda::SQS;

    use parent qw(Amazon::Lambda::Runtime::Event::SQS);

    sub on_message {
      my ($self, $body, $record) = @_;
      $self->get_logger->info("received: $body");
    }

    1;

There are three levels of customization - TIMTOWTDI:

- 1. Override `handler` entirely and ignore the event framework.
- 2. Register event handler classes via `register_event_handler`.
The base `handler` routes automatically.
- 3. Subclass an event object and override a single stub method.
Pure business logic - no routing code required.

Available event source constants (exported via `:all`):

    $EVENT_SQS         # aws:sqs
    $EVENT_SNS         # aws:sns
    $EVENT_S3          # aws:s3
    $EVENT_EVENTBRIDGE # aws:events

For sample event payloads for all supported event sources see:

[https://github.com/tschoffelen/lambda-sample-events](https://github.com/tschoffelen/lambda-sample-events)

## Streaming Responses

Handlers can stream responses progressively by returning a coderef
instead of a string. The runtime detects the coderef and switches to
chunked HTTP transfer encoding via `Amazon::Lambda::Runtime::Writer`:

    sub handler {
      my ($self, $event, $context) = @_;

      return sub {
        my ($writer) = @_;
        $writer->write('{"chunk":1,"message":"Hello"}');
        $writer->write('{"chunk":2,"message":"World"}');
        $writer->close;
      };
    }

Streaming requires a Lambda Function URL configured with
`InvokeMode=RESPONSE_STREAM` or API Gateway HTTP API with streaming
enabled. Use `make lambda-function-url` from `streaming-test.mk`
to create a public streaming endpoint.

**Note:** AWS accounts may require both `lambda:InvokeFunctionUrl`
and `lambda:InvokeFunction` permissions for public Function URL
access. Both are added by `make lambda-function-url-permission` and
`make lambda-function-url-invoke-permission`. Direct CLI invocations,
SQS, SNS, S3, and EventBridge triggers do not support streaming.

See [Amazon::Lambda::Runtime::Writer](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3ARuntime%3A%3AWriter) for the full writer API.

## AWS X-Ray

For distributed tracing add `AWS::XRay` to your `cpanfile`:

    requires 'AWS::XRay';

`AWS::XRay` communicates with the X-Ray daemon via UDP on
`localhost:2000` - no additional HTTP dependencies are required.

    use AWS::XRay qw(capture);

    sub handler {
      my ($self, $event, $context) = @_;
      capture 'myApp' => sub {
        # your code here
      };
    }

See [AWS::XRay](https://metacpan.org/pod/AWS%3A%3AXRay) on CPAN for full usage details.

## Makefile.build Variables

- PERL\_LAMBDA

    Docker image name. Default: `perl-lambda`

- AWS\_PROFILE

    AWS CLI profile. Default: `default`. Can also be set in the environment.

- REGION

    AWS region. Default: `us-east-1`

- REPO\_NAME

    ECR repository name. Default: `perl-lambda`

- FUNCTION\_NAME

    Lambda function name. Default: `lambda-handler`

- ROLE\_NAME

    IAM role name. Default: `lambda-role`

- POLICIES\_FILE

    Path to the policies file. Default: `policies`. See ["The policies File"](#the-policies-file).

- AWS\_ACCOUNT

    AWS account ID. Resolved automatically via `aws sts get-caller-identity`
    if not set in the environment.

- LAMBDA\_MODULE

    Your handler module filename. Default: `LambdaHandler.pm`

- PAYLOAD

    Payload file for `make invoke` and `make test-sns`. Default: `payload.json`

- QUEUE\_NAME

    SQS queue name. Default: `lambda-runtime`

- BATCH\_SIZE

    SQS messages per invocation. Default: `10`

- BUCKET\_NAME

    S3 bucket name for `make lambda-s3-trigger`. Default: `my-bucket`

- S3\_EVENT

    S3 event type. Default: `s3:ObjectCreated:*`

- RULE\_NAME

    EventBridge rule name. Default: `lambda-handler-test`

- SCHEDULE\_EXPRESSION

    EventBridge schedule. Default: `rate(1 minute)`

- INVOKE\_MODE

    Lambda Function URL invoke mode. Default: `RESPONSE_STREAM`

- TIMEOUT

    Lambda startup time timeout value in seconds. Default: 30

## Makefile.build Targets

- image

    Builds the Docker image from `Dockerfile` and your handler module.

- ecr-repo

    Creates the ECR repository if it does not exist. Idempotent. Sentinel
    file contains the ECR repository URI.

- deploy

    Logs in to ECR, tags and pushes the image using the image digest rather
    than `:latest` to ensure Lambda always pulls the correct image.

- policy-document

    Generates the IAM assume-role trust policy JSON document. Prerequisite
    for `lambda-role`.

- lambda-role

    Creates the IAM role if it does not exist. Idempotent.

- lambda-policies

    Attaches all policies in the `policies` file to the Lambda execution
    role. Idempotent - safe to run at any time.

- update-policies

    Re-runs `lambda-policies` to pick up changes to the `policies` file.

- lambda-function

    Creates the Lambda function if it does not exist. Depends on
    `ecr-repo` and `lambda-policies`, with `deploy` as an order-only
    prerequisite.

- update-function

    Pushes a new image to ECR and updates the Lambda function code. Waits
    for the function to become active before returning.

- invoke

    Invokes the function with `$(PAYLOAD)` and prints the response.

- lambda-sqs-trigger

    Creates an SQS queue (`QUEUE_NAME`) and attaches it as an event source.
    Requires `AWSLambdaSQSQueueExecutionRole` in the `policies` file.

- lambda-s3-permission

    Grants S3 permission to invoke the Lambda function for the bucket
    specified by `BUCKET_NAME`.

- lambda-s3-trigger

    Configures S3 bucket notifications to trigger the Lambda on
    `S3_EVENT` events.

- lambda-eventbridge-rule

    Creates an EventBridge scheduled rule. Starts enabled.

- lambda-eventbridge-permission

    Grants EventBridge permission to invoke the Lambda function.

- lambda-eventbridge-trigger

    Registers the Lambda function as the target of the EventBridge rule.

- enable-eventbridge-rule / disable-eventbridge-rule

    Enables or disables the EventBridge rule without deleting the
    infrastructure. Use `make disable-eventbridge-rule` after testing
    to stop scheduled invocations.

- delete-eventbridge-rule

    Removes targets, deletes the rule, and removes local sentinel files.
    Targets must be removed before the rule can be deleted.

- lambda-function-url-permission

    Grants `lambda:InvokeFunctionUrl` to `*` principal for public
    Function URL access.

- lambda-function-url-invoke-permission

    Grants `lambda:InvokeFunction` to `*` principal. Required in
    addition to `lambda-function-url-permission` for public access on
    accounts with block public access enabled.

- lambda-function-url

    Creates a Lambda Function URL with `auth-type NONE` and
    `InvokeMode=$(INVOKE_MODE)`. Depends on both permission targets.

- test-streaming

    Invokes the Function URL with `curl -sN` to test streaming responses.

- clean

    Removes all local sentinel files. AWS resources are not deleted.

# METHODS

## new

    new(options)

Constructor. Your class may override this but must call the base class.
`options` is a hash reference:

- loglevel

    Log level: `fatal`, `error`, `warn`, `info`, `debug`, `trace`.
    Default: `info`. Can also be set via the `LOG_LEVEL` Lambda
    environment variable.

## register\_event\_handler

    __PACKAGE__->register_event_handler($EVENT_SQS => 'My::SQS::Handler');

Class method. Registers an event handler class for a given event
source. The base `handler` method consults this registry on each
invocation to route events to the appropriate handler class.

## handler

    handler($event, $context)

The base class implementation detects the event source and dispatches
to the registered handler class via `Amazon::Lambda::Runtime::Event`.
If no handler is registered for the source, falls back to the
appropriate default event class.

Override this method to bypass the event framework entirely and handle
the raw event hashref directly.

Handlers can:

- 1. die - Lambda reports a function error
- 2. return undef - assumes the handler sent the response itself
- 3. return a string - sent as the invocation response
- 4. return a coderef - triggers streaming response via `Amazon::Lambda::Runtime::Writer`

## get\_logger

Returns the [Log::Log4perl](https://metacpan.org/pod/Log%3A%3ALog4perl) logger. Prefer the coderef form for
expensive operations:

    $self->get_logger->debug(sub { Dumper($event) });

## run

    run()

The main event loop. Polls for events and invokes the handler for each.

## next\_event

    next_event()

Internal. Polls the Lambda Runtime API for the next event. State
stored in package variables persists between warm invocations - use
this to cache database connections or credential objects.

## send\_invocation\_response

    send_invocation_response($response)

Internal. Sends the response string to the Lambda service.

## send\_streaming\_response

    send_streaming_response($coderef)

Internal. Called automatically when the handler returns a coderef.
Opens a raw TCP connection to the Runtime API and streams chunks via
`Amazon::Lambda::Runtime::Writer`. See ["Streaming Responses"](#streaming-responses).

## send\_invocation\_error

    send_invocation_error($message, $type)

Sends a structured error to the Lambda service. Preferred over
throwing an exception for graceful error reporting.

## send\_init\_error

    send_init_error($message, $type)

Reports an initialization error. Call from your `new()` override if
initialization fails and the function should not be invoked.

# NOTES

## Logging

Output to `STDERR` is captured in the CloudWatch log stream. Use the
internal logger for structured, CloudWatch-friendly output:

    $self->get_logger->info("a message");
    $self->get_logger->debug(sub { Dumper($event) });

Log levels from least to most verbose: `fatal`, `error`, `warn`,
`info`, `debug`, `trace`. Default is `info`.

Set the `LOG_LEVEL` environment variable in your Lambda configuration
to change the level at runtime:

    aws lambda update-function-configuration \
        --function-name my-function \
        --environment "Variables={LOG_LEVEL=debug}"

## Required IAM Permissions

### ECR

    ecr:CreateRepository
    ecr:DescribeRepositories
    ecr:GetAuthorizationToken
    ecr:BatchCheckLayerAvailability
    ecr:PutImage
    ecr:InitiateLayerUpload
    ecr:UploadLayerPart
    ecr:CompleteLayerUpload
    ecr:PutLifecyclePolicy

### IAM

    iam:GetRole
    iam:CreateRole
    iam:AttachRolePolicy
    iam:PassRole
    iam:ListAttachedRolePolicies

**Note:** `iam:PassRole` is frequently overlooked. Its absence
produces a confusing `InvalidParameterValueException` stating the
role cannot be assumed by Lambda even though the role exists and
appears correctly configured.

### Lambda

    lambda:GetFunction
    lambda:CreateFunction
    lambda:UpdateFunctionCode
    lambda:UpdateFunctionConfiguration
    lambda:InvokeFunction
    lambda:GetFunctionConfiguration
    lambda:CreateEventSourceMapping
    lambda:ListEventSourceMappings
    lambda:GetPolicy
    lambda:AddPermission
    lambda:CreateFunctionUrlConfig
    lambda:GetFunctionUrlConfig

### STS

    sts:GetCallerIdentity

Set `AWS_ACCOUNT` in your environment to avoid this call:

    export AWS_ACCOUNT=$(aws sts get-caller-identity \
        --query Account --output text --profile myprofile)

### Additional Permissions for Your Handler

`AWSLambdaBasicExecutionRole` covers CloudWatch logging only. Add
additional policies to the `policies` file and run
`make update-policies`.

Receiving an event from a service does not automatically grant your
handler permission to call that service's APIs. For example, an S3
event trigger gives Lambda permission to invoke your function when an
object is created - it does not grant your function permission to read
or write objects in that bucket. Similarly, an SQS trigger grants
Lambda permission to poll the queue - it does not grant permission to
call other SQS APIs.

The `policies` file ships with commonly needed managed policies
pre-commented. Uncomment those you require:

    # S3 access
    # arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    # arn:aws:iam::aws:policy/AmazonS3FullAccess

    # SQS access
    # arn:aws:iam::aws:policy/AmazonSQSFullAccess

**Note:** IAM policies grant access at the account level but individual
S3 buckets may have their own resource-based bucket policies that
restrict access further. If your Lambda has the correct IAM policy but
still receives `AccessDenied` errors accessing a specific bucket,
check the bucket policy - it may explicitly deny access to your Lambda
execution role regardless of what IAM allows.

## AWS Reference Implementation

For reference, the AWS shell script custom runtime:

    #!/bin/sh
    set -euo pipefail
    source $LAMBDA_TASK_ROOT/"$(echo $_HANDLER | cut -d. -f1).sh"
    while true
    do
      HEADERS="$(mktemp)"
      EVENT_DATA=$(curl -sS -LD "$HEADERS" -X GET \
        "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next")
      REQUEST_ID=$(grep -Fi Lambda-Runtime-Aws-Request-Id "$HEADERS" \
        | tr -d '[:space:]' | cut -d: -f2)
      RESPONSE=$($(echo "$_HANDLER" | cut -d. -f2) "$EVENT_DATA")
      curl -X POST \
        "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/$REQUEST_ID/response" \
        -d "$RESPONSE"
    done

# AUTHOR

Rob Lauer - <rlauer@treasurersbriefcase.com>

# LICENSE

(c) Copyright 2019-2026 Robert C. Lauer. All rights reserved. This
module is free software. It may be used, redistributed and/or
modified under the same terms as Perl itself.
