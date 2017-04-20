require 'thread'

module Logglier
  module Client
    class HTTP

      # Used by the Threaded client to manage the delivery thread
      # recreating it if is lost due to a fork.
      #
      class DeliveryThreadManager
        def initialize(input_uri, opts={})
          @input_uri, @opts = input_uri, opts
          start_thread
        end

        # Pushes a message to the delivery thread, starting one if necessary
        def deliver(message)
          start_thread unless @thread.alive?
          @thread.deliver(message)
          #Race condition? Sometimes we need to rescue this and start a new thread
        rescue NoMethodError
          @thread.kill #Try not to leak threads, should already be dead anyway
          start_thread
          retry
        end

        private

        def start_thread
          @thread = DeliveryThread.new(@input_uri, @opts)
        end
      end

      # Taken from https://spin.atomicobject.com/2014/07/07/ruby-queue-pop-timeout/
      class QueueWithTimeout
        def initialize
          @mutex = Mutex.new
          @queue = []
          @received = ConditionVariable.new
        end

        def <<(x)
          @mutex.synchronize do
            @queue << x
            @received.signal
          end
        end

        def push(x)
          self << x
        end

        def pop(non_block = false)
          pop_with_timeout(non_block ? 0 : nil)
        end

        def pop_with_timeout(timeout = nil)
          @mutex.synchronize do
            if @queue.empty?
              @received.wait(@mutex, timeout) if timeout != 0
              #if we're still empty after the timeout, raise exception
              raise ThreadError, "queue empty" if @queue.empty?
            end
            @queue.shift
          end
        end
      end

      # Used by the DeliveryThreadManager to hold a queue, deliver messsages from it
      # and to ensure it's flushed on program exit.
      #
      # @note Uses NetHTTPProxy
      #
      class DeliveryThread < Thread

        # @param [URI] input_uri The uri to deliver messages to
        # @param [Hash] opts Option hash
        # @option [Integer] read_timeout Read timeout for the http session. defaults to 120
        # @option [Integer] open_timeout Open timeout for the http session. defaults to 120
        #
        # @note See NetHTTPProxy for further option processing of opts
        # @note registers an at_exit handler that signals exit intent and joins the thread.
        def initialize(input_uri, opts={})
          @input_uri = input_uri

          opts[:read_timeout] = opts[:read_timeout] || 120
          opts[:open_timeout] = opts[:open_timeout] || 120

          opts[:bulk] = opts[:bulk] || false
          opts[:bulk_pop_timeout] = opts[:bulk_pop_timeout] || 5
          opts[:bulk_max_size] = opts[:bulk_max_size] || 100 # messages
          # something lower than loggly's 5MB maximum per batch.
          # @note https://www.loggly.com/docs/http-bulk-endpoint/

          @http = Logglier::Client::HTTP::NetHTTPProxy.new(@input_uri, opts)
          @queue = create_queue(opts)
          @exiting = false

          super do
            exit_after_this_round = false
            loop do
              msg = nil

              if opts[:bulk] == true then
                bulk_messages = fetch_bulk_message(opts[:bulk_max_size], opts[:bulk_pop_timeout])

                if bulk_messages.last == :__delivery_thread_exit_signal__
                  bulk_messages.pop
                  exit_after_this_round = true
                end

                msg = bulk_messages.join("\n")
              else
                msg = @queue.pop
                break if msg == :__delivery_thread_exit_signal__
              end

              @http.deliver(msg)
              break if exit_after_this_round
            end
          end

          at_exit {
            exit!
            join
          }
        end

        # Signals the queue that we're exiting
        def exit!
          @exiting = true
          @queue.push :__delivery_thread_exit_signal__
        end

        # Pushes a message onto the internal queue
        def deliver(message)
          @queue.push(message)
        end

        private

        def fetch_bulk_message(bulk_max_size, pop_timeout)
          bulk_msg = []

          loop do
            begin
              msg = @queue.pop_with_timeout(pop_timeout)
              bulk_msg << msg
              break if msg == :__delivery_thread_exit_signal__
            rescue ThreadError
              break
            end

            break if bulk_msg.size == bulk_max_size
          end

          bulk_msg
        end

        def create_queue(opts)
          if opts[:bulk] == true
            QueueWithTimeout.new
          else
            Queue.new
          end
        end
      end

    end
  end
end
