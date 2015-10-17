require 'helper'

module NewrelicAsync
  class TestTransactionState < Minitest::Test
    def test_state_returns_same_object_on_each_call
      state = NewRelic::Agent::TransactionState.tl_get
      assert_equal state, NewRelic::Agent::TransactionState.tl_get
    end

    def test_state_can_be_scoped
      env = {}
      state = NewRelic::Agent::TransactionState.tl_get
      NewRelic::Agent::TransactionState.scope_env(env) do
        scoped_state = NewRelic::Agent::TransactionState.tl_get
        refute_equal state, scoped_state
      end
      assert_equal state, NewRelic::Agent::TransactionState.tl_get
    end

    def test_state_can_have_multiple_independent_scopes
      env1, env2 = {}, {}
      state1, state2 = nil, nil
      NewRelic::Agent::TransactionState.scope_env(env1) do
        state1 = NewRelic::Agent::TransactionState.tl_get
      end
      NewRelic::Agent::TransactionState.scope_env(env2) do
        state2 = NewRelic::Agent::TransactionState.tl_get
      end
      refute_equal state1, state2
    end
  end # class TestTransactionState

  class TestMiddlewareTracing < Minitest::Test

    class HostClass
      include NewRelic::Agent::Instrumentation::MiddlewareTracing

      attr_reader :category, :notifications

      def initialize(&blk)
        @action = blk
      end

      def target
        self
      end

      def transaction_options
        {}
      end

      def traced_call(env)
        @action.call
      end

      def events
        self
      end

      def notify(event, *attrs)
        @notifications ||= []
        @notifications << [event, attrs]
      end
    end

    def test_starts_and_stops_transaction_for_regular_requests
      NewRelic::Agent::Transaction.expects(:start).once
      NewRelic::Agent::Transaction.expects(:stop).once

      middleware = HostClass.new { [200, {}, ['hi!']] }
      middleware.call({})
    end

    def test_starts_but_doesnt_stop_transaction_for_async_requests
      NewRelic::Agent::Transaction.expects(:start).once
      NewRelic::Agent::Transaction.expects(:stop).never

      middleware = HostClass.new { [-1, {}, []] }
      middleware.call({})
    end
  end # class TestMiddlewareTracing
end
