# Common methods used by FilesystemConsumer and FilesystemPublisher for dealing with the
# directories which implement the queue.
module Chore::FilesystemQueue

  # Local directory for new jobs to be placed
  NEW_JOB_DIR = "new"
  # Local directory for jobs currently in-process to be moved
  IN_PROGRESS_DIR = "inprogress"
  # Local directory for configuration info
  CONFIG_DIR = "config"
  
  # Retrieves the directory for in-process messages to go. If the directory for the +queue_name+ doesn't exist,
  # it will be created for you. If the directory cannot be created, an IOError will be raised
  def in_progress_dir(queue_name)
    validate_dir(queue_name, IN_PROGRESS_DIR)
  end

  # Retrieves the directory for newly recieved messages to go. If the directory for the +queue_name+ doesn't exist,
  # it will be created for you. If the directory cannot be created, an IOError will be raised
  def new_dir(queue_name)
    validate_dir(queue_name, NEW_JOB_DIR)
  end
  
  # Returns the root directory where messages are placed
  def root_dir
    @root_dir ||= prepare_dir(File.expand_path(Chore.config.fs_queue_root))
  end

  # Returns the fully qualified path to the directory for +queue_name+
  def queue_dir(queue_name)
    prepare_dir(File.join(root_dir, queue_name))
  end

  # The configuration for the given queue
  def config_dir(queue_name)
    validate_dir(queue_name, CONFIG_DIR)
  end

  def config_value(queue_name, config_name)
    config_file = File.join(config_dir(queue_name), config_name)
    if File.exist?(config_file)
      File.read(config_file).strip
    end
  end

  # Returns the timeout for +queue_name+
  def queue_timeout(queue_name)
    (config_value(queue_name, 'timeout') || Chore.config.default_queue_timeout).to_i
  end

  private
  # Returns the directory for the given +queue_name+ and +task_state+. If the directory doesn't exist, it will be
  # created for you. If the directory cannot be created, an IOError will be raised
  def validate_dir(queue_name, task_state)
    prepare_dir(File.join(queue_dir(queue_name), task_state))
  end

  # Creates a directory if it does not exist. Returns the directory
  def prepare_dir(dir)
    unless Dir.exist?(dir)
      FileUtils.mkdir_p(dir)
    end
    
    raise IOError.new("directory for file system queue does not have write permission: #{dir}") unless File.writable?(dir)
    dir
  end
  
end
