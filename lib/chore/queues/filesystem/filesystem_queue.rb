# Common methods used by FilesystemConsumer and FilesystemPublisher for dealing with the
# directories which implement the queue.
module Chore::FilesystemQueue

  NEW_JOB_DIR = "new"
  IN_PROGRESS_DIR = "inprogress"
  
  def in_progress_dir(queue_name)
    validate_dir(queue_name, IN_PROGRESS_DIR)
  end

  def new_dir(queue_name)
    validate_dir(queue_name, NEW_JOB_DIR)
  end
  
  def root_dir
    @root_dir ||= prepare_dir(File.expand_path(Chore.config.fs_queue_root))
  end

  def queue_dir(queue_name)
    prepare_dir(File.join(root_dir, queue_name))
  end

  private
  
  def validate_dir(queue_name, task_state)
    prepare_dir(File.join(queue_dir(queue_name), task_state))
  end

  def prepare_dir(dir)
    unless Dir.exists?(dir)
      FileUtils.mkdir_p(dir)
    end
    
    raise IOError.new("directory for file system queue does not have write permission: #{dir}") unless File.writable?(dir)
    dir
  end
  
end