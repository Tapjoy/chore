class TestJob 
  include Chore::Job
  queue_options :name => 'test', :publisher => Chore::Publisher

  def perform(*args)
  end
end
