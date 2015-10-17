require 'new_relic/agent/transaction_state'
require 'new_relic/agent/instrumentation/middleware_tracing'
require 'new_relic/agent/transaction'
require 'new_relic/agent/method_tracer'
require 'new_relic/agent/method_tracer_helpers'

module NewRelic
  module Agent
    # Patch TransactionState to be local to the currently scoped request
    # Relies on the application code to use `scope_env` to scope code to the env
    class TransactionState

      def self.scope_env(env_or_request, &block)
        previous = @current_env
        @current_env = env_or_request.respond_to?(:env) ? env_or_request.env : env_or_request
        ensure_scope_id!
        result = yield
        @current_env = previous
        result
      end

      def self.ensure_scope_id!
        unless @current_env['new_relic.scope_id']
          @new_relic_scope_ids ||= 0
          @new_relic_scope_ids += 1
          @current_env['new_relic.scope_id'] = @new_relic_scope_ids.to_s
        end
      end

      def self.scope_id
        @current_env ? @current_env['new_relic.scope_id'] : nil
      end

      def self.tl_get
        id = scope_id
        if id
          tl_state_for_scope(id)
        else
          tl_state_for(Thread.current)
        end
      end

      def self.tl_state_for_scope(scope_id)
        @transaction_states ||= {}
        state = @transaction_states[scope_id]
        if state.nil?
          state = TransactionState.new
          @transaction_states[scope_id] = state
        end
        state
      end

    end # class TransactionState

    # Patch MiddlewareTracing to defer stopping of transaction and leave
    # that for the application level code to do
    module Instrumentation
      module MiddlewareTracing

        def call(env)
          NewRelic::Agent::TransactionState.scope_env(env) do
            first_middleware = note_transaction_started(env)

            state = NewRelic::Agent::TransactionState.tl_get
            is_async = nil
            env['new_relic.middleware_depth'] ||= 0
            env['new_relic.middleware_depth'] += 1

            begin
              Transaction.start(state, category, build_transaction_options(env, first_middleware))
              events.notify(:before_call, env) if first_middleware

              result = (target == self) ? traced_call(env) : target.call(env)

              is_async = result[0] == -1

              capture_http_response_code(state, result)
              events.notify(:after_call, env, result) if first_middleware

              result
            rescue Exception => e
              NewRelic::Agent.notice_error(e)
              raise e
            ensure
              # If the request is async, we expect the handler to end these transactions
              Transaction.stop(state) unless is_async
            end
          end
        end

      end # module MiddlewareTracing
    end # module Instrumentation

    class Transaction
      # End async request cycle
      def self.stop_async(env, response=nil)
        state = NewRelic::Agent::TransactionState.tl_get
        state.current_transaction.http_response_code = response.status if response && state.current_transaction
        env['new_relic.middleware_depth'].times do
          NewRelic::Agent::Transaction.stop(state)
        end
      end
    end # class Transaction

    module MethodTracer
      def trace_execution_scoped(metric_names, options={}) #THREAD_LOCAL_ACCESS
        if block_given?
          NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped(metric_names, options) do
            # Using an implicit block avoids object allocation for a &block param
            yield
          end
        else
          NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped(metric_names, options)
        end
      end
    end # module MethodTracer

    # We override these in order to allow passing in start_time instead of relying on a block to time the call
    module MethodTracerHelpers
      def trace_execution_scoped(metric_names, options={}) #THREAD_LOCAL_ACCESS
        state = NewRelic::Agent::TransactionState.tl_get
        return (block_given? ? yield : nil) unless state.is_execution_traced?

        metric_names = Array(metric_names)
        first_name   = metric_names.shift
        return (block_given? ? yield : nil) unless first_name

        additional_metrics_callback = options[:additional_metrics_callback]
        start_time = options[:start_time] || Time.now.to_f
        expected_scope = trace_execution_scoped_header(state, start_time)

        begin
          result = block_given? ? yield : nil
          metric_names += Array(additional_metrics_callback.call) if additional_metrics_callback
          result
        ensure
          trace_execution_scoped_footer(state, start_time, first_name, metric_names, expected_scope, options)
        end
      end
    end # class MethodTracerHelpers

  end # module Agent
end # module NewRelic
