# NAME

Amazon::Lambda::Runtime

# SYNOPSIS

    package Lambda;

    use strict;
    use warnings;

    use parent qw(Amazon::Lambda::Runtime);

    sub handler {
      my ($self, $event, $context) = @_;

      return 'Hello World!';
    }

    1;

# DESCRIPTION

Base class for creating Perl based Lambda functions using the AWS
Lambda Custom Runtime API. The runtime implements the polling loop
that retrieves events from the Lambda service, invokes your handler,
and returns responses or errors.

This distribution uses a container image deployment model based on
`debian:trixie-slim`. No Amazon Linux or layer management is
required.

# QUICK START

## 1. Write your handler

Create a Perl module that subclasses `Amazon::Lambda::Runtime` and
implements a `handler` method:

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

The handler receives the decoded event as a hashref and an
[Amazon::Lambda::Context](https://metacpan.org/pod/Amazon%3A%3ALambda%3A%3AContext) object. It should return a JSON string.

## 2. Create a Dockerfile

A minimal Dockerfile for your Lambda:

    FROM debian:trixie-slim

    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            perl libssl3 libexpat1 zlib1g ca-certificates \
            gcc make libssl-dev libexpat-dev zlib1g-dev libperl-dev curl && \
        curl -fsSL https://cpanmin.us | perl - App::cpanminus && \
        cpanm --notest --no-man-pages Amazon::Lambda::Runtime && \
        apt-get purge -y gcc make libssl-dev libexpat-dev libperl-dev curl && \
        apt-get autoremove -y && apt-get clean && \
        rm -rf /var/lib/apt/lists/* /root/.cpanm

    WORKDIR /var/task
    COPY MyLambda.pm /var/task/

    ENTRYPOINT ["/usr/local/bin/bootstrap"]
    CMD ["MyLambda.handler"]

`bootstrap` is installed to `/usr/local/bin/bootstrap` by this
distribution. The `ENTRYPOINT` points directly to it — no symlink
required.

The `CMD` value sets `$_HANDLER` which `bootstrap` parses to
determine the module name (`MyLambda`) and the method (`handler`).

## 3. Deploy with Makefile.poc

This distribution includes a `Makefile.poc` template in the share
directory that handles the full deployment lifecycle. Copy it to your
project directory:

    cp $(perl -MFile::ShareDir=dist_file \
        -e 'print dist_file("Amazon-Lambda-Runtime", "Makefile.poc")') \
        Makefile

Configure the variables at the top of the Makefile, then:

    make lambda-function   # first-time setup: creates ECR repo, IAM role, and Lambda function
    make invoke            # test the function
    make update-function   # deploy a new image after changes

### Makefile.poc Variables

- PERL\_LAMBDA

    Docker image name. Default: `perl-lambda-poc`

- AWS\_PROFILE

    AWS CLI profile. Default: `default`. Can also be set in the
    environment.

- REGION

    AWS region. Default: `us-east-1`

- REPO\_NAME

    ECR repository name. Default: `perl-lambda-poc`

- FUNCTION\_NAME

    Lambda function name. Default: `hello-perl`

- ROLE\_NAME

    IAM role name. Default: `lambda-role`

- POLICIES\_FILE

    Path to the policies file containing IAM managed policy ARNs to
    attach to the Lambda execution role. Default: `policies`. See
    ["The policies File"](#the-policies-file).

- AWS\_ACCOUNT

    AWS account ID. If not set in the environment, resolved automatically
    via `aws sts get-caller-identity`. Set this in your environment to
    avoid the extra API call on every `make` invocation:

        export AWS_ACCOUNT=$(aws sts get-caller-identity \
            --query Account --output text --profile myprofile)

- LAMBDA\_MODULE

    Your handler module filename. Default: `HelloLambda.pm`

- QUEUE\_NAME

    SQS queue name for `make lambda-sqs-trigger`. Default: `my-queue`

- BATCH\_SIZE

    Number of SQS messages delivered per Lambda invocation. Default: `10`.
    Valid range is 1-10 for standard queues, 1-10000 for FIFO queues.

### Makefile.poc Targets

- image

    Builds the Docker image from `Dockerfile` and your handler module.

- ecr-repo

    Creates the ECR repository if it does not exist. Idempotent. The
    sentinel file contains the ECR repository URI used by subsequent
    targets.

- deploy

    Logs in to ECR, tags and pushes the image using the image digest
    rather than the `:latest` tag to ensure Lambda always pulls the
    correct image.

- policy-document

    Generates the IAM assume-role trust policy JSON document using Perl.
    Prerequisite for `lambda-role`. The document grants
    `lambda.amazonaws.com` permission to assume the role.

- lambda-role

    Creates the IAM role if it does not exist. Idempotent. Policy
    attachment is handled separately by `lambda-policies`.

- lambda-policies

    Attaches all policies listed in the `policies` file to the Lambda
    execution role. The `attach-role-policy` API is idempotent so this
    target can be run at any time safely. See ["The policies File"](#the-policies-file).

- update-policies

    Re-runs `lambda-policies` to pick up any changes to the `policies`
    file. Use this after adding new permissions for your handler.

- lambda-function

    Creates the Lambda function if it does not exist. Depends on
    `ecr-repo` and `lambda-policies`, with `deploy` as an order-only
    prerequisite — the image must exist in ECR at creation time but a
    new deploy does not force function recreation.

- update-function

    Pushes a new image to ECR and updates the Lambda function code using
    the image digest. Waits for the function to become active before
    returning.

- queue

    Creates the SQS queue named `QUEUE_NAME` if it does not exist.
    Idempotent. Prerequisite for `lambda-sqs-trigger`.

- lambda-sqs-trigger

    Attaches the Lambda function to the SQS queue specified by
    `QUEUE_NAME` as an event source. Idempotent. Depends on both
    `lambda-function` and `queue`. Requires
    `AWSLambdaSQSQueueExecutionRole` in the `policies` file — run
    `make update-policies` before creating the trigger.

- invoke

    Invokes the function with `payload.json` and prints the response.

- clean

    Removes all local sentinel files including `image`, `ecr-repo`,
    `deploy`, `lambda-role`, `lambda-function`, `lambda-sqs-trigger`,
    `policy-document`, `queue`, and `invoke`. AWS resources are not
    deleted.

## The policies File

The `policies` file controls which IAM managed policies are attached
to the Lambda execution role. It ships with this distribution as part
of the `Makefile.poc` project template.

The file contains one policy ARN per line. Lines beginning with `#`
are treated as comments. A default `policies` file is provided with
the most commonly needed policies pre-commented:

    # Basic Lambda execution (CloudWatch logging) - required
    arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Event source triggers - uncomment as needed
    # arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole
    # arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole

    # S3 access
    # arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    # arn:aws:iam::aws:policy/AmazonS3FullAccess

The `policies` file is part of your project and should be version
controlled alongside your handler code. To apply changes:

    make update-policies

Since `attach-role-policy` is idempotent, `make update-policies`
can be run at any time without side effects — policies already
attached are silently skipped.

## Design Philosophy

`Amazon::Lambda::Runtime` takes a deliberately minimal approach.
The distribution provides exactly three components: a base class
that implements the Lambda Runtime API polling loop, a context
object that surfaces Lambda invocation metadata, and a bootstrap
script. Nothing more.

Your handler is an ordinary Perl class that inherits from
`Amazon::Lambda::Runtime` and implements a `handler` method.
This means the full power of Perl's object system is available —
override `new` for initialization, compose roles, add methods,
use any CPAN module you need. There is no framework to learn, no
DSL to adopt, no exported magic.

The container image deployment model means you choose your own
base image. This distribution is developed and tested on
`debian:trixie-slim`, giving you a proper Linux distribution
with a predictable package ecosystem rather than a cloud-vendor
variant. Your development environment and your Lambda environment
are the same.

If you are evaluating Perl Lambda runtime options, you may find
other implementations on CPAN. This one prioritizes simplicity,
transparency, and compatibility with standard Perl idioms over
convenience wrappers or pre-built infrastructure. If you can read
a Perl class and a Dockerfile, you understand everything this
distribution does.

## Handling Multiple Event Types

A single Lambda function can handle multiple event types by
dispatching on the event structure. This is particularly useful
when processing SNS notifications that wrap S3 events, or when
a single function serves as a general purpose handler for related
S3 operations.

The following pattern uses a dispatch table keyed on the S3 event
name:

    package S3EventHandler;

    use strict;
    use warnings;

    use parent qw(Amazon::Lambda::Runtime);

    use JSON qw(encode_json decode_json);

    my %DISPATCH = (
      's3:ObjectCreated:Put'                      => \&on_object_created,
      's3:ObjectCreated:CompleteMultipartUpload'  => \&on_object_created,
      's3:ObjectRemoved:Delete'                   => \&on_object_removed,
    );

    sub handler {
      my ($self, $event, $context) = @_;

      for my $record (@{$event->{Records}}) {

        # unwrap SNS envelope if present
        if ( ($record->{EventSource} // q{}) eq 'aws:sns' ) {
          $record = decode_json($record->{Sns}{Message});
        }

        my $event_name = $record->{eventName} // 'unknown';
        my $handler    = $DISPATCH{$event_name} // \&on_unhandled;

        $self->$handler($record);
      }

      return encode_json({ status => 'ok' });
    }

    sub on_object_created {
      my ($self, $record) = @_;
      my $bucket = $record->{s3}{bucket}{name};
      my $key    = $record->{s3}{object}{key};
      $self->get_logger->info("created: s3://$bucket/$key");
    }

    sub on_object_removed {
      my ($self, $record) = @_;
      my $bucket = $record->{s3}{bucket}{name};
      my $key    = $record->{s3}{object}{key};
      $self->get_logger->info("removed: s3://$bucket/$key");
    }

    sub on_unhandled {
      my ($self, $record) = @_;
      $self->get_logger->warn(
        sprintf 'unhandled event type: %s', $record->{eventName} // 'unknown'
      );
    }

    1;

The dispatch table approach keeps each event handler focused on a
single responsibility. Adding support for a new event type requires
only a new entry in `%DISPATCH` and a corresponding method —
the `handler` method itself never changes.

**SNS Envelope:** When S3 events are delivered via SNS the S3 event
record is JSON-encoded inside `$record->{Sns}{Message}`. The
pattern above unwraps this envelope transparently before dispatching
so your event handlers always receive a plain S3 event record
regardless of whether the trigger is S3 directly or SNS.

**Note:** `EventSource` (uppercase E) is used by SNS records while
`eventSource` (lowercase e) is used by SQS and S3 records directly.
This inconsistency is in the AWS event structure itself.

## SQS Event Handling

When an SQS queue is configured as a Lambda event source, Lambda
polls the queue on your behalf and delivers messages directly to
your handler. **No SQS client is required in your handler** — Lambda
handles polling, visibility timeouts, and message deletion
automatically.

On successful handler completion Lambda deletes the messages from
the queue. If your handler dies or throws an exception Lambda leaves
the messages in the queue for retry up to the queue's
`maxReceiveCount`, then routes them to the dead letter queue if
configured.

An SQS event looks like this:

    {
      "Records": [
        {
          "messageId": "059f36b4-87a3-44ab-83d2-661975830a7d",
          "receiptHandle": "AQEBwJnKyrHigUMZj...",
          "body": "your message body here",
          "attributes": {
            "ApproximateReceiveCount": "1",
            "SentTimestamp": "1545082649183"
          },
          "messageAttributes": {},
          "eventSource": "aws:sqs",
          "eventSourceARN": "arn:aws:sqs:us-east-1:123456789012:my-queue",
          "awsRegion": "us-east-1"
        }
      ]
    }

The `body` field is always a string. If your producer sends JSON
you must decode it explicitly:

    use JSON qw(encode_json decode_json);

    sub handler {
      my ($self, $event, $context) = @_;

      for my $record (@{$event->{Records}}) {
        my $payload = eval { decode_json($record->{body}) }
                      // { message => $record->{body} };

        $self->get_logger->info("received: $record->{body}");
        $self->process($payload);
      }

      return encode_json({ status => 'ok' });
    }

**SNS to SQS:** If your messages originate from SNS published to an
SQS queue (the fan-out pattern), the `body` field contains an SNS
notification envelope. Unwrap it to get your actual payload:

    my $body    = decode_json($record->{body});
    my $payload = decode_json($body->{Message})
      if $body->{Type} eq 'Notification';

To attach a Lambda function to an SQS queue use `make
lambda-sqs-trigger`. The Lambda execution role requires the
`AWSLambdaSQSQueueExecutionRole` managed policy — add it to your
`policies` file and run `make update-policies` before creating
the trigger.

**Note:** For low-frequency queues (under a few hundred messages per
day) Lambda is significantly more cost-effective than a long-polling
daemon on EC2. Lambda charges only for actual invocations and the
SQS free tier covers millions of requests per month.

# METHODS

## new

    new(options)

Constructor for the class. Since your class is being instantiated by
the runtime harness, in practice, you'll never call this directly in
any of your code. However, your class may override the method in the
usual way (make sure you call the base class at some point). This
class subclasses `Class::Accessor::Fast`.

`options` is a hash reference of possible options as described below:

- loglevel

    [Log::Log4perl](https://metacpan.org/pod/Log%3A%3ALog4perl) log level. One of:

        fatal
        error
        warn
        info
        debug
        trace

    Default: `info`

Example:

    package Lambda;
    use strict;
    use warnings;

    use parent qw(Amazon::Lambda::Runtime);

    sub new {
      my ($class, @args) = @_;
      my $self = $class->SUPER::new(@args);

      # your initialization here

      return $self;
    }

    sub handler {
      my ($self, $event, $context) = @_;

      return encode_json({ message => 'Hello World!' });
    }

    1;

## get\_logger

Returns a [Log::Log4perl](https://metacpan.org/pod/Log%3A%3ALog4perl) logger object. See ["Logging"](#logging).

You can pass a string or a code reference to the log methods
(`debug`, `info`, `warn`, `error`, `fatal`). The code reference
form is preferred for expensive operations since it is only evaluated
if the current log level warrants it:

    $self->get_logger->debug(sub { Dumper($event) });

## run

    run()

Executes the event loop, retrieving events from the Lambda Runtime
API and invoking the handler for each. Sends the response or error
back to the Lambda service after each invocation.

## next\_event

    next_event()

Implements the Lambda Runtime API protocol by polling for the next
event. As an optimization, Lambda may reuse the same execution
environment for multiple invocations. This means state stored in
package variables or module-level data persists between invocations
within the same environment — use this to cache expensive
initialization such as database connections or credential objects.

This method is used internally and should not be called from your
handler code. It returns the decoded event hashref.

## handler

    handler(event, context)

Your class must provide its own `handler()` method and return a
response string (typically JSON). The base class implementation sends
a `NoHandlerDefinedException` error to the Lambda service.

Anything written to `STDERR` is captured in the CloudWatch log
stream for this Lambda. Throwing an exception from your handler
causes Lambda to report a function error — use
`send_invocation_error()` for more graceful error reporting.

## send\_invocation\_response

    send_invocation_response(response)

Used internally to send the response string back to the Lambda
service.

## send\_invocation\_error

    send_invocation_error(error-message, error-type)

Sends an error message and error type to the Lambda service. This is
the preferred way of signaling errors rather than throwing an
exception, as it allows you to provide a structured error type
alongside the message.

## send\_init\_error

    send_init_error(error-message, error-type)

Reports an initialization error to the Lambda service. Call this
from your `new()` override if initialization fails and the function
should not be invoked.

# NOTES

## Logging

Any output to `STDERR` is captured in the CloudWatch log stream for
the Lambda. For better log messages use the internal logging system
which outputs in a more CloudWatch-friendly format:

    $self->get_logger->debug("a log message");
    $self->get_logger->info(sub { Dumper($event) });

Available log levels, from least to most verbose:

- fatal
- error
- warn
- info
- debug
- trace

By default logging is at the `info` level. Set the `LOG_LEVEL`
environment variable in the Lambda function configuration to change
it:

    aws lambda update-function-configuration \
        --function-name my-function \
        --environment "Variables={LOG_LEVEL=debug}"

## Required IAM Permissions

To use the targets in `Makefile.poc` the AWS identity you are
operating as must have the following permissions. The simplest
approach is to attach these to your IAM user or role as an inline
policy or a custom managed policy.

### ECR

Required for `make image`, `make ecr-repo`, and `make deploy`:

    ecr:CreateRepository
    ecr:DescribeRepositories
    ecr:GetAuthorizationToken
    ecr:BatchCheckLayerAvailability
    ecr:PutImage
    ecr:InitiateLayerUpload
    ecr:UploadLayerPart
    ecr:CompleteLayerUpload

### IAM

Required for `make lambda-role` and `make lambda-policies`:

    iam:GetRole
    iam:CreateRole
    iam:AttachRolePolicy
    iam:PassRole
    iam:ListAttachedRolePolicies

**Note:** `iam:PassRole` is frequently overlooked. Its absence
produces a confusing `InvalidParameterValueException` stating that
the role cannot be assumed by Lambda even though the role exists and
appears correctly configured. Always verify `iam:PassRole` is
granted for the role ARN in question.

### Lambda

Required for `make lambda-function`, `make update-function`,
`make lambda-sqs-trigger`, and `make invoke`:

    lambda:GetFunction
    lambda:CreateFunction
    lambda:UpdateFunctionCode
    lambda:UpdateFunctionConfiguration
    lambda:InvokeFunction
    lambda:ListFunctions
    lambda:GetFunctionConfiguration
    lambda:CreateEventSourceMapping
    lambda:ListEventSourceMappings

### STS

Required for automatic `AWS_ACCOUNT` resolution when the variable
is not set in the environment:

    sts:GetCallerIdentity

Setting `AWS_ACCOUNT` in your environment avoids this call entirely:

    export AWS_ACCOUNT=$(aws sts get-caller-identity \
        --query Account --output text --profile myprofile)

### Additional Permissions for Your Handler

The `AWSLambdaBasicExecutionRole` managed policy attached by default
covers only CloudWatch logging. Add any additional policies your
handler requires to the `policies` file and run `make
update-policies`. See ["The policies File"](#the-policies-file).

## AWS Reference Implementation

For reference, this is the AWS reference implementation of a custom
runtime as a shell script:

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

Rob Lauer - <rlauer6@comcast.net>

# LICENSE

(c) Copyright 2019-2026 Robert C. Lauer. All rights reserved. This
module is free software. It may be used, redistributed and/or
modified under the same terms as Perl itself.

# POD ERRORS

Hey! **The above document had some coding errors, which are explained below:**

- Around line 378:

    Non-ASCII character seen before =encoding in '—'. Assuming UTF-8
