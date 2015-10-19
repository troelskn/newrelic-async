newrelic-async
===

A set of patches for `newrelic_rpm` that makes it work with async code. See [blog-post](http://troelskn.com/posts/how-i-got-new-relic-working-with-thin-async/) for an explanation.

Simple example, using [thin_async](https://github.com/macournoyer/thin_async):

    class MyApp
      def call(env)
        NewRelic::Agent::TransactionState.scope_env(env) do
          Thin::AsyncResponse.perform(env) do |response|
            response.headers["Content-Type"] = "text/plain"
            db = Mysql2::EM::Client.new($mysql_configuration)
            defer = db.query "select now()"
            defer.callback do |result|
              NewRelic::Agent::TransactionState.scope_env(env) do
                now = result.first
                response.status = 200
                response << "The time is #{now}"
                response.done
              end
            end
            defer.errback do |err|
              NewRelic::Agent::TransactionState.scope_env(env) do
                response.status = 500
                response << "Oops - Something went wrong: #{err}"
                response.done
              end
            end
          end
        end
        response.callback do
          NewRelic::Agent::Transaction.stop_async(env, response)
        end
      end
    end

    run MyApp.new

Copyright
---

Copyright (c) 2015 Troels Knak-Nielsen. Code is BSD licensed.
