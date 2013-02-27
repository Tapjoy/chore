require 'spec_helper'

describe Chore::Semaphore do

  let(:resource_name) { "sqs" }
  let(:max_locks) { 1 }
  let(:semaphore) { Chore::Semaphore.new(resource_name, max_locks: max_locks ) }

end
