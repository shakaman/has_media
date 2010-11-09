class Medium < ActiveRecord::Base
  set_table_name 'media'

  has_many   :media_links, :foreign_key => :medium_id, :dependent => :destroy
  has_many   :mediated, :through => :media_links

  mount_uploader :file, MediumUploader

  validates_presence_of :context

  ENCODE_WAIT      = 0
  ENCODE_ENCODING  = 1
  ENCODE_SUCCESS   = 2
  ENCODE_FAILURE   = 3
  ENCODE_NOT_READY = 4
  NO_ENCODING      = 5

  after_destroy :remove_file_from_fs
  after_initialize  :set_default_encoding_status

  scope :with_context, lambda {|context|
    { :conditions => { :context => context.to_s} }
  }

  def self.sanitize(name)
    name = name.gsub("\\", "/") # work-around for IE
    name = File.basename(name)
    name = name.gsub(/[^a-zA-Z0-9\.\-\+_]/,"_")
    name = "_#{name}" if name =~ /\A\.+\z/
    name = "unnamed" if name.size == 0
    return name.downcase
  end

  def self.new_from_value(object, value, context, encode, only)
    if value.respond_to?(:content_type)
      mime_type = value.content_type
    else
      mime_type = MIME::Types.type_for(value.path).first.content_type
    end
    only ||= ""
    medium_types = HasMedia.medium_types.keys.collect{|c| Kernel.const_get(c)}
    if only != "" and klass = Kernel.const_get(only.camelize)
      medium_types = [klass]
    end
    klass = medium_types.find do |k|
      HasMedia.medium_types[k.to_s].empty? || HasMedia.medium_types[k.to_s].include?(mime_type)
    end
    if klass.nil?
      object.media_errors = [HasMedia.errors_messages[:type_error]]
      return
    end
    medium = klass.new
    if value.respond_to?(:original_filename)
      medium.filename = self.sanitize(value.original_filename)
    else
      medium.filename = self.sanitize(File.basename(value.path))
    end
    medium.file = value
    medium.content_type = mime_type
    medium.context = context
    medium.encode_status = (encode == "false" ? NO_ENCODING : ENCODE_WAIT)
    medium.save
    medium
  end

  ##
  # Is this medium encoding?
  #
  def encoding?
    encode_status == ENCODE_ENCODING
  end

  ##
  # Is this medium ready?
  #
  def ready?
    encode_status == ENCODE_SUCCESS
  end

  ##
  # Has the encoding failed for this medium
  #
  def failed?
    encode_status == ENCODE_FAILURE
  end

  ##
  # Delete media file(s) from disk
  #
  def unlink_files
    file = self.full_filename
    File.unlink(file) if File.exists? file
  end

  # Public path to the file originally uploaded.
  def original_file_path
    File.join(directory_path, self.filename)
  end

  # Http uri to the originally file
  def original_file_uri
    File.join(directory_uri, self.filename)
  end

  # System directory to store files
  def directory_path
    self.file.store_dir
  end
  # system path for a medium
  def file_path(version = nil)
    File.join(directory_path, encoded_file_name(version))
  end

  # http uri for a medium
  def file_uri(version = nil)
    File.join(directory_uri, encoded_file_name(version))
  end

  def encoded_file_name(version = nil)
    # remove original extension and add the encoded extension
    final_name = filename.gsub(/\.[^.]{1,4}$/, "") + '.' + file_extension
    final_name[-4,0] = "_#{version}" if version
    final_name
  end

  # http uri of directory which stores media
  def directory_uri
    File.join(HasMedia.directory_uri,
              ActiveSupport::Inflector.underscore(self.type),
              self.id.to_s)
  end

  def file_exists?(thumbnail = nil)
    File.exist?(File.join(Rails.root, 'public', file_uri(thumbnail)))
  end

  def file_extension
    sym = type.underscore.to_sym
    unless HasMedia.encoded_extensions.keys.include?(sym)
      raise Exception.new("You need to add encoded extension configuration for :#{sym}")
    end
    HasMedia.encoded_extensions[sym]
  end

private

  ##
  # Set encode_status value to notify the encoder of a new file
  def set_default_encoding_status
    self.encode_status = ENCODE_NOT_READY if filename_changed?
  end

  ##
  # Unlink the folder containing the files
  # TODO : remove all files, not only the original one
  def remove_file_from_fs
    require 'fileutils'
    FileUtils.rm_rf(self.directory_path)
  end
end
