# NAME

Amazon::Lambda::Runtime

# SYNOPSIS

    package Lambda;

    use strrict;
    use warnings;

    use parent qw(Amazon::Lambda::Runtime);

    sub handler {
      my ($self, $event, $context) = @_;

      return 'Hello World!';
    }

    1;

# DESCRIPTION

Base class for creating Perl based Lambdas in the AWS environment.

# METHODS

## new

    new(options)

Constructor for the class.  Since your class is being instantiated by
the runtime harness, in practice, you'll never call this directly in
any of your code.  However, your class may override the method in the
usual way (make sure you  call the base class at some point).  This
class subclasses `Class::Accessor::Fast`.

`options` is a hash reference of possible options as described below:

- log\_level

    [Log::Log4perl](https://metacpan.org/pod/Log%3A%3ALog4perl) log level. One of:

        fatal
        error
        warn
        info
        debug

Example:

    package Lambda;
    use strict;
    use warnings;

    use parent qw(Amazon::Lambda::Runtime);

    sub new {
      my ($class, @args) = @_;
      my $self = $class->SUPER::new(@args);

      # your code here ....

      return $self;
    }

    sub handler {
      my ($self, $event, $context) = @_;

      return 'Hello World!';
    }

    1;

## get\_logger

Returns a log object suitable for passing log messages to.  See
["Logging"](#logging).

You can pass a string or a code reference that will be executed to the
log methods (`debug`, `info`,`warn`,`error`,`fatal`) if the
current logging level is at or above the logging level corresponding
to the method invoked.

## run

    run()

Executes the event loop, looking for events invoking the handler.
Sends the response or error back to the Lambda service after calling
the handler.

## next\_event

    next_event()

Implements the protocol of custom AWS Lambda Runtimes by retrieving
the next event.  As an optimization, calls to an an AWS Lambda
function may land on the same or different instance.  Apparently this
protocol might allow for multiple Lambda functions to be processed by
the same running Lambda environment.  This allows for some
optimizations in your own code by saving data that might speed up or
faciliate future invocations.  Keep in mind you should not expect to
have persistence of your data and should code accordingly.

The method is used internally and should not be called by any of your
own Lambda code.

The method returns an event object.

## handler

    handler(event, context)

Your class should provide its own `handler()` method and return a
response. Anything sent to `STDERR` will be sent to the CloudWatch
logstream for this Lambda.  A non-zero status from the runtime harness
will signal a Lambda error, so throwing an exception is sufficient to
indicate an error condition.  You can however use the
`send_invocation_error()` to indicate an error and a message in a
more graceful way.

## send\_invocation\_reponse

    send_invocation_response(response)

Used interally to send the response back to the Lambda service.

## send\_invocation\_error

    send_error(error-message, error-type)

Sends an error message and error type to the Lambda service.  This is
the preferred way of indicating errors to the service.

# NOTES

## Logging

Any output to `STDERR` will be captured in the CloudWatch logstream
for the Lambda.  You can log messages by simply writing to STDERR,
however you might find however that messages sent in this fashion are
**not** as easy to decipher as you might like because of newline
mangling.  For better log messages use the internal logging system for
`Amazon::Lambda::Runtime` which outputs messages in a more CloudWatch
friendly format.

    $self->get_logger->debug("a log message");

    $self->get_logger->info(sub { Dumper $event });

Use the `get_logger` method to get an instance of the log
object. Available log methods are:

- debug
- info
- error
- warn
- fatal

By default, logging will be done at the `info` level.  You can set the
log level in your handler or in the environment by setting the
`LOG_LEVEL` environment variable in the `environment` section of
your `buildspec.yml` file.

## AWS Reference Implementation

As a reminder, this is the AWS reference implementation for a custom
runtime (as a bash script):

    #!/bin/sh

    set -euo pipefail

    # Initialization - load function handler
    source $LAMBDA_TASK_ROOT/"$(echo $_HANDLER | cut -d. -f1).sh"

    while true
     do
       HEADERS="$(mktemp)"
       # Get an event
       EVENT_DATA=$(curl -sS -LD "$HEADERS" -X GET "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next")
       REQUEST_ID=$(grep -Fi Lambda-Runtime-Aws-Request-Id "$HEADERS" | tr -d '[:space:]' | cut -d: -f2)

       # Execute the handler function from the script
       RESPONSE=$($(echo "$_HANDLER" | cut -d. -f2) "$EVENT_DATA")

       # Send the response
       curl -X POST "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/$REQUEST_ID/response"  -d "$RESPONSE"
     done

# AUTHOR

Rob Lauer - <rlauer6@comcast.net>

# COPYRIGHT

(c) Copyright 2019-2024 Robert C. Lauer. All rights reserved.  This module
is free software. It may be used, redistributed and/or modified under
the same terms as Perl itself.
