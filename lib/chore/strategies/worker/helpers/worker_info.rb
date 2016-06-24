module Chore
  module Strategy
    class WorkerInfo
      # Holds meta information about the worker: pid, and connection socket
      attr_accessor :pid, :socket

      def initialize(socket)
        @pid = nil
        @socket = socket
      end
    end
  end
end
