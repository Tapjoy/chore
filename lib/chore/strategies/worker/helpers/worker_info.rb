module Chore
  module Strategy
    class WorkerInfo
      # Holds meta information about the worker: pid, and connection socket
      attr_accessor :pid, :socket

      def initialize(pid)
        @pid = pid
        @socket = nil
      end
    end
  end
end
